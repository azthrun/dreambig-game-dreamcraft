extends "res://tests/test_case.gd"
## Tests island generation: quantization, the ocean border, and determinism.

const IslandGenerator := preload("res://scripts/world/island_generator.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")

## Seeds spread across the range, so a property is asserted for more than one
## island rather than for one lucky map.
const SEEDS: Array[int] = [1, 20260729, -4711, 999983]


func _generate(seed_value: int) -> RefCounted:
	var generator: RefCounted = IslandGenerator.new()
	return generator.generate(seed_value)


func test_heights_are_stored_as_whole_metres() -> void:
	# Quantization is enforced by the representation: an integer array cannot hold
	# a fractional height, so the terraced silhouette cannot silently smooth out.
	var map := _generate(SEEDS[0])
	assert_eq(typeof(map.heights()), TYPE_PACKED_INT32_ARRAY,
			"heights must be integers, not floats")
	assert_eq(typeof(map.height_at_cell(10, 10)), TYPE_INT)


func test_heightmap_covers_the_configured_island() -> void:
	var map := _generate(SEEDS[0])
	assert_eq(map.cells_per_axis, IslandGenerator.CELLS_PER_AXIS)
	assert_almost_eq(map.size_m(), IslandGenerator.ISLAND_SIZE_M, 0.01)
	assert_eq(map.heights().size(),
			IslandGenerator.CELLS_PER_AXIS * IslandGenerator.CELLS_PER_AXIS)


func test_every_edge_cell_is_at_or_below_sea_level() -> void:
	# The ocean border is what removes the need for an invisible wall. If any edge
	# cell were land, the island would touch the world boundary.
	for seed_value in SEEDS:
		var map := _generate(seed_value)
		var last: int = map.cells_per_axis - 1
		var offenders := 0
		for i in map.cells_per_axis:
			if map.height_at_cell(i, 0) > Heightmap.SEA_LEVEL_M:
				offenders += 1
			if map.height_at_cell(i, last) > Heightmap.SEA_LEVEL_M:
				offenders += 1
			if map.height_at_cell(0, i) > Heightmap.SEA_LEVEL_M:
				offenders += 1
			if map.height_at_cell(last, i) > Heightmap.SEA_LEVEL_M:
				offenders += 1
		assert_eq(offenders, 0,
				"seed %d has land on the world border" % seed_value)


func test_heights_stay_within_the_configured_range() -> void:
	for seed_value in SEEDS:
		var map := _generate(seed_value)
		assert_in_range(float(map.min_height()),
				IslandGenerator.SEA_FLOOR_M, IslandGenerator.PEAK_M,
				"seed %d min height out of range" % seed_value)
		assert_in_range(float(map.max_height()),
				IslandGenerator.SEA_FLOOR_M, IslandGenerator.PEAK_M,
				"seed %d max height out of range" % seed_value)


func test_every_seed_produces_an_island_with_land() -> void:
	# Guards the interior lift: without it a low noise sample could drown the
	# whole map and produce an ocean with no island in it.
	for seed_value in SEEDS:
		var map := _generate(seed_value)
		assert_in_range(map.land_fraction(), 0.10, 0.90,
				"seed %d land fraction implausible" % seed_value)


func test_island_centre_is_always_land() -> void:
	for seed_value in SEEDS:
		var map := _generate(seed_value)
		assert_true(map.height_at_world(0.0, 0.0) > Heightmap.SEA_LEVEL_M,
				"seed %d has water at the island centre" % seed_value)


func test_same_seed_produces_an_identical_heightmap() -> void:
	# Determinism is what lets a save file store a seed instead of terrain, and
	# what makes every other test here reproducible.
	var first := _generate(SEEDS[1])
	var second := _generate(SEEDS[1])
	assert_eq(first.heights(), second.heights())


func test_different_seeds_produce_different_heightmaps() -> void:
	var first := _generate(SEEDS[0])
	var second := _generate(SEEDS[1])
	assert_ne(first.heights(), second.heights())


func test_world_and_cell_coordinates_agree() -> void:
	var map := _generate(SEEDS[0])
	# The island is centred on the origin, so the world origin is the middle cell.
	var centre: Vector2i = map.world_to_cell(0.0, 0.0)
	assert_eq(centre.x, map.cells_per_axis / 2)
	assert_eq(centre.y, map.cells_per_axis / 2)
	assert_eq(map.height_at_world(0.0, 0.0),
			map.height_at_cell(centre.x, centre.y))


func test_out_of_bounds_cells_clamp_to_the_edge() -> void:
	# Meshing and creature ground queries rely on this instead of bounds-checking
	# at every call site.
	var map := _generate(SEEDS[0])
	var last: int = map.cells_per_axis - 1
	assert_eq(map.height_at_cell(-50, 10), map.height_at_cell(0, 10))
	assert_eq(map.height_at_cell(9999, 10), map.height_at_cell(last, 10))
	assert_eq(map.height_at_cell(10, -50), map.height_at_cell(10, 0))
	assert_eq(map.height_at_cell(10, 9999), map.height_at_cell(10, last))
	assert_false(map.in_bounds(-1, 0))
	assert_true(map.in_bounds(0, 0))
	assert_true(map.in_bounds(last, last))
	assert_false(map.in_bounds(last + 1, last))
