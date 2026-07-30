extends RefCounted
## Finds where the player starts, and where they come back after dying.
##
## The shore, specifically: SPEC has the player washing up on a beach, and respawning
## there gives death a consistent, findable consequence — you lose your position, not
## your progress.
##
## Pure: takes the world grid as data and returns a position.

const Biome := preload("res://scripts/world/biome.gd")

## Clearance above the terrace so the player settles onto it under gravity rather than
## starting embedded in it.
const CLEARANCE_M := 1.5


## A beach cell that touches the ocean, chosen deterministically from the seed.
##
## Scans on a stride rather than every cell: beaches are continuous, so sampling finds
## one immediately, and this runs on every death.
func shore_spawn(map: RefCounted, seed_value: int) -> Vector3:
	var candidates: Array[Vector2i] = []
	var stride := 3
	for cz in range(0, map.cells_per_axis, stride):
		for cx in range(0, map.cells_per_axis, stride):
			if map.biome_at_cell(cx, cz) != Biome.Kind.BEACH:
				continue
			if _touches_ocean(map, cx, cz):
				candidates.append(Vector2i(cx, cz))

	if candidates.is_empty():
		# No beach at all should be impossible — the generator forces a beach ring — but
		# falling back to the island centre beats spawning at the origin underwater.
		return _world_position(map, map.cells_per_axis / 2, map.cells_per_axis / 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 31337
	var chosen: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
	return _world_position(map, chosen.x, chosen.y)


func _touches_ocean(map: RefCounted, cx: int, cz: int) -> bool:
	for offset in [Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(0, -1), Vector2i(0, 1)]:
		if map.biome_at_cell(cx + offset.x, cz + offset.y) == Biome.Kind.OCEAN:
			return true
	return false


func _world_position(map: RefCounted, cx: int, cz: int) -> Vector3:
	var half: float = map.size_m() * 0.5
	var cell_size: float = map.cell_size_m
	return Vector3(
			float(cx) * cell_size - half + cell_size * 0.5,
			float(map.height_at_cell(cx, cz)) + CLEARANCE_M,
			float(cz) * cell_size - half + cell_size * 0.5)
