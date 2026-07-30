extends RefCounted
## Generates the island: heights, rivers, and biome classification, from one seed.
##
## Runs in three passes, in this order because each depends on the last:
##   1. heights — broad landform, plus a ridged mountain range weighted to the north
##   2. rivers  — carved downhill from high ground until they reach the sea
##   3. biomes  — classified from the final heights, so a carved valley is a river
##
## Pure: no Node, no SceneTree, no rendering. Given a seed it returns data, which is
## what makes it testable headlessly and reproducible.
##
## Noise sampling is native C++ (FastNoiseLite), so the GDScript cost is the per-cell
## arithmetic rather than the noise itself.

const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

## Island extent in metres along one axis. A power of two so the tile grid divides
## evenly.
const ISLAND_SIZE_M := 2048.0

## Horizontal size of one heightmap cell, in metres.
##
## This is the single number that decides the terrain triangle count: halving it
## quadruples the mesh. 4 m keeps the whole island affordable as static meshes with
## no LOD, which is what lets the finite-island decision delete streaming. Terraces
## are therefore 4 m wide and 1 m tall.
const CELL_SIZE_M := 4.0

const CELLS_PER_AXIS := int(ISLAND_SIZE_M / CELL_SIZE_M)

## Deepest seabed, and the absolute ceiling any cell may reach.
const SEA_FLOOR_M := -24.0
const PEAK_M := 96.0

## Ceiling for the broad landform alone, before mountains are added.
##
## Held below MOUNTAIN_MIN_HEIGHT on purpose: if the base landform could reach
## mountain height by itself, southern high ground would classify as mountains and
## "mountains concentrated north" would only be a tendency. Keeping base terrain
## under that line means mountain height can only come from the ridge layer, which is
## weighted north.
const BASE_PEAK_M := 52.0

## Broad landform feature size in metres. Larger means broader shapes.
const FEATURE_SIZE_M := 420.0

## Land ends at this fraction of the half-extent, leaving an ocean ring so the island
## never reaches the world border.
const SHORE_RADIUS := 0.82

## How sharply elevation falls towards the shore.
const EDGE_FALLOFF_POWER := 2.4

## Floor applied to the interior so a low noise sample cannot drown the centre.
const INTERIOR_LIFT := 0.45

# --- mountains ----------------------------------------------------------------

## Height the ridged mountain layer can add on top of the base landform.
##
## Sized against the 4 m cell: broad noise alone produced a ~14 degree average slope,
## meaning an 83 m peak reached by a thousand gentle 1 m steps and essentially no
## cliffs. A tighter, taller ridge layer is what makes a mountain read as a mountain
## and produces height jumps a 1.05 m step cannot climb.
const MOUNTAIN_AMPLITUDE_M := 62.0

## Ridge feature size. Small relative to FEATURE_SIZE_M so ridges are sharp.
const MOUNTAIN_FEATURE_SIZE_M := 190.0
const MOUNTAIN_OCTAVES := 4

## North is -Z. Mountain weight saturates over the northern half of the landmass and
## reaches zero just past the middle, so the range covers land rather than ocean.
##
## Defined over the land range on purpose. An earlier version ramped across the full
## -1..+1 map and multiplied by the radial shore falloff, which put peak mountain
## weight at the northern shoreline where falloff is zero — the two terms cancelled
## and the range never rose above the base landform at all.
const MOUNTAIN_NORTH_SATURATION := -0.5
const MOUNTAIN_SOUTH_LIMIT := 0.1

## Mountains are suppressed only near the waterline. Full strength once the shore
## falloff clears this value, rather than scaling with it all the way inland.
const MOUNTAIN_COAST_GUARD := 0.45

# --- rivers -------------------------------------------------------------------

const RIVER_COUNT := 7

## Only cells at least this high may seed a river, so rivers start on high ground.
const RIVER_SOURCE_MIN_HEIGHT := 34

## Minimum separation between sources, in cells, so rivers do not all share a valley.
const RIVER_SOURCE_SPACING_CELLS := 40

## Hard bound on path length. A river always moves outward, so it cannot exceed the
## half-width of the map in steps; this is slack on top of that.
const RIVER_MAX_STEPS := 400

# --- classification -----------------------------------------------------------

## Land at or below this height is beach.
const BEACH_MAX_HEIGHT := 2

## Land at or above this height is mountains. Above BASE_PEAK_M, so only the ridge
## layer can lift terrain into this band.
const MOUNTAIN_MIN_HEIGHT := 54

