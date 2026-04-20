-- ============================================================
-- Bastion_MaeClient.lua  (media/lua/client/)
-- Client-side only.
-- Handles: context menus (establish, collapse, settler chat,
--          mark-private, noise budget), ModData sync on load.
-- ============================================================
print("[Bastion] MaeClient loading")

-- ── ModData helpers ───────────────────────────────────────────────────────────

local function getWorldData()
    return ModData.get(Bastion.DATA_KEY) or {}
end

local function getMaeRecord(username)
    return getWorldData()[username]
end

-- ── Building helpers ──────────────────────────────────────────────────────────

-- Walk worldObjects for the first square that has a room; fall back to the
-- player's own square.  Returns building, square (or nil, nil).
local function getClickedBuilding(player, worldObjects)
    for _, obj in ipairs(worldObjects) do
        if obj.getSquare then
            local sq = obj:getSquare()
            if sq then
                local room = sq:getRoom()
                if room then return room:getBuilding(), sq end
            end
        end
    end
    local sq = player:getCurrentSquare() or player:getSquare()
    if sq then
        local room = sq:getRoom()
        if room then return room:getBuilding(), sq end
    end
    return nil, nil
end

-- Returns true when the player's building matches the bastion's stored square.
local function playerIsInBastionBuilding(player, worldObjects, rec)
    local playerBuilding = getClickedBuilding(player, worldObjects)
    if not playerBuilding then return false end

    local cell = getWorld():getCell()
    if not cell then return false end

    local bastionSq = cell:getGridSquare(rec.bx, rec.by, rec.bz)
    if not bastionSq then return false end

    local bastionRoom = bastionSq:getRoom()
    if not bastionRoom then return false end

    return playerBuilding == bastionRoom:getBuilding()
end

-- ── Mae / settler identification ──────────────────────────────────────────────

-- True if obj is the Mae mannequin for this player.
-- Checks both moddata (reliable once synced) and position fallback.
local function isMaeMannequin(obj, username, rec)
    if not instanceof(obj, "IsoMannequin") then return false end

    local md = obj:getModData()
    if md["Bastion_Mae"] and md["Bastion_Owner"] == username then
        return true
    end

    -- Position fallback: handles cases where moddata hasn't arrived yet.
    if rec then
        local sq = obj:getSquare()
        if sq and sq:getX() == rec.x and sq:getY() == rec.y and sq:getZ() == rec.z then
            return true
        end
    end
    return false
end

-- Returns the settler data table for a mannequin, or nil.
local function getSettlerForMannequin(obj, rec)
    if not instanceof(obj, "IsoMannequin") then return nil end
    if not rec or not rec.settlers then return nil end

    local md = obj:getModData()
    local settlerID = md["Bastion_SettlerID"]

    for _, s in ipairs(rec.settlers) do
        if settlerID and s.id == settlerID then return s end
        -- Position fallback
        if s.x and s.y then
            local sq = obj:getSquare()
            if sq and sq:getX() == s.x and sq:getY() == s.y then return s end
        end
    end
    return nil
end

-- True if this obj is any bastion mannequin (Mae or settler) for this player.
local function isBastionMannequin(obj, username, rec)
    if not instanceof(obj, "IsoMannequin") then return false end
    if isMaeMannequin(obj, username, rec) then return true end
    if getSettlerForMannequin(obj, rec) then return true end
    return false
end

-- ── Container helpers ─────────────────────────────────────────────────────────

-- Returns the "x,y,z" key for any world object.
local function objKey(obj)
    local sq = obj:getSquare()
    if not sq then return nil end
    return sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
end

-- True if the object is a container that belongs to the bastion (not private).
local function isContainerObject(obj)
    if not obj.getItemContainer then return false end
    local ok, c = pcall(function() return obj:getItemContainer() end)
    return ok and c ~= nil
end

-- ── Text display ──────────────────────────────────────────────────────────────

local function maeSpeak(mae, text)
    if HaloTextHelper and HaloTextHelper.addText then
        HaloTextHelper.addText(mae, text, 5)
    end
    if addLineInChat then
        addLineInChat("[Bastion] " .. text, 0.85, 0.75, 1.0, 1.0)
    end
end

-- ── Noise-budget sub-menu ─────────────────────────────────────────────────────

local function addNoiseBudgetMenu(context, player, rec)
    local budgetSub = context:addOptionOnTop("Noise Budget", nil, nil)
    local subMenu   = ISContextMenu:getNew(context)
    context:addSubMenu(budgetSub, subMenu)

    local current = rec and rec.noiseBudgetLevel or "Normal"
    for _, level in ipairs(Bastion.NOISE_BUDGET_LEVELS) do
        local label = level .. (level == current and "  ✓" or "")
        subMenu:addOption(label, player, function()
            sendClientCommand(player, Bastion.MOD_KEY, "SetNoiseBudget", { level = level })
        end)
    end
end

-- ── Context-menu hook ─────────────────────────────────────────────────────────

-- Force safehouseAllowInteract = true so our context entries appear inside
-- safehouses we don't own.
Events.OnPreFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects, test)
    local fetch = ISWorldObjectContextMenu and ISWorldObjectContextMenu.fetchVars
    if fetch then
        fetch.safehouseAllowInteract = true
        if fetch.c == 0 then fetch.c = 1 end
    end
