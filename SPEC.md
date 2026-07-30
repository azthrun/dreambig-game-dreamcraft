# Dreamcraft — Specification

> Status: agreed, not yet implemented. Repository is empty at time of writing.
> This document is the single source of truth for round one. Amend it when decisions change.

## Problem Statement

I want to build a first-person open-world survival game in Godot, set on a sandbox island with a
living climate, wild animals to hunt, and found gadgets that power up my character.

What I don't have is a design that survives contact with reality. My initial framing was
"Minecraft-like," but the features I actually care about — hunting predators, day/night, weather,
guns, a flying suit — are not Minecraft's features, and pursuing both at once would mean spending
the entire first round building a voxel engine and never reaching the game I described. I also have
no 3D art of any kind and no modelling tool, so any plan that depends on animated creature models
is dead on arrival.

I need a specification that is honest about scope, resolves the contradictions in my own feature
list, and can be built incrementally on the machine I actually own — an 8 GB M2 MacBook Pro.

## Solution

**Dreamcraft** is a first-person survival game on a finite procedurally generated island, rendered
in a deliberately blocky style. The player washes up on a shore, harvests wood and stone, crafts
fire and hide armour, hunts prey to eat, learns to fight predators, and eventually finds firearms
and a flying suit that make a mountain-nesting dragon killable.

The design resolves the original contradictions as follows:

- **Not a voxel game.** Blocky *aesthetic* via a heightmap quantized to 1m steps. No block breaking
  or placing. This removes chunk meshing entirely and frees round one for actual gameplay.
- **Creatures are cuboids.** Built from box meshes with pivot-rotated limbs, exactly as Minecraft
  builds its animals. No external art, no rigging, no licensing questions, and stylistically
  consistent with the terrain.
- **Finite island, not infinite terrain.** Ocean is the world border, which is free level design and
  removes streaming, LOD, and chunk residency bookkeeping.
- **Shelter without building.** Cold is countered by campfires, hide armour, and natural cover
  props — not by placing structures.
- **Materials without mining.** Harvestable props (trees, rock outcrops, berry bushes) replace the
  block-breaking loop as the resource source.
- **Prey as well as predators.** The original bestiary was four apex predators, which left no early
  game and no food. Deer and boar provide an opening and a difficulty curve.
- **Gadgets are scarce, not a power fantasy.** Ammo and fuel are found and cannot be crafted, so
  firearms stay emergency tools and melee hunting remains the core loop.

Delivery is six independently playable milestones, each committed separately, so course correction
happens early rather than after twenty entangled systems exist.

## Glossary

Vocabulary used consistently throughout this document and expected in code.

| Term | Meaning |
|---|---|
| **Island** | The entire finite world: 2 km × 2 km, seeded, ocean-bordered |
| **Heightmap** | Per-cell terrain height array, quantized to whole metres |
| **Biome** | Terrain classification of a cell: ocean, beach, plains, forest, mountains, river |
| **Tile** | One static terrain mesh + baked collision unit; the Island is a grid of Tiles |
| **Prop** | A placed object on the terrain: tree, rock outcrop, berry bush, overhang, cave mouth, cache |
| **Shelter volume** | An `Area3D` on a Prop marking its interior as sheltered from weather |
| **Creature** | Any animal. Subdivided into **Prey** (deer, boar) and **Predator** (leopard, tiger, lion, dragon) |
| **Climate** | The combined day/night cycle, weather state, and temperature model |
| **Weather state** | One of: clear, cloudy, overcast, rain, thunderstorm, fog |
| **Snowline** | Altitude above which rain manifests as snow |
| **Gadget** | Pistol, machine gun, or flying suit |
| **Cache** | A supply container Prop holding a Gadget, ammo, or fuel |
| **Simulation layer** | Pure `RefCounted` classes holding game logic, with no `Node`/`SceneTree` dependency |
| **Presentation layer** | `Node`-based scenes, shaders, particles, and UI that read from the Simulation layer |

## User Stories

### Traversal and world (M1)

