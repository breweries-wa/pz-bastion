-- Bastion_MaeServer.lua
-- Server-side only (media/lua/server/).
-- Works in singleplayer and multiplayer.
--
-- Responsibilities:
--   • Spawn Mae (IsoMannequin) when a player establishes a bastion.
--   • Remove Mae when a player collapses their bastion.
--   • Persist bastion state in world-level ModData (transmitted to all clients).

-- Bastion_Shared is auto-loaded by PZ from media/lua/shared/ — do NOT require it.
print("[Bastion] MaeServer loading")

-- ── World ModData helpers ─────────────────────────────────────────────────────

local function getWorldData()
    return ModData.getOrCreate(Bastion.DATA_KEY)
end

local function getMaeRecord(username)
    return getWorldData()[username]
end

local function saveMaeRecord(username, bx, by, bz, mx, my, mz)
    local wd = getWorldData()
    wd[username] = {
        bx         = bx, by = by, bz = bz,  -- building reference square (player position at Establish)
        x          = mx, y  = my, z  = mz,  -- Mae's actual spawn position
        introIndex = 1,                      -- index of the NEXT intro line to show (1-based)
        introDone  = false,
    }
    ModData.transmit(Bastion.DATA_KEY)
end

local function clearMaeRecord(username)
    local wd = getWorldData()
    wd[username] = nil
    ModData.transmit(Bastion.DATA_KEY)
end

-- ── Mae spawn ─────────────────────────────────────────────────────────────────
-- Mae is an IsoMannequin placed directly at the target square.
-- Moddata is set synchronously before adding to the world — no deferred tagging needed.

local MAE_SPRITE = "location_shop_mall_01_65"  -- female store mannequin sprite

local function spawnMae(username, mx, my, mz)
    local cell = getCell()
    if not cell then
        print("[Bastion] spawnMae: getCell() returned nil")
        return
    end

    local sq = cell:getGridSquare(mx, my, mz)
    if not sq then
        print("[Bastion] spawnMae: no grid square at " .. mx .. "," .. my .. "," .. mz)
        return
    end

    local spr = getSprite(MAE_SPRITE)
    if not spr then
        print("[Bastion] spawnMae: sprite not found: " .. MAE_SPRITE)
        return
    end

    local obj = IsoMannequin.new(cell, sq, spr)
    obj:setSquare(sq)

    -- Use the base female mannequin script (pose01, no outfit).
    -- TODO: define a custom "MaeMedical" mannequin script with scrubs outfit.
    if obj.setMannequinScriptName then
        obj:setMannequinScriptName("FemaleBlack01")
    end

    -- Tag so we can identify Mae later (by moddata AND position).
    local md = obj:getModData()
    md["Bastion_Mae"]   = true
    md["Bastion_Owner"] = username

    -- Add to world and sync to all clients.
    local insertIdx = sq:getObjects():size()
    sq:AddSpecialObject(obj, insertIdx)
    if obj.transmitCompleteItemToClients then
        obj:transmitCompleteItemToClients()
    end

    print("[Bastion] Mae spawned for " .. username .. " at " .. mx .. "," .. my .. "," .. mz)
end

-- ── Mae removal ───────────────────────────────────────────────────────────────

local function removeMae(rec)
    local cell = getCell()
    if not cell then return end

    local sq = cell:getGridSquare(rec.x, rec.y, rec.z)
    if not sq then return end

    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoMannequin") then
            local md = o:getModData()
            if md["Bastion_Mae"] then
                sq:transmitRemoveItemFromSquare(o)
                print("[Bastion] Mae removed from " .. rec.x .. "," .. rec.y .. "," .. rec.z)
                return
            end
        end
    end
    print("[Bastion] removeMae: no tagged mannequin found at " .. rec.x .. "," .. rec.y .. "," .. rec.z)
end

-- ── Client command handler ────────────────────────────────────────────────────

local function onClientCommand(module, command, player, args)
    if module ~= Bastion.MOD_KEY then return end

    local username = player:getUsername()

    if command == "EstablishBastion" then
        if getMaeRecord(username) then return end  -- already has a bastion

        local bx = args.bx
        local by = args.by
        local bz = args.bz or 0
        local mx = bx + Bastion.MAE_OFFSET.x
        local my = by + Bastion.MAE_OFFSET.y
        local mz = bz + (Bastion.MAE_OFFSET.z or 0)

        saveMaeRecord(username, bx, by, bz, mx, my, mz)
        spawnMae(username, mx, my, mz)

    elseif command == "CollapseBastion" then
        local rec = getMaeRecord(username)
        if not rec then return end

        -- Clear the record BEFORE removeMae so any future lookup misses it.
        clearMaeRecord(username)
        removeMae(rec)

    elseif command == "AdvanceIntro" then
        local wd  = getWorldData()
        local rec = wd[username]
        if not rec or rec.introDone then return end

        rec.introIndex = rec.introIndex + 1

        if rec.introIndex > #Bastion.DIALOGUE.intro then
            rec.introDone  = true
            rec.introIndex = #Bastion.DIALOGUE.intro  -- clamp; never goes out of bounds
        end

        ModData.transmit(Bastion.DATA_KEY)
    end
end

-- ── Event registration ────────────────────────────────────────────────────────

Events.OnClientCommand.Add(onClientCommand)
