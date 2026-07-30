extends "res://tests/test_case.gd"
## Tests biome classification, macro geography, and river carving.

const IslandGenerator := preload("res://scripts/world/island_generator.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

const SEEDS: Array[int] = [1, 20260729, -4711]


func _generate(seed_value: int) -> RefCounted:
	var generator: RefCounted = IslandGenerator.new()
	return generator.generate(seed_value)


func test_every_cell_is_classified() -> void:
	var map := _generate(SEEDS[1])
	var counts: Dictionary = map.biome_counts()
	var total := 0
	for kind in counts:
		assert_has(Biome.ALL, kind, "unknown biome value %d" % kind)
		total += int(counts[kind])
	assert_eq(total, map.heights().size(), "every cell must carry a biome")


func test_all_six_biomes_are_present() -> void:
	for seed_value in SEEDS:
		var map := _generate(seed_value)
		var counts: Dictionary = map.biome_counts()
		for kind in Biome.ALL:
			assert_true(int(counts.get(kind, 0)) > 0,
					"seed %d has no %s" % [seed_value, Biome.name_of(kind)])


func test_classification_is_deterministic() -> void:
	var first := _generate(SEEDS[0])
	var second := _generate(SEEDS[0])
	assert_eq(first.biomes(), second.biomes())


func test_different_seeds_classify_differently() -> void:
	assert_ne(_generate(SEEDS[0]).biomes(), _generate(SEEDS[1]).biomes())


func test_ocean_and_land_agree_with_sea_level() -> void:
	# Classification is derived from height, so the two cannot disagree.
	var map := _generate(SEEDS[1])
	var mismatched := 0
	for cz in range(0, map.cells_per_axis, 3):
		for cx in range(0, map.cells_per_axis, 3):
			var wet: bool = map.height_at_cell(cx, cz) <= Heightmap.SEA_LEVEL_M
			var ocean: bool = map.biome_at_cell(cx, cz) == Biome.Kind.OCEAN
			if wet != ocean:
				mismatched += 1
	assert_eq(mismatched, 0, "ocean cells must be exactly the submerged cells")


func test_beach_sits_between_ocean_and_inland_biomes() -> void:
	# Every land cell touching the sea is beach, so no forest or mountain drops
	# straight into the water.
	for seed_value in SEEDS:
		var map := _generate(seed_value)
		var offenders := 0
		for cz in map.cells_per_axis:
			for cx in map.cells_per_axis:
				var kind: int = map.biome_at_cell(cx, cz)
				if kind == Biome.Kind.OCEAN or kind == Biome.Kind.RIVER:
					continue
				var coastal := false
				for offset in [Vector2i(-1, 0), Vector2i(1, 0),
						Vector2i(0, -1), Vector2i(0, 1)]:
					if map.biome_at_cell(cx + offset.x, cz + offset.y) \
							== Biome.Kind.OCEAN:
						coastal = true
						break
				if coastal and kind != Biome.Kind.BEACH:
					offenders += 1
		assert_eq(offenders, 0,
				"seed %d has non-beach land touching the ocean" % seed_value)


func test_every_river_reaches_the_sea() -> void:
	# The step rule always moves outward and every edge cell is below sea level, so
	# reaching the coast should be guaranteed rather than likely.
	for seed_value in SEEDS:
		var map := _generate(seed_value)
		assert_true(map.river_sources > 0,
				"seed %d seeded no rivers" % seed_value)
		assert_eq(map.rivers_to_sea, map.river_sources,
				"seed %d has a river dead-ending inland" % seed_value)


func test_every_river_cell_has_a_downhill_continuation() -> void:
	# The carved bed never rises, so from any river cell the water can always keep
	# going: some adjacent river or ocean cell sits at or below it. No river cell may
	# be a local maximum, which is what a bed that rose would produce.
	#
	# Deliberately not asserting that adjacent river cells are within a terrace of
	# each other — steep northern terrain makes genuine waterfalls, where a bed drops
	# many metres in one step. That is correct, not a defect.
	for seed_value in SEEDS:
		var map := _generate(seed_value)
		var trapped := 0
		for cz in map.cells_per_axis:
			for cx in map.cells_per_axis:
				if map.biome_at_cell(cx, cz) != Biome.Kind.RIVER:
					continue
				var here: int = map.height_at_cell(cx, cz)
				var can_continue := false
				for dz in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx == 0 and dz == 0:
							continue
						var kind: int = map.biome_at_cell(cx + dx, cz + dz)
						if kind != Biome.Kind.RIVER and kind != Biome.Kind.OCEAN:
							continue
						if map.height_at_cell(cx + dx, cz + dz) <= here:
							can_continue = true
							break
					if can_continue:
						break
				if not can_continue:
					trapped += 1
		assert_eq(trapped, 0,
				"seed %d has river cells with nowhere downhill to go" % seed_value)


func test_mountains_are_concentrated_in_the_north() -> void:
	# North is -Z, so the northern half is the lower half of the cell index range.
	for seed_value in SEEDS:
		var map := _generate(seed_value)
		var half: int = map.cells_per_axis / 2
		var north := 0
		var south := 0
		for cz in map.cells_per_axis:
			for cx in map.cells_per_axis:
				if map.biome_at_cell(cx, cz) != Biome.Kind.MOUNTAINS:
					continue
				if cz < half:
					north += 1
				else:
					south += 1
		assert_true(north > south * 2,
				"seed %d: mountains should favour the north (north %d, south %d)"
						% [seed_value, north, south])


func test_plains_sit_closer_to_the_centre_than_forest() -> void:
	var map := _generate(SEEDS[1])
	var centre := float(map.cells_per_axis - 1) * 0.5
	var centre_v := Vector2(centre, centre)
	var plains_total := 0.0
	var plains_count := 0
	var forest_total := 0.0
	var forest_count := 0
	for cz in map.cells_per_axis:
		for cx in map.cells_per_axis:
			var distance := Vector2(cx, cz).distance_to(centre_v)
			match map.biome_at_cell(cx, cz):
				Biome.Kind.PLAINS:
					plains_total += distance
					plains_count += 1
				Biome.Kind.FOREST:
					forest_total += distance
					forest_count += 1
	assert_true(plains_count > 0 and forest_count > 0)
	assert_true(plains_total / plains_count < forest_total / forest_count,
			"plains should average closer to the centre than forest")


func test_northern_mountains_produce_unclimbable_faces() -> void:
	# The ridge layer exists to make mountains read as mountains. Without steps taller
	# than the player's 1.05 m step-up, an 83 m peak is just a long gentle ramp.
	var map := _generate(SEEDS[1])
	var tall_steps := 0
	for cz in range(1, map.cells_per_axis):
		for cx in range(1, map.cells_per_axis):
			var here: int = map.height_at_cell(cx, cz)
			if here <= Heightmap.SEA_LEVEL_M:
				continue
			for offset in [Vector2i(-1, 0), Vector2i(0, -1)]:
				var there: int = map.height_at_cell(cx + offset.x, cz + offset.y)
				if there > Heightmap.SEA_LEVEL_M and absi(here - there) >= 2:
					tall_steps += 1
	assert_true(tall_steps > 2000,
			"expected real cliffs from the ridge layer, found %d" % tall_steps)


func test_biome_names_are_defined_for_every_kind() -> void:
	for kind in Biome.ALL:
		assert_ne(Biome.name_of(kind), "unknown",
				"biome %d has no name" % kind)
	assert_false(Biome.is_land(Biome.Kind.OCEAN))
	assert_true(Biome.is_land(Biome.Kind.BEACH))
	assert_true(Biome.is_land(Biome.Kind.MOUNTAINS))