1. As a player, I want to move with WASD and look with the mouse, so that first-person control feels immediate and familiar.
2. As a player, I want to sprint and have it cost stamina, so that movement involves a resource decision.
3. As a player, I want to jump, so that I can clear small obstacles.
4. As a player, I want to crouch, so that I can move quietly when stalking prey.
5. As a player, I want to automatically step up 1m ledges without jumping, so that the terraced terrain does not make walking tedious.
6. As a player, I want to be refused when walking up a near-vertical cliff, so that steep terrain reads as a genuine obstacle.
7. As a player, I want to enter water and swim, so that rivers and coastline are traversable rather than lethal walls.
8. As a player, I want the ocean to deepen as I swim out, so that the world border feels natural and I turn back without hitting an invisible wall.
9. As a player, I want to see a varied island with beaches, plains, forest, mountains, and rivers, so that exploration is rewarded with visual change.
10. As a player, I want rivers that run from high ground to the sea, so that the landscape reads as coherent rather than as random noise.
11. As a player, I want trees, rocks, and bushes scattered according to biome, so that each region feels distinct.
12. As a player, I want the far distance to fade into atmospheric haze, so that the edge of what is rendered does not read as a missing world.
13. As a player, I want the island to regenerate identically from the same seed, so that I can return to a world I liked.
14. As a developer, I want the world generated once at startup rather than streamed, so that there are no load hitches while playing.

### Climate (M2)

15. As a player, I want the sun to rise, cross the sky, and set over roughly twenty minutes, so that a play session contains several full days.
16. As a player, I want shadows to swing and lengthen as the sun moves, so that time of day is legible without looking at a clock.
17. As a player, I want dawn and dusk to show warm atmospheric colour, so that sunrise and sunset are worth stopping to watch.
18. As a player, I want night to be genuinely dark and shorter than day, so that it registers as a threatening event rather than half my playtime.
19. As a player, I want a moon and stars at night, so that the night sky is not an empty void.
20. As a player, I want weather to change on its own as I play, so that the world feels alive without my input.
21. As a player, I want rain I can see and hear, so that weather is felt rather than merely reported.
22. As a player, I want thunderstorms with lightning, so that the worst weather is dramatic.
23. As a player, I want fog to reduce how far I can see, so that weather changes how I play rather than only how things look.
24. As a player, I want fog to pool in valleys and river basins, so that weather interacts with the landscape.
25. As a player, I want rain to fall as snow on high peaks, so that altitude visibly matters.
26. As a player, I want stronger wind on the coast, so that regions feel climatically distinct.
27. As a developer, I want a debug key to accelerate time, so that I can test midnight storms without waiting for them.
28. As a developer, I want day length exposed as a tunable value, so that pacing can be adjusted without touching code.

### Survival (M3)

29. As a player, I want a health pool that can be depleted, so that danger has consequences.
30. As a player, I want to die and respawn on the shore, so that failure costs me progress without ending the game.
31. As a player, I want hunger that rises over time, so that I have a standing reason to hunt.
32. As a player, I want to take damage when starving, so that ignoring hunger is a real failure state.
33. As a player, I want stamina that depletes when I sprint and regenerates when I rest, so that chases and escapes have tension.
34. As a player, I want to feel cold at night, at altitude, and in bad weather, so that the climate system affects my survival rather than only my screen.
35. As a player, I want to take damage from prolonged cold, so that temperature is a threat I must answer.
36. As a player, I want to warm up beside a lit campfire, so that fire is worth the wood it costs.
37. As a player, I want hide armour to reduce cold, so that hunting directly improves my survivability.
38. As a player, I want to shelter under overhangs, in cave mouths, and beneath dense forest canopy, so that the landscape offers protection.
39. As a player, I want to harvest wood from trees, so that I can make fire.
40. As a player, I want to harvest stone from rock outcrops, so that I can make tools.
41. As a player, I want to gather berries from bushes, so that I have weak food before my first kill and do not starve immediately.
42. As a player, I want harvested props to deplete and regrow over time, so that the world is not stripped permanently and resources have locality.
43. As a player, I want an inventory I can open and inspect, so that I know what I am carrying.
44. As a player, I want to craft items from a recipe list, so that gathering has a purpose.
45. As a player, I want to place a campfire, so that I can establish a warm point I choose.
46. As a player, I want to cook raw meat on a campfire, so that hunting yields better food than eating it raw.
47. As a player, I want raw meat to be worse for me than cooked, so that cooking is worth doing.
48. As a player, I want a HUD showing health, hunger, stamina, and temperature, so that I can read my state at a glance.
49. As a player, I want a hotbar with scroll-wheel selection, so that switching what I am holding is fast.

