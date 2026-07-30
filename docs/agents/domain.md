# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

This repo is **single-context**: one `CONTEXT.md` plus `docs/adr/` at the root. There is no
`CONTEXT-MAP.md` and no per-context split.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root
- **`docs/adr/`** — read ADRs that touch the area you're about to work in

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest
creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and
`/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

```
/
├── AGENTS.md
├── SPEC.md
├── CONTEXT.md                 ← created lazily, does not exist yet
├── docs/
│   ├── adr/                   ← created lazily, does not exist yet
│   └── agents/                ← this directory
├── project.godot
├── scenes/
├── scripts/
├── tests/
├── assets/
└── addons/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test
name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language
the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

**Interim glossary.** `CONTEXT.md` does not exist yet. Until it does, the agreed vocabulary for this
project lives in the **Glossary** section of [SPEC.md](../../SPEC.md), which defines: Island,
Heightmap, Biome, Tile, Prop, shelter volume, Creature (Prey / Predator), Climate, weather state,
snowline, Gadget, Cache, simulation layer, presentation layer. Use those terms. When `CONTEXT.md` is
created, that glossary should move there and SPEC.md should point at it.

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
