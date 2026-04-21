# Bastion — Design Document
> Project Zomboid Build 42 Mod | v2.0

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
Modifying how fast the player reads a skill book requires a client-side tick hook watching for an open book.  While an active Teacher is in the settlement, a reading time modifier applies when the player is inside the bastion radius.  Exact API for reading state is unverified — see Open Question #20.

### 2.3 Feasible but With Known Risks

**Animated, pathfinding NPCs.**
The Bandits mod (workshop ID 3268487204) proves this is achievable in B42: NPCs are `IsoZombie` instances with zombie AI disabled, a Lua brain stored in ModData, and PZ's own pathfinding and animation system doing the movement.  This is not Truly Impossible — it is deferred to a visual-only phase.  See Section 12.

**Item spawning in containers.**
The server can call `container:addItem()` to place items in world containers.  Risk: targeting the right container, handling full containers, ensuring item type strings are valid.  All production tasks that create items depend on this.  Item type strings for each role must be verified against the B42 registry before that role's production step is implemented.

**Item registry performance.**
Iterating every container in the settlement on every tick is fine at small scale.  At large settlements it may cause frame hitches.  The registry is built with caching and does not scan the world more than once per tick.

**World-state cache (water source, heat source, animals).**
Scanning 50-tile radius for water sources at every tick would be expensive.  Cache results are refreshed every 7 in-game days.  The player can force a refresh by disbanding and re-establishing (or via admin command in a later phase).

### 2.4 Kahlua-Specific Gotchas

- **No `goto` / `::label::`** — Lua 5.1 only.
- **Java exceptions escape `pcall`** — any call through a Java-backed object can throw a `RuntimeException` that `pcall` cannot catch.  Do not treat `pcall` as a safety net for Java method calls.  Avoid methods known to throw; use Lua-side checks (sprite name comparisons, nil guards) instead.
- **`math.random` is nil** — use `ZombRand(n)` instead.  Returns 0 to n-1.
- **`table.unpack` is nil** — use `unpack` (Lua 5.1 global).
- **No reliable cross-client data sync event** — panels repopulate their display data on open rather than subscribing to a server broadcast.

### 2.5 The Consequence for Design Language

Any place in this document that describes a settler *doing* something physically should be understood as shorthand for: **the tick runs, the log records it, the outcome is applied.**  "Timmy walked to the treeline and chopped wood" means "the Woodcutter task ran, plank items were added to storage, and a log entry was written."  There is no Timmy walking anywhere — until Section 12's later visual phase.  This is not a limitation to apologize for — it is the design.  The log is the simulation.

---

## 3. Settlement Boundary

The settlement boundary determines what is "inside" the Bastion — which containers are community storage, which settlers are home, which beds and work sites count, and what the zombie attraction radius covers.

### 3.1 Radius-Based Boundary

The boundary is a **fixed tile radius from the bastion anchor square** (the tile clicked when the bastion was established).  The radius grows automatically as the settler count increases — no manual expansion is needed.

> ⚑ OPEN: Exact growth formula not yet defined.  Starting radius, step size per additional settler, and maximum radius to be tuned during Phase 3 playtesting.  See Open Question #27.

Player-built extensions (walls, floors, roofed areas attached to the main building) fall inside the radius automatically.  The boundary is purely geometric — room type is not used for inclusion decisions, which means player-constructed additions count from the start.

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

The visualization is client-side only — no server communication is needed, since the client already knows the anchor square and radius.  The tile list is rebuilt each time the window opens so it reflects any world changes since last viewed.

---

## 4. The Settlement Tick

The simulation advances once per in-game day.  Each tick has four sequential phases that complete in order.

### 4.1 Phase 1 — Consumption

Settlers eat and drink.  This phase runs unconditionally — regardless of how much work capacity exists, settlers have needs.

Daily food and water are calculated from current settler count and deducted from community storage.  The consumption pass leaves storage in its post-consumption state before Phase 2 begins.

**Consequence triggers:**

| Deficit | Immediate | Prolonged |
|---------|-----------|-----------|
| Food gap | Happiness drops | Struggling → Critical → departure → death |
| Water gap | Happiness drops (faster escalation than food) | Struggling → Critical → departure → death |

Deficits are logged with enough specificity to act on: `Settlement ran short on food (3 of 6 settlers fed). Happiness declining.`