### The hunt (M4)

50. As a player, I want to see deer grazing in the plains and forest, so that the world feels inhabited.
51. As a player, I want deer to flee when they notice me, so that hunting requires approach and patience.
52. As a player, I want crouching to reduce how easily animals notice me, so that stealth is a real tactic.
53. As a player, I want boar to retaliate when cornered, so that I learn danger on something survivable.
54. As a player, I want leopards, tigers, and lions to detect, stalk, and attack me, so that the island is genuinely dangerous.
55. As a player, I want predators to be beatable in ascending order of difficulty, so that there is a curve rather than a wall.
56. As a player, I want wounded predators to break off and retreat, so that fights have a rhythm and are not purely attrition.
57. As a player, I want to watch predators hunt prey without me, so that the ecosystem feels like it exists independently.
58. As a player, I want animals to leave meat and hide when killed, so that hunting feeds the survival loop.
59. As a player, I want larger animals to yield more, so that risk is proportionate to reward.
60. As a player, I want animals to move plausibly over hills and around trees, so that they read as creatures rather than sliding props.
61. As a player, I want each species to be visually distinguishable at a glance, so that I can assess threat before I am close enough to be in danger.
62. As a player, I want animals to be denser in the biomes that suit them, so that where I go determines what I meet.

### Gadgets and the dragon (M5)

63. As a player, I want to find supply caches while exploring, so that exploration has a reward beyond scenery.
64. As a player, I want to find a pistol, so that I have a ranged option against predators.
65. As a player, I want to find a machine gun, so that I have an answer to the most dangerous threats.
66. As a player, I want ammunition to be scarce and unmakeable, so that firearms stay precious and melee hunting remains the core of the game.
67. As a player, I want to see my equipped weapon on screen, so that I know what I am holding.
68. As a player, I want recoil and muzzle feedback when firing, so that shooting feels physical.
69. As a player, I want to find a flying suit, so that I can see the island from above.
70. As a player, I want flight to consume limited found fuel, so that flying is a thrill rather than a permanent bypass of the terrain.
71. As a player, I want a dragon nesting in the northern mountains, so that the island has a clear endgame destination.
72. As a player, I want the dragon to patrol, circle, and dive at me, so that fighting a flying enemy plays differently from fighting a cat.
73. As a player, I want the dragon to breathe fire in a cone, so that its threat is ranged and positional.
74. As a player, I want the dragon to require firearms to kill realistically, so that finding the machine gun is a meaningful escalation.
75. As a player, I want the dragon to drop the best materials in the game, so that the hardest fight is the most rewarding.
76. As a player, I want to fight the dragon while flying, so that the flying suit and the endgame reinforce each other.

### Persistence and shell (M6)

77. As a player, I want my progress saved, so that a twenty-minute day does not force marathon sessions.
78. As a player, I want my position, health, hunger, stamina, and temperature restored on load, so that I resume where I left off.
79. As a player, I want my inventory and equipped gear restored, so that my accumulated progress survives quitting.
80. As a player, I want my placed campfires still standing on load, so that the base I established persists.
81. As a player, I want trees I stripped to still be depleted on load, so that the world remembers my activity.
82. As a player, I want caches I already looted to stay looted, so that saving and loading cannot be used to farm ammo.
83. As a player, I want time of day and weather restored, so that loading does not reset the climate.
84. As a player, I want a main menu with new game, continue, and quit, so that the game has a front door.
85. As a player, I want to pause, so that I can stop without dying.

### Developer-facing

