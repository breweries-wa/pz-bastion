-- ============================================================
-- Bastion_MaeServer.lua  (media/lua/server/)
-- Server-side only.  Works in singleplayer and multiplayer.
--
-- Core systems:
--   • Settlement tick — four phases (Consumption → Queue → Work Units → Execution)
--   • Container scanning + resource estimation
--   • Settler-managed water pool
--   • Client command dispatch (EstablishBastion, CollapseBastion,
--     MarkPrivate, SetNoiseBudget, SetRoleSetting,
--     ForceTick, AddSettler, AdminCmd)
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

-- Returns a storage table with:
--   .general / .refrigerated / .frozen  — flat item arrays (for predicate loops)
--   .itemMap  — { item_userdata → container }  (for removeItem)
--   .allContainers — ordered list of containers  (for addItemToStorage)
--   .capacity — { general, refrigerated, frozen }
--   .weight   — { current, max }
local function scanContainers(rec)
    local cell = getCell()
    if not cell then
        return {
            general={}, refrigerated={}, frozen={},
            capacity={ general=0, refrigerated=0, frozen=0 },
            itemMap={}, allContainers={},
            weight={ current=0, max=0 },
        }
    end

    local result = {
        general      = {},
        refrigerated = {},
        frozen       = {},
        capacity     = { general=0, refrigerated=0, frozen=0 },
        itemMap      = {},
        allContainers = {},
        weight       = { current=0, max=0 },
    }

    local bx, by = rec.bx, rec.by
    local r = Bastion.SCAN_RANGE

    for z = 0, Bastion.MAX_FLOOR do
    for x = bx - r, bx + r do
        for y = by - r, by + r do
            local sq = cell:getGridSquare(x, y, z)
            if sq then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local obj = objs:get(i)
                    if obj and obj.getContainer then
                        local container = obj:getContainer()
                        if container then
                            local key = x .. "," .. y .. "," .. z
                            local isPrivate = rec.privateContainers
                                           and rec.privateContainers[key]
                            if not isPrivate then
                                local cat = getContainerCategory(obj)

                                -- Track container for item addition
                                table.insert(result.allContainers, container)

                                -- Capacity (used for weight.max)
                                local ok_cap, cap = pcall(function()
                                    return container:getCapacity()
                                end)
                                if ok_cap and type(cap) == "number" then
                                    result.capacity[cat] = result.capacity[cat] + cap
                                    result.weight.max    = result.weight.max + cap
                                end

                                local items = container:getItems()
                                for j = 0, items:size() - 1 do
                                    local item = items:get(j)
                                    if item then
                                        table.insert(result[cat], item)
                                        result.itemMap[item] = container

                                        local ok_w, w = pcall(function()
                                            return item:getWeight()
                                        end)
                                        if ok_w and type(w) == "number" then
                                            result.weight.current = result.weight.current + w
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end end  -- z loop
    return result
end

-- ── Resource estimation (display-only; called after the tick) ─────────────────

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
    local foodItemCount = 0

    local allItems = {}
    for _, item in ipairs(storage.general)      do table.insert(allItems, item) end
    for _, item in ipairs(storage.refrigerated) do table.insert(allItems, item) end
    for _, item in ipairs(storage.frozen)       do table.insert(allItems, item) end

    for _, item in ipairs(allItems) do
        if isFood(item) then
            totalCalories = totalCalories + 500
            foodItemCount = foodItemCount + 1
        end
        totalWater = totalWater + getWaterUnits(item)
    end

    local caloriesPerDay = count * Bastion.CALORIES_PER_SETTLER_PER_DAY
    local waterPerDay    = count * Bastion.WATER_PER_SETTLER_PER_DAY

    rec.foodDays  = caloriesPerDay > 0
        and math.floor(totalCalories / caloriesPerDay * 10) / 10 or 0
    local actualWaterDays = waterPerDay > 0
        and math.floor(totalWater / waterPerDay * 10) / 10 or 0
    rec.waterDays = actualWaterDays + (rec.settlerWaterPool or 0)

    rec.storageCapacity = {
        general      = storage.capacity.general,
        refrigerated = storage.capacity.refrigerated,
        frozen       = storage.capacity.frozen,
    }
    rec.storedFoodItems      = foodItemCount
    rec.storedWaterUnits     = math.floor(totalWater * 10) / 10
    rec.storageWeightCurrent = math.floor(storage.weight.current * 10) / 10
    rec.storageWeightMax     = math.floor(storage.weight.max * 10) / 10
end

-- ── Water pool helpers ────────────────────────────────────────────────────────

local function debitWater(rec, amount)
    local pool = rec.settlerWaterPool or 0
    if pool < amount then return false end
    rec.settlerWaterPool = math.max(0, pool - amount)
    return true
end

local function addSettlerWater(rec, amount)
    local current = rec.settlerWaterPool or 0
    rec.settlerWaterPool = math.min(current + amount, Bastion.WATER_POOL_MAX)
end

-- ── World-state scanning (cached per N in-game days) ─────────────────────────

local function hasWaterSource(rec)
    local cell = getCell()
    if not cell then return false end

    local r    = Bastion.getSetting(rec, "WaterCarrier", "collectRadius") or 50
    local step = Bastion.WATER_SOURCE_SCAN_STEP
    local bx, by = rec.bx, rec.by

    for z = 0, Bastion.MAX_FLOOR do
    for x = bx - r, bx + r, step do
        for y = by - r, by + r, step do
            local sq = cell:getGridSquare(x, y, z)
            if sq then
                local objs = sq:getObjects()
                if objs then
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        if obj then
                            local ok, spr = pcall(function() return obj:getSprite() end)
                            if ok and spr then
                                local ok2, n = pcall(function() return spr:getName() end)
                                if ok2 and type(n) == "string" then
                                    local nl = n:lower()
                                    if nl:find("rain") or nl:find("barrel") or nl:find("well") then
                                        return true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end end  -- z loop
    return false
