extends RefCounted
## Generates the island heightmap from an integer seed.
##
## Deliberately narrow for now: a single noise octave shaped by a radial falloff,
## producing land and ocean only. Biomes, macro geography and rivers are a later
## concern and will layer on top of this.
##
## Pure: no Node, no SceneTree, no rendering. Given a seed it returns data, which is
## what makes it testable headlessly and reproducible.
##
## Noise sampling itself is native C++ (FastNoiseLite), so the GDScript cost here is
## the per-cell arithmetic, not the noise.

const Heightmap := preload("res://scripts/world/heightmap.gd")

## Island extent in metres along one axis. A power of two so the tile grid divides
## evenly.
const ISLAND_SIZE_M := 2048.0

## Horizontal size of one heightmap cell, in metres.
##
## This is the single number that decides the terrain triangle count: halving it
## quadruples the mesh. 4 m keeps the whole island affordable as static meshes with
## no LOD, which is what lets SPEC.md delete streaming. Terraces are therefore 4 m
## wide and 1 m tall.
const CELL_SIZE_M := 4.0

const CELLS_PER_AXIS := int(ISLAND_SIZE_M / CELL_SIZE_M)

## Deepest seabed and highest peak, in metres relative to sea level.
const SEA_FLOOR_M := -24.0
const PEAK_M := 96.0

## Noise feature size in metres. Larger means broader landforms.
const FEATURE_SIZE_M := 420.0

## Land ends at this fraction of the half-extent, leaving an ocean ring so the
## island never reaches the world border.
const SHORE_RADIUS := 0.82

## How sharply elevation falls towards the shore. Higher keeps the interior
## plateau flatter and steepens the coast.
const EDGE_FALLOFF_POWER := 2.4

## Floor applied to the interior so a low noise sample cannot drown the island's
## centre. Guarantees land exists for every seed.
const INTERIOR_LIFT := 0.45


## Builds the heightmap for a seed. The same seed always produces identical data.
func generate(seed_value: int) -> RefCounted:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Single octave, per the current scope: no fractal layering yet.
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = 1.0 / FEATURE_SIZE_M

	var map: RefCounted = Heightmap.new(CELLS_PER_AXIS, CELL_SIZE_M)
	var half := ISLAND_SIZE_M * 0.5
	var centre := float(CELLS_PER_AXIS - 1) * 0.5

	for cz in CELLS_PER_AXIS:
		# Normalised distance from centre along Z, -1 at one edge to +1 at the other.
		var nz := (float(cz) - centre) / centre
		var world_z := float(cz) * CELL_SIZE_M - half
		for cx in CELLS_PER_AXIS:
			var nx := (float(cx) - centre) / centre
			var world_x := float(cx) * CELL_SIZE_M - half

			# Noise in 0..1.
			var elevation := (noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5

			# Radial falloff: 1 at the centre, 0 at and beyond the shore radius.
			var distance := sqrt(nx * nx + nz * nz)
			var falloff := clampf(
					1.0 - pow(distance / SHORE_RADIUS, EDGE_FALLOFF_POWER),
					0.0, 1.0)

			var shaped := falloff * (INTERIOR_LIFT
					+ (1.0 - INTERIOR_LIFT) * elevation)
			var height := lerpf(SEA_FLOOR_M, PEAK_M, shaped)

			map.set_height(cx, cz, roundi(height))

	return map