86. As a developer, I want game logic in pure classes free of `Node` dependencies, so that I can test it headlessly without booting a scene.
87. As a developer, I want to assert on real generated values — height ranges, biome distribution, temperature results, damage numbers, AI transitions — so that correctness is verified rather than assumed.
88. As a developer, I want tuning values exposed as data rather than buried in code, so that balance changes do not require edits to logic.
89. As a developer, I want each milestone independently playable and separately committed, so that feedback arrives before systems entangle.
90. As a developer, I want a documented performance budget, so that I can tell when a change has broken it.

## Implementation Decisions

### Engine and platform

- **Godot 4.6.1 stable (Mono build)**, located at `/Applications/Godot_mono.app`.
- **Forward+ renderer** on the Metal backend. This is a deliberate divergence from the sibling
  `dreambig-game-alpha` project, which uses `gl_compatibility`. Forward+ is required because GL
  Compatibility supports neither volumetric fog nor the full physical sky, without which the
  climate system degrades to a background colour swap and a particle emitter.
- **Jolt Physics**, matching the sibling project.
- **Jolt / Forward+ fallback:** if volumetric fog proves unaffordable within the memory budget, the
  documented retreat is the Mobile renderer, accepting flatter weather. Decision point is M2.
- **Language: GDScript throughout.** This follows the convention already documented in
  `dreambig-game-alpha/AGENT.md` — C# only where a subsystem is demonstrably a bottleneck under
  profiling, never pre-emptively. Terrain generation, the most plausible hotspot, stays GDScript
  because `FastNoiseLite` is already native C++; only the vertex assembly loop is interpreted. If
  chunk generation measurably stutters, the remedy is `WorkerThreadPool`, not a language change.
- **Single-player only.** No networking, no authority model, no replication. Systems mutate state
  directly. World generation is nonetheless deterministic from an integer seed, because that is good
  practice independently and costs nothing.
- **Input: keyboard and mouse only.** All bindings are declared as named input-map actions
  (`move_forward`, `fire`, `interact`, …) rather than raw key reads, so gamepad support is later a
  configuration addition rather than a rewrite. No stick curves or controller UI navigation in
  round one.

### Performance budget

Binding constraint is the target machine: MacBook Pro M2, 8 cores, **8 GB unified memory**,
2560×1600 Retina panel.

- Window **1600×900** at full 3D render scale. Resolution remains a project setting.
- Hard target **60 FPS**. A 30 FPS target is rejected: mouselook and flight both feel bad at 30.
- **View distance ~500 m**, with distance fog blending to the sky. The weather system already owes
  us fog, so the far plane is hidden by a feature rather than by a cheat.
- Props (trees, rocks, bushes) culled aggressively past **~150 m**.
- SDFGI disabled. Shadow atlas kept modest.

### World generation

- **Finite island, 2 km × 2 km.** Generated once at startup from a seed. No chunk streaming, no
  LOD, no residency bookkeeping — all removed by the finite-world decision.
- **Ocean is the border.** No invisible walls and no edge-of-map messaging. The seabed slopes away
  so that swimming out is self-discouraging.
- **Heightmap quantized to whole metres.** Produces the terraced silhouette that matches the
  cuboid creatures and the game's name. Flat-shaded.
- **Coarser 2 m quantization is rejected**: ledges taller than the player turn cliffs into walls and
  make quadruped locomotion substantially harder.
- The heightmap is authoritative and **retained in memory after generation**, not discarded to the
  GPU. This is load-bearing: creature ground queries and shelter tests read it directly as an O(1)
  array lookup.
- Terrain is emitted as a grid of **static mesh Tiles with baked collision**.
- **Biomes**: ocean, beach, plains, forest, mountains, river. Classified per cell from altitude,
  distance to water, and noise. Biome placement is deliberate at the macro scale — mountains north,
  plains central — rather than uniformly random, so the island has geography rather than texture.
- **Rivers** are carved from high ground to the coast, so drainage reads as coherent.

### Props, cover, and shelter