end

local function hasHeatSource(rec)
    local cell = getCell()
    if not cell then return false end
    local r = Bastion.SCAN_RANGE
    local bx, by = rec.bx, rec.by

    for z = 0, Bastion.MAX_FLOOR do
    for x = bx - r, bx + r do
        for y = by - r, by + r do
            local sq = cell:getGridSquare(x, y, z)
            if sq and sq:getRoom() then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local obj = objs:get(i)

                    local ok, isCamp = pcall(function()
                        return instanceof(obj, "IsoCampfire")
                    end)
                    if ok and isCamp then return true end

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
    end end  -- z loop
    return false
end

local function hasAnimals(rec)
    local cell = getCell()
    if not cell then return false end
    local r = Bastion.SCAN_RANGE
    local bx, by = rec.bx, rec.by

    -- Animals are always on z=0 (ground); no need to scan upper floors
    for x = bx - r, bx + r do
        for y = by - r, by + r do
            local sq = cell:getGridSquare(x, y, 0)
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

-- ── Item-type predicate helpers ───────────────────────────────────────────────

local function itemType(item)
    local ok, t = pcall(function() return item:getType() end)
    if ok and type(t) == "string" then return t:lower() end
    return ""
end

local function isRag(item)
    local t = itemType(item)
    return t == "rag" or t == "rippedsheets" or t == "sheetsmall" or t:find("rag") ~= nil
end

local function isDirtyRag(item)
    local ok, t = pcall(function() return item:getType() end)
    if ok and type(t) == "string" and t:lower():find("dirty") then return true end
    local ok2, b = pcall(function() return item:isBloody() end)
    if ok2 and b then return true end
    return false
end

local function isCleanRag(item)
    return isRag(item) and not isDirtyRag(item)
end

local function isScrap(item)
    local t = itemType(item)
    return t:find("scrap") ~= nil or t == "smallmetal" or t == "metalpipe"
        or t == "metalbar" or t:find("brokenmetaltool") ~= nil
end

local function isPerishable(item)
    if not item then return false end
    local ok, age = pcall(function() return item:getAgeDelta() end)
    if ok and type(age) == "number" and age > 0 then return true end
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

-- Phase 2 predicates: used for consumption checks and cap tracking.

local function isLog(item)
    local t = itemType(item)
    return t == "log" or t == "treelog"
end

local function isAxe(item)
    local t = itemType(item)
    return t:find("axe") ~= nil
end

local function isPlank(item)
    local t = itemType(item)
    return t:find("plank") ~= nil or t:find("woodenboard") ~= nil
end

local function isThread(item)
    local t = itemType(item)
    return t == "thread" or t:find("thread") ~= nil
end

local function isSterileBandage(item)
    local t = itemType(item)
    return t:find("bandagesterile") ~= nil or t:find("sterilisedband") ~= nil
        or t == "bandagesterile"
end

local function isMetalBar(item)
    local t = itemType(item)
    return t == "metalbar" or t == "ironbar" or t:find("metalingot") ~= nil
end

local function isGrainFeed(item)
    local t = itemType(item)
    return t:find("grain") ~= nil or t:find("corn") ~= nil or t:find("hay") ~= nil
        or t:find("seed") ~= nil
end

local function isBait(item)
    local t = itemType(item)
    return t == "worms" or t:find("bait") ~= nil or t == "crickets"
end

local function isFishingLine(item)
    local t = itemType(item)
    return t:find("fishingline") ~= nil or t:find("string") ~= nil
end

local function isFish(item)
    local t = itemType(item)
    -- Match fish items but not fishing line/rod
    return t:find("fish") ~= nil and t:find("line") == nil and t:find("rod") == nil
end

local function isWaterItem(item)
    return getWaterUnits(item) > 0
end

local function isFuel(item)
    local t = itemType(item)
    return t:find("gascan") ~= nil or t:find("petrol") ~= nil or t:find("fuel") ~= nil
end

-- ── Storage manipulation helpers ──────────────────────────────────────────────

-- Count items matching predicate across all categories.
local function countStorageItems(storage, predicate)
    local n = 0
    for _, cat in ipairs({"general", "refrigerated", "frozen"}) do
        for _, item in ipairs(storage[cat]) do
            if predicate(item) then n = n + 1 end
        end
    end
    return n
end

-- Remove one item matching predicate from storage (Java container + Lua array).
-- Tries refrigerated first (perishables most urgent), then general, then frozen.
-- Returns true on success.
local function removeItem(storage, predicate)
    for _, cat in ipairs({"refrigerated", "general", "frozen"}) do
        local lst = storage[cat]
        for i = 1, #lst do
            local item = lst[i]
            if predicate(item) then
                local c = storage.itemMap[item]
                if c then
                    local ok = pcall(function() c:Remove(item) end)
                    if ok then
                        table.remove(lst, i)
                        storage.itemMap[item] = nil
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Remove up to n items matching predicate. Returns count removed.
local function removeItems(storage, predicate, n)
    local removed = 0
    while removed < n do
        if not removeItem(storage, predicate) then break end
        removed = removed + 1
    end
    return removed
end

-- Remove up to n water-bearing items from storage. Returns count removed.
local function consumeWaterItems(storage, n)
    local removed = 0
    for _, cat in ipairs({"general", "refrigerated", "frozen"}) do
        local lst = storage[cat]
        local i   = 1
        while i <= #lst and removed < n do
            local item = lst[i]
            if isWaterItem(item) then
                local c = storage.itemMap[item]
                if c then
                    local ok = pcall(function() c:Remove(item) end)
                    if ok then
                        table.remove(lst, i)
                        storage.itemMap[item] = nil
                        removed = removed + 1
                    else
                        i = i + 1
                    end
                else
                    i = i + 1
                end
            else
                i = i + 1
            end
        end
        if removed >= n then break end
    end
    return removed
end

