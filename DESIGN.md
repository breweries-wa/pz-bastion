# Bastion — Design Document
> Project Zomboid Build 42 Mod | v0.3 Draft

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
10. [Comparable Games & Borrowed Mechanics](#10-comparable-games--borrowed-mechanics)
11. [Implementation Phases](#11-implementation-phases)
12. [Open Questions](#12-open-questions)

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

The settlement boundary determines what is "inside" the Bastion — which containers belong to community inventory, which settlers are home, and what the zombie attraction radius covers.

**Working approach: use PZ's existing safehouse property system.**

PZ already tracks what tiles belong to a claimed safehouse, and enforces rules against claiming a safehouse with zombies on the property. This gives us a ready-made boundary with known behavior. For v1, the Bastion boundary *is* the safehouse boundary.

Implications:
- Container flagging operates within safehouse-owned tiles
- Settler "home" status is determined by whether they are on safehouse tiles
- Zombie attraction radius is centered on or derived from the safehouse boundary
- The player expands the settlement by expanding the safehouse — no new UI needed

> ⚑ OPEN: PZ's safehouse system may have constraints we haven't hit yet (size limits, multi-building behavior). This assumption needs validation during Phase 1 implementation.

---

## 3. The Settlement Tick

Settlers don't visibly walk around performing tasks. There are no animations of the Woodcutter hiking to the treeline. Instead, the simulation advances on a **settlement tick** — either once per in-game day or at a regular interval (e.g., every few in-game hours). On each tick, each settler with an assigned role performs their function invisibly and the result is logged.

### 3.1 How the Tick Works

On each tick, for each settler:
1. Check if their role's requirements are met (resources available, tools present, etc.)
2. If yes: apply the effect (add items to community inventory, update a score, consume inputs)
3. If no: log a shortage or idle message
4. Append a log entry describing what happened

The log is the player's window into settlement activity. It replaces animation with narration.

### 3.2 Log Messages

Short, plain-language entries. Named settlers, specific quantities where useful.

**Examples:**
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
```

Messages are readable in a settlement log panel (see Section 9). Critical shortage messages surface as notifications even if the player doesn't open the log.

### 3.3 Tick Frequency

> ⚑ OPEN: Once per in-game day is simplest and most legible. Periodic ticks (every few hours) create more log entries and finer granularity but may feel noisy. Start with once-per-day and adjust.

---

## 4. Community Scores

Community scores reflect the health and capability of the settlement. These are community-wide metrics — not per-settler. They influence settler behavior, production efficiency, and survivor arrival rates.

The exact set of scores is not yet finalized. Two categories are emerging:

### 4.1 Resource Scores (Objective)

Measurable quantities with direct in-game consequences. These are closer to gauges than scores.

| Score | What It Measures | Critical Threshold Effect |
|-------|-----------------|--------------------------|
| **Food** | Days of food remaining at current consumption | Below 3 days: Happiness drops rapidly; settlers may leave |
| **Water** | Days of water remaining | Below 2 days: Cook and Doctor lose effectiveness |
| **Health** | Community-wide health (injuries, illness) | Low: productivity loss, risk of death without intervention |
| **Defense** | Threat level relative to defensive capability | Low: incursion events escalate |

### 4.2 Community Scores (Subjective)

These reflect the emotional and social state of the settlement. Harder to measure, slower to move.

| Score | What It Measures |
|-------|-----------------|
| **Happiness** | Day-to-day comfort and quality of life |
| **Resolve** | Long-term will to survive; hope |
| **Education** | Accumulated knowledge and skills |

> ⚑ OPEN: Are these the right scores? Are there others worth tracking (Security? Reputation? Population stability)? The resource scores feel more concrete and immediately useful. The subjective scores need clearer mechanical consequences before they're worth implementing. Revisit after Phase 2.

### 4.3 Score Contributors (UI)

Inspired by State of Decay 2's morale breakdown: each score panel shows every active positive and negative contributor with its current value. The player should never need to guess why a score is moving.

```
COMMUNITY STATUS
----------------
Food: 8 days  [OK]
  + Rosa cooking (reduces waste)     +1 day
  - 6 settlers consuming             -0.8/day

Water: 2 days  [LOW]
  + Rain barrels collecting          +0.3/day
  - Community consumption            -0.5/day
  ! Shortage warning active

Happiness: 64  [+]
  + Warm meals active                +8
  + Reading materials available      +4
  - Water shortage                   -5
  - Recent settler death             -12

Resolve: 41  [~]
  + Successful defense (3 days ago)  +6
  - Marcus died                      -18
```

---

## 5. Settlers & Specialists

Settlers are the community. They arrive as generic survivors and can be assigned to specialist roles as the settlement grows. Specialists apply passive effects to the community on each settlement tick.

**Design principle:** Settlers exist in the world and in the settlement log. The player learns who they are through tick reports and observation — not through a roster screen. There is no settler management UI.

### 5.1 Specialist Roles

Each role has: a **passive effect** (always active while assigned), **tick actions** (what they do each settlement tick), and **requirements** (what they need to function).

#### Mechanic
- **Passive:** Slight daily repair to all vehicles parked within the settlement boundary
- **Tick actions:** Repairs vehicle components incrementally; logs progress per vehicle
- **Requirements:** Mechanical tools, vehicle parts (consumed on repair), vehicle present
- **Example log:** *Marcus repaired the pickup truck (engine: 68% → 74%).*

#### Woodcutter
- **Passive:** Settlement always has a fuel reserve for heating
- **Tick actions:** Collects logs if stock is low; converts excess logs to planks
- **Requirements:** Axe, tree access (proximity to settlement), storage space
- **Example log:** *Timmy collected 2 logs.* / *Timmy cut 3 planks (logs were plentiful).*

#### Farmer
- **Passive:** Crop maintenance (watering, pest control) without player intervention
- **Tick actions:** Tends crops each tick; harvests when ready; reports crop status
- **Seasonal behavior:** Adjusts to PZ's temperature system; warns of winter crop failure
- **Requirements:** Seeds, fertilizer, water, farming tools
- **Example log:** *The tomatoes are ready. Rosa harvested 8.* / *Frost warning — crops may fail without a greenhouse.*

#### Cook
- **Passive:** Community eats warm cooked meals → Happiness bonus
- **Tick actions:** Prepares meals from community food stores; prioritizes spoilage when enabled
- **Requirements:** Fuel, cooking tools, food stocks
- **Example log:** *Rosa cooked a warm meal. The community ate well.* / *Rosa couldn't cook — no fuel.*

#### Doctor
- **Passive:** Reduced infection chance for all settlers; faster healing
- **Tick actions:** Treats injuries and illness; crafts basic medical supplies if materials available
- **Requirements:** Medical supplies, reference books, clean water
- **Example log:** *Dr. Okafor treated a minor infection.* / *Dr. Okafor is low on bandages. Bring more.*

#### Teacher
- **Passive:** Raises Education score over time
- **Tick actions:** Teaches available settlers; effect stronger when children are present
- **Requirements:** Books, designated quiet space
- **Example log:** *Lesson held. Education improving slowly.*

#### Defender
- **Passive:** Reduces zombie incursion frequency around the perimeter
- **Tick actions:** Patrols and neutralizes wanderers before they trigger events
- **Requirements:** Weapons, ammunition or melee equipment
- **Example log:** *Two zombies cleared from the perimeter.*

#### Tailor
- **Passive:** Settler clothing maintained; warmth and protection don't degrade
- **Tick actions:** Repairs worn clothing; may craft basic gear for Defenders
- **Requirements:** Thread, needles, fabric
- **Example log:** *Sarah patched three jackets.*

### 5.2 Settler Arrivals

New survivors arrive over time. Arrival rate is influenced by Happiness, Resolve, and settlement visibility. Some specialists can only be recruited through quests.

**Quest-gated specialists:**
- Certain roles — Doctor, Teacher, Blacksmith — require a specific quest to recruit
- Player receives a lead (radio intercept, note, survivor tip) pointing to a location
- Target survivor must be found and escorted back safely
- Failed escort attempt delays the quest

> ⚑ OPEN: Quest generation scope TBD. v1 may use fixed quest locations.

---

## 6. NPC Generation

Bastion uses PZ's existing RNG table patterns for all settler generation. No hand-authored characters.

### 6.1 Generation Layers

**Name**
Pull from PZ's existing regional name tables by gender. No separate list to maintain.

**Role**
Assigned at join time. Priority: fill an open community need first. If no gap exists, assign randomly or leave as generic settler until the player assigns them.

**Trait Tags**
1–2 tags pulled at spawn from a curated pool of ~25–30. These are narrative flags, not stat modifiers. They surface in settlement log messages and tick reports.

Example tags:
- `Optimist` — log lines skew hopeful even when things are rough
- `Nervous` — first name mentioned when there's a threat
- `Practical` — never complains about food variety
- `Bad Dreams` — mentioned during difficult stretches
- `Keeps to Herself` — rarely surfaces in group reports
- `Tells Bad Jokes` — surfaces in high-Happiness moments
- `Believes in Something` — subtle Resolve contribution when present
- `Gets Quiet When It Rains` — flavor only
- `Former Teacher` — hints at specialist potential
- `Light Sleeper` — surfaces during threat events

**Backstory Seed**
One line, generated from 2–3 small tables:
`[former occupation] from [PZ location name] who [circumstance]`

Examples:
- *Carpenter from Louisville who lost his kids*
- *Nurse from Muldraugh who doesn't talk about before*
- *Mechanic from the highway who walked for three weeks*

Shown once in the arrival log entry. Implied thereafter.

**Mood State**
Three states only.

| State | Effect |
|-------|--------|
| `Content` | Normal tick contribution, no flags |
| `Struggling` | Reduced tick effectiveness, flagged in log |
| `Critical` | No tick contribution, leaves if unresolved |

Mood is influenced by community scores, personal events, and trait tags. Not a stat the player manages directly — it surfaces in log messages.

### 6.2 Death Weight

Named settlers with trait tags make death land without cutscenes. When a settler dies, the log uses their name and references their tag if appropriate:

> *"Marcus didn't make it. He was the one who always had something to say at the wrong moment. We're going to feel that."*

No death screen. No popup. Just a log entry, and then silence.

---

## 7. Resources & Storage

### 7.1 Community Inventory

The community maintains its own inventory separate from the player's personal stocks. Specialists draw from community inventory on each tick.

**Container flagging:**
- Containers inside the safehouse boundary can be flagged as "Bastion Owned"
- Flagged containers are community inventory — specialists draw from and deposit into them
- Player can still access these containers; UI indicates community ownership
- Items placed in flagged containers enter the simulation

> ⚑ OPEN: Flag containers via ModData on each container, or maintain a list of container positions in world ModData? The former is more PZ-like. The latter is easier to query. Recommendation: ModData flag on each container, with a cached list in world ModData for tick queries.

### 7.2 Food Management

**Spoilage priority:**
- Toggle: "Eat nearly-stale food first"
- Cook balances spoilage priority against dietary variety when both are active

**Food projection:**
- Primary HUD metric: estimated days of food remaining at current consumption
- *"You have 8 days before shortages begin"*
- Adjusts based on community size and Cook efficiency

**Diet effects:**
- Balanced diet: Happiness bonus, small efficiency boost
- Monotonous diet: Happiness penalty
- Shortage: rapid score decay, settler defection risk

### 7.3 Water

- Rain barrels as primary collection; capacity is finite
- Consumption tracked — settlers drink, cooking uses water
- Water shortage: Cook and Doctor lose effectiveness
- HUD metric alongside food projection

---

## 8. Threats & Defense

### 8.1 Zombie Attraction

Settlement activity generates noise and smell. Larger, more active communities attract more zombie attention.

- Population size is the primary multiplier
- Blacksmith and Woodcutter generate significant noise
- Cooking and farming generate scent attractors
- Defenders reduce effective threat by handling wanderers before events trigger

### 8.2 Threat Events

Three tiers:

| Tier | Description | Resolution |
|------|-------------|------------|
| Probe | Small group drawn to perimeter | Defenders handle automatically |
| Incursion | Larger group | Defenders engage; may need player support |
| Horde | Serious threat | Requires player participation; may damage structures |

Predictable escalation (borrowed from 7 Days to Die): probes build toward a foreseeable horde event. The player knows it's coming and can prepare.

> ⚑ OPEN: Event frequency curve, trigger conditions, and structural damage scope TBD.

### 8.3 Loot & Cleanup

- Zombies killed near the settlement can be looted and cleaned up by settlers
- Uncleaned corpses create a health and mood debuff over time
- Looted gear from nearby kills goes into community inventory

---

## 9. Communication & Feedback

The player's primary feedback channel is the **settlement log** — a running record of tick actions, arrivals, deaths, shortages, and events. There is no roster screen, no settler management panel, and no per-settler stat view.

### 9.1 Settlement Log

- Accessible in-game via a panel (keybind or menu option TBD)
- Chronological list of entries, most recent first
- Color-coded by type: standard (white), shortage/warning (yellow), death/critical (red), milestone (green)
- Log persists across sessions as part of world ModData

### 9.2 HUD Elements

Minimal persistent HUD overlay showing:
- Food: days remaining
- Water: days remaining
- Active threat level (none / probe / incursion / horde)
- Settler count

Everything else is in the log or the Community Status panel.

### 9.3 NPCs as Information Sources

Any settler can be right-clicked for a brief status exchange. They don't deliver structured reports — that's the log's job. Right-clicking a settler might surface a one-liner related to their mood state or current activity:

> *"The crops look okay. Worried about the cold coming."*
> *"I'm fine. Just tired."*
> *"We're running low on bandages. Someone should make a run."*

This is flavor and ambient information, not a menu system. Settlers are not quest-givers.

### 9.4 Radio Check-In

- If the settlement has a Ham Radio, player can check in via walkie-talkie while out scavenging
- Returns a summary: food level, water, active threats, any flagged settlers
- Delivered by whoever is "on radio duty" at the settlement (could be any settler, not a named role)
- Critical events (attack underway, settler critically ill) trigger emergency broadcasts
- No check-in signal if out of range

---

## 10. Comparable Games & Borrowed Mechanics

### State of Decay 2 — Primary Reference

**Borrow:**
- The score breakdown UI: every active contributor listed with its value. Makes the simulation legible without an external manual.
- The negative spiral: low morale causes behavior that causes further morale loss. Collapse should feel like collapse.
- Outpost resource model: if Bastion expands to annexing nearby buildings, SoD2's outpost-as-daily-resource-provider is the right pattern.

**Avoid:**
- The roster management screen. SoD2 expects you to study your survivors. Bastion's settlers are known through the log and observation, not a UI panel.
- Per-survivor morale tracking at the player-facing level. Community-wide scores are enough.

### This War of Mine — Emotional Reference

**Borrow:**
- Named characters with trait tags make death and struggle land without mechanical complexity.
- Arrival framing as the highest-value characterization moment. One log entry does more work than a stats screen.
- The insight that you feel something because of *who* is struggling, not *how many points* they've lost.

**Avoid:**
- The per-character sympathy/archetype morale system. Brilliant but punishing when it snowballs. Community-level scores are safer.
- Morale as moral enforcement. Bastion is neutral on what the player does outside the settlement.

### 7 Days to Die — Threat Escalation

**Borrow:**
- Predictable horde escalation. The player knows it's coming and can prepare. Tension through anticipation, not randomness.

### Dwarf Fortress / RimWorld — Passive Simulation

**Borrow:**
- The "storytelling through log" pattern. You don't watch the woodcutter chop — you read that he did. The imagination fills the gap.
- Specialists producing outputs on a tick cycle without requiring player micromanagement.
- Mood/needs as emergent story rather than explicit quest.

**Avoid:**
- The complexity ceiling. Both games are infamous for depth that becomes inaccessible. Every system in Bastion should be understandable within one play session.

---

## 11. Implementation Phases

> **Current status:** Proof of concept only. Right-click context menu works, Establish/Collapse Bastion sends server commands, and a mannequin spawns at the bastion location. No game systems are implemented yet.

### Phase 1 — Foundation
- Settlement boundary (safehouse property integration)
- Settler spawning: place NPC mannequins in the settlement, persist across sessions
- Basic NPC generation (name, role, one trait tag, backstory seed)
- Community inventory: container flagging via ModData
- Settlement tick: once-per-day cycle, basic log output
- Settlement log panel (in-game UI)
- Food and water tracking with HUD display

### Phase 2 — First Specialists
- Cook: warm meal production, Happiness score
- Woodcutter: log/plank production, fuel reserve
- Farmer: crop tending, harvest, seasonal awareness
- Settler mood states (Content / Struggling / Critical)
- Arrival log entries with NPC backstory seeds
- Basic radio check-in via walkie-talkie
- Resolve score

### Phase 3 — Community Depth
- Doctor, Teacher, Tailor specialists
- Education score and library mechanic
- Balanced diet tracking and effects
- Spoilage priority toggle
- Death weight — log uses names and trait tags
- Quest-gated specialist recruitment (Doctor, Teacher)
- Settler defection when Resolve hits zero

### Phase 4 — Threat & Endgame
- Mechanic and Defender specialists
- Zombie attraction scaling by population and activity
- Threat event tiers (Probe / Incursion / Horde)
- Blacksmith specialist (Education gated, B42 smithing integration)
- Self-sufficiency milestone tracking
- Settlement expansion mechanics

---

## 12. Open Questions

| # | Question | Status | Notes |
|---|----------|--------|-------|
| 1 | Container flagging: ModData on each container vs. cached list in world ModData | Open | Recommendation: flag on container + cached list |
| 2 | Should illness spread between settlers? | Open | High drama, high complexity — defer to Phase 3 |
| 3 | Zombie attraction scaling formula | Open | Needs playtesting to calibrate |
| 4 | Quest system scope for specialist recruitment in v1 | Open | Fixed locations acceptable for v1 |
| 5 | Horde event structural damage to settlement | Open | Large scope increase if yes |
| 6 | Score threshold values and decay rates | Open | Requires balance pass after Phase 2 |
| 7 | Multiplayer: community scores and tick behavior with multiple players | Open | B42 MP implications significant; defer |
| 8 | Balanced diet tracking — per food type or per food group? | TBD | Food group simpler |
| 9 | Tick frequency: once per day vs. periodic | Open | Start with once per day |
| 10 | Trait tag pool size and content | TBD | ~25–30 tags for v1 |
| 11 | Backstory seed table content | TBD | Needs authored micro-tables |
| 12 | Right-click settler dialogue — authored lines per tag, or templated? | Open | Templated with tag substitution likely sufficient |
| 13 | Are Happiness / Resolve / Education the right subjective scores? | Open | Revisit after Phase 2 implementation |
| 14 | PZ safehouse boundary constraints (size limits, multi-building) | Open | Needs validation in Phase 1 |
| 15 | NPC representation — mannequin for all settlers, or variation? | Open | Mannequin is proven; other representations TBD |

---

*Bastion Design Document v0.3 — Working Draft*
*Maintain this file in the repo root. Update alongside implementation.*
