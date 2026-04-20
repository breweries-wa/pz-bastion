# Bastion — Design Document
> Project Zomboid Build 42 Mod | v1.1

---

## Development Workflow

**Design before code.**  The design document is the source of truth for what the mod does.  Updates to phases, systems, and tests are made here first.  Code follows the design.  If code diverges from the document during implementation, the document is updated immediately to reflect the actual decision and the reason for it.

**Each phase has a test plan.**  Tests are written alongside the design spec — before implementation begins.  Tests are numbered hierarchically (T{group}.{test}).  Untested behavior doesn't ship.

**Open questions are tracked explicitly.**  If a design decision is unsettled, it lives in Section 16.  Resolved questions stay in the table with status `Resolved` and a brief note.

---

## Table of Contents
1. [Concept](#1-concept)
2. [Technical Constraints](#2-technical-constraints)
3. [Settlement Boundary](#3-settlement-boundary)
4. [The Settlement Tick](#4-the-settlement-tick)
5. [Community Scores](#5-community-scores)
6. [Settlers & Specialists](#6-settlers--specialists)
7. [NPC Generation](#7-npc-generation)
8. [Resources & Storage](#8-resources--storage)
9. [Threats & Defense](#9-threats--defense)
10. [Communication & Feedback](#10-communication--feedback)
11. [Admin & Debug Controls](#11-admin--debug-controls)
12. [NPC Representation](#12-npc-representation)
13. [Comparable Games & Borrowed Mechanics](#13-comparable-games--borrowed-mechanics)
14. [Implementation Phases](#14-implementation-phases)
15. [Test Plans](#15-test-plans)
16. [Open Questions](#16-open-questions)

---

## 1. Concept

Bastion is a community-building mod for Project Zomboid.  You are the scavenger — the one who goes out into the dangerous world to bring things back.  The community depends on you.  You depend on the community.

The mod adds something to care about.  The people in your settlement have names, roles, and light personalities.  When someone dies, someone says their name.  That's enough.

### 1.1 Core Fantasy

- You are the link between civilization and the wasteland
- Going out feels meaningful because people are counting on you
- Coming back feels like coming home
- Each survivor added is a small victory with ongoing stakes

### 1.2 Settler Purpose: Taking Over the Grind

Build 42 added significant repetitive work to the survival loop: picking thread from rags, boiling rags into bandages, the blacksmith spoon-grind, watering every crop plot individually, checking trap lines, daily animal husbandry.  These tasks are necessary but not interesting.  The Indie Stone has stated that B42's grind is intentionally designed for NPC delegation in the planned B43 NPC system.  Bastion delivers that vision early.

The design principle: **settlers take over tasks that are time-consuming by repetition, not by decision**.  If the interesting part of a task is the first time you do it, the settler should handle every subsequent iteration.

Examples of what settlers take from the player:
- Tailor picks thread from rags and washes dirty rags daily (but never depletes the rag supply — configurable cap)
- Doctor boils rags into sterilized bandages (up to a cap; the stock is there when needed)
- WaterCarrier collects and boils dirty water into the settler water pool (so other roles don't drain player containers)
- Cook uses perishable food first — the food that would spoil before the player eats it
- Blacksmith smelts scrap into ingots — prep work, not the XP grind the player wants to run themselves
- Rancher feeds animals, collects eggs and milk daily

What settlers **do not** take:
- Resources the player needs for skill advancement (e.g., the spoon grind stays for the player; the blacksmith only smelts scrap above a configurable floor)
- Shelf-stable reserves unless explicitly allowed (Cook default: perishables only)
- All water (the settler pool supplements — it never replaces — player container water)
- The last unit of any resource (every role has a floor setting it respects)

### 1.3 Endgame Goal: Self-Sufficiency

The long-term goal is a community that can sustain itself across five pillars:

| Pillar | What Self-Sufficiency Looks Like |
|--------|----------------------------------|
| Food | Farming + preservation produce enough calories; no dependence on looting for sustenance |
| Water | WaterCarriers + rain collection sustain the population without outside supply runs |
| Medical | Doctor, herb garden, and crafted supplies handle illness and injury without hospital raids |
| Defense | Defenders, fortifications, and threat management handle zombie pressure autonomously |
| Morale | Reading, community culture, and children sustain morale without constant intervention |

---

## 2. Technical Constraints

What PZ's Lua modding API can and cannot do.  These are hard limits, not design choices.  Every system in this document should be read with these in mind.

### 2.1 Truly Impossible (Java-side, no Lua exposure)

**Animated, pathfinding NPCs.**
PZ's character movement, pathfinding, and animation systems are Java.  There is no Lua API to create a walking, animated NPC.  The B42 team is building a native NPC system, but it is not yet moddable.  Until that changes, settlers cannot physically move through the world.  Every design element that implies a settler *doing something physically* — walking to the woodpile, patrolling a perimeter, following the player — is a simulation that exists only in the log.  Section 12 addresses what we can fake and how.

**Modifying zombie noise/attraction AI.**
Zombie pathfinding toward sound sources is Java.  We cannot make zombies genuinely react to settlement noise.  The simulation: schedule zombie spawns near the settlement at a rate derived from the noise score.  The effect is the same from the player's perspective; the mechanism is different.

**Real escort quests.**
An NPC following the player through the open world requires pathfinding.  Not possible.  The mod version: the player finds a quest target, right-clicks to recruit them, and they appear at the settlement.  The journey is implied, not animated.

### 2.2 Requires Custom Simulation

**Settler skill advancement.**
PZ's XP and skill system is for the player character only.  Settler skill levels are plain numbers stored in ModData, incremented by our own logic each tick.

**Farmer interacting with crops.**
PZ's farming Lua API surface is unverified.  Fall back to: Farmer adds harvested food to virtual yield on tick, with no actual crop object interaction, until verified otherwise.

**Refrigerated storage genuinely slowing spoilage.**
In vanilla PZ, items inside a powered fridge spoil slower — that's Java-side.  Our category labels and PZ's spoilage logic are separate systems.

**Reading speed modification.**
Modifying how fast the player reads a skill book requires a client-side tick hook watching for an open book.  The Teacher role sets `teacherActive = true`; the client applies a reading time modifier when that flag is set and the player is inside the bastion.  Exact API for reading state is unverified — see Open Question #20.

### 2.3 Feasible but With Known Risks

**Item spawning in containers (virtual yield claiming).**
The server can call `container:addItem()` to place items in world containers.  Risk: finding the right container, handling full containers, ensuring the item type string is valid.  This is Phase 3 work.  For now, virtual yield is tracked in ModData and displayed; the player cannot claim it as physical items yet.

**Item registry performance.**
Iterating every container in the settlement on every tick is fine at small scale.  At large settlements it may cause frame hitches.  The registry is built with caching and does not scan the world more than once per tick.

**World-state cache (water source, heat source, animals).**
Scanning 50-tile radius for water sources at every tick would be expensive.  Cache results are refreshed every 7 in-game days.  The player can force a refresh by disbanding and re-establishing (or via admin command in a later phase).

### 2.4 Kahlua-Specific Gotchas

- **No `goto` / `::label::`** — Lua 5.1 only.  Use `if instanceof` blocks instead of `continue`.
- **Java exceptions escape `pcall`** — `item:getNutrition():getCalories()` can throw a Java `RuntimeException` that `pcall` cannot catch.  All Java-backed calls go through `pcall` chains; fallback flat estimates used where exceptions are known to occur.
- **`math.random` is nil** — use `ZombRand(n)` instead.  Returns 0 to n-1.
- **`Events.OnModDataTransmit` does not exist in B42** — removed; panels repopulate on open.
- **`table.unpack` is nil** — use `unpack` (Lua 5.1 global).

### 2.5 The Consequence for Design Language

Any place in this document that describes a settler *doing* something physically should be understood as shorthand for: **the tick runs, the log records it, the outcome is applied.**  "Timmy walked to the treeline and chopped wood" means "the Woodcutter tick ran, a plank count was added to virtual yield, and a log entry was written."  There is no Timmy walking anywhere.  This is not a limitation to apologize for — it is the design.  The log is the simulation.

---

## 3. Settlement Boundary

The settlement boundary determines what is "inside" the Bastion — which containers are community storage, which settlers are home, which beds and work sites count, and what the zombie attraction radius covers.

### 3.1 Radius-Based Boundary

The boundary is a **fixed tile radius from the bastion anchor square** (the tile clicked when the bastion was established).  The radius grows automatically as the settler count increases — no manual expansion is needed.

> ⚑ OPEN: Exact growth formula not yet defined.  Starting radius, step size per additional settler, and maximum radius to be tuned during Phase 3 playtesting.  See Open Question #27.

Player-built extensions (walls, floors, roofed areas attached to the main building) fall inside the radius automatically because the radius is geometric, not room-based.  `sq:getRoom()` is explicitly **not** used for boundary decisions — see Section 2.4.

The safehouse property system is no longer the primary boundary mechanism.  The radius is the boundary.

> ⚑ OPEN: PZ's safehouse system may still be relevant for container marking / shared-container state.  Validate whether we need it at all in Phase 3.  See Open Question #1.

### 3.2 Radius Visualization ("Bastion View")

When the **Bastion Window is open**, the settlement radius is visualized in the world.  When it is closed, the visualization disappears.  The two are inseparable — there is no separate "show radius" toggle.

**What is shown:**

| Element | Behavior |
|---------|----------|
| **Colored tile overlay** | Each tile within the radius is tinted by category: general zone (neutral), container-bearing tiles (blue tint), bed tiles (green tint), detected work sites (yellow tint), water sources (cyan tint) |
| **Hover labels** | Hovering the mouse over a tile within the radius shows a floating label naming the relevant object (bed, container, work site type, etc.) |

Both elements activate together and deactivate together when the window opens/closes.

> ⚑ OPEN: PZ's `WorldToScreen` API for rendering tile-space overlays and floating labels needs verification.  The exact draw hook (likely `Events.OnPostRenderFloor` or similar) is unconfirmed.  See Open Question #28.

**Implementation approach:**
- Client-side only; no server communication
- On window open: build a tile list from anchor + radius, categorize each tile, store in `BastionWindow.overlayTiles`
- Each render tick: walk `overlayTiles` and draw colored quads / floating strings
- On window close: clear `overlayTiles`

The overlay is rebuilt whenever the window is opened (not cached between sessions) to pick up any world changes since last open.

---

## 4. The Settlement Tick

Settlers don't visibly walk around performing tasks.  Instead, the simulation advances on a **settlement tick** — once per in-game day.  On each tick, each settler with an assigned role performs their function invisibly and the result is logged.

### 4.1 How the Tick Works

On each tick, for each settler:
1. Check if their role's requirements are met (resources available, tools present, skill sufficient, resource floor not hit, cap not reached)
2. If yes: apply the effect (add to virtual yield, update scores, debit from settler water pool)
3. If no: log a shortage or idle message — never silently skip
4. Append a log entry

### 4.2 Log Message Style

Short, named, specific.  The player should be able to read the log and understand exactly what happened without inferring.

```
Timmy collected 2 logs from the woodpile.
Timmy — plank stock at cap (60). No logs consumed.
Rosa prepared 4 meals (3 from perishables).
Rosa couldn't cook — settler water supply too low for washing.
Dr. Okafor sterilized 5 bandages. Stock: 17/20.
Dr. Okafor — no heat source in bastion; can't sterilize.
Sarah collected and boiled water. +2.0 days to pool (6.5 / 21.0).
Sarah couldn't collect water — no water source found nearby.
Marcus — thread stock is at cap (50). No rags consumed.
[QUIET MODE] Woodcutting skipped — noise budget exceeded.
```

### 4.3 Tick Frequency

Once per in-game day.  The check runs on `Events.EveryOneMinute`; the tick fires only if the current in-game day is greater than `rec.lastTickDay`.

---

## 5. Community Scores

Community-wide metrics that influence settler behavior, production, and arrival rates.

### 5.1 Resource Scores (Objective Gauges)

| Score | What It Measures | Critical Effect |
|-------|-----------------|-----------------|
| **Food** | Days of food remaining at current consumption | Below 3 days: warning logged; below 1: Happiness drops |
| **Water** | Days of water (containers + settler pool) | Below 2 days: Doctor and Farmer skip water-using steps |
| **Settler Water Pool** | Settler-managed water buffer (days) | Fills from WaterCarrier role; drawn by Doctor, Farmer, Tailor |
| **Noise** | Current noise output vs. player-set budget | Over budget: noisy roles suppressed |
| **Storage** | Available community container capacity | Full: virtual yield can't be deposited |

### 5.2 Subjective Scores

Slower to move.  Reflect the emotional and social state of the settlement.

| Score | What It Measures |
|-------|-----------------|
| **Happiness** | Day-to-day comfort and quality of life |
| **Resolve** | Long-term will to survive; hope |
| **Education** | Accumulated community knowledge |

> ⚑ OPEN: Score threshold values and decay rates not yet tuned.  See Open Question #7.

### 5.3 Score Contributor UI (Phase 3 target)

Every score in the Overview tab lists every active contributor directly below it.  The player should never guess why a score is moving.

```
OVERVIEW
────────────────────────────
Food: 8 days  [OK]
  + Rosa cooking (reduces waste)       +1 day
  - 6 settlers consuming               -0.8/day

Water: 6.2 days  (1.5 from settler pool)  [OK]
  + Sarah (Water Carrier)              +2.0/day
  - Doctor sterilizing bandages        -0.8/day
  - Farmer watering crops              -1.0/day

Noise: 4 / 6  [OK]
  + Woodcutter chopping                +3
  + General settlement presence        +1
  [Silent mode: smithing suppressed]
```

The contributor breakdown is a Phase 3 feature.  Phase 1–2 show the score value only.

---

## 6. Settlers & Specialists

### 6.1 Design Principle

Settlers exist in the settlement and in the log.  The player learns who they are through tick reports, the Settlers tab in the Bastion Window, and right-click dialogue.  The roster is read-only from the player's perspective; settler management (adding, removing, editing roles) is an admin-only function accessed via chat commands or the debug panel.

### 6.2 Skill-Based Roles

Every PZ skill maps to a specialist role.  A settler assigned to a role performs tick actions appropriate to their **skill level** — higher skill means more efficient recipes, better output, and less waste.  Roles with a minimum skill requirement are only usable by settlers who qualify.

**Example:** A Cook at skill level 1 prepares basic meals from perishables only.  A Cook at level 5 can preserve food in jars, reducing waste.  A Cook at level 8 produces high-nutrition meals that provide a Happiness bonus.

Skill levels improve over time — settlers learn by doing.  (Advancement rate: Phase 3 feature.)

### 6.3 Per-Role Settings

Each role has a settings record in `rec.roleSettings[roleName]` — a table of named parameters initialized from `Bastion.ROLE_SETTINGS_DEFAULTS`.  These are changed via the `SetRoleSetting` client command (and eventually via a Settings tab UI in a later phase).

**Resource floor principle:** every role that consumes a limited resource has at least one setting that defines a floor or cap.  The settler **stops** when the cap is reached and logs clearly that it has.  It never silently consumes toward zero.

| Role | Key Settings | Purpose |
|------|-------------|---------|
| Tailor | `maxThread = 50`, `addPatches = false` | Stop picking thread at cap; clothing repair at skill 8+ |
| Doctor | `maxBandages = 20` | Stop making bandages at cap |
| Cook | `mealsPerDay = 0` (auto), `allowDryGoods = false` | Auto-sizes to settlers + 1; never touches shelf-stable reserves by default |
| Farmer | `saveSeeds = true` | Set aside ~15% of harvest as seeds before reporting yield |
| Woodcutter | `maxPlanks = 60`, `keepFiresLit = true` | Cap plank production; secondary task of keeping fires fueled |
| Fisher | `fishRadius = 80`, `maxFishStock = 30` | Cap to prevent overfishing |
| Trapper | `trapRadius = 60` | Search radius for set traps (Phase 2+) |
| Mechanic | `vehicleRadius = 30`, `fuelOnly = false` | Radius for vehicle checks; fuelOnly skips part maintenance |
| Blacksmith | `maxIngots = 20`, `scrapFloor = 10` | Cap ingot production; always leave scrapFloor items for the player |
| Rancher | `minGrainReserve = 10` | Never feed animals below this grain count |
| WaterCarrier | `collectRadius = 50` | Scan radius for water sources (ponds, rain barrels) |

### 6.4 Full Role List

| Role | Primary Skill | Type | Tedium Replaced | Requires |
|------|--------------|------|-----------------|---------|
| Farmer | Farming | Production | Daily watering, composting, harvest | Water from pool |
| Cook | Cooking | Production | Perishable-first meal prep | Heat source (for advanced meals) |
| Doctor | First Aid | Support | Boiling rags → sterilized bandages | Water pool + heat source |
| Mechanic | Mechanics | Maintenance | Generator refueling, vehicle inspection | Fuel/parts in storage |
| Woodcutter | Axe | Production | Log splitting, fire stoking | Axe in storage |
| Tailor | Tailoring | Maintenance | Thread picking, rag washing, hole repair | Water pool (washing) |
| Trapper | Trapping | Production | Trap checking, resetting, baiting | Bait in storage |
| Fisher | Fishing | Production | Net and line fishing | Bait + fishing line in storage |
| Forager | Foraging | Production | Daily resource gathering | — |
| Defender | Aiming + Weapon | Security | Corpse disposal, perimeter patrol | — |
| Teacher | — | Passive | Reading-speed multiplier while player is at bastion | Chalkboard within radius |
| Hunter | Aiming, Trapping | Production | Hunting runs | — |
| Child | — | Passive | — (morale lift) | — |
| **Blacksmith** | Metal Working | Production | Scrap → ingots (not the spoon grind) | Heat source + scrap above floor |
| **Rancher** | Animal Husb. | Maintenance | Daily feeding, milking, egg collection | Grain reserve above floor; animals detected |
| **WaterCarrier** | — | Production | Collecting and boiling water | Water source nearby + heat source + pot |

#### Bundled Professions (Phase 4+)

| Profession | Skills Bundled | Rationale |
|-----------|---------------|-----------|
| Scout | Sprinting, Lightfooted, Sneak | Perimeter awareness; reduces threat detection delay |
| Soldier | Aiming, Reloading, Long Blunt/Blade | Combat-focused Defender; high noise |
| Medic | First Aid, Tailoring | Field medicine; broader than Doctor |

#### Role Limitations by Design

- **Blacksmith does not run the spoon grind.**  The spoon grind exists so the player can advance their own Metalworking skill.  The settler smelts scrap into ingots (prep work) and stops there.  If the player needs ingot stock, the settler provides it.  If the player needs to level Metalworking, they do that themselves.
- **Cook does not touch dry goods by default.**  Dried beans, canned goods, and other non-perishables are the player's long-term reserves.  They only get cooked if the player explicitly sets `allowDryGoods = true`.
- **Farmer saves seeds by default.**  Consuming the entire harvest means nothing to plant next season.  The farmer always sets aside a fraction.

### 6.5 Settler Arrivals

New survivors arrive over time.  Arrival rate is influenced by Happiness, Resolve, and settlement visibility.  Some roles (Doctor, Teacher, Blacksmith) are quest-gated — requires finding and escorting the survivor.  (Arrival mechanics: Phase 3.)

### 6.6 Beds

Settlers need somewhere to sleep.  The mod counts bed capacity within the bastion radius and compares it to the settler count.

**Rules:**
- Beds must be within the bastion radius to count.  Beds outside the radius do not count.
- Beds are **not** assigned to specific settlers.  It is a pool count only.
- Each bed object provides one sleep slot (some objects may provide two — e.g., double beds; TBD by sprite detection).
- If `bedCount < settlerCount`: settlers experience a **Happiness penalty** (mood state moves toward `Struggling`).  The shortage is logged and shown in the Overview.
- If `bedCount >= settlerCount`: no effect.  Surplus beds are fine.

**Detection method:** sprite-name scan within the radius.  Bed objects are identified by sprite name substrings (e.g., `"bed"`, `"cot"`, `"mattress"`).

> ⚑ OPEN: Exact sprite name substrings for single beds, double beds, and cots need to be verified against PZ B42 furniture sprites.  See Open Question #29.

### 6.7 Work Sites

Work sites are physical objects required for certain roles to operate at full effectiveness (a stove for the Cook, a forge for the Blacksmith, a classroom chalkboard for the Teacher).

**Rules:**
- Work site presence is a **boolean per role type**: does ANY qualifying object exist within the radius?
- Work sites are **shared** — if there are 3 Cooks and 1 stove, all 3 Cooks benefit.  No per-settler assignment.
- If no work site is found: the role operates at **reduced productivity** (yield penalty, e.g. 50% output).  This is a productivity issue, not a happiness issue — settlers are not unhappy, just less effective.
- The penalty is logged clearly: "Rosa cooked meals but no stove was found — output reduced."

**Detection method:** recipe-based lookup via `CraftRecipeManager` (or equivalent B42 API).  Query what objects/surfaces a relevant recipe requires, then check for those objects within the radius.  This is more mod-compatible than a hardcoded sprite list: mods that add new cooking appliances or forges will automatically be recognized if they register their recipes correctly.

> ⚑ OPEN: The correct B42 API for recipe-to-required-object lookup is unconfirmed.  `CraftRecipeManager` is a candidate.  See Open Question #30.

**Work site requirements by role:**

| Role | Requires | Fallback (no site) |
|------|----------|--------------------|
| Cook | Stove, oven, or campfire | 50% meal output |
| Doctor | Heat source (stove, campfire) | Already gated by `hasHeatSource` — may overlap |
| Blacksmith | Forge or metalworking station | 50% ingot output |
| Teacher | Chalkboard within radius | Role inactive entirely (chalkboard is prerequisite, not a productivity modifier) |
| Woodcutter | Sawmill or workbench | No penalty — splitting logs needs no appliance |
| Tailor | Sewing machine | 50% thread/repair output |

*Other roles have no work site requirement.*

---

## 7. NPC Generation

Bastion uses PZ's RNG patterns for all settler generation.  No hand-authored characters.

### 7.1 Generation Layers

**Name:** First + last from gender-appropriate pools (30 male, 30 female, 40 last names).

**Role:** Fill open community needs first.  Assign randomly if no gap.

**Skill Level:** `ZombRand(4) + 1` (1–4).  Role-appropriate range tuning: Phase 3.

**Trait Tags:** 1 tag from a pool of ~23.  Narrative flags, not stat modifiers.  Appear in arrival log and Settlers tab profile.

**Backstory Seed:** One generated line.  `[occupation] from [PZ location] who [circumstance]`.  Shown in arrival log; available in Settlers tab.

**Mood State:**

| State | Effect |
|-------|--------|
| `Content` | Normal tick contribution |
| `Struggling` | Reduced output; flagged in log |
| `Critical` | No contribution; leaves if unresolved |

### 7.2 Death Weight

> *"Marcus didn't make it.  He was the one who always had something to say at the wrong moment.  We're going to feel that."*

No death screen.  Just a log entry with their name and trait tag, and silence.

---

## 8. Resources & Storage

### 8.1 Community Storage

All containers within the settlement boundary are **community storage by default**.  The player marks individual containers as **private** to exclude them from the simulation.

**Storage categories:**

| Category | Container Types | Notes |
|----------|----------------|-------|
| **General** | Crates, shelves, cabinets, bags | Base capacity |
| **Refrigerated** | Fridges, coolers | Label only; actual PZ spoilage is Java-side |
| **Frozen** | Freezers | Label only |

The scanner walks all objects in the indoor squares within `SCAN_RANGE` tiles of the bastion anchor square.

### 8.2 Settler Water Pool

Settlers manage their own water supply independent of the player's containers.  This is tracked in `rec.settlerWaterPool` — measured in settler-days of safe water.

**How the pool works:**
- WaterCarrier role adds to the pool (requires: water source within `collectRadius`, heat source in bastion, pot in shared storage)
- Roles that need water (Doctor, Farmer, Tailor) call `debitWater()` — if the pool is empty, their water-requiring step is skipped with a warning log
- The pool is capped at `WATER_POOL_MAX` (21 days — a 3-week hard cap)
- The pool is **separate from player containers** — settler roles never touch the water in the player's barrels or bottles
- `rec.waterDays` displayed in the Overview = actual container water + settler pool

**World-state cache:**  Whether a water source and heat source exist is expensive to scan every day.  Results are cached in `rec.cachedWaterSource` and `rec.cachedHeatSource` and refreshed every 7 in-game days.  Infrastructure status is shown in the Overview tab so the player can see why WaterCarrier isn't working.

**WaterCarrier yield formula:**
```
produced = WATER_PER_CARRIER_TICK + (settler.skillLevel - 1) * WATER_CARRIER_SKILL_MOD
         = 2.0 + (skillLevel - 1) * 0.3   settler-days per tick
```

### 8.3 Virtual Yield System

Settlers produce output that is tracked in `rec.virtualYield` — a key/value table accumulating pending production.  This is a Phase 2 tracking system; physical item spawning is Phase 3.

**Current virtual yield keys:**

| Key | Description | Produced By |
|-----|-------------|-------------|
| `thread` | Thread units (picked from rags) | Tailor |
| `bandages` | Sterilized bandages | Doctor |
| `meals` | Prepared meals (count) | Cook |
| `fish` | Fresh fish | Fisher |
| `meat` | Trap/hunt catch | Trapper, Hunter |
| `planks` | Sawn planks | Woodcutter |
| `firewood` | Firewood loads | Woodcutter |
| `ingots` | Metal ingots | Blacksmith |
| `eggs` | Eggs | Rancher |
| `milk` | Milk units | Rancher |
| `savedSeeds` | Seeds reserved for replanting | Farmer |

All yield entries are capped by the role's `max*` setting.  Once a cap is reached, the settler logs "stock at cap" and stops consuming the input resource.

**Phase 3: Claiming yield** — a "Collect Production" action in the Bastion Window will spawn the accumulated virtual yield as actual items into a designated output container in the settlement.  The exact item type strings and container targeting logic are deferred to Phase 3 design.

### 8.4 Kitchen Awareness (Phase 3)

The Cook specialist will be aware of appliance locations (stoves, ovens) within the settlement.  Food items drift toward containers near cooking appliances over time.  The player doesn't need to manually sort the pantry.

> ⚑ OPEN: "Drift" is a soft mechanic.  Needs bounds so it doesn't move everything to one spot.  See Open Question #2.

### 8.5 Private Container Flagging

- Right-click any container inside the settlement → "Mark as Private" / "Mark as Shared"
- Private containers are invisible to the simulation; specialists never draw from them
- Persists across sessions via `rec.privateContainers[objKey] = true`

### 8.6 Food Management

- Cook uses perishable food first (items with a positive `AgeDelta` or "fresh"/"raw" in type name)
- `allowDryGoods = false` protects shelf-stable reserves by default
- Food projection shown in Bastion Window Overview tab

---

## 9. Threats & Defense

### 9.1 Noise Score

Settlement activity generates noise that attracts zombies.  Noise is tracked as a discrete score with a player-configurable budget.

**Noise contributors by role:**

| Activity | Noise Level |
|----------|------------|
| General settlement presence | +1 (always-on baseline) |
| Woodcutter chopping | +3 |
| Blacksmith hammering | +3 |
| Mechanic (engine work) | +2 |
| Defender patrol | +2 |
| Hunter | +3 |
| Cook, Farmer, Tailor, Rancher, WaterCarrier | 0 |

When the noise score exceeds the player's set budget, the settlement tick suppresses the noisiest activities first and logs the skipped actions.

**Noise budget levels:**

| Level | Budget |
|-------|--------|
| Silent | 1 |
| Quiet | 3 |
| Normal | 6 |
| Loud | 12 |

### 9.2 Player Activity Controls (Settings Tab)

- **Noise budget:** Silent / Quiet / Normal / Loud
- **Firearms toggle:** Allow / Melee-only (Phase 4)
- **Noisy work hours:** Unrestricted / Daylight only (Phase 4)
- **Per-role suspend:** Pause any specialist entirely (Phase 4)
- **Per-role settings:** `maxThread`, `allowDryGoods`, `scrapFloor`, etc. (Phase 3 UI; currently via admin command)

### 9.3 Ambient Sounds (Phase 4)

When specialist activities run on the tick, real in-game sounds play at the settlement location.  The player hears log chopping if the Woodcutter worked.  These sounds exist in 3D space.

### 9.4 Zombie Attraction (Phase 5)

- Noise score is the primary zombie attraction driver
- Threat event tiers: Probe → Incursion → Horde
- Defenders handle probes automatically; incursions and hordes require player involvement

---

## 10. Communication & Feedback

### 10.1 Design Principle

Everything lives in one window.  Status checks, log entries, settler roster, scores, and settings are all in the Bastion Window — a single tabbed panel.  The right-click menu is deliberately thin; it exists only to open the window, not to replace it.

---

### 10.2 The Bastion Window

A draggable tabbed panel.  Built on `ISTabPanel` inside a custom `ISPanel` with title-bar drag handling.  Auto-refreshes every ~5 seconds while open.

**Implementation notes:**
- `BastionWindow` extends `ISPanel` with manual drag via `onMouseDown`/`update()` and `getMouseX()`/`getMouseY()`
- `ISTabPanel:addView(name, panel)` positions each content panel at `y = tabHeight` automatically
- Content panel height = `WIN_H - TITLE_H - TAB_H = 376px`
- Close button uses colon-syntax ISButton callback where `self = target = the window`

#### Tabs

**Overview**
Settlement status at a glance.  Currently shows:
- Settlers count, Food days, Water days (with settler pool breakdown), Noise score/budget
- Infrastructure flags: water source found/not found, heat source found/not found, animals detected
- Settler production (virtual yield) — pending items accumulated since last claim
- Last 3 log entries

*Phase 3 target: contributor breakdown below each score.*

**Settlers**
Full roster.  Each row: name, role, mood, skill level.  Clicking a row shows settler profile inline (backstory, trait, mood detail).

**Log**
Full settlement log, scrollable.  Color-coded by entry type:

| Color | Type |
|-------|------|
| White | Standard tick output |
| Yellow | Warning / shortage |
| Red | Death / critical event |
| Green | Arrival / milestone |
| Purple | Admin log entry |
| Gray | Suppressed activity (noise budget) |

Newest entries at bottom (scroll-to-bottom on open).  Max 200 entries; oldest pruned.

**Settings**
- Noise Budget buttons (Silent / Quiet / Normal / Loud) — active level highlighted
- Disband Bastion (two-step: first click shows Confirm button; confirm sends CollapseBastion)

*Phase 3 target: per-role settings UI (maxThread, allowDryGoods, etc.) as editable fields.*
*Phase 4 target: firearms toggle, time restriction, per-role suspend.*

---

### 10.3 Right-Click Menu

**Anywhere inside the bastion (no bastion exists):**
- `Establish Bastion` — creates the settlement; opens Bastion Window immediately.

**Anywhere inside the bastion (bastion exists):**
- `Check on Bastion` — opens/toggles the Bastion Window.

**On a container inside the bastion:**
- `Mark as Private` / `Mark as Shared`

**On a settler mannequin:**
- One-liner dialogue (mood-appropriate ambient flavor)
- "View profile" — prints backstory/trait to chat

That's the full right-click surface.  Noise budget, role management, and disband are inside the window.

---

### 10.4 Radio Check-In (Phase 2)

Right-click walkie-talkie or ham radio → `Call Bastion`.  Opens the same Bastion Window.  Available if player has a walkie-talkie with battery and the settlement has a ham radio, or player is standing at any ham radio.

---

### 10.5 Critical Alerts

The only Bastion information that appears outside the window: a one-line alert in the chat area for critical events.

> `[Bastion] Food supply is running low (1.2 days remaining).`

---

## 11. Admin & Debug Controls

### 11.1 Philosophy

- **Chat commands** — for server admins and hosts.  Gated on `getAccessLevel()`.
- **Debug panel** — for the developer.  Gated on `isDebugEnabled()`.  Phase 4.

### 11.2 Chat Commands (Implemented)

All commands prefixed `/bastion`.  Server checks access level before executing.

#### Implemented

| Command | Effect |
|---------|--------|
| `/bastion help` | Print available commands to server console |
| `/bastion status` | Print settlement scores to server console |
| `/bastion tick` | Force a tick on the next minute check |
| `/bastion reset [username]` | Collapse a player's bastion |
| `/bastion addlog <text>` | Append a milestone log entry |

#### Planned (Phase 3+)

| Command | Effect |
|---------|--------|
| `/bastion food <days>` | Set food days remaining |
| `/bastion water <days>` | Set water days |
| `/bastion settler list` | Print settler roster to console |
| `/bastion settler add [role]` | Generate and add a settler |
| `/bastion settler remove <index>` | Remove by index |
| `/bastion settler mood <index> <state>` | Set mood |
| `/bastion settler role <index> <role>` | Reassign role |
| `/bastion threat <tier>` | Trigger a threat event |
| `/bastion version` | Print mod version |

### 11.3 Debug Panel (Phase 4)

Separate window, `Ctrl+Shift+B`, only renders if `isDebugEnabled()`.  Tabs: State (raw ModData), Scores (editable), Settlers (full edit), Tick (manual controls), Storage (inject items), Log (filtered view + clear).

### 11.4 Access Control

| Surface | Who Can Use | Gate |
|---------|------------|------|
| Chat commands | Host + Admin/Moderator | `getAccessLevel()` server-side |
| Debug panel | Developer | `isDebugEnabled()` |
| Bastion Window | Any player with a bastion | No gate |
| Right-click menu | Any player | Context-sensitive |

---

## 12. NPC Representation

### 12.1 The Problem

Bastion's simulation is invisible.  Specialists work, the log records it — but if no physical NPCs are present, the settlement feels empty.

### 12.2 Options

**Option A: Mannequins (current)**  Proven.  Completely static.  Credible as a Phase 1 placeholder.

**Option B: Mostly Indoors**  Settlers are implied rather than shown.  Sounds come from inside buildings.

**Option C: One Visible Spokesperson Per Building**  One mannequin near each building entrance.  Sounds come from inside.

**Option D: Wait for B42 NPC System**  The developers are building this for B43.

**Option E: Modified IsoZombie**  Fragile; not recommended.

### 12.3 Current Recommendation

**Option A (mannequins) for Phase 1–2.  Option B+C for Phase 3.**

One mannequin per settler for now.  When B42's ambient sound API is confirmed, switch to one spokesperson per building with sounds implying activity inside.

---

## 13. Comparable Games & Borrowed Mechanics

**State of Decay 2 — Primary Reference**
Borrow: Score breakdown UI with all contributors listed.  Negative spiral mechanics.
Avoid: Roster management screen.  Per-survivor morale tracking.

**This War of Mine — Emotional Reference**
Borrow: Named characters with trait tags make death land.  One arrival log entry does more work than a stats screen.
Avoid: Per-character sympathy system.

**7 Days to Die — Threat Escalation**
Borrow: Predictable horde cycle.  Tension through anticipation, not randomness.

**Dwarf Fortress / RimWorld — Passive Simulation**
Borrow: Storytelling through log — you read what happened, imagination fills the gap.
Avoid: Complexity ceiling.

**Frostpunk — Minimal NPC Visibility**
Borrow: Workers exist and matter narratively, but you rarely see individuals.

---

## 14. Implementation Phases

> **Workflow reminder:** Design and test plan for each phase are written before implementation begins.  This document is updated immediately when a design decision changes during implementation.

---

### Phase 1 — Foundation ✅ COMPLETE

**Goal:** Prove the core loop works end-to-end.

- [x] Settlement boundary (SCAN_RANGE tile radius from anchor square)
- [x] Settler spawning: IsoMannequin placed at establish, removed at collapse, persists across sessions
- [x] NPC generation: name, role, skill level, trait tag, backstory seed
- [x] Community storage: opt-out container system, item registry (general / refrigerated / frozen)
- [x] Settlement tick: once-per-day via `EveryOneMinute`, `lastTickDay` guard
- [x] **Bastion Window** (ISTabPanel): Overview, Settlers, Log, Settings tabs
- [x] Food and water tracking displayed in Overview
- [x] Noise score with player budget control (Silent / Quiet / Normal / Loud) via Settings tab
- [x] Admin chat commands (`/bastion help/status/tick/reset/addlog`)
- [x] Right-click: Establish Bastion (opens window) / Check on Bastion
- [x] Container mark-private / mark-shared via right-click
- [x] ModData persistence across save/load
- [x] Kahlua compatibility: no goto, no Java exception in nutrition chain, no OnModDataTransmit

---

### Phase 2 — Settler Purpose: Tedium Reduction 🔄 IN PROGRESS

**Goal:** Make settlers meaningfully take over B42 grind tasks.  Every role has concrete output, resource floors, and clear failure logging.

#### Implemented ✅

- [x] **Settler water pool** (`rec.settlerWaterPool`): separate from player containers, capped at 21 days
- [x] **WaterCarrier role**: collect + boil water; requires water source + heat source + pot; skill-scaled yield
- [x] **Per-role settings** (`rec.roleSettings` initialized from `ROLE_SETTINGS_DEFAULTS`; `Bastion.getSetting()` helper)
- [x] **Virtual yield system** (`rec.virtualYield`; `Bastion.addVirtualYield()` with cap)
- [x] **`SetRoleSetting` client command** (validated against known keys)
- [x] **World-state cache**: `hasWaterSource`, `hasHeatSource`, `hasAnimals` scan on establish and every 7 days; shown in Overview
- [x] **Resource-floor-aware role ticks:**
  - Tailor: washes dirty rags (water pool), picks thread up to `maxThread` cap
  - Doctor: sterilizes bandages up to `maxBandages`; prorates batch when water is short; requires heat source
  - Cook: perishables-first ordering; respects `allowDryGoods = false`; auto-sizes meals to settler count + 1
  - Farmer: costs 1 water-day; saves seed fraction before reporting
  - Woodcutter: respects `maxPlanks`; secondary fire-stoking if `keepFiresLit`
  - Fisher: requires bait + fishing line from storage; respects `maxFishStock`
  - Blacksmith: scrap → ingots; never touches `scrapFloor` reserve; requires heat source; skill-gated throughput
  - Rancher: detects `IsoAnimal`; grain floor prevents feed depletion; produces eggs/milk yield
  - Mechanic: generator refueling (skill 1) + vehicle parts check (skill 3)
  - Trapper: bait check before reporting catch (abstract yield for now)
- [x] Overview tab: water pool breakdown, infrastructure flags, virtual yield display

#### Remaining Phase 2 Work 📋

- [ ] **Role settings UI** in Settings tab: editable fields for `maxThread`, `allowDryGoods`, `scrapFloor`, etc.  Currently only settable via admin command.
- [ ] **Teacher reading speed multiplier**: client-side `Events.OnTick` hook; modify book reading timer when `rec.teacherActive = true` and player is inside bastion.  Exact API unverified — see Open Question #20.
- [ ] **Trapper trap scanning**: scan for actual `IsoTrap` objects in a ring *outside* the bastion radius.  Distance affects tick cost.  Phase 2 design below.
- [ ] **Phase 2 test plan execution** (see Section 15.2)

#### Trapper Trap Scanning Design

Traps must be placed **outside** the bastion's indoor zone to work (you don't trap your own living space).

- Scan for `IsoTrap` objects in a ring from `min(15 tiles)` to `trapRadius (60)` from anchor square
- Each trap within range is "checked" — roll yield based on settler skill + trap type
- Traps beyond 40 tiles cost 2 action points; settler has a daily pool of `4 + skillLevel` action points
- Unchecked traps are noted in the log
- Rebaiting: consume worms/berries/corn from shared storage per reset trap
- Result goes to `rec.virtualYield.meat`

---

### Phase 3 — Production Claiming, Score Depth & Bastion View 📋 PLANNED

**Goal:** Make settler output tangible; deepen score feedback; bring the radius to life visually; implement bed and work site systems.

**Design decisions needed before implementation:**

1. Virtual yield claiming: which container does output land in?  Options: nearest non-private container with space; a designated "settler output" container the player marks; the first container scanned.  Recommended: nearest non-private container with space, logged clearly.
2. Item type strings: PZ item type names for thread (`Thread`), sterilized bandage (`BandageSterilized`?), ingot (`IronIngot`?).  Need verification against PZ B42 item registry.
3. Settler skill advancement rate: once per N ticks where the role ran successfully.  N = 7 (once per week) as a starting point.
4. Radius visualization: confirm `WorldToScreen` / overlay draw hook available in B42.  See Open Question #28.
5. Bed sprite list: confirm sprite name substrings for all bed/cot/mattress types.  See Open Question #29.
6. Work site recipe API: confirm `CraftRecipeManager` or equivalent.  See Open Question #30.
7. Radius expansion formula: starting radius, step per settler, maximum.  See Open Question #27.

**Scope:**

- [ ] **Radius visualization ("Bastion View")**: colored tile overlay + hover labels shown while Bastion Window is open (see Section 3.2)
- [ ] **Dynamic radius expansion**: radius grows automatically with settler count (formula: Open Question #27)
- [ ] **Bed counting system**: sprite-name scan within radius; deficit → Happiness penalty; shown in Overview (see Section 6.6)
- [ ] **Work site detection**: recipe-based boolean scan per role; no site → productivity penalty; shown in Overview (see Section 6.7)
- [ ] **Teacher chalkboard dependency**: Teacher inactive if no chalkboard found within radius
- [ ] Virtual yield claiming: "Collect Production" action in Overview tab spawns yield as actual items
- [ ] Score contributor breakdown in Overview (contributor table below each score)
- [ ] Settler mood state triggers: food shortage → Struggling; prolonged Struggling → Critical; player interaction → improves
- [ ] Death weight: death log entry uses name + trait tag
- [ ] Settler arrival mechanics: new NPCs arrive based on Happiness / Resolve; arrival rate configurable
- [ ] Skill advancement: settlers improve at their role over time
- [ ] Teacher reading speed multiplier (if API confirmed; see Open Question #20)
- [ ] Kitchen awareness: food drift toward cooking appliances
- [ ] Expanded admin commands: `/bastion settler list/add/remove/mood/role`, `/bastion food/water`
- [ ] Phase 3 test plan (to be written before implementation)

---

### Phase 4 — Community Life & Ambient Presence 📋 PLANNED

**Design decisions needed:**

1. Ambient sound trigger: on tick fire, or independent of tick on a random timer?  Tick-triggered is simplest.
2. Radio check-in range: tile distance check or try PZ's radio frequency API?  Start with tile distance.
3. Per-role suspend: add to Settings tab as toggle buttons.

**Scope:**

- [ ] Ambient sounds: chopping, cooking, hammering, patrol sounds at settlement location
- [ ] Radio check-in via walkie-talkie / ham radio (opens Bastion Window remotely)
- [ ] Quest-gated specialist recruitment (Doctor, Teacher, Blacksmith)
- [ ] Settler defection at zero Resolve
- [ ] Per-role suspend in Settings tab
- [ ] Firearms toggle for Defenders
- [ ] Noisy work hours (daylight-only mode)
- [ ] Debug panel (developer-only, `isDebugEnabled()` gated)
- [ ] Phase 4 test plan (to be written before implementation)

---

### Phase 5 — Threats, Defense & Endgame 📋 PLANNED

**Scope:**

- [ ] Zombie attraction scaling from noise score
- [ ] Threat event tiers: Probe → Incursion → Horde
- [ ] Defender, Scout, Soldier, Hunter specialist ticks
- [ ] Threat event ambient sound cues
- [ ] Self-sufficiency milestone tracking (five-pillar completion)
- [ ] Settlement expansion mechanics
- [ ] Multiplayer: tick behavior with multiple player bastions
- [ ] Phase 5 test plan (to be written before implementation)

---

## 15. Test Plans

> **Legend:** ✅ Pass | ❌ Fail | ⚠ Partial  
> Tests are run in order within each group; later tests assume earlier ones passed.

---

### 15.1 Phase 1 Test Plan

All tests use a fresh single-player save with Bastion enabled.

#### Group 1 — Bastion Establishment

**T1.1 — Establish Bastion in a building**
- *Pre:* Player inside a building.  No bastion exists.
- *Steps:* Right-click inside → "Establish Bastion."
- *Pass:* Option appears.  No error.  Console confirmation.  Bastion Window opens.

**T1.2 — Cannot establish a second bastion**
- *Pre:* T1.1 passed.
- *Steps:* Right-click inside a different building.
- *Pass:* "Establish Bastion" absent.  "Check on Bastion" present if inside the bastion building.

**T1.3 — Disband removes bastion**
- *Pre:* T1.1 passed, player inside bastion.
- *Steps:* "Check on Bastion" → Settings → "Disband Bastion" → Confirm.  Right-click same building.
- *Pass:* "Establish Bastion" reappears.  ModData cleared.

**T1.4 — Bastion persists across save/load**
- *Pre:* T1.1 passed.
- *Steps:* Save, quit, load.  Right-click inside bastion.
- *Pass:* "Check on Bastion" appears.  Record intact.

#### Group 2 — Settler Spawning & Persistence

**T2.1 — Establishing spawns a settler**
- *Steps:* Establish bastion, look inside.
- *Pass:* At least one mannequin present.  Arrival entry in Log tab.

**T2.2 — Settler persists across save/load**
- *Steps:* Note position, save, load.
- *Pass:* Mannequin at same position.  Name and role unchanged.

**T2.3 — Collapse removes settlers**
- *Steps:* Collapse bastion, check building.
- *Pass:* Mannequins removed.  No orphans.

#### Group 3 — NPC Generation

**T3.1 — Settler has a name**
*Pass:* First + last name shown in Settlers tab.  Not nil or blank.

**T3.2 — Settler has a role**
*Pass:* A role name assigned (Cook / Woodcutter / Farmer / etc.).

**T3.3 — Settler has a trait tag**
*Pass:* One tag listed in arrival log and Settlers tab profile.

**T3.4 — Settler has a backstory**
*Pass:* One-line `[occupation] from [location] who [circumstance]` in arrival log.

**T3.5 — Multiple settlers have distinct names**
*Pass:* No two settlers share the same full name.

#### Group 4 — Community Storage

**T4.1 — Containers default to shared**
*Pass:* Containers inside boundary have no "Mark as Shared" needed; already shared.

**T4.2 — Mark private excludes container**
- *Steps:* "Mark as Private," add distinctive item, trigger tick.
- *Pass:* Item absent from community totals.

**T4.3 — Re-marking as shared restores it**
- *Steps:* "Mark as Shared," trigger tick.
- *Pass:* Item reappears in totals.

#### Group 5 — Settlement Tick

**T5.1 — Tick fires once per day**
- *Steps:* Note time, advance to next day, check Log tab.
- *Pass:* New batch of tick entries for new day.  No duplicate entries.

**T5.2 — Tick produces role output**
- *Pre:* Woodcutter with axe + logs in storage.
- *Steps:* Advance one day, open Log tab.
- *Pass:* Named Woodcutter entry with specific output.

**T5.3 — Tick logs missing requirements**
- *Pre:* Cook exists, no food in storage.
- *Steps:* Advance one day.
- *Pass:* Entry says Cook couldn't work and states reason.

**T5.4 — Tick does not double-fire**
- *Steps:* Save, quit, reload mid-day.  Advance to end of same day.
- *Pass:* Exactly one tick batch for that day.

#### Group 6 — Bastion Window

**T6.1 — Window opens with all four tabs**
*Pass:* Overview, Settlers, Log, Settings all visible.  No Lua error.

**T6.2 — Log tab: newest entries at bottom**
- *Pre:* Two days of entries.
- *Pass:* Scroll to bottom shows most recent day.

**T6.3 — Log persists across save/load**
*Pass:* All prior entries present after reload.

**T6.4 — Log color-coding correct**
*Pass:* Standard = white; warning = yellow; arrival = green; suppressed = gray.

**T6.5 — Settlers tab shows roster with profiles**
*Pass:* Each settler has a row.  Clicking shows backstory, trait, mood.

**T6.6 — Settings tab: noise budget buttons work**
- *Steps:* Click "Silent," advance one day.
- *Pass:* Noise budget is 1.  Woodcutter suppressed if noise would exceed it.

#### Group 7 — Food, Water & Noise Display

**T7.1 — Food days displayed**
*Pass:* "Food: X days" visible with positive number.

**T7.2 — Water days displayed**
*Pass:* "Water: X days" visible.

**T7.3 — Values change after tick**
*Pass:* Values shift after advancing one day.

**T7.4 — Shortage warning at threshold**
- *Pre:* Food below 3 days.
- *Pass:* Food metric in warning color.  Warning log entry.

**T7.5 — Noise score displayed with budget**
*Pass:* "Noise: X / Y [Level]" visible.

**T7.6 — Noisy role increases noise score**
- *Steps:* Assign Woodcutter, advance day.
- *Pass:* Noise score reflects Woodcutter's +3 contribution.

**T7.7 — Noise budget suppresses over-budget roles**
- *Steps:* Set budget to Silent, advance day.
- *Pass:* Woodcutter log entry is gray suppression notice.

---

### 15.2 Phase 2 Test Plan

Run after Phase 1 tests pass.  Requires: bastion established, at least one settler of each tested role.

#### Group 8 — Settler Water Pool

**T8.1 — Pool shown in Overview**
- *Pre:* Bastion established.
- *Pass:* Overview shows "Water: X.X days" (may show "0.0 from settler pool" initially).

**T8.2 — WaterCarrier requires all three conditions**
- *Test A:* Assign WaterCarrier with no water source nearby, advance day.
  *Pass:* Log warns "no water source found nearby."
- *Test B:* Add pond tile nearby (or confirm existing), but no heat source, advance day.
  *Pass:* Log warns "no heat source."
- *Test C:* Add campfire/stove, but no pot in storage, advance day.
  *Pass:* Log warns "has no pot in shared storage."

**T8.3 — WaterCarrier fills the pool when conditions met**
- *Pre:* All three conditions met (water source + heat source + pot).
- *Steps:* Assign WaterCarrier, advance day.
- *Pass:* `rec.settlerWaterPool` increases by ~2.0 + skill bonus.  Log confirms with "pool" numbers.

**T8.4 — Pool shown in Overview with breakdown**
- *Pre:* T8.3 passed.  Pool > 0.
- *Pass:* Overview shows "X.X days (Y.Y from settler pool)" for water.

**T8.5 — Pool capped at WATER_POOL_MAX**
- *Steps:* Run WaterCarrier for enough ticks to fill pool.
- *Pass:* Log says "water pool is full (21.0 days)."  Pool does not exceed 21.

**T8.6 — Water-consuming role draws from pool**
- *Pre:* Pool is non-zero.  Doctor role assigned.
- *Steps:* Advance day.
- *Pass:* Pool decreases by Doctor's water cost.  Doctor log shows successful sterilization.

**T8.7 — Water-consuming role skips when pool empty**
- *Pre:* Pool = 0 (never filled).  Doctor role assigned.
- *Steps:* Advance day.
- *Pass:* Doctor log warns "settler water supply too low."  No bandages produced.  Player containers unaffected.

**T8.8 — Infrastructure flags in Overview**
- *Pass:* "Water source: found / NOT FOUND" and "Heat source: found / NOT FOUND" shown in Overview.  Accuracy matches world state.

#### Group 9 — Resource Floors & Caps

**T9.1 — Tailor respects maxThread cap**
- *Pre:* Tailor role assigned.  Clean rags in storage.  `maxThread = 50`.
- *Steps:* Advance days until thread stock hits 50.
- *Pass:* Log says "thread stock is at cap (50). No rags consumed."  No further rags consumed.

**T9.2 — Tailor log warns when at cap**
*Pass:* Cap message is clearly logged (not a silent skip).

**T9.3 — Doctor respects maxBandages cap**
- *Pre:* All conditions met.  `maxBandages = 20`.
- *Steps:* Advance days until stock hits 20.
- *Pass:* Log says "bandage stock is at cap (20)."

**T9.4 — Cook does not touch dry goods by default**
- *Pre:* Storage contains only canned goods (no fresh food).  Cook role assigned.
- *Steps:* Advance day.
- *Pass:* Cook log warns "nothing suitable to cook (dry goods excluded by setting)."  Canned goods not consumed.

**T9.5 — Cook uses perishables first**
- *Pre:* Storage contains both fresh vegetables and canned beans.
- *Steps:* Advance day.
- *Pass:* Cook log says meals prepared "from perishables."  Log count > 0 for perishable meals.

**T9.6 — Farmer saves seeds by default**
- *Steps:* Advance day with Farmer assigned.
- *Pass:* Log mentions seeds set aside.  `rec.virtualYield.savedSeeds` > 0.

**T9.7 — Blacksmith does not touch scrapFloor reserve**
- *Pre:* Storage has exactly `scrapFloor` (10) scrap items.  `scrapFloor = 10`.
- *Steps:* Advance day.
- *Pass:* Log warns "not enough scrap above floor."  No ingots produced.  Scrap count unchanged.

**T9.8 — Blacksmith produces ingots when scrap exceeds floor**
- *Pre:* Storage has 14 scrap items.  `scrapFloor = 10`, `SCRAP_PER_INGOT = 4`.
- *Steps:* Advance day.
- *Pass:* 1 ingot added to virtual yield.  Log confirms.  Scrap count decreases by 4.  10 items remain.

**T9.9 — Woodcutter respects maxPlanks**
- *Steps:* Advance days until planks hit 60.
- *Pass:* Log says "plank stock at cap (60)."

**T9.10 — Rancher skips when grain below floor**
- *Pre:* Storage has exactly `minGrainReserve` (10) grain items.
- *Steps:* Advance day.
- *Pass:* Log warns "feed stock too low."  No yield produced.  Grain unchanged.

#### Group 10 — Virtual Yield

**T10.1 — Yield accumulates in Overview**
- *Pre:* At least one production role running.
- *Steps:* Advance several days.  Open Overview.
- *Pass:* "Settler production (pending):" section shows non-zero values for relevant keys.

**T10.2 — Yield persists across save/load**
- *Steps:* Let yield accumulate, save, load.  Check Overview.
- *Pass:* Yield values unchanged after reload.

**T10.3 — Multiple roles accumulate yield independently**
- *Pre:* Tailor (thread), Fisher (fish), Blacksmith (ingots) all assigned.
- *Steps:* Advance days.
- *Pass:* All three yield keys show values.

#### Group 11 — Role Settings

**T11.1 — SetRoleSetting command works**
- *Steps:* Send `SetRoleSetting` with `role="Tailor"`, `key="maxThread"`, `val=25`.  Advance day.
- *Pass:* Tailor stops at 25 thread.  Log confirms cap at 25.

**T11.2 — Invalid key rejected**
- *Steps:* Send `SetRoleSetting` with `key="notakey"`.
- *Pass:* Server logs rejection.  `rec.roleSettings` unchanged.

**T11.3 — Settings persist across save/load**
- *Steps:* Set `maxThread = 25`, save, load.
- *Pass:* `rec.roleSettings.Tailor.maxThread = 25` after reload.

---

## 16. Open Questions

| # | Question | Status | Notes |
|---|----------|--------|-------|
| 1 | PZ safehouse boundary constraints (size limits, multi-building) | Open | Validate in Phase 1 testing |
| 2 | Container "drift" bounds for kitchen awareness | Open | Phase 3 design; needs playtesting |
| 3 | Illness spreading between settlers | Open | Phase 3; high drama, high complexity |
| 4 | Zombie attraction scaling formula | Open | Calibrate during Phase 5 |
| 5 | Quest system scope for specialist recruitment | Open | Fixed locations acceptable for v1 |
| 6 | Horde event structural damage to settlement | Open | Large scope increase if yes |
| 7 | Score threshold values and decay rates | Open | Balance pass after Phase 3 |
| 8 | Multiplayer: tick behavior with multiple player bastions | Open | Phase 5; significant implications |
| 9 | Balanced diet tracking — per food type or per food group? | Open | Food group simpler |
| 10 | Trait tag pool content | Partial | 23 tags implemented; authored review needed |
| 11 | Backstory seed tables | Partial | Basic tables implemented; may need more variety |
| 12 | Settler right-click dialogue — authored per tag or templated? | Open | Templated with tag substitution likely sufficient |
| 13 | Subjective score set — are Happiness / Resolve / Education correct? | Open | Revisit after Phase 3 with real data |
| 14 | NPC representation long-term | Open | Option A (mannequins) for Phase 1–2; revisit at Phase 3 |
| 15 | Bundled profession skill advancement | Open | Recommendation: track each skill separately |
| 16 | Storage capacity units — weight or slot count? | Open | Weight is more PZ-like; slot count simpler to display |
| 17 | Item registry rebuild frequency | Open | Every tick (simplest); may optimize later |
| 18 | Ambient sound trigger — on tick or independent timer? | Open | Tick-triggered simplest; independent allows time-of-day variation |
| 19 | Noise budget UI | **Resolved** | Tiered presets (Silent/Quiet/Normal/Loud) in Settings tab |
| 20 | Teacher reading speed: does PZ expose book reading rate in Lua? | Open | Need to verify `IsoPlayer:getReadingSpeed()` or equivalent in B42 |
| 21 | Virtual yield claiming: which container does output land in? | Open | Phase 3 design decision; recommendation: nearest non-private with space |
| 22 | Item type strings for virtual yield claiming (Thread, BandageSterilized, IronIngot) | Open | Verify against PZ B42 item registry before Phase 3 |
| 23 | Role settings UI: editable fields in Settings tab vs. separate per-settler panel? | Open | Phase 3 design; per-role settings (not per-settler) in Settings tab recommended |
| 24 | Trapper: can `IsoTrap` be found via `instanceof` and `sq:getObjects()` in B42? | Open | Phase 2 implementation; verify in test environment |
| 25 | WaterCarrier: does `sq:isWater()` reliably identify ponds and rivers in B42? | **Resolved** | `sq:isWater()` throws a Java exception that escapes Kahlua `pcall` in B42 — cannot be used at all.  Natural water terrain detection deferred; sprite-name scan (rain barrels, wells) is the current fallback.  See OQ #26 for a safe alternative. |
| 26 | Natural water terrain (ponds, rivers): B42-safe detection method? | Open | `sq:isWater()` is off the table (see OQ #25).  Candidates: iterate `sq:getObjects()` looking for water-tagged sprite names; check tile definition via `TileDefinition`; use `getWorld():getWater()` if it exists.  None confirmed in B42 yet. |
| 27 | Radius expansion formula: starting size, step per settler, maximum? | Open | Phase 3 design.  Candidates: flat +2 tiles per settler; logarithmic growth.  Needs playtesting to tune. |
| 28 | `WorldToScreen` / tile overlay draw hook in B42: what is the correct API? | Open | Need to confirm the right event hook (likely `Events.OnPostRenderFloor` or `Events.OnRenderTick`) and whether tile-space coordinate conversion is exposed via Lua.  Required for radius visualization (Section 3.2). |
| 29 | Bed sprite name substrings: what names cover all single beds, double beds, and cots in B42? | Open | Candidates: `"bed"`, `"cot"`, `"mattress"`.  Verify against PZ B42 furniture sprite list before implementation. |
| 30 | Work site recipe lookup API: is `CraftRecipeManager` (or equivalent) the right approach in B42? | Open | Recipe-based detection preferred over hardcoded sprite lists for mod compatibility.  Need to confirm the API surface, whether it exposes required objects/surfaces per recipe, and performance implications of calling it at tick time. |

---

*Bastion Design Document v1.1*
*Design before code.  Tests before implementation.  Update this file whenever a decision changes.*
