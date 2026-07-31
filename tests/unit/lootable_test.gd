extends "res://tests/test_case.gd"
## Tests corpse loot: drop tables, partial pickup, and refusal.

const Lootable := preload("res://scripts/creatures/lootable.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")
const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")

var _made: Array[Node] = []


func after_each() -> void:
	for node in _made:
		if is_instance_valid(node):
			node.free()
	_made.clear()


func _corpse(drops: Dictionary) -> Node:
	var loot: Node = Lootable.new()
	loot.configure(drops)
	_made.append(loot)
	return loot


func test_a_fresh_corpse_can_be_looted() -> void:
	var corpse := _corpse({ItemKind.Kind.RAW_MEAT: 2})
	assert_true(corpse.can_loot())
	assert_eq(corpse.remaining_count(), 2)


func test_looting_moves_everything_into_the_inventory() -> void:
	var corpse := _corpse({ItemKind.Kind.RAW_MEAT: 2, ItemKind.Kind.HIDE: 1})
	var inventory: RefCounted = Inventory.new()
	var taken: Dictionary = corpse.loot(inventory)
	assert_eq(inventory.total_of(ItemKind.Kind.RAW_MEAT), 2)
	assert_eq(inventory.total_of(ItemKind.Kind.HIDE), 1)
	assert_eq(int(taken[ItemKind.Kind.RAW_MEAT]), 2)
	assert_false(corpse.can_loot(), "a picked-clean corpse offers nothing")


func test_a_full_inventory_leaves_the_corpse_intact() -> void:
	# The kill must not be lost because the bag was full: the player can drop something
	# and come back.
	var corpse := _corpse({ItemKind.Kind.RAW_MEAT: 2})
	var inventory: RefCounted = Inventory.new(1)
	inventory.add(ItemKind.Kind.STONE, ItemKind.stack_limit(ItemKind.Kind.STONE))
	assert_true(inventory.is_full())

	var taken: Dictionary = corpse.loot(inventory)
	assert_true(taken.is_empty())
	assert_true(corpse.can_loot(), "nothing taken, so nothing lost")
	assert_eq(corpse.remaining_count(), 2)


func test_partial_looting_keeps_the_remainder() -> void:
	var corpse := _corpse({ItemKind.Kind.RAW_MEAT: 5})
	var inventory: RefCounted = Inventory.new(1)
	# Room for only part of the stack.
	inventory.add(ItemKind.Kind.RAW_MEAT,
			ItemKind.stack_limit(ItemKind.Kind.RAW_MEAT) - 2)

	var taken: Dictionary = corpse.loot(inventory)
	assert_eq(int(taken.get(ItemKind.Kind.RAW_MEAT, 0)), 2)
	assert_eq(corpse.remaining_count(), 3, "the rest stays on the corpse")
	assert_true(corpse.can_loot())


func test_being_emptied_is_announced() -> void:
	var corpse := _corpse({ItemKind.Kind.HIDE: 1})
	var seen := [false]
	corpse.looted.connect(func(): seen[0] = true)
	corpse.loot(Inventory.new())
	assert_true(seen[0])


func test_a_corpse_names_something_for_the_prompt() -> void:
	var corpse := _corpse({ItemKind.Kind.RAW_MEAT: 1})
	assert_ne(corpse.headline_item(), ItemKind.Kind.NONE)
	assert_eq(ItemKind.name_of(corpse.headline_item()), "raw meat")


func test_deer_drops_come_from_the_species_table() -> void:
	# Drop tables are data per species, so a new animal needs no new looting code.
	var drops: Dictionary = CreatureKind.drops(CreatureKind.Kind.DEER)
	var corpse := _corpse(drops)
	var inventory: RefCounted = Inventory.new()
	corpse.loot(inventory)
	assert_true(inventory.total_of(ItemKind.Kind.RAW_MEAT) > 0)
	assert_true(inventory.total_of(ItemKind.Kind.HIDE) > 0)


func test_looting_a_corpse_does_not_mutate_the_species_table() -> void:
	# The drop table is shared by every animal of that species; consuming it once must
	# not empty it for all of them.
	var before: Dictionary = CreatureKind.drops(CreatureKind.Kind.DEER).duplicate()
	var corpse := _corpse(CreatureKind.drops(CreatureKind.Kind.DEER))
	corpse.loot(Inventory.new())
	assert_eq(CreatureKind.drops(CreatureKind.Kind.DEER), before,
			"the species table must be unchanged after a kill is looted")


func test_a_stone_tool_hits_harder_than_a_fist() -> void:
	assert_true(ItemKind.is_weapon(ItemKind.Kind.STONE_TOOL))
	assert_true(ItemKind.melee_damage(ItemKind.Kind.STONE_TOOL)
			> ItemKind.BARE_HAND_DAMAGE)
	assert_false(ItemKind.is_weapon(ItemKind.Kind.WOOD),
			"carrying a log is not carrying a weapon")
	assert_almost_eq(ItemKind.melee_damage(ItemKind.Kind.WOOD),
			ItemKind.BARE_HAND_DAMAGE, 0.001)


func test_bare_hands_can_still_kill_a_deer() -> void:
	# The game has to be playable before the first craft.
	var swings := CreatureKind.health(CreatureKind.Kind.DEER) \
			/ ItemKind.BARE_HAND_DAMAGE
	assert_true(swings > 3.0, "a fist should not one-shot an animal")
	assert_true(swings <= 12.0,
			"but it should not take forever either, needs %.0f swings" % swings)
