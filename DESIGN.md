# Bastion — Design Document
> Project Zomboid Build 42 Mod | v0.2 Draft

---

## Table of Contents
1. [Concept](#1-concept)
2. [Community Scores](#2-community-scores)
3. [Settlers & Specialists](#3-settlers--specialists)
4. [NPC Generation](#4-npc-generation)
5. [Resources & Storage](#5-resources--storage)
6. [Threats & Defense](#6-threats--defense)
7. [Communication](#7-communication)
8. [Comparable Games & Borrowed Mechanics](#8-comparable-games--borrowed-mechanics)
9. [Implementation Phases](#9-implementation-phases)
10. [Open Questions](#10-open-questions)

---

## 1. Concept

Bastion is a community-building mod for Project Zomboid. You are the scavenger — the one who goes out into the dangerous world to bring things back. The community depends on you. You depend on the community.

The mod adds something to care about. The people in your settlement have names, roles, and light personalities. When someone dies, Mae says their name. That's enough.

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
| Happiness | Reading, community culture, and children sustain morale without constant intervention |

---

## 2. Community Scores

Three scores reflect the health of the Bastion community. These are community-wide metrics, not per-settler. They influence settler behavior, production efficiency, and survivor arrival rates.

### 2.1 Happiness

Represents the emotional and psychological health of the community.

**Increases from:**
- Warm cooked food (Cook specialist active)
- Reading materials available in common areas
- Children present in the settlement
- Balanced diet (not just survival rations)
- Community milestones (first harvest, successful defense, etc.)

**Decreases from:**
- Illness or death of community members
- Cold temperatures in winter without heat source
- Food shortages or eating food near spoilage
- Zombie attacks reaching the settlement
- Prolonged absence of the player character

**Effects:**
- High: boosted production rates, easier NPC recruitment
- Low: settlers become unproductive, morale events trigger, defection risk

> ⚑ OPEN: Threshold values, morale event types, and defection mechanics TBD

### 2.2 Resolve

Represents the community's will to keep going — their belief that survival is worth it. Harder to raise than Happiness. It reflects hope, not comfort.

**Increases from:**
- Successful defense against zombie waves
- Completing community goals
- Children present (long-term hope signal)
- Teacher specialist active and educating
- Reaching self-sufficiency milestones

**Decreases from:**
- Settler deaths
- Failed defenses
- Food running critically low
- Settlement damage

**Effects:**
- Gates certain late-game expansions and specialist quests
- At zero Resolve, the settlement begins to dissolve — settlers leave

### 2.3 Education

Represents the community's accumulated knowledge and skills.

**Increases from:**
- Teacher specialist actively teaching
- Books and skill manuals in community library
- Completing research tasks (player brings back manuals)

**Effects:**
- Unlocks advanced crafting recipes for settlers
- Faster skill acquisition for new settlers
- Unlocks certain specialist roles (Blacksmith requires Education threshold)
- Reduces resource waste in crafting and farming

### 2.4 Score UI

Inspired by State of Decay 2's morale breakdown screen: the Community Status panel should show every active positive and negative contributor with its value. Example:

```
COMMUNITY STATUS
----------------
Happiness: 64  [+]
  + Warm meals active          +8
  + Reading materials          +4
  - Water shortage             -5
  - Recent settler death       -12

Resolve: 41  [~]
  + Successful defense (3d ago) +6
  - Marcus died                -18

Education: 28  [+]
  + Teacher active              +3
  + 4 skill books in library    +4
```

This removes guesswork and teaches the system while the player plays it. No external manual needed.

---

## 3. Settlers & Specialists

Settlers are the community. They start as generic survivors and can be assigned to specialist roles as the settlement grows. Specialists produce passive benefits and require resources to function.

**Design principle:** Settlers exist in the world and in Mae's dialogue. The player learns who they are through reports and observation — not through a roster screen they open and study. There is no settler management UI.

### 3.1 Specialist Roles

#### Farmer
- Manages crops through seasonal cycles
- Handles pesticide/spraying to protect harvests
- Tracks harvest status — player can see current crop states via Mae check-in
- Seasonal awareness: crops fail in winter without greenhouse setup
- Requires: seeds, fertilizer, tools, water access

> Seasons tie into PZ's existing system. Farmer behavior changes with temperature.

#### Cook
- Ensures warm cooked meals are always prepared from community food stores
- Provides Happiness bonus to all settlers
- Converts raw ingredients into preserved food (jars, smoked meat) to extend shelf life
- Balanced diet mode: Cook attempts varied meals if ingredients allow
- Requires: fuel/wood, cooking tools, food stocks

#### Doctor
- Reduces infection chance for wounded settlers
- Increases healing rate across the community
- Monitors for illness spreading through the settlement
- Crafts bandages, poultices, and basic medical supplies
- Requires: medical supplies, reference books, clean water

> ⚑ OPEN: Should illness be able to spread between settlers? Creates dramatic tension but significant complexity.

#### Blacksmith
- Crafts and repairs melee weapons and tools
- Requires ongoing supply of raw materials (metal scrap, coal/charcoal)
- Unlocks advanced weapon and tool recipes at higher Education levels
- Requires: forge/anvil setup, fuel, raw metal
- Gated: requires Education threshold to unlock. Ties into B42 blacksmithing mechanics.

#### Woodcutter
- Provides fuel for heating during winter, reducing cold penalties
- Supplies lumber for construction and repairs
- Happiness contribution from warmth in winter
- Requires: axes, forest access (proximity), storage space

#### Teacher
- Actively raises Education score over time
- Boosts Resolve when children are in the settlement
- Requires: books, designated space
- Slow effect — long-term investment, not a quick fix

#### Defender
- Handles zombie threat reduction around the settlement perimeter
- Reduces frequency of zombie incursion events
- Settlement size and noise attract more zombies — Defenders counteract this
- Requires: weapons, ammunition or melee equipment

> ⚑ OPEN: Zombie attraction scaling formula by population size TBD. Needs playtesting to calibrate.

#### Tailor
- Collects and processes thread and fabric from clothing
- Repairs settler clothing to maintain warmth and protection
- May craft basic protective gear for Defenders
- Requires: thread, needles, fabric sources

### 3.2 Settler Arrivals

New survivors arrive over time. Arrival rate is influenced by Happiness, Resolve, and settlement visibility. Some specialists can only be recruited through quests.

**Quest-gated specialists:**
- Certain roles — Doctor, Teacher, Blacksmith — require a specific quest to recruit
- Player receives a lead (radio intercept, note, survivor tip) pointing to a location
- Target survivor must be found and escorted back safely
- Failed escort attempt delays the quest

> ⚑ OPEN: Quest generation scope TBD. v1 may use fixed quest locations.

---

## 4. NPC Generation

Bastion uses PZ's existing RNG table patterns for all settler generation. No hand-authored characters. This fits the game's DNA and keeps scope manageable.

### 4.1 Generation Layers

**Name**
Pull directly from PZ's existing regional name tables by gender. No separate list to maintain.

**Role**
Assigned at join time. Priority: fill an open community need first. If no gap exists, assign randomly or leave as generic settler until the player assigns them.

**Trait Tags**
1–2 tags pulled at spawn from a curated pool of ~25–30. These are narrative flags, not stat modifiers. They surface occasionally in Mae's dialogue and check-in reports.

Example tags:
- `Optimist` — check-in lines skew hopeful even when things are rough
- `Nervous` — first name Mae mentions when there's a threat
- `Practical` — never complains about food variety
- `Bad Dreams` — mentioned during difficult stretches
- `Keeps to Herself` — rarely surfaces in group reports
- `Tells Bad Jokes` — surfaces in high-Happiness moments
- `Believes in Something` — boosts Resolve subtly when present
- `Gets Quiet When It Rains` — flavor only
- `Former Teacher` — hints at specialist potential
- `Light Sleeper` — surfaces during threat events

The player's imagination fills in the rest. The tags exist to give Mae something specific to say.

**Backstory Seed**
One line, generated from 2–3 small tables:
`[former occupation] from [PZ location name] who [circumstance]`

Examples:
- *Carpenter from Louisville who lost his kids*
- *Nurse from Muldraugh who doesn't talk about before*
- *Mechanic from the highway who walked for three weeks*

Shows up once: in Mae's arrival report. Implied after that.

**Mood State**
Three states only. Functional, not generated.

| State | Effect |
|-------|--------|
| `Content` | Normal production, no events |
| `Struggling` | Reduced effectiveness, Mae flags them |
| `Critical` | Non-functional, requires player attention or they leave |

Mood is influenced by community scores, personal events (witnessing death, going hungry), and trait tags. It is not a stat the player manages directly — it surfaces through Mae.

### 4.2 Death Weight

Named settlers with trait tags make death land without requiring cutscenes or special mechanics. When a settler dies, Mae uses their name and references their tag if appropriate:

> *"Marcus didn't make it. He was the one who always had something to say at the wrong moment. We're going to feel that."*

No death screen. No popup. Just Mae, and then silence.

---

## 5. Resources & Storage

### 5.1 Community Inventory

The community maintains its own inventory separate from the player's personal inventory. Items designated as community property are consumed by specialists performing their jobs.

**Container flagging:**
- Containers inside the settlement boundary can be flagged as "Bastion Owned"
- Flagged containers are treated as community inventory — specialists draw from them
- Player can still access these containers; UI indicates community ownership
- Items placed in flagged containers enter the simulation

> ⚑ OPEN: Flag containers via ModData, or use a single virtual inventory? Virtual inventory is simpler but less visible. Container flagging feels more natural and more PZ-like. Recommendation: container flagging, consistent with how PZ handles safehouses.

### 5.2 Food Management

**Spoilage priority:**
- Settings toggle: "Eat nearly-stale food first"
- Reduces waste when food stocks are rotating
- Cook balances spoilage priority against dietary variety when both modes are active

**Food projection:**
- HUD displays: estimated days of food remaining at current consumption rate
- Player-facing framing: *"You have 8 days before shortages begin"*
- Projection adjusts based on community size and Cook's efficiency
- This is a primary HUD metric alongside water level

**Diet effects:**
- Balanced diet: Happiness bonus, small production efficiency boost
- Monotonous diet: small ongoing Happiness penalty
- Shortage: rapid Happiness and Resolve decay, settler defection risk

### 5.3 Water

- Rain barrels serve as primary water collection; capacity is finite
- Community water consumption is tracked — settlers drink, cooking uses water
- Water shortage is a crisis event: Cook stops producing warm meals, Doctor loses effectiveness
- Long-term solutions: wells, water purification, larger storage
- Water level visible on main HUD alongside food projection

---

## 6. Threats & Defense

### 6.1 Zombie Attraction

Settlement activity generates noise and smell. Larger, more active communities attract more zombie attention.

- Population size is the primary multiplier on attraction rate
- Blacksmith and Woodcutter generate significant noise
- Cooking and farming generate scent attractors
- Defenders reduce effective threat by handling wanderers before events trigger

### 6.2 Threat Events

Three tiers:

| Tier | Description | Resolution |
|------|-------------|------------|
| Probe | Small group drawn to perimeter | Defenders handle automatically |
| Incursion | Larger group | Defenders engage; may need player support |
| Horde | Serious threat | Requires player participation; may damage structures |

Predictable escalation pattern (borrowed from 7 Days to Die): smaller probes build toward a foreseeable horde event. The player knows it's coming and can prepare. Tension without pure randomness.

> ⚑ OPEN: Event frequency curve, trigger conditions, and structural damage scope TBD.

### 6.3 Loot & Cleanup

- Zombies killed near the settlement can be looted and cleaned up
- Cleanup is a settler task — uncleaned corpses create a health/mood debuff over time
- Looted gear from nearby kills goes into community inventory

---

## 7. Communication

### 7.1 Radio Check-In

- If the settlement has a Ham Radio, player can check in via walkie-talkie while out scavenging
- Check-in returns a status report: food level, water, current threats, settler morale, any flagged individuals
- Mae delivers the report in character
- Critical events (attack underway, settler critically ill) trigger emergency broadcasts
- No check-in if out of range — creates genuine tension when you're far out

### 7.2 Mae

Mae is the settlement's narrative interface. She is the voice of the community, not a special character. The pattern she established (mannequin, nurse outfit, right-click menu) is a technical proof of concept — the actual settlers are the point.

Mae's functions:
- Delivers status updates, quest hooks, and flavor dialogue
- Arrival reports for new settlers (name, backstory seed, first impression)
- Death announcements using settler names and trait tags
- Emergency radio broadcasts during threat events
- Right-click menu: **Check In** | **What Do We Need** | **Tell Me Something**

Mae does not have a personality arc. She is a window into the community.

---

## 8. Comparable Games & Borrowed Mechanics

### State of Decay 2 — Primary Reference

**Borrow:**
- The morale breakdown UI: every active contributor listed with its value (see Section 2.4). Makes the simulation legible without an external manual.
- The negative spiral: low morale causes behavior (fighting, stealing, leaving) that causes further morale loss. Collapse should feel like collapse.
- Outpost resource model: if Bastion ever expands to annexing nearby buildings, SoD2's outpost-as-daily-resource-provider is the right pattern.

**Avoid:**
- The roster management screen. SoD2 expects you to study your survivors. Bastion's settlers are known through Mae and observation, not a UI panel.
- Per-survivor morale tracking at the player-facing level. Three community scores is enough.

### This War of Mine — Emotional Reference

**Borrow:**
- Named characters with trait tags make death and struggle land without mechanical complexity. The player fills in the narrative gaps.
- Arrival framing as the highest-value characterization moment. One line from Mae does more work than a stats screen.
- The insight that you feel something because of *who* is struggling, not *how many points* they've lost.

**Avoid:**
- The per-character sympathy/archetype morale system. Brilliant but widely cited as punishing when it snowballs. Bastion's community-level scores are a safer and more appropriate scale for a PZ mod.
- Morale as moral enforcement. TWoM punishes ethically questionable decisions. Bastion is neutral on player behavior outside the settlement — what you do out there is your business.

### 7 Days to Die — Threat Escalation

**Borrow:**
- Predictable horde escalation. Probes → incursions → horde event on a readable cycle. The player can prepare because they know it's coming. Tension through anticipation, not randomness.

---

## 9. Implementation Phases

### Phase 1 — Foundation *(In Progress)*
- Settlement claiming via safehouse mechanic
- Mae NPC (mannequin, nurse outfit, basic dialogue menu)
- World ModData persistence across deaths
- Basic community inventory (flagged containers)
- Food projection display

### Phase 2 — First Settlers
- NPC generation system (name tables, role assignment, trait tags, backstory seed)
- Settler arrival events with Mae introduction reports
- Happiness and Resolve score tracking with breakdown UI
- Cook specialist with warm meal production
- Farmer specialist with seasonal crop management
- Water consumption and shortage events
- Basic radio check-in via walkie-talkie
- Three mood states surfaced through Mae dialogue

### Phase 3 — Community Depth
- Doctor, Teacher, Woodcutter, Tailor specialists
- Education score and library mechanic
- Quest-gated specialist recruitment
- Balanced diet tracking and effects
- Spoilage priority setting
- Death weight — Mae uses names and trait tags

### Phase 4 — Threat & Endgame
- Zombie attraction scaling by settlement size
- Defender specialist and threat event tiers
- Blacksmith specialist (Education gated)
- Self-sufficiency milestone tracking
- Horde events and settlement defense

---

## 10. Open Questions

| # | Question | Status | Notes |
|---|----------|--------|-------|
| 1 | Container flagging vs. virtual inventory | Open | Flagging recommended — more PZ-like |
| 2 | Should illness spread between settlers? | Open | High drama, high complexity |
| 3 | Zombie attraction scaling formula | Open | Needs playtesting to calibrate |
| 4 | Quest system scope for specialist recruitment in v1 | Open | Fixed locations acceptable for v1 |
| 5 | Horde event structural damage to settlement | Open | Large scope increase if yes |
| 6 | Score threshold values and decay rates | Open | Requires balance pass |
| 7 | Multiplayer: community scores and Mae interaction with multiple players | Open | B42 MP implications significant |
| 8 | Balanced diet tracking — per food type or per food group? | TBD | Food group simpler |
| 9 | Settlement boundary — radius, building list, or zone? | Open | Affects container flagging implementation |
| 10 | Trait tag pool size and content | TBD | ~25–30 tags recommended for v1 |
| 11 | Backstory seed table content | TBD | Needs authored micro-tables |

---

*Bastion Design Document v0.2 — Working Draft*
*Maintain this file in the repo root. Update via Claude Code or by pasting into Claude.ai chat for revision.*