### 4.2 Phase 2 — Queue Building

After consumption, the tick scans current storage and bastion state and builds the prioritized work queue.

**A task only appears on the queue if ALL of the following are true:**
- The bastion has sufficient specialty ranks for the task (see Section 6.2)
- Required input items exist in storage
- Required work site is present (if the task needs one)
- Output is not already at its configured cap

Tasks that cannot run this tick are absent from the queue.  The log records why expected tasks were skipped.

**Priority tiers** are assigned based on current need relative to target levels:

| Tier | Condition |
|------|-----------|
| **Urgent** | Resource below 50% of daily requirement |
| **High** | Resource below 100% — not meeting daily need |
| **Normal** | Resource below 200% target — building a buffer |
| **Low** | Resource above buffer — low marginal value this cycle |

Example: water in storage covering less than half the daily need → water collection is Urgent.  Once storage exceeds twice the daily need → water collection drops to Low.

### 4.3 Phase 3 — Work Unit Calculation

Each settler contributes work units to the tick's labor budget.  Units reflect available effort, reduced by poor mood, illness, or low resolve.

| Mood State | Work Unit Contribution |
|------------|----------------------|
| Content | 1.0 |
| Struggling | 0.5 |
| Critical | 0.1 |

**Total work units** = sum of all settler contributions for this tick.

Specialty ranks do not affect work unit count.  A highly-ranked Cook and a low-ranked one contribute the same units — ranks determine what tasks are *available*, units determine how much *gets done*.

### 4.4 Phase 4 — Work Execution

Tasks execute from the queue in priority order, highest first.  Each task costs one work unit.  Execution continues until the work unit budget is exhausted or the queue empties.

Tasks not reached this cycle are logged: `Work units exhausted — N tasks deferred.`

Produced items are placed into available community storage containers.  If storage is at weight capacity, production tasks that would add items are excluded from the queue in Phase 2.

### 4.5 Log Message Style

Short, named, specific.  The player should be able to read the log and understand exactly what happened without inferring.

```
Settlement consumed: 6 meals, 12 units of water.
Rosa cooked 4 meals from perishables. [shelf B]
Dr. Okafor sterilized 5 bandages. [medical kit]
Dr. Okafor — no heat source in bastion; bandages skipped.
Sarah collected and boiled water. +6 units added to storage.
Sarah — no pot in storage; water collection skipped.
Marcus — thread at cap. Rag picking skipped.
[QUIET MODE] Woodcutting skipped — noise budget exceeded.
Work units exhausted — 3 tasks deferred (cooking tier 2, trapping, foraging).
```

### 4.6 Tick Frequency

Once per in-game day.  The last tick date is persisted in the settlement record so reloading mid-day does not cause a double-fire.

---

## 5. Community Scores

Community-wide metrics that influence settler behavior, production, and arrival rates.

### 5.1 Resource Scores (Objective Gauges)

| Score | What It Measures | Critical Effect |
|-------|-----------------|-----------------|
| **Food** | Days of food remaining at current consumption | Below 3 days: warning logged; below 1: Happiness drops |
| **Water** | Days of water in community storage at current consumption | Below 2 days: Doctor and Farmer skip water-requiring tasks |
| **Noise** | Current noise output vs. player-set budget | Over budget: noisy tasks suppressed |
| **Storage** | Current weight vs. total weight capacity of all community containers | Above 80%: warning shown; at 100%: production tasks blocked |

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

Water: 6.2 days  [OK]
  + Sarah (Water Carrier)              +2.0/day
  - Doctor sterilizing bandages        -0.8/day
  - Farmer watering crops              -1.0/day

Storage: 247 / 450 kg  [OK]

Noise: 4 / 6  [OK]
  + Woodcutter chopping                +3
  + General settlement presence        +1
  [Silent mode: smithing suppressed]
