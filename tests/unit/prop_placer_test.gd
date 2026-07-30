extends "res://tests/test_case.gd"
## Tests prop placement: biome weighting, surface placement, and determinism.

const IslandGenerator := preload("res://scripts/world/island_generator.gd")
const PropPlacer := preload("res://scripts/world/props/prop_placer.gd")
const PropKind := preload("res://scripts/world/props/prop_kind.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

const SEED := 20260729


func _world() -> RefCounted:
	var generator: RefCounted = IslandGenerator.new()
	return generator.generate(SEED)


func _place(map: RefCounted, seed_value: int) -> Array:
	var placer: RefCounted = PropPlacer.new()
	return placer.place(map, seed_value)


func test_placement_is_deterministic_from_the_seed() -> void:
	# Props are reproduced from the seed rather than saved, so this is what makes a
	# save file able to store a seed instead of thousands of positions.
	var map := _world()
	var first := _place(map, SEED)
	var second := _place(map, SEED)
	assert_eq(first.size(), second.size())
	for i in first.size():
		assert_eq(first[i]["position"], second[i]["position"])
		assert_eq(first[i]["kind"], second[i]["kind"])


func test_different_seeds_place_props_differently() -> void:
	var map := _world()
	assert_ne(_place(map, SEED).size(), 0)
	var a := _place(map, SEED)
	var b := _place(map, SEED + 1)
	var same := 0
	for i in mini(a.size(), b.size()):
		if a[i]["position"] == b[i]["position"]:
			same += 1
	assert_true(same < mini(a.size(), b.size()),
			"a different seed should move at least some props")


func test_props_sit_exactly_on_the_terrace_surface() -> void:
	# Neither floating nor sunk: the prop root is its base, and the terrace top is a
	# whole number of metres, so Y must equal the cell height exactly.
	var map := _world()
	var offenders := 0
	for placement in _place(map, SEED):
		var position: Vector3 = placement["position"]
		var ground: int = map.height_at_world(position.x, position.z)
		if absf(position.y - float(ground)) > 0.001:
			offenders += 1
	assert_eq(offenders, 0, "every prop should rest on its own cell's surface")


func test_no_props_are_placed_in_the_ocean() -> void:
	var map := _world()
	var wet := 0
	for placement in _place(map, SEED):
		var cell: Vector2i = placement["cell"]
		if map.biome_at_cell(cell.x, cell.y) == Biome.Kind.OCEAN:
			wet += 1
	assert_eq(wet, 0, "props must not spawn underwater")


func test_trees_are_dense_in_forest_and_sparse_in_plains() -> void:
	# The clearest ground-level difference between the two biomes.
	var map := _world()
	var forest_trees := 0
	var plains_trees := 0
	var forest_cells := 0
	var plains_cells := 0

	for placement in _place(map, SEED):
		if placement["kind"] != PropKind.Kind.TREE:
			continue
		var cell: Vector2i = placement["cell"]
		match map.biome_at_cell(cell.x, cell.y):
			Biome.Kind.FOREST:
				forest_trees += 1
			Biome.Kind.PLAINS:
				plains_trees += 1

	var counts: Dictionary = map.biome_counts()
	forest_cells = int(counts.get(Biome.Kind.FOREST, 0))
	plains_cells = int(counts.get(Biome.Kind.PLAINS, 0))
	assert_true(forest_cells > 0 and plains_cells > 0)

	var forest_density := float(forest_trees) / float(forest_cells)
	var plains_density := float(plains_trees) / float(plains_cells)
	assert_true(forest_trees > 0, "forest should have trees")
	assert_true(forest_density > plains_density * 4.0,
			"forest should be markedly denser than plains (%f vs %f)"
					% [forest_density, plains_density])


func test_no_trees_grow_above_the_treeline() -> void:
	# A visible treeline is what makes high ground read as bare rock.
	var map := _world()
	var too_high := 0
	for placement in _place(map, SEED):
		if placement["kind"] != PropKind.Kind.TREE:
			continue
		var cell: Vector2i = placement["cell"]
		if map.height_at_cell(cell.x, cell.y) > PropPlacer.TREELINE_M:
			too_high += 1
	assert_eq(too_high, 0, "trees must stop at the treeline")


func test_every_kind_appears_somewhere() -> void:
	var map := _world()
	var seen := {}
	for placement in _place(map, SEED):
		seen[placement["kind"]] = true
	for kind in PropKind.ALL:
		assert_true(seen.has(kind),
				"no %s was placed anywhere" % PropKind.name_of(kind))


func test_each_kind_declares_what_it_yields() -> void:
	# Harvesting reads the yield from the kind, so no harvestable may be worthless.
	for kind in PropKind.HARVESTABLE:
		var resource: int = PropKind.yield_of(kind)
		assert_ne(resource, PropKind.Yield.NONE,
				"%s yields nothing" % PropKind.name_of(kind))
		assert_ne(PropKind.yield_name(resource), "none")
	assert_eq(PropKind.yield_of(PropKind.Kind.TREE), PropKind.Yield.WOOD)
	assert_eq(PropKind.yield_of(PropKind.Kind.ROCK_OUTCROP), PropKind.Yield.STONE)
	assert_eq(PropKind.yield_of(PropKind.Kind.BERRY_BUSH), PropKind.Yield.BERRIES)


func test_bushes_do_not_block_movement_but_trunks_do() -> void:
	assert_true(PropKind.is_solid(PropKind.Kind.TREE))
	assert_true(PropKind.is_solid(PropKind.Kind.ROCK_OUTCROP))
	assert_false(PropKind.is_solid(PropKind.Kind.BERRY_BUSH),
			"being blocked by a berry bush would be annoying, not realistic")