end)

Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects, test)
    local player   = getSpecificPlayer(playerIndex)
    if not player then return end

    local username = player:getUsername()
    local rec      = getMaeRecord(username)

    -- ── 1. Bastion mannequin interactions ─────────────────────────────────────
    -- Note: Kahlua (PZ's Lua VM) does not support goto/::label:: syntax.
    -- We wrap the body in `if instanceof` instead of using continue.
    for _, obj in ipairs(worldObjects) do
        if instanceof(obj, "IsoMannequin") then

            -- Mae (intro mannequin)
            if isMaeMannequin(obj, username, rec) then
                if not rec or not rec.introDone then
                    local idx  = rec and rec.introIndex or 1
                    local line = Bastion.DIALOGUE and Bastion.DIALOGUE.intro
                                 and Bastion.DIALOGUE.intro[idx] or "..."
                    context:addOption("Talk to Mae", obj, function(target)
                        maeSpeak(target, line)
                        sendClientCommand(player, Bastion.MOD_KEY, "AdvanceIntro", {})
                    end)
                else
                    context:addOption("Check in", obj, function(target)
                        local lines = Bastion.DIALOGUE.checkIn
                        maeSpeak(target, lines[ZombRand(#lines) + 1])
                    end)
                    context:addOption("What do we need", obj, function(target)
                        local lines = Bastion.DIALOGUE.needs
                        maeSpeak(target, lines[ZombRand(#lines) + 1])
                    end)
                    context:addOption("Tell me something", obj, function(target)
                        local lines = Bastion.DIALOGUE.flavor
                        maeSpeak(target, lines[ZombRand(#lines) + 1])
                    end)
                end
                -- Suppress vanilla "Pick up / Move" for Mae.
                return
            end

            -- Settler mannequin
            local settler = getSettlerForMannequin(obj, rec)
            if settler then
                -- Greeting line based on mood
                local lines = Bastion.SETTLER_LINES[settler.mood or "Content"]
                           or Bastion.SETTLER_LINES.Content
                local line  = lines[ZombRand(#lines) + 1]

                -- Header: "James Smith (Cook)" — read-only info
                local label = settler.name .. " (" .. (settler.role or "?") .. ")"
                context:addOption(label, nil, nil)  -- non-clickable label

                context:addOption("Talk to " .. (settler.name or "settler"), obj,
                    function(target) maeSpeak(target, line) end)

                context:addOption("View profile", obj, function(_target)
                    -- Show backstory and trait in chat as a cheap alternative to a
                    -- full UI panel (LogPanel is a separate feature).
                    if addLineInChat then
                        addLineInChat("-- " .. settler.name .. " --", 0.9, 0.85, 1.0, 1.0)
                        addLineInChat(settler.backstory or "(unknown)", 0.85, 0.85, 0.85, 1.0)
                        addLineInChat("Trait: " .. (settler.traitTag or "none"), 0.75, 0.9, 0.75, 1.0)
                        addLineInChat("Skill: " .. (settler.skillLevel or 1)
                                      .. "  Mood: " .. (settler.mood or "Content"), 0.75, 0.9, 0.75, 1.0)
                    end
                end)

                -- Suppress vanilla "Pick up / Move" for settlers.
                return
            end

        end  -- instanceof IsoMannequin
    end

    -- ── 2. Container mark-private / mark-shared ───────────────────────────────
    if rec then
        for _, obj in ipairs(worldObjects) do
            if isContainerObject(obj) and playerIsInBastionBuilding(player, worldObjects, rec) then
                local key     = objKey(obj)
                if not key then break end
                local private = rec.privateContainers and rec.privateContainers[key]

                if private then
                    context:addOption("Mark as Shared", obj, function(target)
                        sendClientCommand(player, Bastion.MOD_KEY, "MarkPrivate",
                            { key = key, private = false })
                    end)
                else
                    context:addOption("Mark as Private", obj, function(target)
                        sendClientCommand(player, Bastion.MOD_KEY, "MarkPrivate",
                            { key = key, private = true })
                    end)
                end
                break  -- only the first container object matters here
            end
        end
    end

    -- ── 3. Building-level bastion options ─────────────────────────────────────
    local clickedBuilding, clickedSq = getClickedBuilding(player, worldObjects)
    if not clickedBuilding then return end

    local refSq = clickedSq or player:getCurrentSquare() or player:getSquare()
    if not refSq then return end

    if not rec then
        context:addOption("Establish Bastion", nil, function(_target)
            sendClientCommand(player, Bastion.MOD_KEY, "EstablishBastion", {
                bx = refSq:getX(),
                by = refSq:getY(),
                bz = refSq:getZ(),
            })
        end)
    elseif playerIsInBastionBuilding(player, worldObjects, rec) then
        -- Show HUD/log panel toggles plus noise budget
        context:addOption("Open Settlement Log", nil, function(_target)
            if BastionLogPanel then BastionLogPanel.toggle(player) end
        end)
        addNoiseBudgetMenu(context, player, rec)
        context:addOption("Collapse Bastion", nil, function(_target)
            sendClientCommand(player, Bastion.MOD_KEY, "CollapseBastion", {})
        end)
    end
end)

-- ── Initialisation ────────────────────────────────────────────────────────────

Events.OnGameStart.Add(function()
    -- Pull the shared ModData key so the client has up-to-date settlement state.
    ModData.request(Bastion.DATA_KEY)
end)

print("[Bastion] MaeClient done")
