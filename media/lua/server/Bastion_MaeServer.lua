-- ============================================================
-- Bastion_MaeServer.lua  (media/lua/server/)
-- Server-side only.  Works in singleplayer and multiplayer.
--
-- Core systems:
--   • Settlement tick (once per in-game day)
--   • Container scanning + resource estimation
--   • Settler-managed water pool
--   • Virtual yield accumulation
--   • Settler mannequin spawn / removal
--   • Client command dispatch (EstablishBastion, CollapseBastion,
--     MarkPrivate, SetNoiseBudget, SetRoleSetting, AdminCmd)
-- ============================================================
print("[Bastion] Server loading")

-- ── ModData helpers ───────────────────────────────────────────────────────────

local function getWorldData()
    return ModData.getOrCreate(Bastion.DATA_KEY)
end

local function getRecord(username)
    return getWorldData()[username]
end

local function saveRecord(username, rec)
    getWorldData()[username] = rec
    ModData.transmit(Bastion.DATA_KEY)
end

local function clearRecord(username)
    getWorldData()[username] = nil
    ModData.transmit(Bastion.DATA_KEY)
end

-- ── Container scanning ────────────────────────────────────────────────────────

local function getContainerCategory(obj)
    local name = ""
    local ok, spr = pcall(function() return obj:getSprite() end)
    if ok and spr then
        local ok2, n = pcall(function() return spr:getName() end)
        if ok2 and type(n) == "string" then name = n:lower() end
    end
    if name:find("freezer")                         then return "frozen"        end
    if name:find("fridge") or name:find("refriger") then return "refrigerated"  end
    return "general"
end

local function scanContainers(rec)
    local cell = getCell()
    if not cell then
        return { general={}, refrigerated={}, frozen={},
                 capacity={ general=0, refrigerated=0, frozen=0 } }
    end

    local result = {
        general      = {},
        refrigerated = {},
        frozen       = {},
        capacity     = { general=0, refrigerated=0, frozen=0 },
    }

    local bx, by, bz = rec.bx, rec.by, rec.bz
    local r = Bastion.SCAN_RANGE

    for x = bx - r, bx + r do
        for y = by - r, by + r do
            local sq = cell:getGridSquare(x, y, bz)
            if sq and sq:getRoom() then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local obj = objs:get(i)
                    if obj and obj.getContainer then
                        local container = obj:getContainer()
                        if container then
                            local key = x .. "," .. y .. "," .. bz
                            local isPrivate = rec.privateContainers
                                           and rec.privateContainers[key]
                            if not isPrivate then
                                local cat   = getContainerCategory(obj)
                                local items = container:getItems()
                                for j = 0, items:size() - 1 do
                                    table.insert(result[cat], items:get(j))
                                end
                                local cap = container:getCapacity() or 0
                                result.capacity[cat] = result.capacity[cat] + cap
                            end
                        end
                    end
                end
            end
        end
    end
    return result
end

-- ── Resource estimation ───────────────────────────────────────────────────────

local function isFood(item)
    if not item then return false end
    local ok, r = pcall(function() return item:isFood() end)
    if ok and r then return true end
    ok, r = pcall(function() return item:getDisplayCategory() end)
    if ok and type(r) == "string" and r:lower():find("food") then return true end
    return false
end

local function getWaterUnits(item)
    if not item then return 0 end
    local ok, fc = pcall(function() return item:getFluidContainer() end)
    if ok and fc then
        local ok2, empty = pcall(function() return fc:isEmpty() end)
        if ok2 and not empty then
            local ok3, amt = pcall(function() return fc:getAmount() end)
            if ok3 and type(amt) == "number" and amt > 0 then return amt end
            return 1
        end
    end
    return 0
end

