# Performance

The measured performance envelope for Dreamcraft, and how to re-measure it.

## Target machine

| | |
|---|---|
| Machine | MacBook Pro, Apple M2 |
| Cores | 8 (4 performance, 4 efficiency) |
| Memory | **8 GB unified** — shared between CPU and GPU |
| Display | 2560×1600 Retina |
| Renderer | Forward+ on Metal 4 |

The 8 GB is the binding constraint on the whole design. It is why the island is finite,
why terrain is not voxels, and why the view distance is capped.

## Budget

Configured in `project.godot` under `[dreamcraft]`, read through `scripts/config.gd`.
Nothing hard-codes these values.

| Setting | Value |
|---|---|
| Window | 1600×900 |
| Target frame rate | 60 FPS |
| View distance (camera far plane) | 500 m |
| Distance fog starts | 55% of view distance (275 m) |
| Prop cull distance | 150 m |

Fog uses `FOG_MODE_DEPTH` rather than exponential fog, because depth fog can be made
fully opaque exactly at the far plane. That is what hides the far plane instead of
merely softening it. The sky horizon colour and the fog colour are derived from a single
constant in `scripts/main.gd`, so distant terrain fades into the sky rather than into a
differently coloured wall.

## How to measure

```
/Applications/Godot_mono.app/Contents/MacOS/Godot --path . -- --perf
```

The probe walks the player forward across the island for 20 seconds after a 3 second
warmup, sweeping the camera slowly so the measurement covers varied terrain and varied
prop counts rather than one lucky sightline. It exits `0` if the budget is met and `1`
if not, so it can gate CI.

Two deliberate choices in the harness:

- **Vsync is disabled while measuring.** Left on, every reading would be pinned to the
  display refresh rate and "60 FPS" would say nothing about headroom.
- **The first 3 seconds are discarded.** They include shader compilation and the first
  visibility pass, which are not steady state.
- **Real input actions are driven**, not a teleported camera, so collision, step-up and
  prop culling are all included in the measurement.

## Measured result

Recorded 2026-07-30, at commit following ticket #8 (island, water, props, controller;
no weather or creatures yet). Geometry was identical across all runs: **527,410 peak
primitives**, ~900–1000 draw calls, ~1300–1400 visible objects.

**Five consecutive runs, same build, same machine:**

| Run | Average FPS | 1% low FPS |
|---|---|---|
| 1 | 310.7 | 274.2 |
| 2 | 287.5 | 113.1 |
| 3 | 144.9 | 140.4 |
| 4 | 144.9 | 140.4 |
| 5 | 159.4 | 136.5 |

**Take the worst figure, not the best: 113 FPS at the 1% low — about 1.9× the 60 FPS
target.** The budget is met, comfortably but not lavishly.

The run-to-run spread is large (2× on the average, 2.4× on the 1% low) and the later runs
are consistently slower than the first. The likely cause is thermal and background load
on a fanless-ish 8 GB laptop that had been running repeated Godot instances, not
variability in the game itself — the geometry counts are identical across every run. Any
future comparison should therefore be made from several consecutive runs rather than one,
and against the worst 1% low rather than the average.

The 1% low is reported alongside the average because the average hides stutter, and
stutter is what a player notices. `meets_target()` gates on the 1% low, not the average,
so a run that averages well but hitches is correctly reported as failing.

## Measured result — with weather (2026-07-30)

Volumetric fog was flagged above as the next real cost on this hardware, so the probe now
**forces a thunderstorm while measuring**: volumetric fog, full precipitation and
lightning at once. Measuring in fair weather would flatter the result, and the budget has
to hold in the worst conditions the game can produce.

| Run | Average FPS | 1% low FPS | Peak primitives | Draw calls |
|---|---|---|---|---|
| 1 | 243.0 | 120.0 | 571,750 | 1082 |
| 2 | 247.5 | 156.0 | 544,460 | 1076 |
| 3 | 211.1 | 120.0 | 544,460 | 795 |

**Worst 1% low: 120 FPS, still 2× the 60 FPS target.**

Against the pre-weather baseline (270 FPS 1% low, clear skies), volumetric fog plus 3200
precipitation particles costs roughly **half the 1% low**. That is the single largest
cost added so far and it was correctly predicted; it is also affordable.

Headroom is now about 2× rather than the 1.9× measured before weather, which is within
run-to-run noise — the fog cost is real but the earlier baseline was measured on a
warmer machine. Treat 120 FPS as the current worst case.

## Measured result — with creatures (2026-07-30)

