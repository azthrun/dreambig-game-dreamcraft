extends RefCounted
## Where the dragon nests: mountain sites in the northern half of the island.
##
## Pure and deterministic from the world seed, like every other placement in this
## project, so the same island always nests its dragons in the same places. North is -Z
## — see `island_generator.gd`, which weights the mountain range itself the same way, so
## a nest is never placed somewhere the terrain would not plausibly put a mountain.

const Biome := preload("res://scripts/world/biome.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")

## Nests are kept well apart, so two dragons read as two separate territories rather than
## one bigger one.
const MIN_SEPARATION_M := 250.0

## Generous, since only mountain cells in the northern half of a mostly-ocean grid
## qualify at all.
const MAX_ATTEMPTS := 4000


## Up to `count` nest positions: each on a mountain cell in the northern half of the map,
## above sea level, and separated from every other nest already chosen. Fewer than
## `count` is returned if the island does not offer enough qualifying ground — a small or
## unlucky seed should never loop forever chasing a site that is not there.
static func sites(map: RefCounted, seed_value: int, count: int) -> Array[Vector3]:
	var chosen: Array[Vector3] = []
	if count <= 0 or map == null:
		return chosen

	var rng := RandomNumberGenerator.new()
	# Offset so nest placement does not correlate with the general population's own roll.
	rng.seed = seed_value + 9001

	var northern_limit := int(map.cells_per_axis / 2)
	var attempts := 0
	while chosen.size() < count and attempts < MAX_ATTEMPTS:
		attempts += 1
		var cx := rng.randi_range(1, map.cells_per_axis - 2)
		var cz := rng.randi_range(1, maxi(northern_limit - 1, 1))
		if map.biome_at_cell(cx, cz) != Biome.Kind.MOUNTAINS:
			continue
		var height: int = map.height_at_cell(cx, cz)
		if height <= Heightmap.SEA_LEVEL_M:
			continue

		var position := _world_position(map, cx, cz, height)
		if _far_enough(position, chosen):
			chosen.append(position)

	return chosen


static func _far_enough(position: Vector3, chosen: Array[Vector3]) -> bool:
	for existing in chosen:
		if existing.distance_to(position) < MIN_SEPARATION_M:
			return false
	return true


static func _world_position(map: RefCounted, cx: int, cz: int, height: int) -> Vector3:
	var half: float = map.size_m() * 0.5
	var cell_size: float = map.cell_size_m
	return Vector3(
			float(cx) * cell_size - half + cell_size * 0.5,
			float(height),
			float(cz) * cell_size - half + cell_size * 0.5)