- **Caves and overhangs are not terrain.** A heightmap stores exactly one height per X/Z coordinate,
  so overhangs are geometrically impossible in it. Cover is therefore provided by Props placed on
  the terrain surface: hand-built overhang meshes, prefab cave-mouth scenes opening into small
  interior rooms, and dense tree clusters.
- **"Sheltered" is an `Area3D` volume** attached to each cover Prop. Testing whether the player is
  sheltered is an area-overlap check, not a geometry query.
- **Harvestable Props** are the material source, replacing mining: tree → wood, rock outcrop →
  stone, berry bush → berries. Berries exist specifically so the opening minutes are survivable
  before the first kill.
- Harvesting is a **hold-to-interact** action at close range. Props **deplete and respawn on a
  timer**, so resources have locality and the island cannot be permanently stripped.
- Prop placement is derived from the seed, so it is reproducible and never saved.

### Climate

- **Day/night: 20-minute full cycle**, approximately 14 minutes day and 6 minutes night. Night is
  deliberately the shorter half so it reads as an event. Cycle length is a tunable value, and a
  debug time-scale key exists for testing.
- **Weather: one global state machine.** States are clear, cloudy, overcast, rain, thunderstorm,
  fog, with weighted random transitions on a timer. There is a single authority that every other
  system reads.
- **Local modulation, not local weather.** Biome and altitude modulate how the global state
  manifests: rain becomes snow above the snowline, coastal wind is stronger, fog settles in valleys
  and river basins. Each modulation is a small pure function.
- A regional pressure-field weather model was considered and rejected for round one: it is the most
  impressive version of the feature but requires position-sampled queries, blended visuals, and a
  temperature model that is much harder to test deterministically.
- **Temperature** is a pure function of biome, altitude, time of day, weather state, sheltered
  state, and proximity to a lit campfire. It is the single point where climate becomes mechanical.

### Survival systems

- Health, hunger, and stamina are plain scalar pools advanced by delta time.
- Prolonged cold and sustained starvation both apply damage. Death respawns the player at the shore.
- **Cold is answered by campfire, hide armour, and natural cover — never by building.** A
  placeable-structure system was explicitly rejected: it would reintroduce the building subsystem
  cut in the voxel decision, plus an enclosure-detection algorithm.
- **Crafting is recipe-driven from data**, not hard-coded. Round one recipe tiers are deliberately
  shallow: fire, basic tools, hide armour, cooked food.
- A workbench and a **craftable-ammunition** chain were considered and rejected. Ammo cannot be
  crafted, which is what keeps firearms scarce.
- Campfires are **placeable Props** that both cook and provide warmth — one object serving two
  systems.

### Creatures

- **Six species, all procedural cuboids.** Each is assembled from box meshes in a scene, animated by
  rotating limb, head, and wing pivots via `AnimationPlayer`. No rigging, no skinning, no imported
  models. This is Minecraft's own approach and is stylistically correct here rather than a
  compromise. Species read through proportion and colour: lion tan with a mane block, tiger orange
  and striped, leopard spotted, dragon far larger with animated wings.
- Downloading CC0 model packs was considered and rejected: it introduces an external dependency,
  cannot be guaranteed to contain this specific species roster, needs rig retargeting, and would
  visually clash with cuboid terrain.
- **Two behaviour trees, not six.** `Prey` (graze, wander, flee, optionally retaliate) covers deer
  and boar. `Predator` (patrol, stalk, charge, attack, retreat when wounded) covers the cats. The
  dragon **extends** `Predator` with flight rather than forming a third tree.
- **Prey exist because the original bestiary was all apex predators**, which left the player
  spawning next to a lion with a knife and no food source. Deer and boar supply the early game, the
  learning curve, and something for predators to visibly hunt.
- Predators hunt prey independently of the player, so the ecosystem reads as self-sustaining.
- **Locomotion is steering, not navmesh.** `NavigationRegion3D` is rejected: baking 2 km² of
  1 m-stepped terrain is slow and memory-hungry against an 8 GB budget, and it is heavy machinery
  for the problem of crossing open grassland. Instead: steering toward a desired direction, ground
  height from the retained heightmap as an O(1) lookup, a max-slope test to refuse cliffs, a
  shapecast for tree and rock avoidance, and a stuck-timer that re-rolls direction. This works
  precisely because the world is open terrain rather than corridors, and because we own the
  heightmap.
