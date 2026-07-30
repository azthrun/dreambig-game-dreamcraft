extends "res://tests/test_case.gd"
## Tests the inventory: capacity, stacking, refusal, and hotbar selection.

const Inventory := preload("res://scripts/items/inventory.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")

const WOOD := ItemKind.Kind.WOOD
const STONE := ItemKind.Kind.STONE
const TOOL := ItemKind.Kind.STONE_TOOL


func _inventory(capacity: int = Inventory.DEFAULT_CAPACITY) -> RefCounted:
	return Inventory.new(capacity)


func test_starts_empty() -> void:
	var inv := _inventory()
	assert_eq(inv.total_of(WOOD), 0)
	assert_false(inv.is_full())
	for slot in inv.capacity():
		assert_true(inv.is_slot_empty(slot))


func test_adding_reports_how_many_were_taken() -> void:
	var inv := _inventory()
	assert_eq(inv.add(WOOD, 5), 5)
	assert_eq(inv.total_of(WOOD), 5)


func test_identical_items_stack_up_to_their_limit() -> void:
	var inv := _inventory()
	var limit: int = ItemKind.stack_limit(WOOD)
	inv.add(WOOD, limit)
	# One full stack occupies exactly one slot.
	var used := 0
	for slot in inv.capacity():
		if not inv.is_slot_empty(slot):
			used += 1
	assert_eq(used, 1, "a full stack should occupy one slot")
	assert_eq(inv.count_in_slot(0), limit)


func test_exceeding_a_stack_opens_another_slot() -> void:
	var inv := _inventory()
	var limit: int = ItemKind.stack_limit(WOOD)
	inv.add(WOOD, limit + 1)
	assert_eq(inv.total_of(WOOD), limit + 1)
	assert_eq(inv.count_in_slot(0), limit)
	assert_eq(inv.count_in_slot(1), 1)


func test_adding_tops_up_partial_stacks_before_opening_slots() -> void:
	# Otherwise the same item ends up spread across half-full slots while the inventory
	# reports itself full.
	var inv := _inventory()
	inv.add(WOOD, 5)
	inv.add(WOOD, 5)
	var used := 0
	for slot in inv.capacity():
		if not inv.is_slot_empty(slot):
			used += 1
	assert_eq(used, 1, "ten wood should still be one stack")
	assert_eq(inv.total_of(WOOD), 10)


func test_items_that_do_not_stack_take_a_slot_each() -> void:
	var inv := _inventory()
	assert_eq(ItemKind.stack_limit(TOOL), 1)
	inv.add(TOOL, 3)
	assert_eq(inv.count_in_slot(0), 1)
	assert_eq(inv.count_in_slot(1), 1)
	assert_eq(inv.count_in_slot(2), 1)


func test_a_full_inventory_refuses_rather_than_discarding() -> void:
	# The heart of the ticket: a harvest that cannot fit must be told so, or the
	# resource vanishes from the world for nothing.
	var inv := _inventory(2)
	var limit: int = ItemKind.stack_limit(WOOD)
	assert_eq(inv.add(WOOD, limit * 2), limit * 2)
	assert_true(inv.is_full())
	assert_eq(inv.add(WOOD, 5), 0, "a full inventory should take nothing")
	assert_eq(inv.total_of(WOOD), limit * 2, "and lose nothing")


func test_partial_success_is_reported_honestly() -> void:
	var inv := _inventory(1)
	var limit: int = ItemKind.stack_limit(WOOD)
	assert_eq(inv.add(WOOD, limit + 10), limit,
			"should take what fits and report exactly that")
	assert_eq(inv.total_of(WOOD), limit)


func test_room_for_matches_what_add_will_accept() -> void:
	# Callers check room before acting; the two must agree or the check is useless.
	var inv := _inventory(3)
	inv.add(WOOD, 5)
	var room: int = inv.room_for(WOOD)
	assert_eq(inv.add(WOOD, 9999), room)
	assert_eq(inv.room_for(WOOD), 0)


func test_a_full_inventory_of_one_item_still_has_no_room_for_another() -> void:
	var inv := _inventory(1)
	inv.add(WOOD, ItemKind.stack_limit(WOOD))
	assert_eq(inv.room_for(STONE), 0)
	assert_eq(inv.add(STONE, 1), 0)


func test_removing_reports_how_many_were_taken() -> void:
	var inv := _inventory()
	inv.add(WOOD, 10)
	assert_eq(inv.remove(WOOD, 4), 4)
	assert_eq(inv.total_of(WOOD), 6)


func test_removing_more_than_held_takes_only_what_is_there() -> void:
	var inv := _inventory()
	inv.add(WOOD, 3)
	assert_eq(inv.remove(WOOD, 10), 3)
	assert_eq(inv.total_of(WOOD), 0)


