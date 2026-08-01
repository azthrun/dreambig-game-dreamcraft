extends "res://tests/test_case.gd"
## Tests what supply caches contain: the table's rarity, and that a crate is the same
## crate on every visit.

const CacheLoot := preload("res://scripts/world/props/cache_loot.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")
const RecipeBook := preload("res://scripts/items/recipe_book.gd")

const SEED := 20260729
const SAMPLES := 4000


## Everything drawn across many caches, as item to total count.
func _sample(count: int = SAMPLES) -> Dictionary:
	var totals := {}
	for id in count:
		var contents: Dictionary = CacheLoot.roll(SEED, id)
		for item in contents:
			totals[item] = int(totals.get(item, 0)) + int(contents[item])
	return totals


## How many of `count` caches held at least one of an item.
func _caches_holding(item: int, count: int = SAMPLES) -> int:
	var found := 0
	for id in count:
		if CacheLoot.roll(SEED, id).has(item):
			found += 1
	return found


func test_a_cache_is_never_empty() -> void:
	# Opening a crate and finding nothing would read as a bug, not as bad luck.
	for id in 200:
		var contents: Dictionary = CacheLoot.roll(SEED, id)
		assert_false(contents.is_empty(), "cache %d held nothing" % id)


func test_the_same_cache_holds_the_same_thing_every_time() -> void:
	# What makes it safe for a save file to record only which caches were opened: the
	# contents can always be re-derived rather than stored.
	for id in [0, 7, 4211, 99999]:
		assert_eq(CacheLoot.roll(SEED, id), CacheLoot.roll(SEED, id))


func test_two_caches_hold_different_things() -> void:
	var distinct := {}
	for id in 60:
		distinct[str(CacheLoot.roll(SEED, id))] = true
	assert_true(distinct.size() > 20,
			"60 caches produced only %d distinct hauls" % distinct.size())


func test_a_different_island_stocks_its_caches_differently() -> void:
	var same := 0
	for id in 100:
		if CacheLoot.roll(SEED, id) == CacheLoot.roll(SEED + 1, id):
			same += 1
	assert_true(same < 20, "%d of 100 caches were identical across seeds" % same)


func test_neighbouring_caches_are_not_near_identical() -> void:
	# Cache ids come from grid cells, so ids 100 and 101 are crates that could be in
	# sight of each other. Seeding by addition would give them adjacent streams.
	var same := 0
	for id in range(0, 200, 2):
		if CacheLoot.roll(SEED, id) == CacheLoot.roll(SEED, id + 1):
			same += 1
	assert_true(same < 10, "%d neighbouring pairs matched" % same)


func test_gadgets_are_rare_and_supplies_are_common() -> void:
	# The order of the whole table, stated as one assertion chain: a pistol behind a
	# common roll would be found in the first hour.
	assert_true(CacheLoot.chance_of(ItemKind.Kind.PISTOL)
					< CacheLoot.chance_of(ItemKind.Kind.PISTOL_AMMO),
			"a pistol should be rarer than its ammunition")
	assert_true(CacheLoot.chance_of(ItemKind.Kind.PISTOL_AMMO)
					< CacheLoot.chance_of(ItemKind.Kind.WOOD),
			"ammunition should be rarer than scrap wood")
	assert_true(CacheLoot.chance_of(ItemKind.Kind.PISTOL) < 0.1,
			"a pistol should be well under one draw in ten")


func test_most_caches_are_a_consolation_rather_than_a_gadget() -> void:
	var with_pistol := _caches_holding(ItemKind.Kind.PISTOL)
	var share := float(with_pistol) / float(SAMPLES)
	assert_in_range(share, 0.02, 0.20,
			"pistols turned up in %.0f%% of caches" % (share * 100.0))


func test_ammunition_is_uncommon_but_findable() -> void:
	# Both halves. Ammunition that never appeared would make the pistol scenery;
	# ammunition in every crate would make it the answer to everything.
	var share := float(_caches_holding(ItemKind.Kind.PISTOL_AMMO)) / float(SAMPLES)
	assert_in_range(share, 0.05, 0.40,
			"ammunition turned up in %.0f%% of caches" % (share * 100.0))


func test_the_table_actually_produces_everything_it_lists() -> void:
	var totals := _sample()
	for entry in CacheLoot.TABLE:
		var item := int(entry["item"])
		assert_true(int(totals.get(item, 0)) > 0,
				"%s is in the table but was never drawn"
						% ItemKind.name_of(item))


func test_nothing_outside_the_table_ever_appears() -> void:
	var totals := _sample(300)
	for item in totals:
		assert_true(CacheLoot.weight_of(item) > 0.0,
				"%s came out of a cache but is not in the table"
						% ItemKind.name_of(item))


func test_ammunition_and_gadgets_cannot_be_crafted() -> void:
	# The central balancing decision in SPEC, pinned so a later recipe cannot quietly
	# undo it: found, or not had.
	for index in RecipeBook.count():
		var output := int(RecipeBook.recipe(index).get("output", ItemKind.Kind.NONE))
		assert_ne(output, ItemKind.Kind.PISTOL_AMMO,
				"there must be no recipe for ammunition")
		assert_ne(output, ItemKind.Kind.PISTOL)
		assert_ne(output, ItemKind.Kind.FUEL)
