extends "res://tests/test_case.gd"
## Nest placement: mountain sites, kept in the northern half of the island, apart from
## each other, and reproducible from the seed.

const DragonNest := preload("res://scripts/world/dragon_nest.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

## Generous enough that two nests kept `DragonNest.MIN_SEPARATION_M` apart have real room
## to be found within a bounded number of attempts, rather than the test depending on a
## lucky roll.
const CELLS := 128
const CELL_SIZE := 4.0


## Land everywhere, mountains confined to the northern half so a placement outside it is
## unambiguously wrong rather than merely unlucky.
func _map() -> RefCounted:
	var map: RefCounted = Heightmap.new(CELLS, CELL_SIZE)
	for cz in CELLS:
		for cx in CELLS:
			map.set_height(cx, cz, 10)
			map.set_biome(cx, cz,
					Biome.Kind.MOUNTAINS if cz < CELLS / 2 else Biome.Kind.PLAINS)
	return map


func test_nests_land_only_on_mountains() -> void:
	var map := _map()
	var sites := DragonNest.sites(map, 1, 2)
	assert_eq(sites.size(), 2)
	for site in sites:
		var cell: Vector2i = map.world_to_cell(site.x, site.z)
		assert_eq(map.biome_at_cell(cell.x, cell.y), Biome.Kind.MOUNTAINS,
				"a nest landed off the mountains at %s" % site)


func test_nests_stay_in_the_northern_half() -> void:
	# North is -Z. A mountain range that also existed south of the midline would still
	# have to keep every nest in the north, so the map here puts mountains only north to
	# make a wrong placement unambiguous.
	var map := _map()
	var sites := DragonNest.sites(map, 2, 2)
	var half: float = map.size_m() * 0.5
	for site in sites:
		assert_true(site.z < 0.0,
				"a nest at %s is not in the northern half" % site)
		assert_true(site.z >= -half)


func test_nests_are_kept_apart() -> void:
	var map := _map()
	var sites := DragonNest.sites(map, 3, 2)
	if sites.size() < 2:
		fail("need at least two nests to test separation")
		return
	assert_true(sites[0].distance_to(sites[1]) >= DragonNest.MIN_SEPARATION_M,
			"two nests landed within %.0f m of each other"
					% sites[0].distance_to(sites[1]))


func test_no_land_gives_no_nests_rather_than_hanging() -> void:
	var map: RefCounted = Heightmap.new(CELLS, CELL_SIZE)
	for cz in CELLS:
		for cx in CELLS:
			map.set_height(cx, cz, 10)
			map.set_biome(cx, cz, Biome.Kind.OCEAN)
	var sites := DragonNest.sites(map, 4, 2)
	assert_eq(sites.size(), 0)


func test_zero_requested_gives_zero_nests() -> void:
	var sites := DragonNest.sites(_map(), 5, 0)
	assert_eq(sites.size(), 0)


func test_the_same_seed_nests_in_the_same_places() -> void:
	var map := _map()
	var first := DragonNest.sites(map, 2024, 2)
	var second := DragonNest.sites(map, 2024, 2)
	var third := DragonNest.sites(map, 9999, 2)
	assert_eq(first, second)
	assert_ne(first, third, "a different seed should nest somewhere different")