60 deer added. Measured under the same forced thunderstorm.

**Before dormancy was implemented**, three runs gave 1% lows of **90.0, 58.7 and 124.5
FPS** — a 66 FPS spread, with one run *below the 60 FPS target*. Average was a healthy
160–172 the whole time, which is exactly why the average is not the figure that matters.

The cost was not the creature logic, which already only decides every 0.2 s. It was that
all 60 `AnimationPlayer`s ticked every frame regardless of distance, and all 60 bodies
drew at any range. An AnimationPlayer costs CPU every frame whatever it is playing, so
sixty idle clips across the island is pure waste.

Creatures beyond `ACTIVE_RADIUS_M` now stop animating and stop drawing entirely.

| Run | Average FPS | 1% low FPS |
|---|---|---|
| 1 | 143.6 | 137.3 |
| 2 | 144.9 | 141.6 |
| 3 | 144.3 | 135.0 |

**Worst 1% low: 135 FPS**, and the spread fell from 66 FPS to 7 FPS. Consistency improved
far more than the headline number — which is the point, since stutter is what a player
notices.

Note the average went *down* slightly (160 → 144) while the 1% low went *up* sharply.
That is the trade being made deliberately: fewer, more even frames beat more frames with
hitches in them.

## Measured result — three cat species (2026-08-01)

The island's 60 animals are now four species rather than two (deer 40, leopard 9, tiger 7,
lion 4). The total is unchanged, so the question was only whether a striped or maned body
— a few more box meshes each — costs anything.

It does not. Three runs on the branch and two on the parent commit, interleaved, all read
**119.2–119.5 FPS average and 120.0 FPS at the 1% low**, with peak primitives within 12 of
each other (540,398 vs 540,410). The extra marking boxes are on 20 animals, of which at
most a handful are ever inside the active radius.

**A caution about the day's readings, which is the reusable part.** Earlier the same day,
six runs gave 1% lows of 52–55 FPS — *below the 60 target*. Three of those runs were on
this branch and three on the unmodified parent commit, and both read the same, which is
what identified the machine rather than the change. Later runs settled at exactly 120.0,
which is a refresh-rate figure rather than a game figure. Neither number is a measurement
of this change; the comparison between them, taken back to back, is.

Always measure the parent commit in the same sitting. A single set of numbers from a
machine in an unknown state can be read as a regression that does not exist.

## Startup cost

Startup is a separate concern from frame rate and is **not** currently within budget in
any meaningful sense — it is simply tolerated.

| Phase | Cost |
|---|---|
| Island generation (noise, rivers, biomes) | ~390 ms |
| Terrace meshing | ~1500 ms |
| Prop construction (4829 props) | ~400 ms |
| **Total** | **~2.3 s** |

Meshing dominates at roughly two thirds of the total. Noise sampling is native C++ via
`FastNoiseLite`, so generation is nearly free; the cost is GDScript vertex loops
assembling ~788 k triangles.

Per the language policy in `AGENTS.md`, the remedy if this becomes a problem is
`WorkerThreadPool` to move meshing off the main thread, **not** a port to C#. Threading
would not reduce the total work, only stop it blocking the frame. At ~2.3 s of one-time
startup this has not been done, because it would add concurrency to a system that
currently has none for no gain a player would notice.

## Headroom, and why not to spend it yet

The obvious lever for better-looking terrain is `CELL_SIZE_M` in
`scripts/world/island_generator.gd`, currently 4 m. Halving it to 2 m would double the
horizontal resolution of the terraces — noticeably finer terrain and coastlines — at
roughly **4× the triangles and 4× the meshing time**.

**On the measured numbers, that does not fit.** Against the worst observed 1% low of
113 FPS, quadrupling terrain geometry would land somewhere near 30–40 FPS, below the 60
target. It would also push startup from ~2.3 s to an estimated ~6 s.

An earlier reading of a single best-case run suggested ~5× headroom and made 2 m cells
look affordable. Five runs show the worst case is ~1.9×, and the worst case is what a
budget has to be set against. **4 m stays.**

Weather and creatures have since landed and been measured under worst-case conditions.
The trajectory is worth watching: 1% low was 270 FPS before weather, 120 after it, and 135
after creatures once dormancy was added. The boar and the dragon are still to come, and
each will need the same dormancy treatment rather than being assumed free.

If finer terrain becomes a priority later, the sequence is: thread the meshing off the
main thread, re-measure with the full scene populated, and only then reconsider cell
size. Neither step is required by any current ticket.
