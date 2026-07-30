extends "res://tests/test_case.gd"
## Tests cover prop placement and the cover taxonomy.

const IslandGenerator := preload("res://scripts/world/island_generator.gd")
const PropPlacer := preload("res://scripts/world/props/prop_placer.gd")
const PropKind := preload("res://scripts/world/props/prop_kind.gd")
const Biome := preload("res://scripts/world/biome.gd")

const SEED := 20260729


func _place() -> Array:
	var generator: RefCounted = IslandGenerator.new()
	var map: RefCounted = generator.generate(SEED)
	var placer: RefCounted = PropPlacer.new()
	return [map, placer.place(map, SEED)]


func test_cover_props_yield_nothing() -> void:
	# Cover is worth something for standing under, not for taking apart.
	for kind in PropKind.COVER:
		assert_eq(PropKind.yield_of(kind), PropKind.Yield.NONE,
				"%s should not be harvestable" % PropKind.name_of(kind))
		assert_true(PropKind.is_cover(kind))
	for kind in PropKind.HARVESTABLE:
		assert_false(PropKind.is_cover(kind),
				"%s is not cover" % PropKind.name_of(kind))


func test_all_cover_kinds_are_placed_somewhere() -> void:
	var result := _place()
	var seen := {}
	for placement in result[1]:
		seen[placement["kind"]] = true
	for kind in PropKind.COVER:
		assert_true(seen.has(kind),
				"no %s was placed anywhere" % PropKind.name_of(kind))


func test_overhangs_and_caves_only_appear_on_mountain_hillsides() -> void:
	# They need a slope face to sit against, so a flat plateau is not eligible.
	var result := _place()
	var map: RefCounted = result[0]
	var wrong_biome := 0
	var flat := 0
	for placement in result[1]:
		var kind: int = placement["kind"]
		if kind != PropKind.Kind.OVERHANG and kind != PropKind.Kind.CAVE_MOUTH:
			continue
		var cell: Vector2i = placement["cell"]
		if map.biome_at_cell(cell.x, cell.y) != Biome.Kind.MOUNTAINS:
			wrong_biome += 1
		var here: int = map.height_at_cell(cell.x, cell.y)
		var drop := 0
		for offset in [Vector2i(-1, 0), Vector2i(1, 0),
				Vector2i(0, -1), Vector2i(0, 1)]:
			drop = maxi(drop, here - map.height_at_cell(cell.x + offset.x,
					cell.y + offset.y))
		if drop < PropPlacer.HILLSIDE_DROP_M:
			flat += 1
	assert_eq(wrong_biome, 0, "overhangs and caves belong in the mountains")
	assert_eq(flat, 0, "overhangs and caves need a slope face to sit against")


func test_thickets_only_appear_in_forest() -> void:
	var result := _place()
	var map: RefCounted = result[0]
	var wrong := 0
	for placement in result[1]:
		if placement["kind"] != PropKind.Kind.THICKET:
			continue
		var cell: Vector2i = placement["cell"]
		if map.biome_at_cell(cell.x, cell.y) != Biome.Kind.FOREST:
			wrong += 1
	assert_eq(wrong, 0, "thickets are a forest feature")


func test_cover_is_rarer_than_harvestable_props() -> void:
	# Shelter should be somewhere the player heads for, not somewhere they always are.
	var result := _place()
	var cover := 0
	var harvestable := 0
	for placement in result[1]:
		if PropKind.is_cover(placement["kind"]):
			cover += 1
		else:
			harvestable += 1
	assert_true(cover > 0, "there must be some shelter on the island")
	assert_true(cover < harvestable, "cover should be the rarer kind")


func test_cover_placement_is_deterministic() -> void:
	var generator: RefCounted = IslandGenerator.new()
	var map: RefCounted = generator.generate(SEED)
	var placer: RefCounted = PropPlacer.new()
	var a: Array = placer.place(map, SEED)
	var b: Array = placer.place(map, SEED)
	var cover_a := 0
	var cover_b := 0
	for p in a:
		if PropKind.is_cover(p["kind"]):
			cover_a += 1
	for p in b:
		if PropKind.is_cover(p["kind"]):
			cover_b += 1
	assert_eq(cover_a, cover_b)