- Creature spawn density is biome-weighted.

### Gadgets

- Gadgets and their consumables come from **Caches** scattered across the island, respawning slowly.
- **Ammunition and fuel are found and cannot be crafted.** This is the central balancing decision:
  a machine gun with unlimited ammo would make hunger, warmth, hide armour, and stalking all
  irrelevant the moment it was found. Pistol ammo is uncommon; machine-gun ammo is rare.
- The **flying suit runs on found fuel** sufficient for short flights, not free travel. Unlimited
  flight would discard the terrain, biome, and river work by removing every obstacle.
- Weapons are drawn as a **first-person viewmodel**. There is no player body: the first-person
  decision removes the player model, the animation state machine, camera collision, and foot-slide
  correction entirely.
- **The dragon is sequenced with the gadgets, not with the other creatures.** It is the most
  expensive creature by a wide margin — 3D flight AI, a wing animation set nothing else uses, a
  cone fire-breath attack nothing else uses, a large health pool — and it is the one enemy that
  genuinely requires firearms and flight to be a real fight rather than either unbeatable or nerfed
  into a flying cow.

### Persistence

- A single `SaveManager` writes **JSON**, chosen for human readability and debuggability.
- **Saved:** world seed, time of day, weather state, player position, health, hunger, stamina,
  temperature, inventory, equipped gear, placed campfires, prop depletion timers, looted cache IDs.
- **Not saved:** terrain, biomes, and prop placement, all of which are reproduced from the seed.
- **Creatures are not saved.** They respawn as a fresh seeded population. Restoring exact positions
  and AI states is possible but meaningless to a player, since animals wander continuously.
- Looted cache IDs are saved specifically so that save-scumming cannot farm ammunition.

### Architecture: simulation / presentation split

The load-bearing structural decision, and the one that makes the testing strategy possible.

- **Simulation layer**: pure `RefCounted` classes with no `Node` or `SceneTree` dependency —
  world generation, climate, temperature, survival stats, inventory, crafting, combat resolution,
  creature decision-making, save serialization. These take plain data and return plain data.
- **Presentation layer**: `Node`-based scenes, shaders, particle systems, and UI, which read from
  the simulation layer and render it. Presentation holds no authoritative game state.
- Consequence: nearly all game logic is testable headlessly without booting a scene, and balance
  can be reasoned about as functions rather than as node interactions.

### Repository conventions

- `project.godot` at repository root.
- `.gitignore` adapted from `dreambig-game-alpha` (`.godot/`, `.import/`, export configs, `bin/`,
  `obj/`, IDE directories).
- The three Godot agent skills from `dreambig-game-alpha/.agents/skills/` —
  `godot-best-practices`, `godot-gdscript-patterns`, `godot-ui` — are copied in along with
  `skills-lock.json`, and their guidance (state machines, object pooling, input handling,
  save/load patterns, typed GDScript, node communication) is followed.
- The `godot_mcp` addon ("Godot MCP Pro" v1.6.5) is copied in but **disabled by default**. It is
  available if a tighter visual verification loop is wanted later; nothing depends on it.
- An `AGENTS.md` at the root records the load-bearing conventions for future sessions and points at
  this spec as the source of truth. Note the sibling project uses the singular `AGENT.md`; this repo
  uses the plural cross-tool convention.
- Agent-skill configuration lives in `docs/agents/` — issue tracker, triage labels, and domain doc
  layout. Issues are tracked in GitHub Issues for this repo.
- Work proceeds on `main`, which currently has zero commits. One commit per milestone.

### Milestone sequencing

Six independently playable milestones, each separately committed. Sequenced so that each corrects
the next; a single undifferentiated push is explicitly rejected because it would defer all feedback
until every misunderstanding had compounded across all systems.

