-- ============================================================
-- Bastion_AdminCommands.lua  (media/lua/client/)
-- Client-side chat interceptor for /bastion admin commands.
-- Admin and Moderator players only; checked server-side.
--
-- Usage (in-game chat):
--   /bastion help
--   /bastion status
--   /bastion tick
--   /bastion reset [username]
--   /bastion addlog <text>
-- ============================================================
print("[Bastion] AdminCommands loading")

-- ── Chat intercept ────────────────────────────────────────────────────────────
-- Events.OnPlayerSay fires client-side when the local player sends a message.
-- The message still appears in chat — acceptable for admin tooling.
-- Signature in B42: OnPlayerSay(player, message)
--   player  — IsoPlayer (or player index in some versions; handled below)
--   message — string

Events.OnPlayerSay.Add(function(playerOrIndex, message)
    -- Normalise: player might be passed as an index in some PZ versions.
    local player
    if type(playerOrIndex) == "number" then
        player = getSpecificPlayer(playerOrIndex)
    else
        player = playerOrIndex
    end
    if not player then return end

    -- Only intercept messages that start exactly with "/bastion"
    local text = type(message) == "string" and message or ""
    if text:sub(1, 8):lower() ~= "/bastion" then return end

    -- Forward to server for access-level check and execution.
    sendClientCommand(player, Bastion.MOD_KEY, "AdminCmd", { raw = text })
end)

print("[Bastion] AdminCommands done")