-- Create one item of typeName and place it into the first available container.
-- Also inserts the item into storage.general so the same-tick count functions
-- see it.  Returns true on success.
local function addItemToStorage(storage, typeName)
    local ok, item = pcall(function()
        return InventoryItemFactory.CreateItem(typeName)
    end)
    if not ok or not item then
        print("[Bastion] addItemToStorage: failed to create '" .. tostring(typeName) .. "'")
        return false
    end
    for _, c in ipairs(storage.allContainers) do
        local ok2 = pcall(function() c:AddItem(item) end)
        if ok2 then
            table.insert(storage.general, item)
            storage.itemMap[item] = c
            return true
        end
    end
    print("[Bastion] addItemToStorage: no container accepted '" .. tostring(typeName) .. "'")
    return false
end

-- ── Bed counting ──────────────────────────────────────────────────────────────

-- Keywords matched against both the sprite name and the display name of each
-- world object.  "bedding" covers sprites like "furniture_bedding_01_54".
-- Double beds span two tiles; each tile counts as one sleep-spot (intentional).
local BED_KEYWORDS = { "bed", "bedding", "cot", "mattress", "bunk" }

local function nameMatchesBed(s)
    if type(s) ~= "string" then return false end
    local sl = s:lower()
    for _, kw in ipairs(BED_KEYWORDS) do
        if sl:find(kw, 1, true) then return true end
    end
    return false
end