| # | Name | Contents |
|---|---|---|
| **M1** | Walk the world | Project config, seeded island heightmap + biomes, ocean + swimming, prop scattering, first-person controller, fog horizon |
| **M2** | Sky and storms | Day/night cycle, physical sky, weather state machine, volumetric fog, precipitation, local modulation, debug time scale |
| **M3** | Bleed and eat | Health/death/respawn, hunger, stamina, temperature, shelter detection, inventory, harvesting, crafting, campfire + cooking, hide armour, HUD |
| **M4** | The hunt | Five ground creatures, Prey and Predator trees, steering locomotion, combat, drops, predator-on-prey behaviour |
| **M5** | Gear up | Caches, pistol, machine gun, flying suit, **and the dragon** as apex encounter |
| **M6** | Persist | JSON save/load, main menu, pause, settings |

Survival precedes gadgets deliberately: shooting is tuned against creatures that exist, and the
difficulty ramp is meaningful. The dragon is the sole exception, deferred to M5 for the reasons
given above.

## Testing Decisions

### What makes a good test here

A good test asserts on **externally observable behaviour and real values**, never on how a system is
structured internally. It should survive a refactor of the thing it tests. Concretely:

- Assert that generated terrain heights fall in a plausible range, that all six biomes appear, and
  that the island is ocean-bordered on every edge — **not** which noise functions were called.
- Assert that temperature drops at altitude, at night, in rain, and rises near fire — **not** the
  order in which those modifiers are applied.
- Assert that a Predator transitions from patrol to stalk when the player enters detection range —
  **not** which internal method performed the transition.
- Assert that a save round-trips to an equivalent game state — **not** the JSON key layout.

Tests must be **deterministic**. Every test that touches generation or randomness supplies an
explicit seed. Time-dependent systems are advanced by injected delta values rather than by real
elapsed time.

### Seams

The seam count is deliberately minimised. **One primary seam, plus one minimal secondary seam for
what physics makes irreducible.**

**Primary seam — the simulation module boundary.** Because all game logic lives in pure `RefCounted`
classes with no `Node` or `SceneTree` dependency (see the simulation/presentation split above), a
single headless runner can construct these classes directly, feed them data, and assert on results.
This is the highest available seam and it covers the large majority of the game's behaviour. Run via
Godot's `--headless` flag, so it requires no display, no editor, and no addon.

Covered through this seam:

- World generation — height range, ocean border, biome presence and distribution, river
  connectivity to the coast, determinism across two runs of the same seed, quantization to whole
  metres
- Climate — day/night phase progression, weather state transition legality, snowline behaviour
- Temperature — directional response to each input; sheltered and fire cases
- Survival stats — hunger and stamina rates, starvation and cold damage thresholds, death
- Inventory and crafting — capacity, stacking, recipe satisfaction and consumption
- Combat resolution — damage application, armour mitigation, death, drop tables
- Creature decision-making — state transitions given synthetic stimuli, slope refusal, stuck recovery
- Save serialization — round-trip equivalence, and that looted caches and prop depletion persist

**Secondary seam — a minimal headless scene harness.** Some behaviour is genuinely a property of the
physics engine and cannot be reduced to a pure function. This harness boots a minimal `SceneTree`
with physics and is kept deliberately small:

- 1 m automatic step-up, and refusal of over-steep slopes
- Walk-to-swim transition at the waterline
- Shelter `Area3D` overlap detection
- Projectile and hitscan registration against creature hitboxes

**Explicitly not automatically tested — the presentation layer.** Sky and atmospheric colour,
volumetric fog appearance, precipitation particles, shader output, creature animation readability,
and HUD layout are all verified by the developer playing each milestone. Automating visual judgement
here would cost more than it returns, and there is no baseline to regress against on a project with
no existing screenshots.

### Prior art

**There is none in this repository — it is empty — and none in the sibling project.**
`dreambig-game-alpha` has no test suite; its `addons/godot_mcp/commands/test_commands.gd` belongs to
the MCP addon rather than to project tests. This spec therefore *establishes* the testing pattern
rather than following one, which is a further reason to keep the seam count at one plus a minimum.

