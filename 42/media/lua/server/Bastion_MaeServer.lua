-- ============================================================
-- Bastion_MaeServer.lua  (media/lua/server/)
-- Server-side only. Works in singleplayer and multiplayer.
-- Handles: settlement tick, storage scanning, settler spawning,
--          ModData persistence, client command dispatch.
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

-- Identify a container's storage category from its world object's sprite name.
-- Returns "frozen", "refrigerated", or "general".
local function getContainerCategory(obj)
    local name = ""
    local ok, spr = pcall(function() return obj:getSprite() end)
    if ok and spr then
        local ok2, n = pcall(function() return spr:getName() end)
        if ok2 and type(n) == "string" then name = n:lower() end
    end
    if name:find("freezer")                        then return "frozen"        end
    if name:find("fridge") or name:find("refriger") then return "refrigerated" end
    return "general"
end

-- Scan all non-private community containers in the settlement and build a
-- registry of items grouped by storage category.
-- Returns: { general={items}, refrigerated={items}, frozen={items},
--            capacity={general=N, refrigerated=N, frozen=N} }
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
            -- Only scan indoor squares (those belonging to a room)
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
                                local cat = getContainerCategory(obj)
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

-- Returns true if an item should count as food.
local function isFood(item)
    if not item then return false end
    local ok, r = pcall(function() return item:isFood() end)
    if ok and r then return true end
    -- Fallback: check display category
    ok, r = pcall(function() return item:getDisplayCategory() end)
    if ok and type(r) == "string" and r:lower():find("food") then return true end
    return false
end

-- Returns water units from a single item (0 if not a water source).
local function getWaterUnits(item)
    if not item then return 0 end
    -- B42 fluid system: check for a non-empty fluid container
    local ok, fc = pcall(function() return item:getFluidContainer() end)
    if ok and fc then
        local ok2, empty = pcall(function() return fc:isEmpty() end)
        if ok2 and not empty then
            -- Try to get the actual amount
            local ok3, amt = pcall(function() return fc:getAmount() end)
            if ok3 and type(amt) == "number" and amt > 0 then return amt end
            return 1  -- non-empty but amount unknown; count as 1 unit
        end
    end
    return 0
end