## Forest/plains mix. Higher means forest needs a stronger noise sample, so plains
## win more often; the centrality term raises the bar near the middle of the island,
## which is what keeps plains central.
const FOREST_THRESHOLD_BASE := 0.34
const FOREST_THRESHOLD_CENTRAL_BIAS := 0.42
const FOREST_FEATURE_SIZE_M := 240.0


func generate(seed_value: int) -> RefCounted:
	var map: RefCounted = Heightmap.new(CELLS_PER_AXIS, CELL_SIZE_M)
	_fill_heights(map, seed_value)
	_carve_rivers(map, seed_value)
	_classify(map, seed_value)
	_force_beach_along_the_coast(map)
	return map


# --- pass 1: heights ----------------------------------------------------------

func _fill_heights(map: RefCounted, seed_value: int) -> void:
	var base := FastNoiseLite.new()
	base.seed = seed_value
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.fractal_type = FastNoiseLite.FRACTAL_NONE
	base.frequency = 1.0 / FEATURE_SIZE_M

	var ridge := FastNoiseLite.new()
	# Offset so the ridge layer is not correlated with the base landform.
	ridge.seed = seed_value + 7919
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = MOUNTAIN_OCTAVES
	ridge.frequency = 1.0 / MOUNTAIN_FEATURE_SIZE_M

	var half := ISLAND_SIZE_M * 0.5
	var centre := float(CELLS_PER_AXIS - 1) * 0.5

	for cz in CELLS_PER_AXIS:
		var nz := (float(cz) - centre) / centre
		var world_z := float(cz) * CELL_SIZE_M - half
		# North is -Z: saturated across the northern half of the land, gone by the middle.
		var northness := clampf(
				(MOUNTAIN_SOUTH_LIMIT - nz)
						/ (MOUNTAIN_SOUTH_LIMIT - MOUNTAIN_NORTH_SATURATION),
				0.0, 1.0)
		for cx in CELLS_PER_AXIS:
			var nx := (float(cx) - centre) / centre
			var world_x := float(cx) * CELL_SIZE_M - half

			var elevation := (base.get_noise_2d(world_x, world_z) + 1.0) * 0.5

			var distance := sqrt(nx * nx + nz * nz)
			var falloff := clampf(
					1.0 - pow(distance / SHORE_RADIUS, EDGE_FALLOFF_POWER),
					0.0, 1.0)

			var shaped := falloff * (INTERIOR_LIFT
					+ (1.0 - INTERIOR_LIFT) * elevation)
			var height := lerpf(SEA_FLOOR_M, BASE_PEAK_M, shaped)

			# Ridged mountains, weighted north and faded out towards the shore so the
			# coastline stays gentle.
			if northness > 0.0 and falloff > 0.0:
				var ridged := (ridge.get_noise_2d(world_x, world_z) + 1.0) * 0.5
				var coast_guard := clampf(falloff / MOUNTAIN_COAST_GUARD, 0.0, 1.0)
				height += MOUNTAIN_AMPLITUDE_M * ridged * northness * coast_guard

			map.set_height(cx, cz,
					roundi(clampf(height, SEA_FLOOR_M, PEAK_M)))


# --- pass 2: rivers -----------------------------------------------------------