local function estimateResources(rec, storage)
    local count = math.max(1, #(rec.settlers or {}))

    local totalCalories = 0
    local totalWater    = 0

    local allItems = {}
    for _, item in ipairs(storage.general)      do table.insert(allItems, item) end
    for _, item in ipairs(storage.refrigerated) do table.insert(allItems, item) end
    for _, item in ipairs(storage.frozen)       do table.insert(allItems, item) end

    for _, item in ipairs(allItems) do
        if isFood(item) then totalCalories = totalCalories + 500 end
        totalWater = totalWater + getWaterUnits(item)
    end

    local caloriesPerDay = count * Bastion.CALORIES_PER_SETTLER_PER_DAY
    local waterPerDay    = count * Bastion.WATER_PER_SETTLER_PER_DAY

    rec.foodDays  = caloriesPerDay > 0 and math.floor(totalCalories / caloriesPerDay * 10) / 10 or 0
    -- waterDays = actual containers + settler-managed pool
    local actualWaterDays = waterPerDay > 0 and math.floor(totalWater / waterPerDay * 10) / 10 or 0
    rec.waterDays = actualWaterDays + (rec.settlerWaterPool or 0)

    rec.storageCapacity = {
        general      = storage.capacity.general,
        refrigerated = storage.capacity.refrigerated,
        frozen       = storage.capacity.frozen,
    }
end

-- ── Water pool helpers ────────────────────────────────────────────────────────

-- Draw water from the settler-managed pool.
-- Returns true if the amount was available and consumed, false otherwise.
local function debitWater(rec, amount)
    local pool = rec.settlerWaterPool or 0
    if pool < amount then return false end
    rec.settlerWaterPool = math.max(0, pool - amount)
    return true
end

-- Add water to the settler-managed pool, capped at WATER_POOL_MAX.
local function addSettlerWater(rec, amount)
    local current = rec.settlerWaterPool or 0
    rec.settlerWaterPool = math.min(current + amount, Bastion.WATER_POOL_MAX)
end

-- ── World-state scanning (cached per N in-game days) ─────────────────────────

-- True if a water source exists within collectRadius tiles.
-- Checks: open water terrain tiles (ponds/rivers) and rain-barrel sprites.
local function hasWaterSource(rec)
    local cell = getCell()
    if not cell then return false end

    local r    = Bastion.getSetting(rec, "WaterCarrier", "collectRadius") or 50
    local step = Bastion.WATER_SOURCE_SCAN_STEP   -- skip tiles for performance
    local bx, by, bz = rec.bx, rec.by, rec.bz

    for x = bx - r, bx + r, step do
        for y = by - r, by + r, step do
            local sq = cell:getGridSquare(x, y, bz)
            if sq then
                -- Water terrain (ponds, rivers)
                local ok, isWater = pcall(function() return sq:isWater() end)
                if ok and isWater then return true end

                -- Rain-barrel objects
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local obj = objs:get(i)
                    local ok2, spr = pcall(function() return obj:getSprite() end)
                    if ok2 and spr then
                        local ok3, n = pcall(function() return spr:getName() end)
                        if ok3 and type(n) == "string" then
                            local nl = n:lower()
                            if nl:find("rain") or nl:find("barrel") then return true end
                        end
                    end
                end
            end
        end
    end
    return false
end

-- True if a heat source (campfire or stove) exists indoors within SCAN_RANGE.
local function hasHeatSource(rec)
    local cell = getCell()
    if not cell then return false end
    local r = Bastion.SCAN_RANGE
    local bx, by, bz = rec.bx, rec.by, rec.bz

    for x = bx - r, bx + r do
        for y = by - r, by + r do
            local sq = cell:getGridSquare(x, y, bz)
            if sq and sq:getRoom() then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local obj = objs:get(i)

                    -- Campfire
                    local ok, isCamp = pcall(function()
                        return instanceof(obj, "IsoCampfire")
                    end)
                    if ok and isCamp then return true end

                    -- Stove/oven by sprite name
                    local ok2, spr = pcall(function() return obj:getSprite() end)
                    if ok2 and spr then
                        local ok3, n = pcall(function() return spr:getName() end)
                        if ok3 and type(n) == "string" then
                            local nl = n:lower()
                            if nl:find("stove") or nl:find("oven") then return true end
                        end
                    end
                end
            end
        end
    end
    return false
end

-- True if any IsoAnimal exists within SCAN_RANGE.
local function hasAnimals(rec)
    local cell = getCell()
    if not cell then return false end
    local r = Bastion.SCAN_RANGE
    local bx, by, bz = rec.bx, rec.by, rec.bz

    for x = bx - r, bx + r do
        for y = by - r, by + r do
            local sq = cell:getGridSquare(x, y, bz)
            if sq then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local obj = objs:get(i)
                    local ok, isAnimal = pcall(function()
                        return instanceof(obj, "IsoAnimal")
                    end)
                    if ok and isAnimal then return true end
                end
            end
        end
    end
    return false
end

-- True if storage contains a pot (for boiling water).
local function hasPot(storage)
    for _, item in ipairs(storage.general) do
        local ok, t = pcall(function() return item:getType() end)
        if ok and type(t) == "string" then
            local tl = t:lower()
            if tl == "cookingpot" or tl == "pot" or tl == "waterpot" then
                return true
            end
        end
    end
    return false
end

-- ── Item-type helpers ─────────────────────────────────────────────────────────

local function isRag(item)
    local ok, t = pcall(function() return item:getType() end)
    if not ok or type(t) ~= "string" then return false end
    local tl = t:lower()
    return tl == "rag" or tl == "rippedsheets" or tl == "sheetsmall" or tl:find("rag")
end

local function isDirtyRag(item)
    local ok, t = pcall(function() return item:getType() end)
    if ok and type(t) == "string" and t:lower():find("dirty") then return true end
    local ok2, b = pcall(function() return item:isBloody() end)
    if ok2 and b then return true end
    return false
end

local function isScrap(item)
    local ok, t = pcall(function() return item:getType() end)
    if not ok or type(t) ~= "string" then return false end
    local tl = t:lower()
    return tl:find("scrap") or tl == "smallmetal" or tl == "metalpipe"
        or tl == "metalbar" or tl:find("brokenmetaltool")
end

local function isPerishable(item)
    -- Heuristic: if the item has a custom age (AgeDelta > 0) it can spoil.
    if not item then return false end
    local ok, age = pcall(function() return item:getAgeDelta() end)
    if ok and type(age) == "number" and age > 0 then return true end
    -- Also check by type: cooked food, fresh meat, vegetables
    local ok2, t = pcall(function() return item:getType() end)
    if ok2 and type(t) == "string" then
        local tl = t:lower()
        if tl:find("cooked") or tl:find("fresh") or tl:find("raw")
        or tl:find("egg") or tl:find("milk") then
            return true
        end
    end
    return false
end

-- ── Settler mannequin helpers ─────────────────────────────────────────────────

local SPRITE_FEMALE = "location_shop_mall_01_65"
local SPRITE_MALE   = "location_shop_mall_01_68"
local SCRIPT_FEMALE = "FemaleBlack01"
local SCRIPT_MALE   = "MaleBlack01"

local function spawnSettlerMannequin(settler)
    local cell = getCell()
    if not cell then return false end

    local sq = cell:getGridSquare(settler.x, settler.y, settler.z)
    if not sq then
        print("[Bastion] spawnSettler: no square at "
            .. settler.x .. "," .. settler.y .. "," .. settler.z)
        return false
    end

    local spriteName = settler.isMale and SPRITE_MALE   or SPRITE_FEMALE
    local scriptName = settler.isMale and SCRIPT_MALE   or SCRIPT_FEMALE
    local spr = getSprite(spriteName)
    if not spr then
        print("[Bastion] spawnSettler: sprite not found: " .. spriteName)
        return false
    end

    local obj = IsoMannequin.new(cell, sq, spr)
    obj:setSquare(sq)
    if obj.setMannequinScriptName then obj:setMannequinScriptName(scriptName) end

    local md = obj:getModData()
    md["Bastion_Settler"]   = true
    md["Bastion_Owner"]     = settler.ownerUsername
    md["Bastion_SettlerID"] = settler.id
    md["Bastion_Name"]      = settler.name
    md["Bastion_Role"]      = settler.role

    local idx = sq:getObjects():size()
    sq:AddSpecialObject(obj, idx)
    if obj.transmitCompleteItemToClients then
        obj:transmitCompleteItemToClients()
    end
    print("[Bastion] Spawned settler " .. settler.name)
    return true
end

local function removeSettlerMannequin(settler)
    if not settler.x then return end
    local cell = getCell()
    if not cell then return end
    local sq = cell:getGridSquare(settler.x, settler.y, settler.z)
    if not sq then return end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoMannequin") then
            local md = o:getModData()
            if md["Bastion_SettlerID"] == settler.id then
                sq:transmitRemoveItemFromSquare(o)
                return
            end
        end
    end
end

local function removeAllSettlerMannequins(rec)
    for _, settler in ipairs(rec.settlers or {}) do
        removeSettlerMannequin(settler)
    end
end

local function findSpawnSquare(bx, by, bz, startOffset)
    local cell = getCell()
    if not cell then return bx, by, bz end
    for i = startOffset or 1, #Bastion.SETTLER_OFFSETS do
        local off = Bastion.SETTLER_OFFSETS[i]
        local x, y, z = bx + off.x, by + off.y, bz + (off.z or 0)
        local sq = cell:getGridSquare(x, y, z)
        if sq and sq:getRoom() then return x, y, z end
    end
    return bx, by, bz
end

local function generateSettlerID()
    return tostring(math.floor(getTimeInMillis()))
        .. tostring(ZombRand(99999))
end

-- ── Role tick functions ───────────────────────────────────────────────────────
-- Signature: function(settler, rec, storage)
-- settler: the settler data table
-- rec:     the settlement record (may be mutated)
-- storage: result of scanContainers(rec)

local ROLE_TICKS = {}

-- ── Tailor ────────────────────────────────────────────────────────────────────
-- Phase 1: wash dirty rags (costs settler water), pick thread up to maxThread.
-- Phase 2 (skill 8+): repair clothing holes (requires addPatches setting).

ROLE_TICKS.Tailor = function(settler, rec, storage)
    local maxThread = Bastion.getSetting(rec, "Tailor", "maxThread") or 50
    local curThread = (rec.virtualYield or {}).thread or 0
    local acted     = false

    -- Step 1: Wash dirty rags — each rag costs a small water draw.
    local dirtyCount = 0
    for _, item in ipairs(storage.general) do
        if isRag(item) and isDirtyRag(item) then dirtyCount = dirtyCount + 1 end
    end
    if dirtyCount > 0 then
        -- Water cost: 0.1 settler-days per rag, capped at 5 rags per tick.
        local batch    = math.min(dirtyCount, 5)
        local cost     = batch * 0.1
        if debitWater(rec, cost) then
            Bastion.addLog(rec,
                string.format("%s washed %d dirty rag%s.",
                    settler.name, batch, batch ~= 1 and "s" or ""),
                "standard")
            acted = true
        else
            Bastion.addLog(rec,
                settler.name .. " couldn't wash rags — settler water supply too low.",
                "warning")
        end
    end

    -- Step 2: Pick thread from clean rags up to the cap.
    if curThread >= maxThread then
        Bastion.addLog(rec,
            settler.name .. " — thread stock is at cap ("
            .. maxThread .. "). No rags consumed.",
            "standard")
        return
    end

    -- Count clean rags available
    local cleanRags = 0
    for _, item in ipairs(storage.general) do
        if isRag(item) and not isDirtyRag(item) then cleanRags = cleanRags + 1 end
    end

    -- Produce up to skillLevel threads per tick from clean rags
    local canProduce = math.min(cleanRags, settler.skillLevel, maxThread - curThread)
    if canProduce > 0 then
        local added = Bastion.addVirtualYield(rec, "thread", canProduce, maxThread)
        if added > 0 then
            Bastion.addLog(rec,
                string.format("%s picked %d thread. Stock: %d/%d.",
                    settler.name, added, curThread + added, maxThread),
                "standard")
            acted = true
        end
    elseif cleanRags == 0 then
        Bastion.addLog(rec, settler.name .. " found no clean rags to pick thread from.", "warning")
    end

    if not acted and dirtyCount == 0 and cleanRags == 0 then
        Bastion.addLog(rec, settler.name .. " had nothing to do today.", "standard")
    end
end

-- ── Doctor ────────────────────────────────────────────────────────────────────
-- Boils clean rags into sterilized bandages up to maxBandages.
-- Requires settler water + a heat source in the bastion.

ROLE_TICKS.Doctor = function(settler, rec, storage)
    local maxBandages = Bastion.getSetting(rec, "Doctor", "maxBandages") or 20
    local curBandages = (rec.virtualYield or {}).bandages or 0
    rec.doctorActive  = true

    if curBandages >= maxBandages then
        Bastion.addLog(rec,
            settler.name .. " — bandage stock is at cap (" .. maxBandages .. ").",
            "standard")
        return
    end

    -- Requires a heat source (cached)
    if not rec.cachedHeatSource then
        Bastion.addLog(rec,
            settler.name .. " can't sterilize bandages — no heat source in the bastion.",
            "warning")
        return
    end

    -- Count clean rags
    local cleanRags = 0
    for _, item in ipairs(storage.general) do
        if isRag(item) and not isDirtyRag(item) then cleanRags = cleanRags + 1 end
    end
    if cleanRags == 0 then
        Bastion.addLog(rec, settler.name .. " found no clean rags to sterilize.", "warning")
        return
    end

    -- Each bandage costs 1 rag + a small water draw (boiling)
    local canMake  = math.min(cleanRags, maxBandages - curBandages, settler.skillLevel + 1)
    local waterCost = canMake * 0.15   -- 0.15 settler-days of water per bandage
    if not debitWater(rec, waterCost) then
        -- Try to make fewer with available water
        local pool    = rec.settlerWaterPool or 0
        canMake       = math.floor(pool / 0.15)
        waterCost     = canMake * 0.15
        if canMake <= 0 then
            Bastion.addLog(rec,
                settler.name .. " couldn't sterilize — settler water supply too low.",
                "warning")
            return
        end
        debitWater(rec, waterCost)
    end

    local added = Bastion.addVirtualYield(rec, "bandages", canMake, maxBandages)
    if added > 0 then
        Bastion.addLog(rec,
            string.format("%s sterilized %d bandage%s. Stock: %d/%d.",
                settler.name, added, added ~= 1 and "s" or "",
                curBandages + added, maxBandages),
            "standard")
    end
end

-- ── Cook ──────────────────────────────────────────────────────────────────────
-- Prepares meals from food in storage. Prioritizes perishables.
-- Respects allowDryGoods setting — never touches non-perishable reserves
-- unless explicitly allowed.

ROLE_TICKS.Cook = function(settler, rec, storage)
    local settingMeals = Bastion.getSetting(rec, "Cook", "mealsPerDay") or 0
    local allowDry     = Bastion.getSetting(rec, "Cook", "allowDryGoods") or false
    local count        = #(rec.settlers or {})
    local targetMeals  = settingMeals > 0 and settingMeals or (count + 1)

    -- Gather candidate food items
    local perishable = {}
    local dryGoods   = {}
    local allItems   = {}
    for _, item in ipairs(storage.general)      do table.insert(allItems, item) end
    for _, item in ipairs(storage.refrigerated) do table.insert(allItems, item) end

    for _, item in ipairs(allItems) do
        if isFood(item) then
            if isPerishable(item) then
                table.insert(perishable, item)
            else
                table.insert(dryGoods, item)
            end
        end
    end

    local pool = {}
    for _, item in ipairs(perishable) do table.insert(pool, item) end
    if allowDry then
        for _, item in ipairs(dryGoods)  do table.insert(pool, item) end
    end

    if #pool == 0 then
        Bastion.addLog(rec,
            settler.name .. " found nothing suitable to cook"
            .. (allowDry and "" or " (dry goods excluded by setting)") .. ".",
            "warning")
        return
    end

    local mealsMade = math.min(targetMeals, #pool, settler.skillLevel + 1)
    local fromPerish = math.min(mealsMade, #perishable)

    rec.cookActive = true
    Bastion.addVirtualYield(rec, "meals", mealsMade)
    Bastion.addLog(rec,
        string.format("%s prepared %d meal%s (%d from perishables).",
            settler.name, mealsMade, mealsMade ~= 1 and "s" or "", fromPerish),
        "standard")
end

-- ── Farmer ───────────────────────────────────────────────────────────────────
-- Waters and tends crops. Costs settler water. Saves a seed portion
-- before reporting yield.

ROLE_TICKS.Farmer = function(settler, rec, storage)
    local saveSeeds = Bastion.getSetting(rec, "Farmer", "saveSeeds")
    if saveSeeds == nil then saveSeeds = true end

    -- Water cost: 1.0 settler-day per tick (watering crops)
    if not debitWater(rec, 1.0) then
        Bastion.addLog(rec,
            settler.name .. " couldn't water crops — settler water supply too low.",
            "warning")
        return
    end

    local produce = ZombRand(settler.skillLevel * 2) + 1

    if saveSeeds then
        local seeds = math.max(1, math.floor(produce * 0.15))
        rec.virtualYield               = rec.virtualYield or {}
        rec.virtualYield.savedSeeds    = (rec.virtualYield.savedSeeds or 0) + seeds
        Bastion.addLog(rec,
            string.format("%s tended crops, harvested %d item%s (%d seed%s set aside).",
                settler.name, produce, produce ~= 1 and "s" or "",
                seeds, seeds ~= 1 and "s" or ""),
            "standard")
    else
        Bastion.addLog(rec,
            string.format("%s tended and harvested %d crop item%s.",
                settler.name, produce, produce ~= 1 and "s" or ""),
            "standard")
    end
end

-- ── Woodcutter ────────────────────────────────────────────────────────────────
-- Chops logs into planks up to maxPlanks.
-- If keepFiresLit, maintains campfire/stove fuel stock.

ROLE_TICKS.Woodcutter = function(settler, rec, storage)
    local maxPlanks    = Bastion.getSetting(rec, "Woodcutter", "maxPlanks") or 60
    local keepFires    = Bastion.getSetting(rec, "Woodcutter", "keepFiresLit")
    if keepFires == nil then keepFires = true end

    local hasAxe  = false
    local logCount = 0

    for _, item in ipairs(storage.general) do
        local ok, t = pcall(function() return item:getType() end)
        if ok and type(t) == "string" then
            local tl = t:lower()
            if tl:find("axe") or tl == "handaxe" then hasAxe = true end
            if tl == "log" or tl == "treelog"     then logCount = logCount + 1 end
        end
    end

    if not hasAxe then
        Bastion.addLog(rec,
            settler.name .. " couldn't work — no axe in shared storage.", "warning")
        return
    end

    local curPlanks = (rec.virtualYield or {}).planks or 0
    local planksNeeded = math.max(0, maxPlanks - curPlanks)

    if planksNeeded == 0 then
        Bastion.addLog(rec,
            settler.name .. " — plank stock at cap (" .. maxPlanks .. ").", "standard")
    elseif logCount == 0 then
        Bastion.addLog(rec,
            settler.name .. " found no logs to chop.", "warning")
    else
        -- Each log yields 4 planks; settler chops up to skillLevel logs
        local logsToChop  = math.min(logCount, settler.skillLevel,
                                     math.ceil(planksNeeded / 4))
        local planksFrom  = logsToChop * 4
        local added       = Bastion.addVirtualYield(rec, "planks", planksFrom, maxPlanks)
        Bastion.addLog(rec,
            string.format("%s chopped %d log%s → %d planks. Stock: %d/%d.",
                settler.name, logsToChop, logsToChop ~= 1 and "s" or "",
                added, curPlanks + added, maxPlanks),
            "standard")
    end

    -- Keep fires lit
    if keepFires and rec.cachedHeatSource then
        local firewoodAdded = Bastion.addVirtualYield(rec, "firewood", settler.skillLevel)
        if firewoodAdded > 0 then
            Bastion.addLog(rec,
                settler.name .. " kept the fires stocked.", "standard")
        end
    end
end

-- ── WaterCarrier ──────────────────────────────────────────────────────────────
-- Collects and boils water, adding to the settler-managed water pool.
-- Requires: a water source nearby + a heat source in bastion + a pot.

ROLE_TICKS.WaterCarrier = function(settler, rec, storage)
    if not rec.cachedWaterSource then
        Bastion.addLog(rec,
            settler.name .. " couldn't collect water — no water source found nearby.",
            "warning")
        return
    end
    if not rec.cachedHeatSource then
        Bastion.addLog(rec,
            settler.name .. " can't boil water — no heat source (campfire/stove) in bastion.",
            "warning")
        return
    end
    if not hasPot(storage) then
        Bastion.addLog(rec,
            settler.name .. " has no pot in shared storage to boil water.",
            "warning")
        return
    end

    -- Pool is full
    if (rec.settlerWaterPool or 0) >= Bastion.WATER_POOL_MAX then
        Bastion.addLog(rec,
            settler.name .. " — water pool is full (" .. Bastion.WATER_POOL_MAX .. " days).",
            "standard")
        return
    end

    -- Produce water: base + skill bonus
    local produced = Bastion.WATER_PER_CARRIER_TICK
                   + (settler.skillLevel - 1) * Bastion.WATER_CARRIER_SKILL_MOD
    produced = math.floor(produced * 10) / 10

    local before = rec.settlerWaterPool or 0
    addSettlerWater(rec, produced)
    local after = rec.settlerWaterPool or 0
    local actual = math.floor((after - before) * 10) / 10

    Bastion.addLog(rec,
        string.format("%s collected and boiled water. +%.1f days to pool (%.1f / %.1f).",
            settler.name, actual, after, Bastion.WATER_POOL_MAX),
        "standard")
end

-- ── Blacksmith ────────────────────────────────────────────────────────────────
-- Smelts scrap metal into ingots. Never touches the scrapFloor reserve.
-- Does NOT run the spoon grind — that is the player's domain for skill XP.

ROLE_TICKS.Blacksmith = function(settler, rec, storage)
    local maxIngots  = Bastion.getSetting(rec, "Blacksmith", "maxIngots")  or 20
    local scrapFloor = Bastion.getSetting(rec, "Blacksmith", "scrapFloor") or Bastion.SCRAP_FLOOR
    local curIngots  = (rec.virtualYield or {}).ingots or 0

    if curIngots >= maxIngots then
        Bastion.addLog(rec,
            settler.name .. " — ingot stock at cap (" .. maxIngots .. "). No scrap smelted.",
            "standard")
        return
    end

    if not rec.cachedHeatSource then
        Bastion.addLog(rec,
            settler.name .. " can't smelt — no heat source (forge/campfire) in bastion.",
            "warning")
        return
    end

    -- Count scrap available above floor
    local scrapCount = 0
    for _, item in ipairs(storage.general) do
        if isScrap(item) then scrapCount = scrapCount + 1 end
    end

    local usable = math.max(0, scrapCount - scrapFloor)
    if usable < Bastion.SCRAP_PER_INGOT then
        Bastion.addLog(rec,
            string.format("%s: not enough scrap above floor to smelt "
                .. "(have %d usable, need %d per ingot; floor=%d).",
                settler.name, usable, Bastion.SCRAP_PER_INGOT, scrapFloor),
            "warning")
        return
    end

    -- Throughput: settler.skillLevel ingots per tick
    local canMake = math.min(
        math.floor(usable / Bastion.SCRAP_PER_INGOT),
        settler.skillLevel,
        maxIngots - curIngots)

    local added = Bastion.addVirtualYield(rec, "ingots", canMake, maxIngots)
    Bastion.addLog(rec,
        string.format("%s smelted %d ingot%s from scrap. Stock: %d/%d.",
            settler.name, added, added ~= 1 and "s" or "",
            curIngots + added, maxIngots),
        "standard")
end

-- ── Rancher ───────────────────────────────────────────────────────────────────
-- Feeds and tends animals within SCAN_RANGE.
-- Requires animals detected nearby (cachedHasAnimals).

ROLE_TICKS.Rancher = function(settler, rec, storage)
    if not rec.cachedHasAnimals then
        Bastion.addLog(rec,
            settler.name .. " — no animals detected near the bastion.", "warning")
        return
    end

    local minGrain = Bastion.getSetting(rec, "Rancher", "minGrainReserve") or 10

    -- Check for feed in storage
    local feedCount = 0
    for _, item in ipairs(storage.general) do
        local ok, t = pcall(function() return item:getType() end)
        if ok and type(t) == "string" then
            local tl = t:lower()
            if tl:find("grain") or tl:find("corn") or tl:find("hay")
            or tl:find("seed") then
                feedCount = feedCount + 1
            end
        end
    end

    if feedCount <= minGrain then
        Bastion.addLog(rec,
            string.format("%s couldn't feed animals — feed stock too low "
                .. "(have %d, floor=%d).", settler.name, feedCount, minGrain),
            "warning")
        return
    end

    -- Produce based on skill: eggs, milk (abstract yield)
    local eggYield  = settler.skillLevel >= 2 and ZombRand(settler.skillLevel) + 1 or 0
    local milkYield = settler.skillLevel >= 3 and ZombRand(2) + 1 or 0

    if eggYield  > 0 then Bastion.addVirtualYield(rec, "eggs",  eggYield)  end
    if milkYield > 0 then Bastion.addVirtualYield(rec, "milk",  milkYield) end

    rec.virtualYield = rec.virtualYield or {}

    Bastion.addLog(rec,
        string.format("%s fed and tended the animals.%s%s",
            settler.name,
            eggYield  > 0 and ("  +" .. eggYield  .. " egg" .. (eggYield ~= 1 and "s" or "")) or "",
            milkYield > 0 and ("  +" .. milkYield .. " milk unit" .. (milkYield ~= 1 and "s" or "")) or ""),
        "standard")
end

-- ── Remaining existing roles ──────────────────────────────────────────────────

ROLE_TICKS.Farmer_old = nil  -- replaced above

ROLE_TICKS.Teacher = function(settler, rec, storage)
    rec.teacherActive = true
    rec.education     = (rec.education or 0) + 1
    Bastion.addLog(rec, settler.name .. " held a lesson. Reading speed enhanced today.", "standard")
end

ROLE_TICKS.Mechanic = function(settler, rec, storage)
    -- Generator refueling (Mechanics level 1+): check fuel in storage.
    local hasFuel = false
    for _, item in ipairs(storage.general) do
        local ok, t = pcall(function() return item:getType() end)
        if ok and type(t) == "string" then
            local tl = t:lower()
            if tl:find("gascan") or tl:find("petrol") or tl:find("fuel") then
                hasFuel = true; break
            end
        end
    end
    if hasFuel then
        Bastion.addLog(rec, settler.name .. " refueled the generator.", "standard")
    else
        Bastion.addLog(rec, settler.name .. " checked the generator — no fuel in storage.", "warning")
    end

    -- Vehicle maintenance (Mechanics 3+)
    if settler.skillLevel >= 3 then
        local fuelOnly = Bastion.getSetting(rec, "Mechanic", "fuelOnly") or false
        if not fuelOnly then
            local hasParts = false
            for _, item in ipairs(storage.general) do
                local ok, t = pcall(function() return item:getType() end)
                if ok and type(t) == "string" then
                    local tl = t:lower()
                    if tl:find("tire") or tl:find("tyre") or tl:find("carbattery")
                    or tl:find("oilcan") or tl:find("brakepad") then
                        hasParts = true; break
                    end
                end
            end
            if hasParts then
                Bastion.addLog(rec,
                    settler.name .. " serviced the vehicles within the compound.", "standard")
            else
                Bastion.addLog(rec,
                    settler.name .. " checked vehicles — no spare parts in storage.", "warning")
            end
        end
    end
end

ROLE_TICKS.Trapper = function(settler, rec, storage)
    -- Phase 1: abstract yield. Phase 2: scan for actual IsoTrap objects.
    local hasBait = false
    for _, item in ipairs(storage.general) do
        local ok, t = pcall(function() return item:getType() end)
        if ok and type(t) == "string" then
            local tl = t:lower()
            if tl == "worms" or tl:find("bait") or tl == "corn" or tl == "maize" then
                hasBait = true; break
            end
        end
    end
    if not hasBait then
        Bastion.addLog(rec,
            settler.name .. " checked the traps but had no bait to reset them.", "warning")
        return
    end
    local caught = ZombRand(settler.skillLevel + 1)
    if caught > 0 then
        Bastion.addVirtualYield(rec, "meat", caught)
        Bastion.addLog(rec,
            settler.name .. " checked the traps. Catch: " .. caught .. " item"
            .. (caught ~= 1 and "s" or "") .. ".", "standard")
    else
        Bastion.addLog(rec, settler.name .. " checked the traps — nothing caught today.", "standard")
    end
end

ROLE_TICKS.Fisher = function(settler, rec, storage)
    -- Requires fishing line and bait in shared storage.
    local hasBait = false
    local hasLine = false
    for _, item in ipairs(storage.general) do
        local ok, t = pcall(function() return item:getType() end)
        if ok and type(t) == "string" then
            local tl = t:lower()
            if tl == "worms" or tl == "crickets" or tl:find("bait") or tl:find("lure") then
                hasBait = true
            end
            if tl:find("fishingline") or tl:find("string") then
                hasLine = true
            end
        end
    end

    if not hasBait or not hasLine then
        Bastion.addLog(rec,
            settler.name .. " couldn't fish — missing "
            .. (not hasBait and "bait" or "")
            .. (not hasBait and not hasLine and " and " or "")
            .. (not hasLine and "fishing line" or "")
            .. " in shared storage.",
            "warning")
        return
    end

    local maxFish = Bastion.getSetting(rec, "Fisher", "maxFishStock") or 30
    local caught  = ZombRand(settler.skillLevel * 2) + 1
    local added   = Bastion.addVirtualYield(rec, "fish", caught, maxFish)

    if added > 0 then
        Bastion.addLog(rec,
            string.format("%s fished and caught %d. Stock: %d/%d.",
                settler.name, added, (rec.virtualYield.fish or 0), maxFish),
            "standard")
    else
        Bastion.addLog(rec,
            settler.name .. " fished — but the stock is already full.", "standard")
    end
end

ROLE_TICKS.Forager = function(settler, rec, storage)
    Bastion.addLog(rec, settler.name .. " foraged in the surrounding area.", "standard")
end

ROLE_TICKS.Defender = function(settler, rec, storage)
    rec.resolve = math.min(100, (rec.resolve or 50) + 1)
    Bastion.addLog(rec, settler.name .. " patrolled the perimeter.", "standard")
end

ROLE_TICKS.Hunter = function(settler, rec, storage)
    local caught = ZombRand(settler.skillLevel) + 1
    Bastion.addVirtualYield(rec, "meat", caught)
    Bastion.addLog(rec,
        settler.name .. " went hunting. Returned with " .. caught .. " item"
        .. (caught ~= 1 and "s" or "") .. ".", "standard")
end

ROLE_TICKS.Child = function(settler, rec, storage)
    rec.resolve = math.min(100, (rec.resolve or 50) + 1)
    -- Children don't consume resources; they quietly lift morale.
end

local function defaultRoleTick(settler, rec, storage)
    Bastion.addLog(rec,
        string.format("%s (%s) worked today.", settler.name, settler.role),
        "standard")
end

-- ── Settlement tick ───────────────────────────────────────────────────────────

local function runSettlementTick(username, rec)
    print("[Bastion] Running tick for " .. username)

    rec.settlers      = rec.settlers     or {}
    rec.virtualYield  = rec.virtualYield or {}
    rec.cookActive    = false
    rec.doctorActive  = false
    rec.teacherActive = false

    -- Refresh world-state cache every WATER_SOURCE_CACHE_DAYS
    local today = Bastion.getCurrentDay()
    if not rec.lastSourceCheck
    or (today - (rec.lastSourceCheck or 0)) >= Bastion.WATER_SOURCE_CACHE_DAYS then
        rec.cachedWaterSource = hasWaterSource(rec)
        rec.cachedHeatSource  = hasHeatSource(rec)
        rec.cachedHasAnimals  = hasAnimals(rec)
        rec.lastSourceCheck   = today
        print(string.format("[Bastion] Cache refresh: waterSource=%s heatSource=%s animals=%s",
            tostring(rec.cachedWaterSource),
            tostring(rec.cachedHeatSource),
            tostring(rec.cachedHasAnimals)))
    end

    -- Compute noise budget
    local budgetLevel = rec.noiseBudgetLevel or "Normal"
    local budget      = Bastion.NOISE_BUDGETS[budgetLevel] or 6
    local noiseUsed   = 1  -- baseline

    -- Scan community storage (shared across all role ticks this turn)
    local storage = scanContainers(rec)

    -- Run each settler's role tick
    for _, settler in ipairs(rec.settlers) do
        local roleDef = Bastion.ROLES[settler.role]
        if not roleDef then
            defaultRoleTick(settler, rec, storage)
        elseif settler.mood == "Critical" then
            Bastion.addLog(rec,
                settler.name .. " is struggling. They didn't contribute today.",
                "warning")
        else
            local roleNoise = roleDef.noise or 0
            if roleNoise > 0 and (noiseUsed + roleNoise) > budget then
                Bastion.addLog(rec,
                    string.format("[QUIET MODE] %s's work (%s) skipped — noise budget exceeded.",
                        settler.name, settler.role),
                    "warning")
            else
                noiseUsed = noiseUsed + roleNoise
                local tickFn = ROLE_TICKS[settler.role] or defaultRoleTick
                tickFn(settler, rec, storage)
            end
        end
    end

    rec.noiseScore  = noiseUsed
    rec.noiseBudget = budget

    -- Update resource estimates (waterDays now includes settlerWaterPool)
    estimateResources(rec, storage)

    -- Shortage warnings (check against total waterDays which includes pool)
    if (rec.foodDays or 0) < 3 and #rec.settlers > 0 then
        Bastion.addLog(rec,
            string.format("Food supply is running low (%.1f days remaining).", rec.foodDays),
            "warning")
    end
    if (rec.waterDays or 0) < 2 and #rec.settlers > 0 then
        Bastion.addLog(rec,
            string.format("Water critically low (%.1f days total — pool: %.1f).",
                rec.waterDays, rec.settlerWaterPool or 0),
            "critical")
    end

    rec.lastTickDay = today
end

-- ── Daily tick check ──────────────────────────────────────────────────────────

local function onEveryOneMinute()
    local today = Bastion.getCurrentDay()
    local wd    = getWorldData()
    local dirty = false

    for username, rec in pairs(wd) do
        if type(rec) == "table" and rec.bx then
            if today > (rec.lastTickDay or -1) then
                runSettlementTick(username, rec)
                dirty = true
            end
        end
    end

    if dirty then ModData.transmit(Bastion.DATA_KEY) end
end

-- ── Client command handler ────────────────────────────────────────────────────

local function onClientCommand(module, command, player, args)
    if module ~= Bastion.MOD_KEY then return end

    local username = player:getUsername()

    -- ── EstablishBastion ──────────────────────────────────────────────────────
    if command == "EstablishBastion" then
        if getRecord(username) then
            print("[Bastion] EstablishBastion ignored — already has one")
            return
        end

        local bx = args.bx or 0
        local by = args.by or 0
        local bz = args.bz or 0

        -- Deep-copy defaults so each settlement has independent settings
        local roleSettings = {}
        for role, defaults in pairs(Bastion.ROLE_SETTINGS_DEFAULTS) do
            roleSettings[role] = {}
            for k, v in pairs(defaults) do roleSettings[role][k] = v end
        end

        local rec = {
            bx               = bx, by = by, bz = bz,
            settlers         = {},
            settlementLog    = {},
            privateContainers = {},
            foodDays         = 0,
            waterDays        = 0,
            settlerWaterPool = 0,
            virtualYield     = {},
            noiseScore       = 1,
            noiseBudget      = 6,
            noiseBudgetLevel = "Normal",
            happiness        = 50,
            resolve          = 50,
            education        = 0,
            cookActive       = false,
            doctorActive     = false,
            teacherActive    = false,
            roleSettings     = roleSettings,
            -- World-state cache (populated on first tick)
            cachedWaterSource = false,
            cachedHeatSource  = false,
            cachedHasAnimals  = false,
            lastSourceCheck   = -99,
            lastTickDay       = Bastion.getCurrentDay(),
        }

        local npc  = Bastion.generateNPC({})
        local role = Bastion.pickRandom(Bastion.STARTER_ROLES)
        local sx, sy, sz = findSpawnSquare(bx, by, bz, 1)

        local settler = {
            id            = generateSettlerID(),
            name          = npc.name,
            isMale        = npc.isMale,
            role          = role,
            skillLevel    = npc.skillLevel,
            traitTag      = npc.traitTag,
            backstory     = npc.backstory,
            mood          = "Content",
            x             = sx, y = sy, z = sz,
            ownerUsername = username,
        }
        table.insert(rec.settlers, settler)
        spawnSettlerMannequin(settler)

        Bastion.addLog(rec,
            string.format("A survivor arrived: %s (%s, skill %d). %s. They seem %s.",
                settler.name, settler.role, settler.skillLevel,
                settler.backstory, settler.traitTag:lower()),
            "arrival")

        saveRecord(username, rec)
        print("[Bastion] Bastion established for " .. username)

    -- ── CollapseBastion ───────────────────────────────────────────────────────
    elseif command == "CollapseBastion" then
        local rec = getRecord(username)
        if not rec then return end
        removeAllSettlerMannequins(rec)
        clearRecord(username)
        print("[Bastion] Bastion collapsed for " .. username)

    -- ── MarkPrivate ───────────────────────────────────────────────────────────
    elseif command == "MarkPrivate" then
        local rec = getRecord(username)
        if not rec then return end
        local key = args.key
        if not key then return end

        rec.privateContainers = rec.privateContainers or {}
        if rec.privateContainers[key] then
            rec.privateContainers[key] = nil
            Bastion.addLog(rec, "A container was marked as shared.", "standard")
        else
            rec.privateContainers[key] = true
            Bastion.addLog(rec, "A container was marked as private.", "standard")
        end
        saveRecord(username, rec)

    -- ── SetNoiseBudget ────────────────────────────────────────────────────────
    elseif command == "SetNoiseBudget" then
        local rec = getRecord(username)
        if not rec then return end
        local level = args.level
        if not Bastion.NOISE_BUDGETS[level] then return end

        rec.noiseBudgetLevel = level
        rec.noiseBudget      = Bastion.NOISE_BUDGETS[level]
        Bastion.addLog(rec,
            "Noise budget set to " .. level .. " (max " .. rec.noiseBudget .. ").",
            "standard")
        saveRecord(username, rec)

    -- ── SetRoleSetting ────────────────────────────────────────────────────────
    elseif command == "SetRoleSetting" then
        local rec = getRecord(username)
        if not rec then return end
        local role = args.role
        local key  = args.key
        local val  = args.val
        if not role or not key or val == nil then return end
        -- Validate the key exists in defaults to prevent arbitrary data injection
        local defaults = Bastion.ROLE_SETTINGS_DEFAULTS[role]
        if not defaults or defaults[key] == nil then
            print("[Bastion] SetRoleSetting: unknown role/key " .. tostring(role) .. "/" .. tostring(key))
            return
        end
        rec.roleSettings         = rec.roleSettings or {}
        rec.roleSettings[role]   = rec.roleSettings[role] or {}
        rec.roleSettings[role][key] = val
        Bastion.addLog(rec,
            string.format("Setting changed: %s.%s = %s", role, key, tostring(val)),
            "standard")
        saveRecord(username, rec)

    -- ── AdminCmd ──────────────────────────────────────────────────────────────
    elseif command == "AdminCmd" then
        local accessLevel = player:getAccessLevel()
        if accessLevel ~= "Admin" and accessLevel ~= "Moderator" then
            print("[Bastion] AdminCmd rejected — " .. username
                  .. " has access level '" .. (accessLevel or "") .. "'")
            return
        end

        local raw   = args.raw or ""
        local parts = {}
        for word in raw:gmatch("%S+") do table.insert(parts, word) end
        local sub = parts[2] and parts[2]:lower() or "help"

        if sub == "help" then
            print("[Bastion] Admin commands:")
            print("  /bastion status            — settlement status")
            print("  /bastion tick              — force tick on next minute")
            print("  /bastion reset [username]  — collapse a player's bastion")
            print("  /bastion addlog <text>     — append a log entry")

        elseif sub == "status" then
            local rec = getRecord(username)
            if rec then
                print(string.format(
                    "[Bastion] %s: %d settlers | food=%.1f d | water=%.1f d (pool=%.1f) | noise=%d/%d",
                    username, #(rec.settlers or {}),
                    rec.foodDays or 0, rec.waterDays or 0,
                    rec.settlerWaterPool or 0,
                    rec.noiseScore or 0, rec.noiseBudget or 6))
            else
                print("[Bastion] No bastion for " .. username)
            end

        elseif sub == "tick" then
            local rec = getRecord(username)
            if rec then
                rec.lastTickDay = -1
                saveRecord(username, rec)
                print("[Bastion] Tick forced for " .. username)
            end

        elseif sub == "reset" then
            local target = parts[3] or username
            local wd     = getWorldData()
            local rec    = wd[target]
            if rec then
                removeAllSettlerMannequins(rec)
                wd[target] = nil
                ModData.transmit(Bastion.DATA_KEY)
                print("[Bastion] Bastion reset for " .. target)
            else
                print("[Bastion] No bastion for " .. target)
            end

        elseif sub == "addlog" then
            local rec  = getRecord(username)
            local text = raw:match("^%S+%s+%S+%s+(.+)$") or ""
            if rec and text ~= "" then
                Bastion.addLog(rec, "[Admin] " .. text, "milestone")
                saveRecord(username, rec)
                print("[Bastion] Log entry added for " .. username)
            end

        else
            print("[Bastion] Unknown subcommand. Type /bastion help.")
        end
    end
end

-- ── Event registration ────────────────────────────────────────────────────────

Events.OnClientCommand.Add(onClientCommand)
Events.EveryOneMinute.Add(onEveryOneMinute)

print("[Bastion] Server done")
