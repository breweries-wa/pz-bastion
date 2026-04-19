-- Bastion_Shared.lua
-- Loaded on both client and server (media/lua/shared/).
-- Contains all constants and dialogue so neither side hard-codes strings.

Bastion = Bastion or {}

Bastion.MOD_KEY  = "Bastion"       -- module name for sendClientCommand / sendServerCommand
Bastion.DATA_KEY = "Bastion_World" -- key into world-level ModData

-- Fixed tile offset from the bastion reference square where Mae spawns.
Bastion.MAE_OFFSET = { x = 2, y = 2, z = 0 }

-- ── Dialogue ──────────────────────────────────────────────────────────────────
-- intro    : shown in order, one line per right-click, then unlocks the menu.
--            introIndex tracks the NEXT line to show (1-based).
--            After showing intro[#intro], the server sets introDone = true.
-- checkIn  : one random line per "Check in" press.
-- needs    : one random line per "What do we need" press.
-- flavor   : one random line per "Tell me something" press.

Bastion.DIALOGUE = {

    intro = {
        "Oh. You can see me. That's... new.",
        "I've been here a while. Watching. You're the first person who's stopped.",
        "This place — if you want it — I can help you hold it. Just say the word.",
    },

    checkIn = {
        "Still here. Still watching.",
        "Quieter than yesterday. I'll take it.",
        "Walls are still standing. That's something.",
        "Everyone's tired but no one's dead. Good enough.",
        "Nothing's come through yet. Knock on wood.",
        "Some days are easier than others. Today isn't one of them.",
    },

    needs = {
        "More food. Preserved stuff — not fresh.",
        "We're low on ammo. Every round counts.",
        "First aid supplies. People keep getting hurt.",
        "A generator would change everything here.",
        "Boards. Always more boards.",
        "Water. Whatever you can carry.",
        "Fuel, if you find it. Generator won't run forever.",
    },

    flavor = {
        "I used to work nights. Turns out that was good practice.",
        "You notice how quiet it gets right before something goes wrong?",
        "I keep a list. It helps me feel like things are still under control.",
        "Don't name the ones outside. I made that mistake once.",
        "There's a difference between surviving and staying alive.",
        "Sound travels differently at night. You'll learn what to listen for.",
        "Some of them still reach for things. Doors. Handles. I try not to think about it.",
    },

}