```

The contributor breakdown is a Phase 3 feature.  Phase 1–2 show the score value only.

---

## 6. Settlers & Specialists

### 6.1 Design Principle

Settlers exist in the settlement and in the log.  The player learns who they are through tick reports and the Settlers tab in the Bastion Window.  The roster is read-only from the player's perspective; settler management (adding, removing) is an admin-only function accessed via chat commands or the debug panel.

### 6.2 Specialist Ranks

Settlers contribute **specialty ranks** to the bastion's total capability.  Ranks determine what tasks the bastion can perform — not how much work gets done this tick.

Each settler has 1–4 ranks in their primary specialty, reflecting their background:

| Ranks | Archetype |
|-------|-----------|
| 1 | Hobbyist or incidental experience (burger flipper → cooking) |
| 2 | Regular practitioner (housewife → cooking) |
| 3 | Journeyman — did this for a living |
| 4 | Professional or expert (chef → cooking) |

**The bastion's total ranks in a specialty = sum across all settlers with that specialty.**

Tasks have minimum rank thresholds.  Examples for cooking:
- Basic meal prep from perishables: 1+ cooking ranks
- Food preservation (jarring): 8+ cooking ranks
- High-nutrition meals (Happiness bonus): 12+ cooking ranks

Adding settlers with relevant backgrounds directly expands what the settlement can do.  No separate skill advancement system is needed — capability grows by recruiting better specialists.

**Ranks are separate from work units.**  A settler with 4 cooking ranks who is Struggling still unlocks advanced cooking tasks — they just contribute fewer work units to execute them.

### 6.3 Per-Role Settings

Each role has a named set of settings defining its resource floors and caps.  Settings default to sensible values on establishment and can be changed via admin command or (Phase 3) the Settings tab UI.

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
| Doctor | Heat source (stove, campfire) | Overlaps with existing heat source infrastructure check — may be consolidated |
| Blacksmith | Forge or metalworking station | 50% ingot output |
| Teacher | Chalkboard within radius | Role inactive entirely (chalkboard is prerequisite, not a productivity modifier) |
| Woodcutter | Sawmill or workbench | No penalty — splitting logs needs no appliance |
| Tailor | Sewing machine | 50% thread/repair output |

*Other roles have no work site requirement.*

### 6.8 Work Units

Work units are the settlement's daily labor budget, calculated fresh each tick during Phase 3.

**Base contribution:** 1 work unit per settler per tick at Content mood.

**State modifiers:**

| Mood State | Work Unit Contribution |
|------------|----------------------|
| Content | 1.0 |
| Struggling | 0.5 |
| Critical | 0.1 |

**Total work units** = sum of all settler contributions.  This is the budget consumed during Phase 4.  Each task costs one work unit.

Specialty ranks do not affect work unit count.  Ranks determine what tasks are *available*; mood and health determine how much *gets done*.

> ⚑ OPEN: Is every task always 1 work unit, or do complex tasks (blacksmithing, surgery) cost more?  Starting assumption is 1 unit per task.  See Open Question #31.

---

## 7. NPC Generation

Bastion uses PZ's RNG patterns for all settler generation.  No hand-authored characters.

### 7.1 Generation Layers

**Name:** First + last from gender-appropriate pools (30 male, 30 female, 40 last names).

**Role / Specialty:** Fill open community needs first.  Assign randomly if no gap.

**Specialty Ranks:** 1–4, assigned based on backstory archetype.  The occupation drives the rank: a professional chef gets 4 cooking ranks, a housewife gets 2, someone who worked a food counter gets 1.  Most settlers fall at 1–2 ranks; 4-rank specialists are rare.

**Trait Tags:** 1 tag from a pool of ~23.  Narrative flags, not stat modifiers.  Appear in arrival log and Settlers tab profile.

**Backstory Seed:** One generated line.  `[occupation] from [PZ location] who [circumstance]`.  Shown in arrival log; available in Settlers tab.  The occupation implies the specialty rank.

**Mood State:**

| State | Work Unit Contribution | Effect |
|-------|----------------------|--------|
| `Content` | 1.0 | Full contribution |
| `Struggling` | 0.5 | Flagged in log |
| `Critical` | 0.1 | Leaves if unresolved |

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

The scanner walks all objects within the bastion radius of the anchor square.

**Storage Weight Capacity**

The bastion tracks total weight capacity vs. current stored weight across all community containers, displayed in the Overview as `current / maximum kg` (e.g., `247 / 450 kg`).

- At ~80% capacity: warning shown — "Storage getting full; new containers needed."
- At 100% capacity: production tasks that would add items are excluded from the Phase 2 queue.

### 8.2 Water in Storage

Settlers drink water from community storage.  The WaterCarrier role produces actual filled water containers each tick, placed into community storage like any other produced item.

The water score reflects days of water remaining at current consumption rate, calculated from the water items actually present in community containers.

**World-state cache:** Water source and heat source presence is expensive to scan every tick.  The result is cached and refreshed every 7 in-game days.  Infrastructure status is shown in the Overview tab so the player can see why the WaterCarrier task is absent from the queue.

**WaterCarrier output per tick:** 2.0 + (specialty ranks − 1) × 0.3 water-units produced per work unit spent.

> ⚑ OPEN: Natural water terrain (ponds, rivers): B42-safe detection method?  `sq:isWater()` throws a Java exception escaping pcall.  See Open Question #26.

### 8.3 Kitchen Awareness (Phase 3)

The Cook specialist will be aware of appliance locations (stoves, ovens) within the settlement.  Food items drift toward containers near cooking appliances over time.  The player doesn't need to manually sort the pantry.

> ⚑ OPEN: "Drift" is a soft mechanic.  Needs bounds so it doesn't move everything to one spot.  See Open Question #2.

### 8.4 Private Container Flagging

- Right-click any container inside the settlement → "Mark as Private" / "Mark as Shared"
- Private containers are invisible to the simulation; specialists never draw from them or place items into them
- Private/shared state persists across sessions

### 8.5 Food Management

- Cook uses perishable food first (fresh and raw items before shelf-stable)
- Dry goods are excluded by default; the setting can be unlocked to allow them
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
- **Per-role settings:** caps and floors per role (Phase 3 UI; currently via admin command)

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

A resizable, draggable tabbed panel.  Auto-refreshes every ~5 seconds while open.

#### Tabs

**Overview**
Settlement status at a glance.  Shows:
- Settlers count, Food days, Water days, Noise score/budget, Storage weight (`247 / 450 kg`)
- Infrastructure flags: water source found/not found, heat source found/not found, animals detected
- Bed count vs. settler count (deficit flagged in yellow)
- Work queue preview: top 5 tasks queued for the next tick, with priority tier
- Last 3 log entries

*Phase 3 target: contributor breakdown below each score.*

**Settlers**
Full roster.  Each row: name, specialty, mood, rank.  Clicking a row shows settler profile inline (backstory, trait, mood detail).

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

**Anywhere (no bastion exists):**
- `Establish Bastion` — creates the settlement; opens Bastion Window immediately.

**Anywhere inside the bastion (bastion exists):**
- `Check on Bastion` — opens/toggles the Bastion Window.

**On a container inside the bastion:**
- `Mark as Private` / `Mark as Shared`

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

### 12.1 Design Principle

Settlers exist in the log and in the Bastion Window.  In early phases there is nothing physical representing them in the world.  The settlement feels alive through the quality of its log, not through figures standing around.

This is not a compromise — it is the design.  See Section 2.5.

### 12.2 Visual Representation (Phase 4+)

When the core simulation is stable and playtested, settlers can be given physical presence using the IsoZombie hijacking technique proven by the Bandits mod.

**How it works:**
- Each settler is an `IsoZombie` instance with zombie AI disabled and a Lua brain stored in ModData
- PZ's own pathfinding (`PathFindBehavior2`), walk animations, and clothing system do the work
- The brain persists across saves and syncs to clients via GlobalModData
- The settler wanders within the bastion radius on a simple ambient loop

**Key distinction:** This layer is **purely visual**.  The tick simulation runs independently.  The walking figure represents what the log says is already happening — it does not do the work.

**Prerequisites before implementation:**
- Core simulation stable and playtested through Phase 3
- Settler brain structure compatible with IsoZombie ModData pattern
- Simple patrol program (wander within radius, idle at work site locations)
- Clothing and appearance built from settler generation data
- Protection from player and zombie aggression (flag approach used by Bandits mod)

### 12.3 Phase Timeline

No NPC spawning in Phases 1–3.  Walking settlers are a Phase 4+ feature added only after the simulation beneath them is worth animating.

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

- [x] Settlement boundary: tile radius from anchor square
- [x] NPC generation: name, role, specialty ranks, trait tag, backstory seed
- [x] Community storage: opt-out container system, item registry (general / refrigerated / frozen)
- [x] Settlement tick: once per in-game day, guarded against double-fire on reload
- [x] **Bastion Window**: Overview, Settlers, Log, Settings tabs; draggable and resizable
- [x] Food and water tracking displayed in Overview
- [x] Noise score with player budget control (Silent / Quiet / Normal / Loud) via Settings tab
- [x] Admin chat commands (`/bastion help/status/tick/reset/addlog`)
- [x] Right-click: Establish Bastion / Check on Bastion / Mark container private/shared
- [x] ModData persistence across save/load

> **Cleanup needed:** Phase 1 code included IsoMannequin spawning (now removed from design) and a virtual yield tracking system (superseded by Phase 2 real-items model).  Both should be stripped in the next pass.

---

### Phase 2 — Real Simulation Loop 🔄 IN PROGRESS

**Goal:** Implement the full four-phase tick.  All settler actions consume and produce real items in storage.  Remove Phase 1 scaffolding (mannequins, virtual yield).

#### Remaining Work 📋

- [ ] **Strip Phase 1 scaffolding**: remove IsoMannequin spawning code and virtual yield tracking
- [ ] **Four-phase tick** (Section 4): consumption pass → queue building → work unit calculation → work execution
- [ ] **Consumption pass**: deduct food and water items from storage per settler per day; apply consequences on deficit
- [ ] **Work unit system**: sum settler contributions modified by mood state (Section 6.8)
- [ ] **Priority queue**: build eligible task list from storage state + rank totals + work site presence; assign priority tiers (Section 4.2)
- [ ] **Storage weight tracking**: scan all community containers for weight capacity and current weight; display `current / max kg` in Overview; warn at 80%; block production tasks at 100%
- [ ] **Produced items land in storage**: each production task calls `container:addItem()` for its output; target = first available non-private container with remaining capacity
- [ ] **Item type string verification**: verify all B42 item type strings for each role's input and output before implementing that role's production step (see Open Question #22)
- [ ] **Resource-floor-aware tasks (all roles):**
  - Tailor: consumes dirty rags, produces thread items; consumes water items (washing step)
  - Doctor: consumes rags, produces sterilized bandages; requires water in storage + heat source
  - Cook: consumes food items (perishables first), produces meal items; respects dry goods cap
  - Farmer: consumes water and seed items, produces food items; retains seed fraction
  - Woodcutter: consumes log items, produces plank items; secondary fire-stoking task
  - Fisher: consumes bait + fishing line, produces fish items
  - Blacksmith: consumes scrap above floor, produces ingot items; requires heat source
  - Rancher: detects animals; consumes grain above floor; produces egg and milk items
  - Mechanic: consumes fuel items (refueling task); consumes parts (maintenance task)
  - Trapper: consumes bait, produces meat items; scans for placed traps in outer ring
  - WaterCarrier: consumes empty containers + fuel, produces filled water containers; requires water source + heat source + pot
- [ ] **Infrastructure flags** in Overview: water source, heat source, animals — cached every 7 days
- [ ] **Bed counting**: sprite-name scan within radius; deficit shown in Overview (Section 6.6)
- [ ] **Work site detection**: recipe-based scan per role type; no work site → productivity penalty (Section 6.7)
- [ ] **Teacher chalkboard dependency**: Teacher task inactive if no chalkboard found within radius
- [ ] **Phase 2 test plan** (Section 15.2)

#### Trapper Design Note

Traps must be placed outside the bastion radius to work.  Scan for placed traps in a ring from 15 tiles to the trap scan radius (default 60) from the anchor square.  Each trap is "checked" — yield rolled based on settler ranks + trap type.  Traps beyond 40 tiles cost 2 work units.  Rebaiting consumes bait items from storage.

---

### Phase 3 — Score Depth & Bastion View 📋 PLANNED

**Goal:** Deepen score feedback; bring the radius to life visually; complete settler lifecycle.

**Open questions to resolve before implementation:** OQ #27 (radius formula), #28 (WorldToScreen API), #29 (bed sprite names), #30 (work site recipe API).

**Scope:**

- [ ] **Radius visualization ("Bastion View")**: colored tile overlay + hover labels shown while window is open (Section 3.2)
- [ ] **Dynamic radius expansion**: grows automatically with settler count (Section 3.1)
- [ ] **Score contributor breakdown** in Overview (contributor table below each score)
- [ ] **Settler mood state triggers**: food/water shortage → Struggling; prolonged → Critical; player interaction → recovery
- [ ] **Death weight**: death log entry uses name + trait tag
- [ ] **Settler arrival mechanics**: new settlers arrive based on Happiness / Resolve; arrival rate configurable
- [ ] **Teacher reading speed multiplier** (if API confirmed; see Open Question #20)
- [ ] **Kitchen awareness**: produced food lands nearest cooking appliances (Section 8.3)
- [ ] **Per-role settings UI** in Settings tab
- [ ] **Expanded admin commands**: `/bastion settler list/add/remove/mood`, `/bastion food/water`
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
- [ ] Debug panel (developer-only, debug mode gated)
- [ ] **Walking NPC visual layer**: IsoZombie-based settlers with ambient patrol behavior within radius (Section 12)
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

Run after Phase 1 tests pass.  Requires: bastion established, relevant items in community storage.

#### Group 8 — Consumption Pass

**T8.1 — Food consumed from storage each tick**
- *Pre:* Known quantity of food items in storage.  One settler.
- *Steps:* Advance one day.
- *Pass:* Food items reduced by one day's consumption.  Log confirms.

**T8.2 — Water consumed from storage each tick**
- *Pre:* Known quantity of water items in storage.  One settler.
- *Steps:* Advance one day.
- *Pass:* Water items reduced.  Log confirms.

**T8.3 — Food deficit triggers Happiness drop**
- *Pre:* No food in storage.
- *Steps:* Advance one day.
- *Pass:* Log warns of deficit with settler count.  Happiness score drops.

**T8.4 — Water deficit triggers faster consequence than food**
- *Pre:* No water in storage.
- *Steps:* Advance one day.
- *Pass:* Log warns of water deficit.  Happiness drops more than equivalent food deficit.

**T8.5 — Consumption runs before queue; post-consumption state drives queue**
- *Pre:* Just enough water for one day's consumption.  WaterCarrier conditions otherwise met.
- *Steps:* Advance one day.
- *Pass:* Water is consumed first; water collection task appears as Urgent in queue and executes that tick.

#### Group 9 — Work Unit System

**T9.1 — Work units equal settler count at Content mood**
- *Pre:* 3 Content settlers.
- *Pass:* Work unit budget for the tick = 3.  Log or debug confirms.

**T9.2 — Struggling settler contributes 0.5 units**
- *Pre:* 2 Content settlers, 1 Struggling.
- *Pass:* Work unit budget = 2.5.

**T9.3 — Budget limits tasks executed**
- *Pre:* 1 settler (1 unit budget).  Queue has 3 eligible tasks.
- *Steps:* Advance one day.
- *Pass:* 1 task executed.  2 tasks logged as deferred.

#### Group 10 — Priority Queue

**T10.1 — Task absent when no capable settlers**
- *Pre:* No settler with Mechanic specialty ranks.
- *Pass:* Vehicle maintenance task does not appear in queue.

**T10.2 — Task absent when input items missing**
- *Pre:* Woodcutter ranks present; no logs in storage.
- *Pass:* Woodcutting task does not appear in queue.

**T10.3 — Task absent when at cap**
- *Pre:* Thread at configured cap.
- *Pass:* Thread-picking task does not appear in queue.

**T10.4 — Task priority reflects resource level**
- *Pre:* Water below 50% of daily need.
- *Pass:* Water collection task appears at Urgent tier.

**T10.5 — Higher priority executes before lower**
- *Pre:* 1 work unit available.  Two tasks: Urgent water collection and Low thread-picking.
- *Pass:* Water collection executes.  Thread-picking deferred.

#### Group 11 — Produced Items

**T11.1 — Production adds real items to containers**
- *Pre:* Cook ranks present; perishable food in storage; space available.
- *Steps:* Advance one day.
- *Pass:* Meal items appear in a community container.  Log confirms with container reference.

**T11.2 — Production blocked at storage capacity**
- *Pre:* Storage at 100% weight capacity.  Cook conditions otherwise met.
- *Steps:* Advance one day.
- *Pass:* Cook task absent from queue.  Log notes storage full.

**T11.3 — Storage weight displayed in Overview**
- *Pass:* "X / Y kg" visible in Overview.  Value matches actual container contents.

#### Group 12 — Resource Floors and Caps

**T12.1 — Task excluded at cap; no work unit consumed**
- *Pre:* Thread at cap.  1 work unit available.  Only thread-picking eligible.
- *Steps:* Advance one day.
- *Pass:* No work unit consumed.  Thread count unchanged.

**T12.2 — Blacksmith does not touch scrap floor**
- *Pre:* Storage has exactly the scrap floor quantity.
- *Steps:* Advance one day.
- *Pass:* Blacksmith task absent.  Scrap count unchanged.

**T12.3 — Cook uses perishables first**
- *Pre:* Storage has fresh vegetables and canned beans.
- *Steps:* Advance one day.
- *Pass:* Fresh items consumed.  Canned goods untouched (dry goods disabled).

**T12.4 — Farmer retains seed fraction**
- *Steps:* Advance one day with Farmer conditions met.
- *Pass:* Seed items appear in storage.  Log confirms fraction retained.

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
| 14 | NPC representation long-term | **Resolved** | No mannequins.  Walking NPCs deferred to Phase 4+ using IsoZombie hijacking (Bandits mod pattern).  See Section 12. |
| 15 | Bundled profession skill advancement | Open | Recommendation: track each skill separately |
| 16 | Storage capacity units — weight or slot count? | **Resolved** | Weight.  Display as `current / max kg` in Overview. |
| 17 | Item registry rebuild frequency | Open | Every tick (simplest); may optimize later |
| 18 | Ambient sound trigger — on tick or independent timer? | Open | Tick-triggered simplest; independent allows time-of-day variation |
| 19 | Noise budget UI | **Resolved** | Tiered presets (Silent/Quiet/Normal/Loud) in Settings tab |
| 20 | Teacher reading speed: does PZ expose book reading rate in Lua? | Open | Need to verify `IsoPlayer:getReadingSpeed()` or equivalent in B42 |
| 21 | Virtual yield claiming | **Resolved** | Removed.  Production places real items directly into storage.  No claiming step. |
| 22 | Item type strings for each role's produced items | Open | Must verify each role's output item type against B42 item registry before implementing that role's production step. |
| 23 | Role settings UI: editable fields in Settings tab | Open | Phase 3 design; per-role settings (not per-settler) in Settings tab. |
| 24 | Trapper: can `IsoTrap` be found via `instanceof` and `sq:getObjects()` in B42? | Open | Phase 2 implementation; verify in test environment |
| 25 | WaterCarrier: does `sq:isWater()` reliably identify ponds and rivers in B42? | **Resolved** | `sq:isWater()` throws a Java exception that escapes Kahlua `pcall` in B42 — cannot be used at all.  Natural water terrain detection deferred; sprite-name scan (rain barrels, wells) is the current fallback.  See OQ #26 for a safe alternative. |
| 26 | Natural water terrain (ponds, rivers): B42-safe detection method? | Open | `sq:isWater()` is off the table (see OQ #25).  Candidates: iterate `sq:getObjects()` looking for water-tagged sprite names; check tile definition via `TileDefinition`; use `getWorld():getWater()` if it exists.  None confirmed in B42 yet. |
| 27 | Radius expansion formula: starting size, step per settler, maximum? | Open | Phase 3 design.  Candidates: flat +2 tiles per settler; logarithmic growth.  Needs playtesting to tune. |
| 28 | `WorldToScreen` / tile overlay draw hook in B42: what is the correct API? | Open | Need to confirm the right event hook (likely `Events.OnPostRenderFloor` or `Events.OnRenderTick`) and whether tile-space coordinate conversion is exposed via Lua.  Required for radius visualization (Section 3.2). |
| 29 | Bed sprite name substrings: what names cover all single beds, double beds, and cots in B42? | Open | Candidates: `"bed"`, `"cot"`, `"mattress"`.  Verify against PZ B42 furniture sprite list before implementation. |
| 30 | Work site recipe lookup API: is `CraftRecipeManager` (or equivalent) the right approach in B42? | Open | Recipe-based detection preferred over hardcoded sprite lists for mod compatibility.  Need to confirm the API surface, whether it exposes required objects/surfaces per recipe, and performance implications of calling it at tick time. |
| 31 | Work unit cost per task: always 1, or do complex tasks cost more? | Open | Starting assumption: 1 unit per task.  Revisit during Phase 2 playtesting if production feels too fast or too slow. |
| 32 | Daily food and water consumption per settler: what are the right quantities? | Open | Balance pass during Phase 2 playtesting.  Starting point: 1 meal and 1 water item per settler per day. |

---

*Bastion Design Document v2.0*
*Design before code.  Tests before implementation.  Update this file whenever a decision changes.*