func _carve_rivers(map: RefCounted, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var sources := _pick_river_sources(map, rng)
	map.river_sources = sources.size()
	var reached := 0
	for source in sources:
		if _carve_one_river(map, source):
			reached += 1
	map.rivers_to_sea = reached


## Picks high, well-separated starting cells by sampling rather than sorting every
## cell, which would cost far more for no better result.
func _pick_river_sources(map: RefCounted, rng: RandomNumberGenerator) -> Array:
	var sources: Array = []
	var attempts := 0
	var limit: int = map.cells_per_axis
	while sources.size() < RIVER_COUNT and attempts < 20000:
		attempts += 1
		var cx := rng.randi_range(1, limit - 2)
		var cz := rng.randi_range(1, limit - 2)
		if map.height_at_cell(cx, cz) < RIVER_SOURCE_MIN_HEIGHT:
			continue
		var candidate := Vector2i(cx, cz)
		var too_close := false
		for existing in sources:
			if (existing as Vector2i).distance_to(candidate) \
					< RIVER_SOURCE_SPACING_CELLS:
				too_close = true
				break
		if not too_close:
			sources.append(candidate)
	return sources


## Walks a river from `start` to the sea, carving as it goes. Returns whether it
## reached the sea.
##
## The step rule is "outward, then downhill": among neighbours strictly further from
## the island centre, take the lowest. Because every edge cell is below sea level, an
## always-outward walk cannot dead-end inland or loop, which is what makes reaching
## the coast a property of the algorithm rather than luck.
func _carve_one_river(map: RefCounted, start: Vector2i) -> bool:
	var centre := float(map.cells_per_axis - 1) * 0.5
	var centre_v := Vector2(centre, centre)
	var pos := start
	var bed: int = map.height_at_cell(pos.x, pos.y)

	for _step in RIVER_MAX_STEPS:
		if map.height_at_cell(pos.x, pos.y) <= Heightmap.SEA_LEVEL_M:
			return true

		# Never let the bed rise, so the channel always runs downhill.
		bed = mini(map.height_at_cell(pos.x, pos.y), bed)
		map.set_height(pos.x, pos.y, bed)
		map.set_biome(pos.x, pos.y, Biome.Kind.RIVER)

		var here_distance := Vector2(pos).distance_to(centre_v)
		var best := Vector2i(-1, -1)
		var best_height := 0
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var next := Vector2i(pos.x + dx, pos.y + dz)
				if not map.in_bounds(next.x, next.y):
					continue
				if Vector2(next).distance_to(centre_v) <= here_distance:
					continue
				var h: int = map.height_at_cell(next.x, next.y)
				if best.x < 0 or h < best_height:
					best = next
					best_height = h
		if best.x < 0:
			return false
		pos = best

	return false


# --- pass 3: biomes -----------------------------------------------------------

func _classify(map: RefCounted, seed_value: int) -> void:
	var forest := FastNoiseLite.new()
	forest.seed = seed_value + 104729
	forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest.fractal_type = FastNoiseLite.FRACTAL_NONE
	forest.frequency = 1.0 / FOREST_FEATURE_SIZE_M

	var half := ISLAND_SIZE_M * 0.5
	var centre := float(CELLS_PER_AXIS - 1) * 0.5

	for cz in CELLS_PER_AXIS:
		var nz := (float(cz) - centre) / centre
		var world_z := float(cz) * CELL_SIZE_M - half
		for cx in CELLS_PER_AXIS:
			var height: int = map.height_at_cell(cx, cz)

			if height <= Heightmap.SEA_LEVEL_M:
				map.set_biome(cx, cz, Biome.Kind.OCEAN)
				continue

			# A carved river keeps its classification; it was marked while carving.
			if map.biome_at_cell(cx, cz) == Biome.Kind.RIVER:
				continue

			if height <= BEACH_MAX_HEIGHT:
				map.set_biome(cx, cz, Biome.Kind.BEACH)
				continue

			if height >= MOUNTAIN_MIN_HEIGHT:
				map.set_biome(cx, cz, Biome.Kind.MOUNTAINS)
				continue

			var nx := (float(cx) - centre) / centre
			var world_x := float(cx) * CELL_SIZE_M - half
			var centrality := clampf(1.0 - sqrt(nx * nx + nz * nz), 0.0, 1.0)
			var threshold := FOREST_THRESHOLD_BASE \
					+ FOREST_THRESHOLD_CENTRAL_BIAS * centrality
			var sample := (forest.get_noise_2d(world_x, world_z) + 1.0) * 0.5
			map.set_biome(cx, cz,
					Biome.Kind.FOREST if sample > threshold else Biome.Kind.PLAINS)


## Forces any land cell touching the ocean to beach.
##
## Classification by height alone almost always produces this anyway, but "beach sits
## between ocean and inland biomes" should be a guarantee rather than a tendency —
## otherwise a steep coastal cell would drop forest straight into the sea.
func _force_beach_along_the_coast(map: RefCounted) -> void:
	var edits: Array[Vector2i] = []
	for cz in map.cells_per_axis:
		for cx in map.cells_per_axis:
			var kind: int = map.biome_at_cell(cx, cz)
			if kind == Biome.Kind.OCEAN or kind == Biome.Kind.RIVER:
				continue
			if _touches_ocean(map, cx, cz):
				edits.append(Vector2i(cx, cz))
	for cell in edits:
		map.set_biome(cell.x, cell.y, Biome.Kind.BEACH)


func _touches_ocean(map: RefCounted, cx: int, cz: int) -> bool:
	for offset in [Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(0, -1), Vector2i(0, 1)]:
		if map.biome_at_cell(cx + offset.x, cz + offset.y) == Biome.Kind.OCEAN:
			return true
	return false
