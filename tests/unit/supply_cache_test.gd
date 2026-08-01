extends "res://tests/test_case.gd"
## Tests the crate itself: opening it, it staying open, and it coming back.

const SupplyCache := preload("res://scripts/world/props/supply_cache.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")

const SEED := 4242

var _made: Array[Node] = []


func after_each() -> void:
	for node in _made:
		if is_instance_valid(node):
			node.free()
	_made.clear()


func _cache(cache_id: int = 1) -> Node:
	var cache: Node = SupplyCache.new()
	cache.configure_cache(SEED, cache_id)
	_made.append(cache)
	return cache


## A cache holding exactly what the test wants, for cases where the roll is noise.
func _stocked(contents: Dictionary) -> Node:
	var cache: Node = SupplyCache.new()
	cache.configure_cache(SEED, 1)
	cache.configure(contents)
	_made.append(cache)
	return cache


func test_a_fresh_cache_can_be_opened() -> void:
	var cache := _cache()
	assert_true(cache.can_loot())
	assert_false(cache.is_looted())
	assert_true(cache.remaining_count() > 0)


func test_opening_a_cache_fills_the_inventory_and_marks_it_looted() -> void:
	var cache := _cache()
	var inventory: RefCounted = Inventory.new()
	var taken: Dictionary = cache.loot(inventory)

	assert_false(taken.is_empty())
	assert_true(cache.is_looted(), "an emptied crate has to stay emptied")
	assert_false(cache.can_loot())
	assert_almost_eq(cache.time_until_refill(), SupplyCache.RESPAWN_SECONDS, 0.001)


func test_a_looted_cache_gives_nothing_on_a_second_visit() -> void:
	# Otherwise a player could stand at one crate and empty it repeatedly, which is
	# exactly the ammunition farm the design forbids.
	var cache := _cache()
	cache.loot(Inventory.new())
	var inventory: RefCounted = Inventory.new()
	assert_true(cache.loot(inventory).is_empty())
	assert_eq(inventory.total_of(ItemKind.Kind.PISTOL_AMMO), 0)


func test_a_crate_the_player_had_no_room_for_is_not_marked_looted() -> void:
	# Same rule as a corpse: arriving full costs you the trip, not the supplies.
	var cache := _stocked({ItemKind.Kind.WOOD: 6})
	var full: RefCounted = Inventory.new(1)
	full.add(ItemKind.Kind.STONE, ItemKind.stack_limit(ItemKind.Kind.STONE))

	assert_true(cache.loot(full).is_empty())
	assert_false(cache.is_looted(), "nothing was taken, so nothing was opened")
	assert_true(cache.can_loot())


func test_a_partly_emptied_crate_keeps_the_rest() -> void:
	var cache := _stocked({ItemKind.Kind.WOOD: 40, ItemKind.Kind.STONE: 5})
	var small: RefCounted = Inventory.new(1)

	cache.loot(small)
	assert_true(cache.remaining_count() > 0, "the rest stays in the crate")
	assert_false(cache.is_looted(), "and it has not started refilling yet")
	assert_true(cache.can_loot())


func test_a_cache_refills_only_after_a_long_wait() -> void:
	# Both halves of the gate. The interval is the thing stopping ammunition being a
	# renewable resource, so a test that only proved it comes back would prove the
	# wrong half.
	var cache := _cache()
	cache.loot(Inventory.new())

	cache.tick(SupplyCache.RESPAWN_SECONDS * 0.9)
	assert_true(cache.is_looted(), "still empty most of the way through the wait")
	assert_false(cache.can_loot())

	cache.tick(SupplyCache.RESPAWN_SECONDS * 0.2)
	assert_false(cache.is_looted())
	assert_true(cache.can_loot(), "and stocked again once the interval passes")
	assert_true(cache.remaining_count() > 0)


func test_a_cache_refills_far_slower_than_a_berry_bush() -> void:
	const Harvestable := preload("res://scripts/world/props/harvestable.gd")
	var bush: Node = Harvestable.new()
	_made.append(bush)
	assert_true(SupplyCache.RESPAWN_SECONDS > bush.respawn_seconds * 4.0,
			"supplies must not come back on the same timescale as berries")


func test_a_refilled_cache_is_not_the_same_reward_again() -> void:
	# A known crate must not become a known reward, or the player farms the good one.
	var cache := _cache(17)
	var first: Dictionary = cache.contents.duplicate()
	cache.loot(Inventory.new())
	cache.tick(SupplyCache.RESPAWN_SECONDS + 1.0)
	assert_ne(cache.contents, first)


func test_a_refill_keeps_the_cache_id() -> void:
	# The id is what a save file keys on. If it changed on refill, a reloaded island
	# would have forgotten which crates had been opened.
	var cache := _cache(4211)
	cache.loot(Inventory.new())
	cache.tick(SupplyCache.RESPAWN_SECONDS + 1.0)
	assert_eq(cache.cache_id, 4211)


func test_a_looted_state_can_be_restored() -> void:
	# What loading a save will do: put the crate back into the state it was left in,
	# rather than handing the player its contents a second time.
	var cache := _cache()
	cache.restore_looted(120.0)
	assert_true(cache.is_looted())
	assert_false(cache.can_loot())
	assert_almost_eq(cache.time_until_refill(), 120.0, 0.001)
	assert_true(cache.loot(Inventory.new()).is_empty())

	cache.tick(121.0)
	assert_true(cache.can_loot(), "and it still refills on schedule afterwards")


func test_a_cache_is_looted_by_the_same_interaction_as_a_corpse() -> void:
	# It is named Lootable in the tree and answers the same calls, which is why caches
	# needed no new key, no new prompt and no second refusal path.
	var cache := _cache()
	for method in [&"loot", &"can_loot", &"headline_item", &"remaining_count"]:
		assert_true(cache.has_method(method), "missing %s" % method)
	assert_ne(cache.headline_item(), ItemKind.Kind.NONE)
