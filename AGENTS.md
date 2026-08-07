# AGENTS.md

Guidance for coding agents working in this repository.

## Project

**Dreamcraft** — a first-person survival game set on a finite, procedurally generated island,
rendered in a deliberately blocky style. Built in **Godot 4.6.1 stable (Mono build)** with
**GDScript**.

[SPEC.md](SPEC.md) is the source of truth for the agreed round-one design. Read it before proposing
work. Do not restate its decisions here — point at it.

## Engineering conventions

The load-bearing rules. Full rationale, including rejected alternatives, is in SPEC.md.

- **GDScript throughout.** C# only where profiling demonstrates a bottleneck, never pre-emptively.
  This follows the convention established in the sibling `dreambig-game-alpha` project.
- **Forward+ renderer on Metal, Jolt Physics.** A deliberate divergence from the sibling project's
  `gl_compatibility`, required for volumetric fog and the physical sky.
- **Simulation / presentation split.** Game logic lives in pure `RefCounted` classes with no `Node`
  or `SceneTree` dependency. `Node` scenes are thin shells that read from them and hold no
  authoritative state. This is what makes the codebase testable headlessly.
- **Performance budget: 1600×900, 60 FPS, ~500 m view distance.** The target machine is an 8 GB M2,
  and that memory ceiling is the binding constraint on design choices. The budget lives in
  `project.godot` under `[dreamcraft]` and is read through `scripts/config.gd` — never hard-code it.
  Measure with `./run_perf.sh`; measured results and startup costs are in `docs/performance.md`.
- **Single-player only.** No networking. World generation is nonetheless deterministic from an
  integer seed.
- **Input via named input-map actions**, never raw key reads.

### Physics layers

Only four are in use, and mixing them up produces bugs that look like missing features
rather than errors:

| Layer | Value | Holds | Notes |
|---|---|---|---|
| World | 1 | Terrain, tree trunks, rock outcrops, cover props | Blocks player movement |
| Interaction | 4 | Berry bushes, campfire bodies | Reachable but **not** solid — the player walks through |
| Creature | 8 | Living creatures, corpses | Collides with nothing; melee and looting rays target this |

Anything the player should be able to *reach* but not be *stopped by* goes on the
interaction layer. Berry bushes were unharvestable for a whole ticket because they had no
body at all, and the same class of bug will recur for anything non-solid.

**Interaction volumes reach above eye height.** The player's eye is at 1.65 m. A collider
that stops at an object's actual height is missed by a level look — this bit berry bushes,
corpses, and campfires in turn. Melee uses a sphere rather than a ray for the same reason.

### Anything the player takes from

There is **one** take-from-the-world interaction: hold `interact`. It finds a child node
named `Harvestable` (regrows, yields one item) or `Lootable` (yields several, may not
come back) on whatever the ray hit, and it never learns what kind of object owns it.

Corpses, the cooking rack and supply caches are all `Lootable`. A supply cache is
literally the corpse's `Lootable` subclassed with a refill. **Adding a new container
means adding a component with that name, not a key, a prompt, or a refusal path** — if
you find yourself writing a second "hold E to…" you have taken a wrong turn.

The interaction volume must reach eye height (1.65 m); see the physics-layer note above.
That is why caches are non-solid: a knee-high crate needs a chest-high collider to be
findable by a level look, and a solid collider that tall is an invisible wall.

### Adding a creature

Species are data: a new animal is an entry in `creature_kind.gd`, not new code. Role
(prey/predator) picks the brain, and the body asks both brains the same questions.
Proportions, colour, coat pattern, gait and spawn weights are all entries in that table.

Two entries are easy to omit and fail quietly. A species with no `max_population`
**never spawns** — zero is the default, and the island simply comes out without it. A
species with no `gait` silently borrows the shared fallback and moves like everything
else, which is exactly what the cuboid style is worst at hiding.

**Markings have to be on the back, not only the flanks.** The player looks *down* at
animals from higher terrain most of the time. The leopard's spots were side-faces only
and it read as a plain tan animal at eleven metres — inside its own charge range.

**Animals find each other through the registry, never through the scene tree.**
`creature_registry.gd` answers "nearest creature of this role within this range"; the
brains stay pure and take positions. A new species joins the ecosystem for free, because
role picks the brain and the registry keys off role.

Two consequences that look like bugs. Dormancy means **autonomous behaviour only happens
near the player** — a hunt on the far side of the island is not slowed down, it does not
occur. And a predator's reach for animals is *not* its player-detection range: it tracks
prey to `PREY_SCENT_MULTIPLIER` times that, or hunts are too rare to ever witness.

