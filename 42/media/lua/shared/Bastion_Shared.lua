-- ============================================================
-- Bastion_Shared.lua  (media/lua/shared/)
-- Auto-loaded by PZ on both client and server. Do NOT require.
-- ============================================================
print("[Bastion] Shared loading")

Bastion = Bastion or {}
Bastion.MOD_KEY  = "Bastion"
Bastion.DATA_KEY = "Bastion_World"
Bastion.VERSION  = 1

-- ── Tuning ────────────────────────────────────────────────────────────────────

Bastion.SCAN_RANGE                   = 25    -- tiles around bx,by to scan for containers
Bastion.MAX_LOG_ENTRIES              = 100
Bastion.CALORIES_PER_SETTLER_PER_DAY = 2000
Bastion.WATER_PER_SETTLER_PER_DAY    = 4     -- rough units

-- Spawn offsets from the bastion reference square for settler mannequins.
Bastion.SETTLER_OFFSETS = {
    { x=2, y=2, z=0 },
    { x=3, y=2, z=0 },
    { x=2, y=3, z=0 },
    { x=4, y=2, z=0 },
    { x=3, y=3, z=0 },
    { x=1, y=2, z=0 },
    { x=2, y=1, z=0 },
}

-- ── Noise budgets ─────────────────────────────────────────────────────────────

Bastion.NOISE_BUDGETS       = { Silent=1, Quiet=3, Normal=6, Loud=12 }
Bastion.NOISE_BUDGET_LEVELS = { "Silent", "Quiet", "Normal", "Loud" }

-- ── Role definitions ─────────────────────────────────────────────────────────
-- noise: units this role adds to the settlement noise score per tick.
-- Tick logic lives in server; only shared metadata here.

Bastion.ROLES = {
    Woodcutter = { noise=3, display="Woodcutter" },
    Cook       = { noise=1, display="Cook"       },
    Farmer     = { noise=1, display="Farmer"     },
    Doctor     = { noise=0, display="Doctor"     },
    Teacher    = { noise=0, display="Teacher"    },
    Mechanic   = { noise=2, display="Mechanic"   },
    Tailor     = { noise=0, display="Tailor"     },
    Trapper    = { noise=0, display="Trapper"    },
    Fisher     = { noise=0, display="Fisher"     },
    Forager    = { noise=0, display="Forager"    },
    Defender   = { noise=2, display="Defender"   },
    Hunter     = { noise=3, display="Hunter"     },
    Child      = { noise=0, display="Child"      },
}

Bastion.STARTER_ROLES = { "Woodcutter", "Cook", "Farmer" }

-- ── NPC Generation Tables ────────────────────────────────────────────────────

Bastion.NAMES = {
    male = {
        "James","John","Robert","Michael","William","David","Richard","Joseph",
        "Thomas","Charles","Daniel","Matthew","Anthony","Donald","Mark","Paul",
        "Steven","Andrew","Kenneth","Joshua","Kevin","Brian","George","Timothy",
        "Ronald","Edward","Jason","Jeffrey","Ryan","Gary",
    },
    female = {
        "Mary","Patricia","Jennifer","Linda","Barbara","Elizabeth","Susan",
        "Jessica","Sarah","Karen","Lisa","Nancy","Betty","Margaret","Sandra",
        "Ashley","Dorothy","Kimberly","Emily","Donna","Michelle","Carol",
        "Amanda","Melissa","Deborah","Stephanie","Rebecca","Sharon","Laura","Cynthia",
    },
    last = {
        "Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis",
        "Wilson","Taylor","Anderson","Thomas","Jackson","White","Harris","Martin",
        "Thompson","Young","Allen","King","Wright","Scott","Torres","Nguyen",
        "Hill","Flores","Green","Adams","Nelson","Baker","Hall","Rivera",
        "Campbell","Mitchell","Carter","Roberts","Gomez","Phillips","Evans","Turner",
    },
}

Bastion.TRAIT_TAGS = {
    "Optimist",
    "Nervous",
    "Practical",
    "Has Bad Dreams",
    "Keeps to Herself",
    "Keeps to Himself",
    "Tells Bad Jokes",
    "Believes in Something",
    "Gets Quiet When It Rains",
    "Former Teacher",
    "Light Sleeper",
    "Doesn't Talk About Before",
    "Hard Worker",
    "Cautious",
    "Quick Temper",
    "Good with Kids",
    "Night Owl",
    "Can't Sleep",
    "Hums While Working",
    "Never Wastes Anything",
    "Keeps a Journal",
    "Used to the Quiet",
    "Counts Things to Stay Calm",
}

