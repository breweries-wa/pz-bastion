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
Bastion.MAX_FLOOR                    = 7     -- highest z-level scanned (PZ supports 0-7)
Bastion.MAX_LOG_ENTRIES              = 200
Bastion.CALORIES_PER_SETTLER_PER_DAY = 2000
Bastion.WATER_PER_SETTLER_PER_DAY    = 4     -- units per settler per day

-- Water-pool tuning
Bastion.WATER_POOL_MAX          = 21.0  -- max settler-managed water (days); 3-week cap
Bastion.WATER_PER_CARRIER_TICK  = 2.0   -- settler-days of water added per WaterCarrier per tick (skill 1)
Bastion.WATER_CARRIER_SKILL_MOD = 0.3   -- extra days per skill level above 1
Bastion.WATER_FLOOR_DAYS        = 2.0   -- settler roles stop consuming when actual+pool < this
Bastion.WATER_SOURCE_SCAN_STEP  = 5     -- step size when scanning for water sources (perf)
Bastion.WATER_SOURCE_CACHE_DAYS = 7     -- re-scan for water sources every N in-game days

-- Scrap-to-ingot ratio for Blacksmith
Bastion.SCRAP_PER_INGOT  = 4    -- scrap items consumed per ingot produced
Bastion.SCRAP_FLOOR      = 10   -- minimum scrap count the blacksmith will never touch

-- ── Item type strings for settler production ──────────────────────────────────
-- OQ #22: verify against B42 registry with getScriptManager():getItem(v)
Bastion.ITEMS = {
    PLANK           = "Base.WoodenPlank",
    THREAD          = "Base.Thread",
    BANDAGE_STERILE = "Base.BandageSterile",
    METAL_BAR       = "Base.MetalBar",
    EGG             = "Base.Egg",
    MILK            = "Base.MilkCarton",
    FISH            = "Base.FishFreshSmall",
    VEGETABLE       = "Base.Tomato",
    BERRY           = "Base.BlackBerries",
}

-- Consumption per settler per day (item counts)
Bastion.FOOD_ITEMS_PER_SETTLER_PER_DAY  = 1
Bastion.WATER_ITEMS_PER_SETTLER_PER_DAY = 1

-- ── Noise budgets ─────────────────────────────────────────────────────────────

Bastion.NOISE_BUDGETS       = { Silent=1, Quiet=3, Normal=6, Loud=12 }
Bastion.NOISE_BUDGET_LEVELS = { "Silent", "Quiet", "Normal", "Loud" }

-- ── Role definitions ─────────────────────────────────────────────────────────
-- noise: units this role adds to the settlement noise score per tick.

Bastion.ROLES = {
    Woodcutter   = { noise=3, display="Woodcutter"    },
    Cook         = { noise=1, display="Cook"          },
    Farmer       = { noise=1, display="Farmer"        },
    Doctor       = { noise=0, display="Doctor"        },
    Teacher      = { noise=0, display="Teacher"       },
    Mechanic     = { noise=2, display="Mechanic"      },
    Tailor       = { noise=0, display="Tailor"        },
    Trapper      = { noise=0, display="Trapper"       },
    Fisher       = { noise=0, display="Fisher"        },
    Forager      = { noise=0, display="Forager"       },
    Defender     = { noise=2, display="Defender"      },
    Hunter       = { noise=3, display="Hunter"        },
    Child        = { noise=0, display="Child"         },
    -- New in this phase:
    Blacksmith   = { noise=3, display="Blacksmith"    },
    Rancher      = { noise=0, display="Rancher"       },
    WaterCarrier = { noise=0, display="Water Carrier" },
}

Bastion.STARTER_ROLES = { "Woodcutter", "Cook", "Farmer" }

-- ── Per-role settings defaults ─────────────────────────────────────────────
-- Override individual keys via rec.roleSettings[roleName][key].
-- Read via Bastion.getSetting(rec, role, key).

Bastion.ROLE_SETTINGS_DEFAULTS = {
    Tailor       = { maxThread    = 50,  addPatches = false },
    Doctor       = { maxBandages  = 20  },
    Trapper      = { trapRadius   = 60  },
    Fisher       = { fishRadius   = 80,  maxFishStock = 30 },
    Cook         = { mealsPerDay  = 0,   allowDryGoods = false },
    -- mealsPerDay=0 means "auto" (settlers + 1 buffer); set >0 to cap
    Farmer       = { saveSeeds    = true },
    Mechanic     = { vehicleRadius = 30, fuelOnly = false },
    Blacksmith   = { maxIngots    = 20,  scrapFloor = 10 },
    Woodcutter   = { maxPlanks    = 60,  keepFiresLit = true },
    Rancher      = { minGrainReserve = 10 },
    WaterCarrier = { collectRadius = 50  },
}

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
    "Optimist","Nervous","Practical","Has Bad Dreams","Keeps to Herself",
    "Keeps to Himself","Tells Bad Jokes","Believes in Something",
    "Gets Quiet When It Rains","Former Teacher","Light Sleeper",
    "Doesn't Talk About Before","Hard Worker","Cautious","Quick Temper",
    "Good with Kids","Night Owl","Can't Sleep","Hums While Working",
    "Never Wastes Anything","Keeps a Journal","Used to the Quiet",
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

Bastion.SETTLER_LINES = {
    Content = {
        "Doing alright.","Just keeping busy.","Could be worse.",
        "We're making it work.","Thanks for checking in.",
    },
    Struggling = {
        "I'm... managing.","Not a great week.",
        "I'll be okay. Just need some time.","Things have been hard lately.",
    },
    Critical = {
        "I can't keep doing this.",
        "I need things to change. Soon.",
        "I'm not sure how much longer I can stay.",
    },
}

-- ── Utility functions ─────────────────────────────────────────────────────────

function Bastion.pickRandom(t)
    if not t or #t == 0 then return nil end
    return t[ZombRand(#t) + 1]
end

function Bastion.buildNameSet(settlers)
    local set = {}
    for _, s in ipairs(settlers or {}) do
        if s.name then set[s.name] = true end
    end
    return set
end

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

-- Append a log entry.  Newest entries at front of list (index 1).
function Bastion.addLog(rec, text, logType)
    rec.settlementLog = rec.settlementLog or {}
    table.insert(rec.settlementLog, 1, {
        day     = Bastion.getCurrentDay(),
        text    = text,
        logType = logType or "standard",
    })
    while #rec.settlementLog > Bastion.MAX_LOG_ENTRIES do
        table.remove(rec.settlementLog)
    end
end

-- Read a per-role setting, falling back to the built-in default.
function Bastion.getSetting(rec, role, key)
    local override = rec.roleSettings and rec.roleSettings[role]
    local val = override and override[key]
    if val ~= nil then return val end
    local defaults = Bastion.ROLE_SETTINGS_DEFAULTS[role]
    return defaults and defaults[key]
end

-- Safe current-day helper.
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