-- Collect candidate name strings from a world object without risking uncaught
-- Java exceptions: each call is individually pcall-wrapped so a failure on one
-- method falls through to the next rather than aborting the whole loop.
local function getBedCandidateNames(obj)
    local names = {}
    -- 1. sprite name  (e.g. "furniture_bedding_01_54")
    local ok, spr = pcall(function() return obj:getSprite() end)
    if ok and spr then
        local ok2, n = pcall(function() return spr:getName() end)
        if ok2 then names[#names+1] = n end
        -- some sprites expose the name via tostring
        local ok3, ts = pcall(function() return tostring(spr) end)
        if ok3 then names[#names+1] = ts end
    end
    -- 2. display name (e.g. "Maple Double Bed")
    local ok4, dn = pcall(function() return obj:getName() end)
    if ok4 then names[#names+1] = dn end
    -- 3. object name
    local ok5, on = pcall(function() return obj:getObjectName() end)
    if ok5 then names[#names+1] = on end
    return names
end

local function countBeds(rec)
    local cell = getCell()
    if not cell then print("[Bastion] countBeds: no cell") return 0 end
    local count = 0
    local bx, by = rec.bx, rec.by
    local r = Bastion.SCAN_RANGE
    print(string.format("[Bastion] countBeds: scanning %d,%d z=0-%d r=%d", bx, by, Bastion.MAX_FLOOR, r))

    for z = 0, Bastion.MAX_FLOOR do
    for x = bx - r, bx + r do
        for y = by - r, by + r do
            local sq = cell:getGridSquare(x, y, z)
            if sq then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local obj = objs:get(i)
                    local candidates = getBedCandidateNames(obj)
                    local anyName = false
                    for _, n in ipairs(candidates) do
                        if type(n) == "string" and n ~= "" then anyName = true end
                    end
                    if anyName then
                        print("[Bastion] countBeds obj @ " .. x .. "," .. y .. "," .. z
                            .. ": " .. table.concat(candidates, " | "))
                    end
                    for _, name in ipairs(candidates) do
                        if nameMatchesBed(name) then
                            count = count + 1
                            print("[Bastion] countBeds MATCH: " .. tostring(name))
                            break
                        end
                    end
                end
            end
        end
    end end  -- z loop
    print("[Bastion] countBeds result: " .. count)
    return count
end

-- ── ID generation ─────────────────────────────────────────────────────────────

local function generateSettlerID()
    return tostring(math.floor(getTimeInMillis()))
        .. tostring(ZombRand(99999))
end

-- ── Phase 1 — Consumption ─────────────────────────────────────────────────────

local function runConsumption(rec, storage)
    local settlers = rec.settlers or {}
    local count    = math.max(1, #settlers)

    -- ── Food ─────────────────────────────────────────────────────────────────
    -- Perishables first (removeItem prefers refrigerated → general → frozen).
    local foodNeeded = count * Bastion.FOOD_ITEMS_PER_SETTLER_PER_DAY
    local foodGot    = removeItems(storage, isFood, foodNeeded)

    if foodGot < foodNeeded then
        local fedCount = math.min(count, foodGot)
        rec.happiness = math.max(0, (rec.happiness or 50) - 5 * (foodNeeded - foodGot))
        Bastion.addLog(rec,
            string.format("Food shortage: %d of %d settlers fed. Happiness declining.",
                fedCount, count),
            "warning")
    else
        Bastion.addLog(rec,
            string.format("Settlement consumed %d meal%s (%d settlers).",
                foodGot, foodGot ~= 1 and "s" or "", count),
            "standard")
    end

    -- ── Water ─────────────────────────────────────────────────────────────────
    -- Draw from settler pool first; remainder from storage containers.
    local waterNeeded = count * Bastion.WATER_ITEMS_PER_SETTLER_PER_DAY
    local fromPool    = math.min(waterNeeded, rec.settlerWaterPool or 0)
    rec.settlerWaterPool = math.max(0, (rec.settlerWaterPool or 0) - fromPool)
    local stillNeeded = waterNeeded - fromPool

    local fromStorage = 0
    if stillNeeded > 0 then
        fromStorage = consumeWaterItems(storage, math.ceil(stillNeeded))
    end

    local totalWaterGot = fromPool + fromStorage
    if totalWaterGot < waterNeeded - 0.01 then
        -- Water deficit hits happiness faster than food
        rec.happiness = math.max(0, (rec.happiness or 50) - 10)
        Bastion.addLog(rec,
            string.format(
                "Water critically short: %.0f / %d units available. Happiness dropping fast.",
                totalWaterGot, waterNeeded),
            "critical")
    else
        Bastion.addLog(rec,
            string.format("Settlement consumed water (%.0f pool + %d storage).",
                fromPool, fromStorage),
            "standard")
    end
end

-- ── Phase 2 helpers — priority queue ─────────────────────────────────────────

-- Returns work budget = sum of settler contributions modified by mood.
local function calcWorkUnits(rec)
    local total = 0
    for _, settler in ipairs(rec.settlers or {}) do
        local mood = settler.mood or "Content"
        if     mood == "Critical"   then total = total + 0.1
        elseif mood == "Struggling" then total = total + 0.5
        else                             total = total + 1.0 end
    end
    return total
end

-- Returns priority tier (1=Urgent … 4=Low) for a given role based on
-- the current post-consumption storage state.
local function getTaskPriority(role, rec, storage)
    -- Food-producing roles: urgency scales with food supply
    if role == "Cook" or role == "Farmer" or role == "Hunter"
    or role == "Fisher" or role == "Trapper" or role == "Forager"
    or role == "Rancher" then
        local foodCount  = countStorageItems(storage, isFood)
        local settlers   = math.max(1, #(rec.settlers or {}))
        local dailyItems = settlers * Bastion.FOOD_ITEMS_PER_SETTLER_PER_DAY
        local daysLeft   = dailyItems > 0 and (foodCount / dailyItems) or 99
        if     daysLeft < 0.5 then return 1
        elseif daysLeft < 1   then return 2
        elseif daysLeft < 2   then return 3
        else                       return 4 end
    end

    -- Water-producing role: urgency scales with water supply
    if role == "WaterCarrier" then
        local waterItems = countStorageItems(storage, isWaterItem)
        local pool       = rec.settlerWaterPool or 0
        local settlers   = math.max(1, #(rec.settlers or {}))
        local dailyItems = settlers * Bastion.WATER_ITEMS_PER_SETTLER_PER_DAY
        local daysLeft   = dailyItems > 0 and ((waterItems + pool) / dailyItems) or 99
        if     daysLeft < 0.5 then return 1
        elseif daysLeft < 1   then return 2
        elseif daysLeft < 2   then return 3
        else                       return 4 end
    end

    return 3  -- all other roles: Normal
end

-- ── Phase 4 — Role tick functions ─────────────────────────────────────────────
-- Signature: function(settler, rec, storage)
-- May remove items from storage and add new items to storage.

local ROLE_TICKS = {}

-- ── Tailor ────────────────────────────────────────────────────────────────────
-- Washes dirty rags (settler water cost) then picks thread from clean rags.
-- Phase 2: places thread items in storage.

ROLE_TICKS.Tailor = function(settler, rec, storage)
    -- Thread cap check
    local threadCount = countStorageItems(storage, isThread)
    local maxThread   = Bastion.getSetting(rec, "Tailor", "maxThread") or 50
    if threadCount >= maxThread then
        Bastion.addLog(rec, settler.name .. " — thread at cap; rag picking skipped.", "standard")
        return
    end

    local acted = false

    -- Step 1: Wash dirty rags
    local dirtyCount = countStorageItems(storage, isDirtyRag)
    if dirtyCount > 0 then
        local batch = math.min(dirtyCount, 5)
        local cost  = batch * 0.1
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

    -- Step 2: Pick thread from clean rags and place in storage
    local cleanRags = countStorageItems(storage, isCleanRag)
    local canProduce = math.min(cleanRags, settler.skillLevel,
                                maxThread - threadCount)
    if canProduce > 0 then
        local added = 0
        for _ = 1, canProduce do
            removeItem(storage, isCleanRag)
            if addItemToStorage(storage, Bastion.ITEMS.THREAD) then
                added = added + 1
            end
        end
        if added > 0 then
            Bastion.addLog(rec,
                string.format("%s picked %d thread from rags.", settler.name, added),
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
-- Boils clean rags into sterilized bandages. Requires heat source + water.
-- Phase 2: places BandageSterile items in storage.

ROLE_TICKS.Doctor = function(settler, rec, storage)
    rec.doctorActive = true

    -- Bandage cap check
    local bandageCount = countStorageItems(storage, isSterileBandage)
    local maxBandages  = Bastion.getSetting(rec, "Doctor", "maxBandages") or 20
    if bandageCount >= maxBandages then
        Bastion.addLog(rec, settler.name .. " — bandage cap reached.", "standard")
        return
    end

    if not rec.cachedHeatSource then
        Bastion.addLog(rec,
            settler.name .. " can't sterilize bandages — no heat source in the bastion.",
            "warning")
        return
    end

    local cleanRags = countStorageItems(storage, isCleanRag)
    if cleanRags == 0 then
        Bastion.addLog(rec, settler.name .. " found no clean rags to sterilize.", "warning")
        return
    end

    local canMake   = math.min(cleanRags, settler.skillLevel + 1,
                               maxBandages - bandageCount)
    local waterCost = canMake * 0.15
    if not debitWater(rec, waterCost) then
        local pool  = rec.settlerWaterPool or 0
        canMake     = math.floor(pool / 0.15)
        waterCost   = canMake * 0.15
        if canMake <= 0 then
            Bastion.addLog(rec,
                settler.name .. " couldn't sterilize — settler water supply too low.",
                "warning")
            return
        end
        debitWater(rec, waterCost)
    end

    local added = 0
    for _ = 1, canMake do
        removeItem(storage, isCleanRag)
        if addItemToStorage(storage, Bastion.ITEMS.BANDAGE_STERILE) then
            added = added + 1
        end
    end
    if added > 0 then
        Bastion.addLog(rec,
            string.format("%s sterilized %d bandage%s.",
                settler.name, added, added ~= 1 and "s" or ""),
            "standard")
    end
end

-- ── Cook ──────────────────────────────────────────────────────────────────────
-- Prioritizes perishable food for consumption. Phase 2: no new items produced
-- (Cook's value is consuming spoilage-risk items before they go bad).

ROLE_TICKS.Cook = function(settler, rec, storage)
    local allowDry    = Bastion.getSetting(rec, "Cook", "allowDryGoods") or false
    local count       = #(rec.settlers or {})
    local targetMeals = count + 1

    local perishables = {}
    local dryGoods    = {}
    local candidates  = {}
    for _, cat in ipairs({"refrigerated", "general"}) do
        for _, item in ipairs(storage[cat]) do
            if isFood(item) then
                if isPerishable(item) then
                    table.insert(perishables, item)
                else
                    table.insert(dryGoods, item)
                end
            end
        end
    end
    for _, item in ipairs(perishables) do table.insert(candidates, item) end
    if allowDry then
        for _, item in ipairs(dryGoods) do table.insert(candidates, item) end
    end

    if #candidates == 0 then
        Bastion.addLog(rec,
            settler.name .. " found nothing suitable to cook"
            .. (allowDry and "" or " (dry goods excluded by setting)") .. ".",
            "warning")
        return
    end

    local mealsMade  = math.min(targetMeals, #candidates, settler.skillLevel + 1)
    local fromPerish = math.min(mealsMade, #perishables)
    rec.cookActive   = true
    Bastion.addLog(rec,
        string.format("%s prepared %d meal%s (%d from perishables).",
            settler.name, mealsMade, mealsMade ~= 1 and "s" or "", fromPerish),
        "standard")
end

-- ── Farmer ────────────────────────────────────────────────────────────────────
-- Tends crops; costs settler water; produces vegetables in storage.

ROLE_TICKS.Farmer = function(settler, rec, storage)
    local saveSeeds = Bastion.getSetting(rec, "Farmer", "saveSeeds")
    if saveSeeds == nil then saveSeeds = true end

    if not debitWater(rec, 1.0) then
        Bastion.addLog(rec,
            settler.name .. " couldn't water crops — settler water supply too low.",
            "warning")
        return
    end

    local produce = ZombRand(settler.skillLevel * 2) + 1
    local seeds   = saveSeeds and math.max(1, math.floor(produce * 0.15)) or 0
    local harvestCount = produce - seeds

    local added = 0
    for _ = 1, harvestCount do
        if addItemToStorage(storage, Bastion.ITEMS.VEGETABLE) then added = added + 1 end
    end

    if saveSeeds then
        Bastion.addLog(rec,
            string.format(
                "%s tended crops, harvested %d item%s (%d seed%s set aside).",
                settler.name,
                added,  added  ~= 1 and "s" or "",
                seeds,  seeds  ~= 1 and "s" or ""),
            "standard")
    else
        Bastion.addLog(rec,
            string.format("%s tended and harvested %d crop item%s.",
                settler.name, added, added ~= 1 and "s" or ""),
            "standard")
    end
end

-- ── Woodcutter ────────────────────────────────────────────────────────────────
-- Consumes logs, produces planks. Requires an axe in shared storage.

ROLE_TICKS.Woodcutter = function(settler, rec, storage)
    local keepFires = Bastion.getSetting(rec, "Woodcutter", "keepFiresLit")
    if keepFires == nil then keepFires = true end

    -- Cap check
    local plankCount = countStorageItems(storage, isPlank)
    local maxPlanks  = Bastion.getSetting(rec, "Woodcutter", "maxPlanks") or 60
    if plankCount >= maxPlanks then
        Bastion.addLog(rec, settler.name .. " — plank cap reached; woodcutting skipped.", "standard")
        return
    end

    if countStorageItems(storage, isAxe) == 0 then
        Bastion.addLog(rec,
            settler.name .. " couldn't work — no axe in shared storage.", "warning")
        return
    end

    local logCount = countStorageItems(storage, isLog)
    if logCount == 0 then
        Bastion.addLog(rec, settler.name .. " found no logs to chop.", "warning")
    else
        local logsToChop = math.min(logCount, settler.skillLevel)
        local planksAdded = 0
        for _ = 1, logsToChop do
            removeItem(storage, isLog)
            -- Each log → 4 planks (two addItemToStorage calls per log = 2 planks to avoid over-stuffing)
            for _ = 1, 4 do
                if plankCount + planksAdded < maxPlanks then
                    if addItemToStorage(storage, Bastion.ITEMS.PLANK) then
                        planksAdded = planksAdded + 1
                    end
                end
            end
        end
        Bastion.addLog(rec,
            string.format("%s chopped %d log%s → %d plank%s.",
                settler.name,
                logsToChop,  logsToChop  ~= 1 and "s" or "",
                planksAdded, planksAdded ~= 1 and "s" or ""),
            "standard")
    end

    if keepFires and rec.cachedHeatSource then
        Bastion.addLog(rec, settler.name .. " kept the fires stocked.", "standard")
    end
end

-- ── WaterCarrier ──────────────────────────────────────────────────────────────
-- Collects and boils water into the settler-managed pool.
-- Phase 2: pool is the delivery mechanism; actual container filling Phase 3+.

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

    if (rec.settlerWaterPool or 0) >= Bastion.WATER_POOL_MAX then
        Bastion.addLog(rec,
            settler.name .. " — water pool is full (" .. Bastion.WATER_POOL_MAX .. " days).",
            "standard")
        return
    end

    local produced = Bastion.WATER_PER_CARRIER_TICK
                   + (settler.skillLevel - 1) * Bastion.WATER_CARRIER_SKILL_MOD
    produced = math.floor(produced * 10) / 10

    local before = rec.settlerWaterPool or 0
    addSettlerWater(rec, produced)
    local after  = rec.settlerWaterPool or 0
    local actual = math.floor((after - before) * 10) / 10

    Bastion.addLog(rec,
        string.format(
            "%s collected and boiled water. +%.1f days to pool (%.1f / %.1f).",
            settler.name, actual, after, Bastion.WATER_POOL_MAX),
        "standard")
end

-- ── Blacksmith ────────────────────────────────────────────────────────────────
-- Smelts scrap above the floor into metal bars. Requires heat source.
-- Phase 2: places MetalBar items in storage.

ROLE_TICKS.Blacksmith = function(settler, rec, storage)
    local scrapFloor = Bastion.getSetting(rec, "Blacksmith", "scrapFloor") or Bastion.SCRAP_FLOOR

    if not rec.cachedHeatSource then
        Bastion.addLog(rec,
            settler.name .. " can't smelt — no heat source (forge/campfire) in bastion.",
            "warning")
        return
    end

    local barCount  = countStorageItems(storage, isMetalBar)
    local maxIngots = Bastion.getSetting(rec, "Blacksmith", "maxIngots") or 20
    if barCount >= maxIngots then
        Bastion.addLog(rec, settler.name .. " — ingot cap reached; smithing skipped.", "standard")
        return
    end

    local scrapCount = countStorageItems(storage, isScrap)
    local usable     = math.max(0, scrapCount - scrapFloor)

    if usable < Bastion.SCRAP_PER_INGOT then
        Bastion.addLog(rec,
            string.format(
                "%s: not enough scrap above floor (have %d usable, need %d per ingot; floor=%d).",
                settler.name, usable, Bastion.SCRAP_PER_INGOT, scrapFloor),
            "warning")
        return
    end

    local canMake = math.min(
        math.floor(usable / Bastion.SCRAP_PER_INGOT),
        settler.skillLevel,
        maxIngots - barCount)

    local made = 0
    for _ = 1, canMake do
        for _ = 1, Bastion.SCRAP_PER_INGOT do
            removeItem(storage, isScrap)
        end
        if addItemToStorage(storage, Bastion.ITEMS.METAL_BAR) then
            made = made + 1
        end
    end

    if made > 0 then
        Bastion.addLog(rec,
            string.format("%s smelted %d ingot%s from scrap.",
                settler.name, made, made ~= 1 and "s" or ""),
            "standard")
    end
end

-- ── Rancher ───────────────────────────────────────────────────────────────────
-- Feeds animals; produces eggs and milk items. Requires animals + grain.
-- Phase 2: places Egg and MilkCarton items in storage.

ROLE_TICKS.Rancher = function(settler, rec, storage)
    if not rec.cachedHasAnimals then
        Bastion.addLog(rec,
            settler.name .. " — no animals detected near the bastion.", "warning")
        return
    end

    local minGrain  = Bastion.getSetting(rec, "Rancher", "minGrainReserve") or 10
    local feedCount = countStorageItems(storage, isGrainFeed)

    if feedCount <= minGrain then
        Bastion.addLog(rec,
            string.format("%s couldn't feed animals — feed stock too low (have %d, floor=%d).",
                settler.name, feedCount, minGrain),
            "warning")
        return
    end

    -- Consume one unit of feed
    removeItem(storage, isGrainFeed)

    local eggYield  = settler.skillLevel >= 2 and (ZombRand(settler.skillLevel) + 1) or 0
    local milkYield = settler.skillLevel >= 3 and (ZombRand(2) + 1) or 0

    local eggsAdded = 0
    for _ = 1, eggYield do
        if addItemToStorage(storage, Bastion.ITEMS.EGG) then eggsAdded = eggsAdded + 1 end
    end
    local milkAdded = 0
    for _ = 1, milkYield do
        if addItemToStorage(storage, Bastion.ITEMS.MILK) then milkAdded = milkAdded + 1 end
    end

    Bastion.addLog(rec,
        string.format("%s fed and tended the animals.%s%s",
            settler.name,
            eggsAdded > 0 and ("  +" .. eggsAdded .. " egg" .. (eggsAdded ~= 1 and "s" or "")) or "",
            milkAdded > 0 and ("  +" .. milkAdded .. " milk") or ""),
        "standard")
end

-- ── Trapper ───────────────────────────────────────────────────────────────────
-- Checks trap lines. Phase 2: requires bait in storage; logs catch.
-- Full IsoTrap scanning deferred to Phase 3 (OQ #24).

ROLE_TICKS.Trapper = function(settler, rec, storage)
    if countStorageItems(storage, isBait) == 0 then
        Bastion.addLog(rec,
            settler.name .. " checked the traps but had no bait to reset them.", "warning")
        return
    end
    removeItem(storage, isBait)  -- consume one bait resetting traps

    local caught = ZombRand(settler.skillLevel + 1)
    if caught > 0 then
        Bastion.addLog(rec,
            settler.name .. " checked the traps. Catch: " .. caught .. " item"
            .. (caught ~= 1 and "s" or "") .. ".",
            "standard")
    else
        Bastion.addLog(rec, settler.name .. " checked the traps — nothing caught today.", "standard")
    end
end

-- ── Fisher ────────────────────────────────────────────────────────────────────
-- Consumes bait + fishing line; produces fish items in storage.

ROLE_TICKS.Fisher = function(settler, rec, storage)
    local fishCount = countStorageItems(storage, isFish)
    local maxFish   = Bastion.getSetting(rec, "Fisher", "maxFishStock") or 30
    if fishCount >= maxFish then
        Bastion.addLog(rec, settler.name .. " — fish stock at cap; fishing skipped.", "standard")
        return
    end

    local hasBait = countStorageItems(storage, isBait) > 0
    local hasLine = countStorageItems(storage, isFishingLine) > 0

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

    removeItem(storage, isBait)

    local caught = ZombRand(settler.skillLevel * 2) + 1
    local added  = 0
    for _ = 1, caught do
        if addItemToStorage(storage, Bastion.ITEMS.FISH) then added = added + 1 end
    end

    Bastion.addLog(rec,
        string.format("%s fished and caught %d fish.", settler.name, added),
        "standard")
end

-- ── Forager ───────────────────────────────────────────────────────────────────
-- Gathers forage items (berries, mushrooms) and places them in storage.

ROLE_TICKS.Forager = function(settler, rec, storage)
    local yield = ZombRand(settler.skillLevel + 1) + 1
    local added = 0
    for _ = 1, yield do
        if addItemToStorage(storage, Bastion.ITEMS.BERRY) then added = added + 1 end
    end
    Bastion.addLog(rec,
        string.format("%s foraged in the surrounding area. Found %d item%s.",
            settler.name, added, added ~= 1 and "s" or ""),
        "standard")
end

-- ── Remaining roles ───────────────────────────────────────────────────────────

ROLE_TICKS.Teacher = function(settler, rec, storage)
    rec.teacherActive = true
    rec.education     = (rec.education or 0) + 1
    Bastion.addLog(rec, settler.name .. " held a lesson. Reading speed enhanced today.", "standard")
end

ROLE_TICKS.Mechanic = function(settler, rec, storage)
    local hasFuelItems = countStorageItems(storage, isFuel) > 0
    if hasFuelItems then
        Bastion.addLog(rec, settler.name .. " refueled the generator.", "standard")
    else
        Bastion.addLog(rec, settler.name .. " checked the generator — no fuel in storage.", "warning")
    end

    if settler.skillLevel >= 3 then
        local fuelOnly = Bastion.getSetting(rec, "Mechanic", "fuelOnly") or false
        if not fuelOnly then
            local hasParts = false
            for _, item in ipairs(storage.general) do
                local t = itemType(item)
                if t:find("tire") or t:find("tyre") or t:find("carbattery")
                or t:find("oilcan") or t:find("brakepad") then
                    hasParts = true; break
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

ROLE_TICKS.Defender = function(settler, rec, storage)
    rec.resolve = math.min(100, (rec.resolve or 50) + 1)
    Bastion.addLog(rec, settler.name .. " patrolled the perimeter.", "standard")
end

ROLE_TICKS.Hunter = function(settler, rec, storage)
    local caught = ZombRand(settler.skillLevel) + 1
    local added  = 0
    for _ = 1, caught do
        if addItemToStorage(storage, Bastion.ITEMS.FISH) then added = added + 1 end
    end
    Bastion.addLog(rec,
        settler.name .. " went hunting. Returned with " .. caught .. " item"
        .. (caught ~= 1 and "s" or "") .. ".",
        "standard")
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

-- ── Settlement tick — four-phase execution ────────────────────────────────────

local function runSettlementTick(username, rec)
    print("[Bastion] Running tick for " .. username)

    rec.settlers      = rec.settlers or {}
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

    -- ── Phase 1: Consumption ──────────────────────────────────────────────────
    local storage = scanContainers(rec)
    Bastion.addLog(rec, "── Day " .. today .. " ──", "standard")
    runConsumption(rec, storage)

    -- ── Phase 2: Build priority queue ─────────────────────────────────────────
    local budgetLevel = rec.noiseBudgetLevel or "Normal"
    local noiseCap    = Bastion.NOISE_BUDGETS[budgetLevel] or 6
    local noiseUsed   = 1  -- baseline

    local candidates = {}
    for _, settler in ipairs(rec.settlers) do
        local roleDef = Bastion.ROLES[settler.role]
        if settler.mood == "Critical" then
            Bastion.addLog(rec,
                settler.name .. " is struggling. They didn't contribute today.", "warning")
        elseif roleDef then
            local roleNoise = roleDef.noise or 0
            -- Noise suppression: reserve noise in natural order so loud roles
            -- don't crowd out quiet ones when budget is tight.
            if roleNoise > 0 and (noiseUsed + roleNoise) > noiseCap then
                Bastion.addLog(rec,
                    string.format("[QUIET MODE] %s's work (%s) skipped — noise budget exceeded.",
                        settler.name, settler.role),
                    "suppressed")
            else
                noiseUsed = noiseUsed + roleNoise
                local priority = getTaskPriority(settler.role, rec, storage)
                table.insert(candidates, {
                    settler  = settler,
                    priority = priority,
                })
            end
        else
            -- Unknown role: allow, low priority
            table.insert(candidates, { settler=settler, priority=4 })
        end
    end

    -- Sort eligible tasks by urgency (1=Urgent first, 4=Low last)
    table.sort(candidates, function(a, b) return a.priority < b.priority end)

    -- ── Phase 3: Work unit calculation ────────────────────────────────────────
    local workBudget = calcWorkUnits(rec)

    -- ── Phase 4: Execute within budget ────────────────────────────────────────
    local workUsed = 0
    local deferred = 0
    for _, task in ipairs(candidates) do
        if workUsed >= workBudget then
            deferred = deferred + 1
        else
            local tickFn = ROLE_TICKS[task.settler.role] or defaultRoleTick
            tickFn(task.settler, rec, storage)
            workUsed = workUsed + 1
        end
    end

    if deferred > 0 then
        Bastion.addLog(rec,
            string.format("Work units exhausted — %d task%s deferred.",
                deferred, deferred ~= 1 and "s" or ""),
            "standard")
    end

    rec.noiseScore  = noiseUsed
    rec.noiseBudget = noiseCap

    -- ── Bed count ─────────────────────────────────────────────────────────────
    rec.bedCount = countBeds(rec)
    if #rec.settlers > 0 and rec.bedCount < #rec.settlers then
        local shortage = #rec.settlers - rec.bedCount
        Bastion.addLog(rec,
            string.format("Bed shortage: %d settler%s without a bed. Happiness declining.",
                shortage, shortage ~= 1 and "s" or ""),
            "warning")
        rec.happiness = math.max(0, (rec.happiness or 50) - 2 * shortage)
    end

    -- ── Post-production estimates ─────────────────────────────────────────────
    -- Re-scan (storage was mutated by consumption + production) then estimate.
    local freshStorage = scanContainers(rec)
    estimateResources(rec, freshStorage)

    -- Shortage warnings (post-production state)
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
            noiseScore       = 1,
            noiseBudget      = 6,
            noiseBudgetLevel = "Normal",
            happiness        = 50,
            resolve          = 50,
            education        = 0,
            cookActive       = false,
            doctorActive     = false,
            teacherActive    = false,
            bedCount         = 0,
            storageWeightCurrent = 0,
            storageWeightMax     = 0,
            roleSettings     = roleSettings,
            cachedWaterSource = false,
            cachedHeatSource  = false,
            cachedHasAnimals  = false,
            lastSourceCheck   = -99,
            lastTickDay       = Bastion.getCurrentDay(),
        }

        local npc  = Bastion.generateNPC({})
        local role = Bastion.pickRandom(Bastion.STARTER_ROLES)

        local settler = {
            id            = generateSettlerID(),
            name          = npc.name,
            isMale        = npc.isMale,
            role          = role,
            skillLevel    = npc.skillLevel,
            traitTag      = npc.traitTag,
            backstory     = npc.backstory,
            mood          = "Content",
            ownerUsername = username,
        }
        table.insert(rec.settlers, settler)

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
        -- Recalculate food/water estimates immediately so the window reflects
        -- the change without waiting for the next daily tick.
        local s = scanContainers(rec)
        estimateResources(rec, s)
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
                    "[Bastion] %s: %d settlers | food=%.1f d | water=%.1f d | noise=%d/%d | beds=%d",
                    username, #(rec.settlers or {}),
                    rec.foodDays or 0, rec.waterDays or 0,
                    rec.noiseScore or 0, rec.noiseBudget or 6,
                    rec.bedCount or 0))
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
            local trec   = wd[target]
            if trec then
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

    -- ── ForceTick ─────────────────────────────────────────────────────────────
    elseif command == "ForceTick" then
        local rec = getRecord(username)
        if rec then
            rec.lastTickDay = -1
            saveRecord(username, rec)
            print("[Bastion] Tick forced for " .. username)
        end

    -- ── AddSettler ────────────────────────────────────────────────────────────
    elseif command == "AddSettler" then
        local rec = getRecord(username)
        if not rec then return end
        local existingNames = Bastion.buildNameSet(rec.settlers)
        local npc  = Bastion.generateNPC(existingNames)
        local roleKeys = {}
        for k in pairs(Bastion.ROLES) do table.insert(roleKeys, k) end
        local role = Bastion.pickRandom(roleKeys)
        local settler = {
            id            = generateSettlerID(),
            name          = npc.name,
            isMale        = npc.isMale,
            role          = role,
            skillLevel    = npc.skillLevel,
            traitTag      = npc.traitTag,
            backstory     = npc.backstory,
            mood          = "Content",
            ownerUsername = username,
        }
        table.insert(rec.settlers, settler)
        Bastion.addLog(rec,
            string.format("[Admin] %s arrived as %s (skill %d). %s.",
                settler.name, settler.role, settler.skillLevel, settler.traitTag),
            "arrival")
        saveRecord(username, rec)
        print("[Bastion] Settler added for " .. username .. ": " .. settler.name)

    -- ── Dump ──────────────────────────────────────────────────────────────────
    elseif command == "Dump" then
        local rec = getRecord(username)
        if not rec then
            print("[Bastion] Dump: no record for " .. username)
            return
        end
        local cell = getCell()
        if not cell then print("[Bastion] Dump: no cell") return end

        local bx, by, bz = rec.bx, rec.by, rec.bz
        local r = Bastion.SCAN_RANGE
        print(string.format("[Bastion] ── DUMP for %s  origin=%d,%d,%d  r=%d  floors=0-%d ──",
            username, bx, by, bz, r, Bastion.MAX_FLOOR))

        local objCount = 0
        for z = 0, Bastion.MAX_FLOOR do
        for x = bx - r, bx + r do
            for y = by - r, by + r do
                local sq = cell:getGridSquare(x, y, z)
                if sq then
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        objCount = objCount + 1

                        -- Java class name
                        local ok0, cls = pcall(function()
                            return tostring(obj:getClass():getSimpleName())
                        end)
                        local className = (ok0 and cls) or "?"

                        -- Sprite name
                        local spriteName = ""
                        local ok1, spr = pcall(function() return obj:getSprite() end)
                        if ok1 and spr then
                            local ok2, sn = pcall(function() return spr:getName() end)
                            if ok2 and type(sn) == "string" then spriteName = sn end
                        end

                        -- Display name
                        local displayName = ""
                        local ok3, dn = pcall(function() return obj:getName() end)
                        if ok3 and type(dn) == "string" then displayName = dn end

                        -- Object name
                        local objName = ""
                        local ok4, on = pcall(function() return obj:getObjectName() end)
                        if ok4 and type(on) == "string" then objName = on end

                        -- Has container?
                        local hasCont = false
                        local ok5, c = pcall(function() return obj:getItemContainer() end)
                        hasCont = ok5 and c ~= nil

                        -- Only print objects that have at least one non-empty name
                        -- (skips blank floor/wall tiles that clutter the log)
                        if spriteName ~= "" or displayName ~= "" or objName ~= "" then
                            print(string.format(
                                "[Bastion] Dump  %d,%d,%d  class=%-20s  sprite=%-35s  name=%-25s  objName=%-20s  container=%s",
                                x, y, z, className, spriteName, displayName, objName,
                                tostring(hasCont)))
                        end
                    end
                end
            end
        end
        end  -- z loop
        print(string.format("[Bastion] ── DUMP done  total objects scanned: %d ──", objCount))
    end
end

-- ── Event registration ────────────────────────────────────────────────────────

Events.OnClientCommand.Add(onClientCommand)
Events.EveryOneMinute.Add(onEveryOneMinute)

print("[Bastion] Server done")