**New creatures must inherit dormancy.** Beyond `ACTIVE_RADIUS_M` a creature stops
thinking, stops animating and stops drawing. This is not an optimisation to add later:
adding 60 deer without it put the 1% low *below* the 60 FPS target while the average still
read 160+. See `docs/performance.md`. Never assume a new species is free — measure across
several runs after adding one.

### Procedural audio has to be built once, not per play

`scripts/audio/procedural_audio.gd` synthesises every sound sample by sample — there are
no audio assets in this project, same as there is no 3D art. That synthesis is cheap
called rarely and expensive called often: a gunshot resynthesised fresh on every round of
automatic fire (roughly 12/s) dropped the 1% low from ~200 FPS to below target, discovered
while measuring the machine gun ticket. Build the `AudioStreamWAV` once — in `_ready()` or
at construction — and replay the same buffer, the way the campfire already does for its
fire crackle. Anything fired, looped, or otherwise repeated needs this; a one-shot played
once per user action (a footstep, a menu click) may not.

## Testing

Two seams, deliberately minimised:

1. **Primary — the simulation module boundary.** A headless runner constructs the pure logic classes
   directly and asserts on real values. Run with Godot's `--headless` flag; needs no display, editor,
   or addon.
2. **Secondary — a minimal headless scene harness**, only for behaviour that is genuinely a property
   of the physics engine (step-up, swim transition, shelter overlap, projectile registration).

Tests assert on externally observable behaviour, never on internal structure, and are deterministic —
explicit seeds for anything generated, injected deltas for anything time-dependent.

The **presentation layer has no automated tests**, but it is not unverifiable. Run:

```
./run_screenshot.sh
```

This captures the game's own viewport to PNGs at ground level, lifted, and high. A headless
run has no rendering device — nothing can be culled, lit, or seen — so anything about
appearance needs a windowed run and a look at the output.

Use it for anything a test cannot reach: whether geometry renders at all, face winding,
colour, fog, sky, and later particles and animation. It is not a substitute for a human
judging whether the game *looks good*, but it does catch things that are plainly wrong.
It found the washed-out terrain palette that a hundred passing headless tests had no way
to see.

Note the asymmetry it revealed: props use `albedo_color`, which Godot converts from sRGB,
while mesh vertex colours are passed through as linear. Any material relying on vertex
colours needs `vertex_color_is_srgb = true` or it renders far too pale.

### Running the suite

```
./run_tests.sh
```

Exits `0` when green, `1` when any test fails, `2` when the suite found no tests or evaluated no
assertions — a suite that runs but asserts nothing is a broken suite, not a passing one. Override the
engine location with `GODOT=/path/to/godot` if needed.

`./run_tests.sh --selftest` runs `tests/selftest/`, which holds a deliberately failing test and is
excluded from the normal run. It exists so the non-zero exit path is itself verified: a runner bug
that swallowed failures would otherwise be indistinguishable from a green suite.

### Writing a test

Put `*_test.gd` under `tests/unit/` (pure logic) or `tests/integration/` (needs a `SceneTree` and
physics). Start with `extends "res://tests/test_case.gd"` — extend **by path**, not by `class_name`,
because global class names resolve through Godot's script class cache, which is not guaranteed to be
current for a freshly added file in a headless run.

Name methods `test_*`; the runner discovers them, sorts them for deterministic order, and constructs a
fresh instance per test so state cannot leak between them. `before_each` / `after_each` are
overridable. Assertions record failures rather than halting, so one bad assertion does not hide the
rest of a test.

Available: `assert_true`, `assert_false`, `assert_eq`, `assert_ne`, `assert_almost_eq` (float epsilon),
`assert_in_range` (inclusive), `assert_has` / `assert_not_has` (arrays, packed arrays, dictionary keys,
substrings), and `fail`.

A test that evaluates **zero assertions is reported as a failure**, not a pass. GDScript
runtime errors cannot be caught, so a test that errors before its first assertion would
otherwise look green. This guard has caught real errors more than once.

### The most common mistake in this repo

Roughly a third of the failures during development were **the test's premise being wrong,
not the code**. Recurring examples: asserting starvation after 400 s when hunger takes
714 s to fill; checking a predator's recovery window while it was still wounded enough to
retreat anyway; picking a "cold night" scenario that was 6 °C. When a test fails, check
the scenario actually sets up the situation being asserted before changing the code.

Watch for the inverse too: a test that passes while proving nothing. Both halves of a gate
need testing — that an exhausted player *cannot* sprint **and** that a rested one *can*.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (`azthrun/dreambig-game-dreamcraft`), managed with the `gh`
CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each using its default label string. See
`docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.
