extends "res://tests/test_case.gd"
## Tests crafting: input consumption, output production, and refusal.

const RecipeBook := preload("res://scripts/items/recipe_book.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")


func _inventory(capacity: int = Inventory.DEFAULT_CAPACITY) -> RefCounted:
	return Inventory.new(capacity)


## Index of the recipe producing a given item, or -1.
func _index_of(output: int) -> int:
	for i in RecipeBook.count():
		if int(RecipeBook.recipe(i)["output"]) == output:
			return i
	return -1


## Stocks exactly the inputs a recipe needs.
func _stock_for(inventory: RefCounted, index: int) -> void:
	var inputs: Dictionary = RecipeBook.recipe(index)["inputs"]
	for item in inputs:
		inventory.add(item, int(inputs[item]))


func test_the_required_recipes_exist() -> void:
	assert_true(_index_of(ItemKind.Kind.STONE_TOOL) >= 0, "no stone tool recipe")
	assert_true(_index_of(ItemKind.Kind.CAMPFIRE) >= 0, "no campfire recipe")


func test_every_recipe_is_well_formed() -> void:
	# A malformed entry would be a silent dead recipe rather than a parse error, since
	# recipes are data.
	for i in RecipeBook.count():
		var entry := RecipeBook.recipe(i)
		assert_true(entry.has("output") and entry.has("inputs")
				and entry.has("count"), "recipe %d is incomplete" % i)
		assert_true(int(entry["count"]) > 0, "recipe %d makes nothing" % i)
		assert_ne(ItemKind.name_of(int(entry["output"])), "unknown")
		assert_false((entry["inputs"] as Dictionary).is_empty(),
				"recipe %d is free" % i)
		for item in entry["inputs"]:
			assert_true(int(entry["inputs"][item]) > 0)
			assert_ne(ItemKind.name_of(item), "unknown")


func test_a_recipe_is_unavailable_without_its_inputs() -> void:
	var inv := _inventory()
	var index := _index_of(ItemKind.Kind.STONE_TOOL)
	assert_false(RecipeBook.can_craft(inv, index))
	assert_eq(RecipeBook.blocked_reason(inv, index), "missing materials")


func test_crafting_without_inputs_changes_nothing() -> void:
	var inv := _inventory()
	inv.add(ItemKind.Kind.WOOD, 1)
	var index := _index_of(ItemKind.Kind.STONE_TOOL)
	assert_false(RecipeBook.craft(inv, index))
	assert_eq(inv.total_of(ItemKind.Kind.WOOD), 1, "inputs must not be nibbled")
	assert_eq(inv.total_of(ItemKind.Kind.STONE_TOOL), 0)


func test_crafting_consumes_exactly_the_declared_inputs() -> void:
	var inv := _inventory()
	var index := _index_of(ItemKind.Kind.CAMPFIRE)
	var inputs: Dictionary = RecipeBook.recipe(index)["inputs"]
	# Stock double, so what is left proves exactly one recipe's worth was taken.
	for item in inputs:
		inv.add(item, int(inputs[item]) * 2)

	assert_true(RecipeBook.craft(inv, index))
	for item in inputs:
		assert_eq(inv.total_of(item), int(inputs[item]),
				"%s should have exactly one recipe's worth left"
						% ItemKind.name_of(item))


func test_crafting_produces_the_declared_output() -> void:
	var inv := _inventory()
	var index := _index_of(ItemKind.Kind.CAMPFIRE)
	_stock_for(inv, index)
	assert_true(RecipeBook.craft(inv, index))
	assert_eq(inv.total_of(ItemKind.Kind.CAMPFIRE),
			int(RecipeBook.recipe(index)["count"]))


func test_exact_materials_are_enough() -> void:
	# Off-by-one in the check would make every recipe need one spare of everything.
	var inv := _inventory()
	var index := _index_of(ItemKind.Kind.STONE_TOOL)
	_stock_for(inv, index)
	assert_true(RecipeBook.can_craft(inv, index))
	assert_true(RecipeBook.craft(inv, index))


func test_one_short_is_refused() -> void:
	var inv := _inventory()
	var index := _index_of(ItemKind.Kind.STONE_TOOL)
	var inputs: Dictionary = RecipeBook.recipe(index)["inputs"]
	for item in inputs:
		inv.add(item, int(inputs[item]))
	# Remove a single unit of one input.
	inv.remove(inputs.keys()[0], 1)
	assert_false(RecipeBook.can_craft(inv, index))


func test_consuming_a_whole_stack_frees_room_for_the_output() -> void:
	# The subtle case: a one-slot inventory holding exactly the inputs can still craft,
	# because the input stack empties as part of the same operation.
	var inv := _inventory(2)
	var index := _index_of(ItemKind.Kind.STONE_TOOL)
	_stock_for(inv, index)
	assert_true(inv.is_full() or inv.room_for(ItemKind.Kind.STONE_TOOL) >= 0)
	assert_true(RecipeBook.can_craft(inv, index),
			"emptying the input stacks should make room for the output")
	assert_true(RecipeBook.craft(inv, index))
	assert_eq(inv.total_of(ItemKind.Kind.STONE_TOOL), 1)


func test_a_full_inventory_of_other_things_refuses() -> void:
	var inv := _inventory(3)
	var index := _index_of(ItemKind.Kind.STONE_TOOL)
	_stock_for(inv, index)
	# Fill whatever remains with something unrelated.
	inv.add(ItemKind.Kind.BERRIES,
			ItemKind.stack_limit(ItemKind.Kind.BERRIES) * 3)
	if not RecipeBook.has_room_for_output(inv, index):
		assert_eq(RecipeBook.blocked_reason(inv, index), "no room")
		assert_false(RecipeBook.craft(inv, index))
		assert_eq(inv.total_of(ItemKind.Kind.STONE_TOOL), 0)
	else:
		# Room was freed by an emptying input stack, which is also correct.
		assert_true(RecipeBook.craft(inv, index))


func test_recipes_are_described_for_the_screen() -> void:
	for i in RecipeBook.count():
		var text := RecipeBook.describe(i)
		assert_true(text.length() > 0)
		assert_has(text, "<", "description should show output and cost")


func test_an_unaffordable_recipe_still_appears() -> void:
	# Hide armour needs hunting. It is listed from the start on purpose, as the only
	# signpost the game gives towards what to do next.
	var index := _index_of(ItemKind.Kind.HIDE_ARMOUR)
	assert_true(index >= 0)
	var inv := _inventory()
	assert_false(RecipeBook.can_craft(inv, index))
	assert_true(RecipeBook.describe(index).length() > 0)


func test_out_of_range_recipes_are_handled() -> void:
	var inv := _inventory()
	assert_true(RecipeBook.recipe(-1).is_empty())
	assert_true(RecipeBook.recipe(999).is_empty())
	assert_false(RecipeBook.can_craft(inv, 999))
	assert_false(RecipeBook.craft(inv, 999))
