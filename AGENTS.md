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

## Testing

Two seams, deliberately minimised:

1. **Primary — the simulation module boundary.** A headless runner constructs the pure logic classes
   directly and asserts on real values. Run with Godot's `--headless` flag; needs no display, editor,
   or addon.
2. **Secondary — a minimal headless scene harness**, only for behaviour that is genuinely a property
   of the physics engine (step-up, swim transition, shelter overlap, projectile registration).

Tests assert on externally observable behaviour, never on internal structure, and are deterministic —
explicit seeds for anything generated, injected deltas for anything time-dependent.

The **presentation layer is not automatically tested**: sky, fog, particles, shaders, animation
readability, and HUD layout are verified by a human playing each milestone.

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

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (`azthrun/dreambig-game-dreamcraft`), managed with the `gh`
CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each using its default label string. See
`docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.