A full **GUT** unit-test framework installation was considered and rejected for round one:
test-first development against procedural terrain and creature AI is slow while the design is still
settling, and it would roughly double round-one effort. The lightweight headless-runner approach is
chosen as the pragmatic middle, and adopting GUT later remains open.

### Verification loop

Each milestone is verified in two parts before it is considered done:

1. **Automated** — headless assertion scenes pass, run without a display and without the editor.
2. **Human** — the developer plays the milestone and judges the visuals and the feel.

**Godot MCP Pro** (already owned, copied in, disabled) would allow driving the running game and
screenshotting it for self-verification of visuals. It is not part of the loop for round one because
it requires enabling the addon and registering an MCP server from an interactive session. Wiring it
up later is an available upgrade, not a dependency.

## Out of Scope

Out of scope for round one entirely:

- **Voxel terrain and block breaking/placing.** The defining Minecraft mechanic is deliberately
  absent. Terrain is a non-editable heightmap.
- **Building and placeable structures**, beyond the campfire. No walls, roofs, doors, or bases.
- **Explorable cave systems** carved as real 3D volumes. Cave *mouths* are shallow prefab props.
- **Infinite or streaming terrain**, tile LOD, and prop impostors — and therefore also viewing the
  whole island from a mountaintop, which would require them.
- **Multiplayer** in any form.
- **Craftable ammunition** and a workbench crafting tier.
- **Deep crafting trees**, tech progression, and machinery.
- **NPCs, villages, dialogue, quests, and any narrative.**
- **Imported or purchased 3D models**; all geometry is procedural or hand-built from primitives.
- **A visible player body**, third-person camera, and the player animation state machine.
- **Gamepad tuning**, though the input map is structured to accept it.
- **Seasons**, and regional pressure-field weather.
- **Saved creature state.**
- **Audio design** beyond functional cues for rain, gunfire, and creatures.
- **Export builds and distribution** for any platform. Development runs from the editor.
- **Accessibility options, localisation, and a settings menu** beyond the M6 shell.
- **A GUT test suite** and visual regression testing.

## Further Notes

### Known risks

1. **8 GB unified memory is the binding constraint on the whole design.** Forward+ with volumetric
   fog is the single largest bet in this spec. If it thrashes, the documented retreat is the Mobile
   renderer with flatter weather. The decision point is M2, and it should be measured rather than
   guessed.
2. **Round one is weeks of work, not an evening.** The scope roughly doubled when the full survival
   simulation was chosen over the lighter threat-and-progression loop. That choice was made
   knowingly; the timeline is stated here so it is agreed rather than discovered.
3. **Visual verification depends entirely on the developer** for M1 and M2 unless Godot MCP Pro is
   wired up. Logic is self-verifying; appearance is not.
4. **Steering locomotion can wedge creatures** against cliffs or circle them around props. The
   stuck-timer and shapecast avoidance are the mitigations. If animals visibly misbehave in M4, the
   escalation path is small baked navmesh regions around dense prop clusters only — not a global
   navmesh.
5. **The three big cats remain mechanically similar** even with distinct stats and colours. This is
   accepted for round one. The natural later differentiation is a distinct gimmick per species, such
   as leopards ambushing from trees.

### Divergences from the sibling project

`dreambig-game-alpha` conventions are inherited except where noted, and the exceptions are
deliberate rather than accidental:

- **Renderer**: Forward+ here, `gl_compatibility` there. Required for volumetric fog and physical
  sky, which the climate system depends on.
- **Resolution**: 1600×900 here, 2304×1296 there. The 3D open world cannot afford near-native
  Retina on this hardware.
- **Dimensionality**: 3D here, 2D platformer there. The GDScript-first language policy carries over
  unchanged.

### Open questions deferred to implementation

These are tuning matters, resolvable during the milestone that needs them rather than up front:
exact damage and health numbers per species, hunger and stamina rates, cold damage thresholds,
respawn penalty, cache density and respawn interval, prop depletion timers, creature population
caps, and dragon count (one or two).
