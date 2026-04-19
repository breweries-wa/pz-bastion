-- Bastion_MaeClient.lua
-- Client-side only. Player index is passed as a number to all world context menu events.

print("[Bastion] MaeClient loading")

-- ── Local ModData access ──────────────────────────────────────────────────────

local function getWorldData()
    return ModData.get(Bastion.DATA_KEY) or {}
end

local function getMaeRecord(username)
    return getWorldData()[username]
end

-- ── Building helpers ──────────────────────────────────────────────────────────

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

-- ── Mae identification ────────────────────────────────────────────────────────
-- Checks both moddata (set at spawn) and position (from world ModData record)
-- so the check works even if moddata is not yet transmitted after a fresh load.

local function isMaeMannequin(obj, username, rec)
    if not instanceof(obj, "IsoMannequin") then return false end

    -- Primary: moddata tag set server-side at spawn
    local md = obj:getModData()
    if md["Bastion_Mae"] and md["Bastion_Owner"] == username then
        return true
    end

    -- Fallback: position match against stored record (handles cases where
    -- object moddata hasn't been transmitted to this client yet)
    if rec then
        local sq = obj:getSquare()
        if sq and sq:getX() == rec.x and sq:getY() == rec.y and sq:getZ() == rec.z then
            return true
        end
    end

    return false
end

-- ── Text display ──────────────────────────────────────────────────────────────

local function maeSpeak(mae, text)
    if HaloTextHelper and HaloTextHelper.addText then
        HaloTextHelper.addText(mae, text, 5)
    end
    if addLineInChat then
        addLineInChat("[Mae] " .. text, 0.85, 0.75, 1.0, 1.0)
    end
end

-- ── Context menu ──────────────────────────────────────────────────────────────

-- OnPreFillWorldObjectContextMenu fires unconditionally.
-- We use it to force safehouseAllowInteract = true so that
-- OnFillWorldObjectContextMenu fires regardless of safehouse ownership.
Events.OnPreFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects, test)
    local fetch = ISWorldObjectContextMenu and ISWorldObjectContextMenu.fetchVars
    if fetch then
        fetch.safehouseAllowInteract = true
        if fetch.c == 0 then fetch.c = 1 end
    end
end)

Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects, test)
    local player = getSpecificPlayer(playerIndex)
    if not player then return end

    local username = player:getUsername()
    local rec      = getMaeRecord(username)

    -- ── 1. Mae mannequin interaction ──────────────────────────────────────────
    for _, obj in ipairs(worldObjects) do
        if isMaeMannequin(obj, username, rec) then
            if not rec or not rec.introDone then
                local idx  = rec and rec.introIndex or 1
                local line = Bastion.DIALOGUE.intro[idx] or "..."
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
            -- Return so the vanilla "Pick up / Move" options don't appear for Mae.
            return
        end
    end

    -- ── 2. Building-level bastion options ─────────────────────────────────────
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
        context:addOption("Collapse Bastion", nil, function(_target)
            sendClientCommand(player, Bastion.MOD_KEY, "CollapseBastion", {})
        end)
    end
end)

-- ── Initialisation ────────────────────────────────────────────────────────────

Events.OnGameStart.Add(function()
    ModData.request(Bastion.DATA_KEY)
end)

print("[Bastion] MaeClient done")