Bastion.BACKSTORY = {
    occupations = {
        "Carpenter","Mechanic","Nurse","Truck Driver","Farmer",
        "Librarian","High School Teacher","Line Cook","Army Veteran",
        "Police Officer","Factory Worker","Retail Manager","Plumber",
        "Electrician","College Student","EMT","Construction Worker",
        "Office Worker","Postal Worker","Auto Mechanic",
    },
    locations = {
        "Muldraugh","West Point","Rosewood","Riverside","March Ridge",
        "Louisville","Ekron","Irvington","Brandenburg","Hardin County",
    },
    circumstances = {
        "who doesn't talk about before",
        "who lost everyone in the first week",
        "who walked for three weeks to get here",
        "who was alone for months before this",
        "who was with a group that didn't make it",
        "who watched their town fall",
        "who was passing through when it happened",
        "who hadn't stopped moving until now",
        "who had given up looking for other people",
        "who used to think they could handle anything",
    },
}

-- Settler right-click flavor lines, keyed by mood state.
Bastion.SETTLER_LINES = {
    Content = {
        "Doing alright.",
        "Just keeping busy.",
        "Could be worse.",
        "We're making it work.",
        "Thanks for checking in.",
    },
    Struggling = {
        "I'm... managing.",
        "Not a great week.",
        "I'll be okay. Just need some time.",
        "Things have been hard lately.",
    },
    Critical = {
        "I can't keep doing this.",
        "I need things to change. Soon.",
        "I'm not sure how much longer I can stay.",
    },
}

-- ── Utilities ─────────────────────────────────────────────────────────────────

function Bastion.pickRandom(t)
    if not t or #t == 0 then return nil end
    return t[ZombRand(#t) + 1]
end

-- Build an existing-name set from a settlers list for collision avoidance.
function Bastion.buildNameSet(settlers)
    local set = {}
    for _, s in ipairs(settlers or {}) do
        if s.name then set[s.name] = true end
    end
    return set
end

-- Generate a raw NPC data table.
function Bastion.generateNPC(existingNames)
    existingNames = existingNames or {}
    local isMale   = ZombRand(2) == 0
    local namePool = isMale and Bastion.NAMES.male or Bastion.NAMES.female

    local first = Bastion.pickRandom(namePool)
    local last  = Bastion.pickRandom(Bastion.NAMES.last)
    for _ = 1, 6 do
        if not existingNames[first .. " " .. last] then break end
        first = Bastion.pickRandom(namePool)
        last  = Bastion.pickRandom(Bastion.NAMES.last)
    end

    local tag = Bastion.pickRandom(Bastion.TRAIT_TAGS)
    if isMale     and tag == "Keeps to Herself" then tag = "Keeps to Himself" end
    if not isMale and tag == "Keeps to Himself" then tag = "Keeps to Herself" end

    return {
        name       = first .. " " .. last,
        isMale     = isMale,
        traitTag   = tag,
        backstory  = string.format("%s from %s %s",
                        Bastion.pickRandom(Bastion.BACKSTORY.occupations),
                        Bastion.pickRandom(Bastion.BACKSTORY.locations),
                        Bastion.pickRandom(Bastion.BACKSTORY.circumstances)),
        skillLevel = ZombRand(4) + 1,
        mood       = "Content",
    }
end

-- Append an entry to the settlement log.
-- logType: "standard" | "warning" | "critical" | "arrival" | "milestone"
function Bastion.addLog(rec, text, logType)
    rec.settlementLog = rec.settlementLog or {}
    local day = Bastion.getCurrentDay()
    table.insert(rec.settlementLog, 1, {
        day     = day,
        text    = text,
        logType = logType or "standard",
    })
    while #rec.settlementLog > Bastion.MAX_LOG_ENTRIES do
        table.remove(rec.settlementLog)
    end
end

-- Safe current-day helper (returns 0 if getGameTime is unavailable).
function Bastion.getCurrentDay()
    if not getGameTime then return 0 end
    local ok, d
    ok, d = pcall(function() return getGameTime():getNightsSurvived() end)
    if ok and type(d) == "number" then return d end
    ok, d = pcall(function() return math.floor(getGameTime():getWorldAgeHours() / 24) end)
    if ok and type(d) == "number" then return d end
    return 0
end

print("[Bastion] Shared done")
