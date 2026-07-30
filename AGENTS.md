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
  and that memory ceiling is the binding constraint on design choices.
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

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (`azthrun/dreambig-game-dreamcraft`), managed with the `gh`
CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each using its default label string. See
`docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.
