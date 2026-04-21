-- ============================================================
-- Bastion_MaeClient.lua  (media/lua/client/)
-- Client-side only.
-- Handles: context menus (establish, check-on, settler chat,
--          mark-private), ModData sync on load.
--
-- Noise budget and Disband are now inside BastionWindow (Settings tab).
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

-- ── Container helpers ─────────────────────────────────────────────────────────

local function objKey(obj)
    local sq = obj:getSquare()
    if not sq then return nil end
    return sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
end

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

    -- ── Container mark-private / mark-shared ───────────────────────────────────
    if rec then
        for _, obj in ipairs(worldObjects) do
            if isContainerObject(obj) and playerIsInBastionBuilding(player, worldObjects, rec) then
                local key = objKey(obj)
                if not key then break end
                local private = rec.privateContainers and rec.privateContainers[key]

                if private then
                    context:addOption("Mark as Shared", obj, function(target)
                        sendClientCommand(player, Bastion.MOD_KEY, "MarkPrivate",
                            { key = key, private = false })
                        -- Optimistic local update so the window reflects the change
                        -- immediately while the server recalculates and transmits.
                        local wd = ModData.get(Bastion.DATA_KEY)
                        if wd and wd[username] and wd[username].privateContainers then
                            wd[username].privateContainers[key] = nil
                        end
                        if BastionWindow and BastionWindow._instance then
                            BastionWindow._instance:populate()
                        end
                    end)
                else
                    context:addOption("Mark as Private", obj, function(target)
                        sendClientCommand(player, Bastion.MOD_KEY, "MarkPrivate",
                            { key = key, private = true })
                        -- Optimistic local update so the window reflects the change
                        -- immediately while the server recalculates and transmits.
                        local wd = ModData.get(Bastion.DATA_KEY)
                        if wd and wd[username] and wd[username].privateContainers then
                            wd[username].privateContainers[key] = true
                        end
                        if BastionWindow and BastionWindow._instance then
                            BastionWindow._instance:populate()
                        end
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
        -- No bastion yet — offer to establish one
        context:addOption("Establish Bastion", nil, function(_target)
            sendClientCommand(player, Bastion.MOD_KEY, "EstablishBastion", {
                bx = refSq:getX(),
                by = refSq:getY(),
                bz = refSq:getZ(),
            })
            -- Open the window immediately; Overview will show "establishing…"
            -- until the server processes and ModData syncs (~5 s auto-refresh).
            if BastionWindow then
                BastionWindow.open(player)
            end
        end)
    elseif playerIsInBastionBuilding(player, worldObjects, rec) then
        -- Bastion exists — single entry point into the management window
        context:addOption("Check on Bastion", nil, function(_target)
            if BastionWindow then BastionWindow.toggle(player) end
        end)

        -- Admin tools in a submenu so they don't clutter the main list
        local adminOpt = context:addOption("Bastion Admin", worldObjects, nil)
        local adminSub = ISContextMenu:getNew(context)
        context:addSubMenu(adminOpt, adminSub)
        adminSub:addOption("Force Tick", nil, function()
            sendClientCommand(player, Bastion.MOD_KEY, "ForceTick", {})
        end)
        adminSub:addOption("Add Settler", nil, function()
            sendClientCommand(player, Bastion.MOD_KEY, "AddSettler", {})
        end)
        adminSub:addOption("Dump Building", nil, function()
            sendClientCommand(player, Bastion.MOD_KEY, "Dump", {})
        end)
    end
end)

-- ── Initialisation ────────────────────────────────────────────────────────────

Events.OnGameStart.Add(function()
    -- Pull the shared ModData key so the client has up-to-date settlement state.
    ModData.request(Bastion.DATA_KEY)
end)

print("[Bastion] MaeClient done")