-- Update food/water estimates and storage capacity in the record.
local function estimateResources(rec, storage)
    local count = math.max(1, #(rec.settlers or {}))

    local totalCalories = 0
    local totalWater    = 0

    -- Pool all items across all categories
    local allItems = {}
    for _, item in ipairs(storage.general)      do table.insert(allItems, item) end
    for _, item in ipairs(storage.refrigerated) do table.insert(allItems, item) end
    for _, item in ipairs(storage.frozen)       do table.insert(allItems, item) end

    for _, item in ipairs(allItems) do
        if isFood(item) then
            -- Try to read calories; fall back to 500 per food item
            local cal = 500
            local ok, n = pcall(function() return item:getNutrition() end)
            if ok and n then
                local ok2, c = pcall(function() return n:getCalories() end)
                if ok2 and type(c) == "number" and c > 0 then cal = c end
            end
            totalCalories = totalCalories + cal
        end
        totalWater = totalWater + getWaterUnits(item)
    end

    local caloriesPerDay = count * Bastion.CALORIES_PER_SETTLER_PER_DAY
    local waterPerDay    = count * Bastion.WATER_PER_SETTLER_PER_DAY

    rec.foodDays  = caloriesPerDay > 0 and math.floor(totalCalories / caloriesPerDay * 10) / 10 or 0
    rec.waterDays = waterPerDay > 0    and math.floor(totalWater    / waterPerDay    * 10) / 10 or 0

    rec.storageCapacity = {
        general      = storage.capacity.general,
        refrigerated = storage.capacity.refrigerated,
        frozen       = storage.capacity.frozen,
    }
end

-- ── Settler mannequin helpers ─────────────────────────────────────────────────

local SPRITE_FEMALE   = "location_shop_mall_01_65"
local SPRITE_MALE     = "location_shop_mall_01_68"
local SCRIPT_FEMALE   = "FemaleBlack01"
local SCRIPT_MALE     = "MaleBlack01"

local function spawnSettlerMannequin(settler)
    local cell = getCell()
    if not cell then return false end

    local sq = cell:getGridSquare(settler.x, settler.y, settler.z)
    if not sq then
        print("[Bastion] spawnSettler: no square at "
            .. settler.x .. "," .. settler.y .. "," .. settler.z)
        return false
    end

    local spriteName = settler.isMale and SPRITE_MALE or SPRITE_FEMALE
    local scriptName = settler.isMale and SCRIPT_MALE or SCRIPT_FEMALE

    local spr = getSprite(spriteName)
    if not spr then
        print("[Bastion] spawnSettler: sprite not found: " .. spriteName)
        return false
    end

    local obj = IsoMannequin.new(cell, sq, spr)
    obj:setSquare(sq)
    if obj.setMannequinScriptName then
        obj:setMannequinScriptName(scriptName)
    end

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

    print("[Bastion] Spawned settler " .. settler.name .. " at "
        .. settler.x .. "," .. settler.y)
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

-- Find a valid spawn square for a settler given an offset index.
-- Falls back to the reference square itself if none of the offsets land indoors.
local function findSpawnSquare(bx, by, bz, startOffset)
    local cell = getCell()
    if not cell then return bx, by, bz end

    for i = startOffset or 1, #Bastion.SETTLER_OFFSETS do
        local off = Bastion.SETTLER_OFFSETS[i]
        local x, y, z = bx + off.x, by + off.y, bz + (off.z or 0)
        local sq = cell:getGridSquare(x, y, z)
        if sq and sq:getRoom() then
            return x, y, z
        end
    end
    return bx, by, bz  -- fallback
end

local function generateSettlerID()
    return tostring(math.floor(getTimeInMillis())) .. tostring(ZombRand(99999))
end

-- ── Role tick functions ───────────────────────────────────────────────────────

local ROLE_TICKS = {}

ROLE_TICKS.Woodcutter = function(settler, rec, storage)
    -- Check for an axe in community storage
    local hasAxe = false
    for _, item in ipairs(storage.general) do
        local ok, t = pcall(function() return item:getType() end)
        if ok and type(t) == "string" and t:find("Axe") then
            hasAxe = true; break
        end
    end
    if not hasAxe then
        Bastion.addLog(rec, settler.name .. " couldn't work — no axe in storage.", "warning")
        return
    end
    local amount = ZombRand(settler.skillLevel) + 1
    Bastion.addLog(rec,
        string.format("%s collected %d log%s.",
            settler.name, amount, amount ~= 1 and "s" or ""),
        "standard")
end

ROLE_TICKS.Cook = function(settler, rec, storage)
    local hasFood = false
    for _, item in ipairs(storage.general)      do if isFood(item) then hasFood=true; break end end
    if not hasFood then
        for _, item in ipairs(storage.refrigerated) do if isFood(item) then hasFood=true; break end end
    end
    if not hasFood then
        Bastion.addLog(rec, settler.name .. " couldn't cook — no food in storage.", "warning")
        return
    end
    rec.cookActive = true
    Bastion.addLog(rec, settler.name .. " cooked a warm meal. The community ate well.", "standard")
end

ROLE_TICKS.Farmer = function(settler, rec, storage)
    Bastion.addLog(rec, settler.name .. " tended the crops.", "standard")
end

ROLE_TICKS.Doctor = function(settler, rec, storage)
    rec.doctorActive = true
    Bastion.addLog(rec, settler.name .. " checked on the community's health.", "standard")
end

ROLE_TICKS.Teacher = function(settler, rec, storage)
    rec.education = (rec.education or 0) + 1
    Bastion.addLog(rec, settler.name .. " held a lesson. Education slowly improving.", "standard")
end

ROLE_TICKS.Mechanic = function(settler, rec, storage)
    Bastion.addLog(rec, settler.name .. " looked over the vehicles.", "standard")
end

ROLE_TICKS.Tailor = function(settler, rec, storage)
    Bastion.addLog(rec, settler.name .. " repaired some clothing.", "standard")
end

ROLE_TICKS.Defender = function(settler, rec, storage)
    Bastion.addLog(rec, settler.name .. " patrolled the perimeter.", "standard")
end

ROLE_TICKS.Trapper = function(settler, rec, storage)
    Bastion.addLog(rec, settler.name .. " checked the traps.", "standard")
end

ROLE_TICKS.Fisher = function(settler, rec, storage)
    Bastion.addLog(rec, settler.name .. " fished near the settlement.", "standard")
end

ROLE_TICKS.Forager = function(settler, rec, storage)
    Bastion.addLog(rec, settler.name .. " foraged in the area.", "standard")
end

ROLE_TICKS.Hunter = function(settler, rec, storage)
    Bastion.addLog(rec, settler.name .. " went hunting.", "standard")
end

ROLE_TICKS.Child = function(settler, rec, storage)
    -- Children don't contribute to production but improve Resolve
    rec.resolve = math.min(100, (rec.resolve or 50) + 1)
end

local function defaultRoleTick(settler, rec, storage)
    Bastion.addLog(rec,
        string.format("%s (%s) worked today.", settler.name, settler.role),
        "standard")
end

-- ── Settlement tick ───────────────────────────────────────────────────────────

local function runSettlementTick(username, rec)
    print("[Bastion] Running tick for " .. username)

    rec.settlers         = rec.settlers or {}
    rec.cookActive       = false
    rec.doctorActive     = false

    -- Compute noise budget
    local budgetLevel = rec.noiseBudgetLevel or "Normal"
    local budget      = Bastion.NOISE_BUDGETS[budgetLevel] or 6
    local noiseUsed   = 1  -- baseline: settlement presence

    -- Scan community storage
    local storage = scanContainers(rec)

    -- Run each settler's role tick
    for _, settler in ipairs(rec.settlers) do
        local roleDef = Bastion.ROLES[settler.role]
        if not roleDef then
            -- Unknown role; log generically
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

    -- Update noise score
    rec.noiseScore  = noiseUsed
    rec.noiseBudget = budget

    -- Update resource estimates
    estimateResources(rec, storage)

    -- Shortage warnings
    if (rec.foodDays or 0) < 3 and #rec.settlers > 0 then
        Bastion.addLog(rec,
            string.format("Food supply is running low (%.1f days remaining).", rec.foodDays),
            "warning")
    end
    if (rec.waterDays or 0) < 2 and #rec.settlers > 0 then
        Bastion.addLog(rec,
            string.format("Water supply is critically low (%.1f days remaining).", rec.waterDays),
            "critical")
    end

    -- Record this tick's day
    rec.lastTickDay = Bastion.getCurrentDay()
end

-- ── Daily tick check ──────────────────────────────────────────────────────────

local function onEveryOneMinute()
    local today = Bastion.getCurrentDay()
    local wd    = getWorldData()
    local dirty = false

    for username, rec in pairs(wd) do
        if type(rec) == "table" and rec.bx then
            local lastDay = rec.lastTickDay or -1
            if today > lastDay then
                runSettlementTick(username, rec)
                dirty = true
            end
        end
    end

    if dirty then
        ModData.transmit(Bastion.DATA_KEY)
    end
end

-- ── Client command handler ────────────────────────────────────────────────────

local function onClientCommand(module, command, player, args)
    if module ~= Bastion.MOD_KEY then return end

    local username = player:getUsername()

    -- ── EstablishBastion ──────────────────────────────────────────────────────
    if command == "EstablishBastion" then
        if getRecord(username) then
            print("[Bastion] EstablishBastion ignored — " .. username .. " already has one")
            return
        end

        local bx = args.bx or 0
        local by = args.by or 0
        local bz = args.bz or 0

        local rec = {
            bx               = bx,
            by               = by,
            bz               = bz,
            settlers         = {},
            settlementLog    = {},
            privateContainers = {},
            foodDays         = 0,
            waterDays        = 0,
            noiseScore       = 1,
            noiseBudget      = 6,
            noiseBudgetLevel = "Normal",
            happiness        = 50,
            resolve          = 50,
            education        = 0,
            cookActive       = false,
            doctorActive     = false,
            lastTickDay      = Bastion.getCurrentDay(),  -- don't tick immediately
        }

        -- Generate and spawn first settler
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
            x             = sx,
            y             = sy,
            z             = sz,
            ownerUsername = username,
        }

        table.insert(rec.settlers, settler)
        spawnSettlerMannequin(settler)

        -- Arrival log entry
        Bastion.addLog(rec,
            string.format("A survivor arrived: %s (%s, skill %d). %s. They seem %s.",
                settler.name,
                settler.role,
                settler.skillLevel,
                settler.backstory,
                settler.traitTag:lower()),
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
            rec.privateContainers[key] = nil   -- toggle off (mark as shared)
            Bastion.addLog(rec, "A container was marked as shared.", "standard")
        else
            rec.privateContainers[key] = true   -- mark private
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
    end
end

-- ── Event registration ────────────────────────────────────────────────────────

Events.OnClientCommand.Add(onClientCommand)
Events.EveryOneMinute.Add(onEveryOneMinute)

print("[Bastion] Server done")
