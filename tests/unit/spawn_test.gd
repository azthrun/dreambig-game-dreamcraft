extends "res://tests/test_case.gd"
## Tests the shore spawn point.

const Spawn := preload("res://scripts/world/spawn.gd")
const IslandGenerator := preload("res://scripts/world/island_generator.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

const SEEDS: Array[int] = [1, 20260729, -4711]


func _world(seed_value: int) -> RefCounted:
	var generator: RefCounted = IslandGenerator.new()
	return generator.generate(seed_value)


func test_spawn_is_on_a_beach_touching_the_ocean() -> void:
	# "Washed up on the shore" should mean the shore, not merely dry land.
	for seed_value in SEEDS:
		var map := _world(seed_value)
		var spawn: RefCounted = Spawn.new()
		var position: Vector3 = spawn.shore_spawn(map, seed_value)
		var cell: Vector2i = map.world_to_cell(position.x, position.z)
		assert_eq(map.biome_at_cell(cell.x, cell.y), Biome.Kind.BEACH,
				"seed %d did not spawn on a beach" % seed_value)

		var coastal := false
		for offset in [Vector2i(-1, 0), Vector2i(1, 0),
				Vector2i(0, -1), Vector2i(0, 1)]:
			if map.biome_at_cell(cell.x + offset.x, cell.y + offset.y) \
					== Biome.Kind.OCEAN:
				coastal = true
		assert_true(coastal, "seed %d spawned inland" % seed_value)


func test_spawn_is_above_water_and_above_the_ground() -> void:
	for seed_value in SEEDS:
		var map := _world(seed_value)
		var spawn: RefCounted = Spawn.new()
		var position: Vector3 = spawn.shore_spawn(map, seed_value)
		var ground: int = map.height_at_world(position.x, position.z)
		assert_true(ground > Heightmap.SEA_LEVEL_M,
				"seed %d spawned underwater" % seed_value)
		assert_almost_eq(position.y, float(ground) + Spawn.CLEARANCE_M, 0.001)


func test_spawn_is_deterministic() -> void:
	# A given island always starts you in the same place, and returns you there.
	var map := _world(SEEDS[1])
	var spawn: RefCounted = Spawn.new()
	assert_eq(spawn.shore_spawn(map, SEEDS[1]),
			spawn.shore_spawn(map, SEEDS[1]))


func test_spawn_lies_inside_the_island() -> void:
	var map := _world(SEEDS[1])
	var spawn: RefCounted = Spawn.new()
	var position: Vector3 = spawn.shore_spawn(map, SEEDS[1])
	var half: float = map.size_m() * 0.5
	assert_in_range(position.x, -half, half)
	assert_in_range(position.z, -half, half)
