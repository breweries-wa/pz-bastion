# Bastion — Design Document
> Project Zomboid Build 42 Mod | v0.4 Draft

---

## Table of Contents
1. [Concept](#1-concept)
2. [Settlement Boundary](#2-settlement-boundary)
3. [The Settlement Tick](#3-the-settlement-tick)
4. [Community Scores](#4-community-scores)
5. [Settlers & Specialists](#5-settlers--specialists)
6. [NPC Generation](#6-npc-generation)
7. [Resources & Storage](#7-resources--storage)
8. [Threats & Defense](#8-threats--defense)
9. [Communication & Feedback](#9-communication--feedback)
10. [NPC Representation](#10-npc-representation)
11. [Comparable Games & Borrowed Mechanics](#11-comparable-games--borrowed-mechanics)
12. [Implementation Phases](#12-implementation-phases)
13. [Open Questions](#13-open-questions)

---

## 1. Concept

Bastion is a community-building mod for Project Zomboid. You are the scavenger — the one who goes out into the dangerous world to bring things back. The community depends on you. You depend on the community.

The mod adds something to care about. The people in your settlement have names, roles, and light personalities. When someone dies, someone says their name. That's enough.

### 1.1 Core Fantasy

- You are the link between civilization and the wasteland
- Going out feels meaningful because people are counting on you
- Coming back feels like coming home
- Each survivor added is a small victory with ongoing stakes

### 1.2 Endgame Goal: Self-Sufficiency

The long-term goal is a community that can sustain itself across five pillars:

| Pillar | What Self-Sufficiency Looks Like |
|--------|----------------------------------|
| Food | Farming + preservation produce enough calories; no dependence on looting for sustenance |
| Water | Rain collection, wells, or purification sustain the population without outside supply runs |
| Medical | Doctor, herb garden, and crafted supplies handle illness and injury without hospital raids |
| Defense | Defenders, fortifications, and threat management handle zombie pressure autonomously |
| Morale | Reading, community culture, and children sustain morale without constant intervention |

---

## 2. Settlement Boundary

The settlement boundary determines what is "inside" the Bastion — which containers are community storage, which settlers are home, and what the zombie attraction radius covers.

**Working approach: use PZ's existing safehouse property system.**

PZ already tracks which tiles belong to a claimed safehouse and enforces rules against claiming while zombies are on the property. For v1, the Bastion boundary *is* the safehouse boundary. The player expands the settlement by expanding the safehouse — no new boundary UI needed.

> ⚑ OPEN: PZ's safehouse system may have constraints we haven't hit yet (size limits, multi-building behavior). Needs validation in Phase 1.

---

## 3. The Settlement Tick

Settlers don't visibly walk around performing tasks. Instead, the simulation advances on a **settlement tick** — once per in-game day (adjustable). On each tick, each settler with an assigned role performs their function invisibly and the result is logged.

### 3.1 How the Tick Works

On each tick, for each settler:
1. Check if their role's requirements are met (resources available, tools present, skill sufficient)
2. If yes: apply the effect (add/consume items, update scores)
3. If no: log a shortage or idle message
4. Append a log entry

### 3.2 Log Messages

Short, named, specific.

```
Timmy collected 2 logs from the woodpile.
Timmy cut 3 planks (logs were plentiful).
Rosa cooked a warm meal. The community ate well.
Rosa couldn't cook — no fuel in the firepit.
Dr. Okafor treated a minor infection. No supplies used.
Dr. Okafor is low on bandages. Bring more.
Marcus repaired the pickup truck (engine: 68% → 74%).
No water collected today — barrels are full.
Sarah has been struggling. She didn't contribute today.
[QUIET MODE] Woodcutting skipped — noise budget exceeded.
```

Critical shortages surface as notifications even when the log is closed.

### 3.3 Tick Frequency

> ⚑ OPEN: Once per in-game day is simplest and most legible. Start there and adjust.

---

## 4. Community Scores

Community-wide metrics that influence settler behavior, production, and arrival rates. Two categories: objective resource gauges and slower-moving subjective scores.

### 4.1 Resource Scores (Objective Gauges)

| Score | What It Measures | Critical Effect |
|-------|-----------------|-----------------|
| **Food** | Days of food remaining at current consumption | Below 3 days: Happiness drops; defection risk |
| **Water** | Days of water remaining | Below 2 days: Cook and Doctor lose effectiveness |
| **Health** | Community-wide injury/illness load | Low: productivity loss; death risk without intervention |
| **Defense** | Threat level vs. defensive capability | Deficit: incursions escalate |
| **Storage** | Available community storage capacity | Full: specialists can't deposit output; work halts |
| **Noise** | Current noise output vs. player-set budget | Over budget: noisy activities suppressed or trigger threat |

### 4.2 Subjective Scores

Slower to move. Reflect the emotional and social state of the settlement.

| Score | What It Measures |
|-------|-----------------|
| **Happiness** | Day-to-day comfort and quality of life |
| **Resolve** | Long-term will to survive; hope |
| **Education** | Accumulated community knowledge and skills |

> ⚑ OPEN: Are these the right scores? Are there others worth tracking? Revisit after Phase 2 with real data.

### 4.3 Score Contributor UI

Each score panel shows every active contributor with its value. The player should never guess why a score is moving.

```
COMMUNITY STATUS
----------------
Food: 8 days  [OK]
  + Rosa cooking (reduces waste)       +1 day
  - 6 settlers consuming               -0.8/day

Noise: 4 / 6  [OK]
  + Woodcutter active                  +2
  + Defender patrol (occasional shots) +1
  + General settlement activity        +1
  - Quiet mode: gunshots restricted    -1

Resolve: 41  [~]
  + Successful defense (3 days ago)    +6
  - Marcus died                        -18
```

---

## 5. Settlers & Specialists

### 5.1 Design Principle

Settlers exist in the settlement and in the log. The player learns who they are through tick reports and observation, not a roster screen. There is no settler management UI.

### 5.2 Skill-Based Roles

Every PZ skill maps to a specialist role. A settler assigned to a role performs tick actions appropriate to their **skill level** — higher skill means more efficient recipes, better outputs, and less waste. Recipes with a minimum skill requirement are only usable by settlers who qualify.

**Example:** A Cook at skill level 1 can prepare basic meals. A Cook at level 5 can preserve food in jars, reducing waste. A Cook at level 8 can produce high-nutrition meals that provide a Happiness bonus beyond what low-skill cooking provides.

Skill levels improve over time — settlers learn by doing.

#### Full Role List

| Role | Primary Skill(s) | Type | Notes |
|------|-----------------|------|-------|
| Farmer | Farming | Production | Seasonal; ties into PZ crop system |
| Cook | Cooking | Production | Kitchen-aware; uses nearest cooking appliances |
| Doctor | First Aid | Support | Reduces infection, illness spread |
| Mechanic | Mechanics | Maintenance | Daily vehicle repair tick |
| Carpenter | Carpentry | Production | Planks, furniture, structural repair |
| Woodcutter | Axe | Production | Logs → planks; heating fuel |
| Electrician | Electrical | Maintenance | Keeps powered appliances functional |
| Welder | Welding / Metal Working | Production | Metal fabrication; gates some Blacksmith tasks |
| Blacksmith | Metal Working + Blacksmithing | Production | B42-gated; requires Education threshold |
| Tailor | Tailoring | Maintenance | Clothing repair and basic gear crafting |
| Trapper | Trapping | Production | Passive food from traps placed near settlement |
| Fisher | Fishing | Production | Passive food from water sources in range |
| Forager | Foraging | Production | Collects wild plants and forageable items nearby |
| Defender | Aiming + Weapon skill | Security | Patrols; handles probes; noise variable |
| Teacher | — | Passive | No skill requirement; raises Education score |
| Child | — | Passive | No skill requirement; raises Resolve |

#### Bundled Professions

Some professions draw on multiple skills, reflecting real-world expertise that doesn't fit a single PZ skill.

| Profession | Skills Bundled | Rationale |
|-----------|---------------|-----------|
| **Hunter** | Aiming, Short Blade (skinning), Trapping | Finding, killing, and processing game |
| **Scout** | Sprinting, Lightfooted, Sneak | Perimeter awareness; reduces threat detection delay |
| **Soldier** | Aiming, Reloading, Long Blunt or Long Blade | Combat-focused Defender variant; high noise |
| **Medic** | First Aid, Tailoring (wound dressing) | Field medicine; slightly broader than Doctor |

> ⚑ OPEN: How do bundled professions advance in skill? Does each skill track separately, or does the profession have a single level? Recommendation: track separately, advance independently.

#### Non-Skill Roles

- **Teacher**: No combat or craft skill. Raises Education score by being present and having books available. Effect is slow and long-term.
- **Child**: No contribution to production. Raises Resolve passively — the presence of children signals a future worth protecting. Cannot be assigned a specialist role.

### 5.3 Settler Arrivals

New survivors arrive over time. Arrival rate is influenced by Happiness, Resolve, and settlement visibility. Some roles (Doctor, Teacher, Blacksmith) are quest-gated — requires finding and escorting the survivor.

---

## 6. NPC Generation

Bastion uses PZ's RNG patterns for all settler generation. No hand-authored characters.

### 6.1 Generation Layers

**Name:** Pull from PZ's regional name tables by gender.

**Role:** Fill open community needs first. Assign randomly if no gap, or leave unassigned.

**Skill Level:** Random within a plausible range for the role. A Doctor arrives with First Aid 3–6. A Child arrives with no applicable skills.

**Trait Tags:** 1–2 tags from a pool of ~25–30. Narrative flags, not stat modifiers. Surface in log messages.

Example tags: `Optimist`, `Nervous`, `Practical`, `Bad Dreams`, `Keeps to Herself`, `Tells Bad Jokes`, `Believes in Something`, `Gets Quiet When It Rains`, `Former Teacher`, `Light Sleeper`

**Backstory Seed:** One generated line. `[occupation] from [PZ location] who [circumstance]`. Shown once in the arrival log. Implied thereafter.

**Mood State:**

| State | Effect |
|-------|--------|
| `Content` | Normal tick contribution |
| `Struggling` | Reduced output; flagged in log |
| `Critical` | No contribution; leaves if unresolved |

### 6.2 Death Weight

> *"Marcus didn't make it. He was the one who always had something to say at the wrong moment. We're going to feel that."*

No death screen. Just a log entry, and silence.

---

## 7. Resources & Storage

### 7.1 Community Storage

All containers within the settlement boundary are **community storage by default**. The player marks individual containers as **private** to exclude them from the simulation. This inversion (opt-out rather than opt-in) is more natural — the settlement owns what's in its walls unless the player claims it personally.

**Storage categories:**

| Category | Container Types | Tracked Separately |
|----------|----------------|-------------------|
| **General** | Crates, shelves, cabinets, bags | Base capacity |
| **Refrigerated** | Fridges, coolers | Perishable food shelf-life extended |
| **Frozen** | Freezers | Frozen food; longest preservation |

Each category has a capacity (total item weight or slot count, TBD) tracked as a community score. When a category is full, specialists cannot deposit further output and log a warning.

**Item registry:**
The settlement maintains a live registry of all items across all community containers. This enables:
- Food projection (count calories across all food items)
- Recipe validation (does the Cook have the required ingredients?)
- Shortage detection (is the Defender running low on ammunition?)
- Future: crafting queue, resource allocation per specialist

The registry is rebuilt on each tick and cached. It does not require scanning every container in real time.

### 7.2 Kitchen Awareness

The Cook specialist is aware of appliance locations (stoves, ovens, microwaves) within the settlement. On each tick:
- Food items drift toward containers near cooking appliances
- The Cook draws ingredients from the nearest appropriate container first
- Over time, food naturally congregates in the kitchen without player intervention

This creates emergent organization. The player doesn't need to manually sort the pantry — it happens as a byproduct of the Cook working.

> ⚑ OPEN: "Drift" is a soft mechanic that moves items between containers on the tick. Needs to be bounded so it doesn't move everything to one spot or create annoying surprises for the player.

### 7.3 Private Container Flagging

- Right-click any container inside the settlement → "Mark as Private"
- Private containers are invisible to the simulation; specialists never draw from them
- Player's personal stash, emergency reserves, items in-progress — these stay private
- UI indicates private vs. community ownership on container inspect

### 7.4 Food Management

- **Spoilage priority toggle:** Cook uses nearly-spoiled food first
- **Food projection:** HUD shows days remaining at current consumption
- **Balanced diet:** Cook attempts variety; monotonous diet incurs Happiness penalty

### 7.5 Water

- Rain barrels as primary collection
- Consumption tracked per tick
- Shortage: Cook and Doctor lose effectiveness
- HUD metric alongside food projection

---

## 8. Threats & Defense

### 8.1 Noise Score

Settlement activity generates noise that attracts zombies. Noise is tracked as a discrete score with a player-configurable budget.

**Noise contributors by role:**

| Activity | Noise Level |
|----------|------------|
| General settlement presence | Low (always-on baseline) |
| Woodcutter chopping | High |
| Blacksmith hammering | Very High |
| Mechanic (engine work) | Medium |
| Defender using firearms | Very High (but intermittent) |
| Defender using melee | Low |
| Cooking, farming, tailoring | Minimal |

When the noise score exceeds the player's set budget, the settlement tick suppresses the noisiest activities first and logs the skipped actions. This gives the player a lever to trade productivity for safety.

### 8.2 Player Activity Controls

The player can configure what the settlement is and isn't allowed to do:

- **Noise budget:** A simple slider or tiered setting (Silent / Quiet / Normal / Loud). Constrains which specialist activities run on a given tick.
- **Firearms toggle:** Allow or prohibit Defenders from using guns. Melee-only mode reduces noise significantly at the cost of Defender effectiveness.
- **Time restrictions:** Noisy work (chopping, smithing) restricted to daylight hours only.
- **Individual role suspend:** Pause any specialist role entirely.

These settings persist and are adjustable at any time. They are not "quests" or "upgrades" — they're configuration.

### 8.3 Ambient Sounds

When specialist activities run on the tick, **real in-game sounds play at the settlement location**. The player hears log chopping if the Woodcutter worked. They hear a distant gunshot if the Defender engaged. These sounds exist in 3D space — audible from outside the settlement, louder when nearby.

This creates the illusion of an active community without requiring visible NPCs performing animations. The sounds *are* the evidence.

The sounds also reinforce the noise score — the player can literally hear when the settlement is being loud.

> See Section 10 for the open question about NPC physical representation and why ambient sound is load-bearing.

### 8.4 Zombie Attraction

- Noise score is the primary zombie attraction driver
- Population size adds a baseline scent/presence attractant
- Defenders reduce effective threat by handling wanderers before they trigger events
- Attraction is reduced when activity controls are restricted

### 8.5 Threat Events

| Tier | Description | Resolution |
|------|-------------|------------|
| Probe | Small group drawn to perimeter | Defenders handle automatically |
| Incursion | Larger group | Defenders engage; may need player support |
| Horde | Serious threat | Requires player; may damage structures |

Predictable escalation: the player knows the horde is building and can prepare.

### 8.6 Loot & Cleanup

- Defenders or general settlers clean nearby corpses on the tick
- Uncleaned corpses create a Health and Happiness penalty over time
- Looted gear from kills goes into community inventory

---

## 9. Communication & Feedback

### 9.1 Settlement Log

The player's primary feedback channel. Running record of tick actions, arrivals, deaths, shortages, and events.

- Accessible via panel (keybind TBD)
- Chronological, most recent first
- Color-coded: white (standard), yellow (warning/shortage), red (death/critical), green (milestone)
- Persists across sessions in world ModData

### 9.2 HUD

Minimal persistent overlay:
- Food: days remaining
- Water: days remaining
- Noise: current / budget
- Threat level: none / probe / incursion / horde
- Settler count

### 9.3 Right-Click NPC Dialogue

Any settler can be right-clicked for a one-liner tied to their mood, role, or current situation. This is ambient flavor, not a menu system.

> *"The crops look okay. Worried about the cold coming."*
> *"We're low on bandages. Someone should make a run."*
> *"I'm fine. Just tired."*

Settlers are not quest-givers and do not deliver structured reports.

### 9.4 Radio Check-In

- Ham Radio at settlement + walkie-talkie on player = check-in while out
- Returns summary: food, water, noise level, active threats, flagged settlers
- Delivered by whoever is on radio duty (any settler, not a named role)
- Critical events trigger emergency broadcasts
- No signal if out of range

---

## 10. NPC Representation

This is the hardest unsolved design question in the mod.

### 10.1 The Problem

Bastion's simulation is invisible. Specialists work, the log records it, sounds play — but if no physical NPCs are present, the settlement feels empty. And if physical NPCs are present but static (mannequins), it feels like a display window, not a community.

The tension: we need the settlement to feel *inhabited*, but fully animated NPCs with real AI and pathfinding is a massive technical undertaking that goes far beyond the scope of this mod.

### 10.2 Options Under Consideration

**Option A: Mannequins (current)**
- Proven. Each settler is a placed IsoMannequin with moddata.
- Completely static. No movement. No animation. Looks like a shop.
- Credible as a placeholder for Phase 1. Not credible long-term.

**Option B: Mostly Indoors**
- Assume settlers are always inside buildings. Don't render them externally.
- Sounds come from inside the building (muffled chopping, talking, etc.).
- Player interaction happens by entering buildings or via right-click on the building itself.
- Sidesteps the representation problem entirely — settlers are *implied* rather than shown.
- Precedent: many colony-sims (Frostpunk, etc.) use workers that are barely visible and never individually tracked.

**Option C: One Visible Spokesperson Per Building**
- One mannequin (or IsoObject) near the entrance of each occupied building represents whoever is inside.
- Sounds come from the building. The visible figure is a stand-in, not an individual.
- Reduces the number of objects to render; keeps *some* visible presence outside.
- Interaction is with the building/spokesperson, not with named individuals directly.

**Option D: Wait for B42 NPC System**
- The developers are actively working on a native NPC system for B42.
- If it matures, Bastion settlers could eventually be implemented as real PZ NPCs.
- Risk: timeline unknown. Designing for this now may waste effort.

**Option E: Zombies with Restricted AI**
- Settlers implemented as modified IsoZombie instances with tagged moddata.
- Movement and "presence" built-in. Could be partially working already.
- Fragile. Zombie AI is not designed for friendly NPCs. High maintenance.
- Previous attempts in the mod hit tagging and interaction problems.

### 10.3 Current Recommendation

**Option B (mostly indoors) for Phase 1–2, with Option C for the one primary contact per building.**

The settlement log and ambient sounds carry the simulation. Physical presence is secondary. Start with one visible figure per building entrance as the interaction point, with sounds implying activity inside. Revisit when B42 NPC systems mature.

---

## 11. Comparable Games & Borrowed Mechanics

### State of Decay 2 — Primary Reference
**Borrow:** Score breakdown UI with all contributors listed. Negative spiral mechanics. Outpost-as-resource-provider for expansion.
**Avoid:** Roster management screen. Per-survivor morale tracking.

### This War of Mine — Emotional Reference
**Borrow:** Named characters with trait tags make death land. One arrival log entry does more work than a stats screen.
**Avoid:** Per-character sympathy system (punishing snowball). Morale as moral enforcement.

### 7 Days to Die — Threat Escalation
**Borrow:** Predictable horde cycle. Tension through anticipation, not randomness.

### Dwarf Fortress / RimWorld — Passive Simulation
**Borrow:** Storytelling through log — you read what happened, imagination fills the gap. Tick-cycle specialists. Mood as emergent story.
**Avoid:** Complexity ceiling. Every Bastion system should be understood in one session.

### Frostpunk — Minimal NPC Visibility
**Borrow:** Workers exist and matter narratively, but you rarely see individuals. The simulation is legible without individual visibility. Sounds and activity indicators substitute for animation.

---

## 12. Implementation Phases

> **Current status:** Proof of concept. Right-click context menu works, Establish/Collapse Bastion sends server commands, a mannequin spawns. No game systems implemented yet.

### Phase 1 — Foundation
- Settlement boundary (safehouse property integration + validation)
- Settler spawning: placed NPCs in settlement, persist across sessions
- NPC generation: name, role, skill level, one trait tag, backstory seed
- Community storage: opt-out container system, item registry
- Storage categories: general, refrigerated, frozen
- Settlement tick: once-per-day cycle, basic log output
- Settlement log panel UI
- Food and water tracking with HUD display
- Noise score tracking with player budget control

### Phase 2 — First Specialists
- Cook: warm meal production, kitchen awareness, Happiness score
- Woodcutter: log/plank production, fuel reserve, noise output
- Farmer: crop tending, harvest, seasonal behavior
- Trapper and Fisher: passive food supplementation
- Settler mood states
- Arrival log entries with backstory seeds
- Radio check-in
- Resolve score
- Ambient sounds: chopping, cooking activity

### Phase 3 — Community Depth
- Doctor, Teacher, Tailor, Forager, Mechanic specialists
- Education score and library mechanic
- Balanced diet and spoilage priority
- Death weight (log uses names and trait tags)
- Quest-gated recruitment (Doctor, Teacher)
- Settler defection at zero Resolve
- Skill advancement over time

### Phase 4 — Threat & Endgame
- Defender, Scout, Soldier, Hunter specialists
- Zombie attraction scaling
- Threat event tiers with ambient sound cues
- Firearms toggle and time-restriction controls
- Blacksmith (Education-gated, B42 smithing integration)
- Carpenter, Electrician, Welder specialists
- Self-sufficiency milestone tracking
- Settlement expansion mechanics

---

## 13. Open Questions

| # | Question | Status | Notes |
|---|----------|--------|-------|
| 1 | PZ safehouse boundary constraints (size limits, multi-building) | Open | Validate in Phase 1 |
| 2 | Container "drift" bounds — how aggressively do items migrate toward kitchens? | Open | Needs playtesting |
| 3 | Illness spreading between settlers | Open | High drama, high complexity — defer to Phase 3 |
| 4 | Zombie attraction scaling formula | Open | Calibrate during Phase 4 playtesting |
| 5 | Quest system scope for specialist recruitment | Open | Fixed locations acceptable for v1 |
| 6 | Horde event structural damage to settlement | Open | Large scope increase if yes |
| 7 | Score threshold values and decay rates | Open | Balance pass after Phase 2 |
| 8 | Multiplayer: tick behavior and scores with multiple players | Open | B42 MP implications significant; defer |
| 9 | Balanced diet tracking — per food type or per food group? | TBD | Food group simpler |
| 10 | Trait tag pool content | TBD | ~25–30 tags; needs authored list |
| 11 | Backstory seed tables | TBD | Needs authored micro-tables |
| 12 | Right-click settler dialogue — authored per tag or templated? | Open | Templated with tag substitution likely sufficient |
| 13 | Subjective score set — are Happiness / Resolve / Education correct? | Open | Revisit after Phase 2 |
| 14 | NPC representation long-term (mannequin / indoors / spokesperson / B42 NPC system) | Open | See Section 10; Option B+C recommended for now |
| 15 | Bundled profession skill advancement — track each skill separately or per profession? | Open | Recommendation: separately |
| 16 | Storage capacity units — weight-based or slot-based? | Open | Weight is more PZ-like but harder to display |
| 17 | Item registry rebuild frequency — every tick or on demand? | Open | Every tick simplest; on-demand more performant |
| 18 | Ambient sound events — trigger on tick, or simulate independently of tick? | Open | Tick-triggered simplest; independent would allow time-of-day variation |
| 19 | Noise budget UI — slider, tiered presets, or per-activity toggles? | Open | Tiered presets (Silent/Quiet/Normal/Loud) simplest; per-activity most flexible |

---

*Bastion Design Document v0.4 — Working Draft*
*Maintain this file in the repo root. Update alongside implementation.*