func test_emptying_a_stack_frees_its_slot() -> void:
	var inv := _inventory()
	inv.add(WOOD, 2)
	inv.remove(WOOD, 2)
	assert_true(inv.is_slot_empty(0), "an emptied slot should be reusable")
	assert_eq(inv.add(STONE, 1), 1)


func test_has_answers_against_the_total_not_a_single_stack() -> void:
	var inv := _inventory()
	var limit: int = ItemKind.stack_limit(WOOD)
	inv.add(WOOD, limit + 3)
	assert_true(inv.has(WOOD, limit + 1))
	assert_false(inv.has(WOOD, limit + 99))


func test_adding_nothing_or_a_null_item_does_nothing() -> void:
	var inv := _inventory()
	assert_eq(inv.add(ItemKind.Kind.NONE, 5), 0)
	assert_eq(inv.add(WOOD, 0), 0)
	assert_eq(inv.add(WOOD, -3), 0)
	assert_true(inv.is_slot_empty(0))


func test_hotbar_selection_starts_at_the_first_slot() -> void:
	assert_eq(_inventory().selected_slot(), 0)


func test_number_keys_select_a_slot_directly() -> void:
	var inv := _inventory()
	inv.select(3)
	assert_eq(inv.selected_slot(), 3)


func test_selection_is_confined_to_the_hotbar() -> void:
	var inv := _inventory()
	inv.select(Inventory.HOTBAR_SLOTS + 4)
	assert_eq(inv.selected_slot(), 0, "cannot select a slot off the hotbar")
	inv.select(-1)
	assert_eq(inv.selected_slot(), 0)


func test_cycling_wraps_around_the_hotbar() -> void:
	# The scroll wheel has no ends, so the selection must not stop at one either.
	var inv := _inventory()
	inv.cycle_selection(-1)
	assert_eq(inv.selected_slot(), Inventory.HOTBAR_SLOTS - 1,
			"scrolling back from the first slot should wrap to the last")
	inv.cycle_selection(1)
	assert_eq(inv.selected_slot(), 0)


func test_the_selected_item_is_queryable() -> void:
	# Other systems ask what is in hand rather than reaching into slots themselves.
	var inv := _inventory()
	inv.add(WOOD, 1)
	assert_eq(inv.selected_item(), WOOD)
	inv.select(2)
	assert_eq(inv.selected_item(), ItemKind.Kind.NONE)


func test_removing_from_a_slot_takes_from_that_stack_only() -> void:
	var inv := _inventory()
	inv.add(TOOL, 2)
	assert_eq(inv.remove_from_slot(1, 1), 1)
	assert_eq(inv.item_in_slot(0), TOOL, "the other stack is untouched")
	assert_true(inv.is_slot_empty(1))


func test_changes_are_announced() -> void:
	# The HUD reacts rather than polling.
	var inv := _inventory()
	var seen := [0]
	inv.changed.connect(func(): seen[0] += 1)
	inv.add(WOOD, 1)
	inv.remove(WOOD, 1)
	assert_eq(seen[0], 2)


func test_no_change_is_announced_when_nothing_happened() -> void:
	var inv := _inventory(1)
	inv.add(WOOD, ItemKind.stack_limit(WOOD))
	var seen := [0]
	inv.changed.connect(func(): seen[0] += 1)
	inv.add(WOOD, 5)
	inv.remove(STONE, 5)
	assert_eq(seen[0], 0, "a refused action is not a change")


func test_every_item_is_named_and_stacks_sensibly() -> void:
	for item in ItemKind.ALL:
		assert_ne(ItemKind.name_of(item), "unknown",
				"item %d has no name" % item)
		assert_true(ItemKind.stack_limit(item) >= 1,
				"%s must fit in a slot" % ItemKind.name_of(item))
	assert_eq(ItemKind.name_of(ItemKind.Kind.NONE), "empty")
	assert_eq(ItemKind.stack_limit(ItemKind.Kind.NONE), 0)


func test_food_is_marked_and_cooking_is_worth_it() -> void:
	assert_true(ItemKind.is_food(ItemKind.Kind.BERRIES))
	assert_true(ItemKind.is_food(ItemKind.Kind.RAW_MEAT))
	assert_false(ItemKind.is_food(WOOD))
	assert_true(
			ItemKind.nutrition(ItemKind.Kind.COOKED_MEAT)
					> ItemKind.nutrition(ItemKind.Kind.RAW_MEAT),
			"cooking must be worth the fire it costs")
	assert_true(
			ItemKind.nutrition(ItemKind.Kind.BERRIES)
					< ItemKind.nutrition(ItemKind.Kind.RAW_MEAT),
			"berries should not compete with hunting")
