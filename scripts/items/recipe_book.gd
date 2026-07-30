extends RefCounted
## What can be made, from what.
##
## Recipes are a data table, not code: adding one is a new entry, not a new branch. The
## crafting screen, the tests and any future progression all read the same table, so a
## recipe cannot exist in one place and not another.
##
## Pure. Crafting takes an inventory, checks it, and mutates it — no Node, no UI.

const ItemKind := preload("res://scripts/items/item_kind.gd")

## Each recipe: what it makes, how many, and what it costs.
##
## Costs are deliberately cheap. The friction in this game is meant to be the weather and
## the animals, not the accounting.
const RECIPES: Array[Dictionary] = [
	{
		"output": ItemKind.Kind.STONE_TOOL,
		"count": 1,
		"inputs": {ItemKind.Kind.WOOD: 2, ItemKind.Kind.STONE: 3},
	},
	{
		"output": ItemKind.Kind.CAMPFIRE,
		"count": 1,
		"inputs": {ItemKind.Kind.WOOD: 5, ItemKind.Kind.STONE: 2},
	},
	{
		## Needs hide, which only comes from hunting. It appears in the list from the
		## start on purpose: an unaffordable recipe is a signpost towards what to do next.
		"output": ItemKind.Kind.HIDE_ARMOUR,
		"count": 1,
		"inputs": {ItemKind.Kind.HIDE: 4, ItemKind.Kind.WOOD: 2},
	},
]


static func count() -> int:
	return RECIPES.size()


static func recipe(index: int) -> Dictionary:
	if index < 0 or index >= RECIPES.size():
		return {}
	return RECIPES[index]


## Human-readable "stone tool — 2 wood, 3 stone".
static func describe(index: int) -> String:
	var entry := recipe(index)
	if entry.is_empty():
		return ""
	var parts := PackedStringArray()
	for item in entry["inputs"]:
		parts.append("%d %s" % [int(entry["inputs"][item]),
				ItemKind.name_of(item)])
	var made := ItemKind.name_of(int(entry["output"]))
	var made_count := int(entry["count"])
	var prefix := made if made_count == 1 else "%s x%d" % [made, made_count]
	return "%s  <  %s" % [prefix, ", ".join(parts)]


## Whether the inventory holds every input.
static func has_inputs(inventory: RefCounted, index: int) -> bool:
	var entry := recipe(index)
	if entry.is_empty():
		return false
	for item in entry["inputs"]:
		if not inventory.has(item, int(entry["inputs"][item])):
			return false
	return true


## Whether the output would fit once the inputs are gone.
##
## Checked against the inventory as it will be, not as it is: consuming five wood frees a
## slot, and refusing the craft because that slot is not free yet would be wrong.
static func has_room_for_output(inventory: RefCounted, index: int) -> bool:
	var entry := recipe(index)
	if entry.is_empty():
		return false
	if inventory.room_for(int(entry["output"])) >= int(entry["count"]):
		return true
	# No room as things stand — but an input stack that empties frees its slot.
	for item in entry["inputs"]:
		if inventory.total_of(item) == int(entry["inputs"][item]):
			return true
	return false


static func can_craft(inventory: RefCounted, index: int) -> bool:
	return has_inputs(inventory, index) and has_room_for_output(inventory, index)


## Reason the craft is unavailable, for the screen to show. Empty when it is available.
static func blocked_reason(inventory: RefCounted, index: int) -> String:
	if not has_inputs(inventory, index):
		return "missing materials"
	if not has_room_for_output(inventory, index):
		return "no room"
	return ""


## Consumes the inputs and produces the output. Returns whether anything was made.
##
## All-or-nothing: inputs are only removed once the whole recipe is known to succeed, so a
## failed craft can never eat half the materials.
static func craft(inventory: RefCounted, index: int) -> bool:
	if not can_craft(inventory, index):
		return false

	var entry := recipe(index)
	for item in entry["inputs"]:
		inventory.remove(item, int(entry["inputs"][item]))

	var made: int = inventory.add(int(entry["output"]), int(entry["count"]))
	if made < int(entry["count"]):
		# Should be unreachable given has_room_for_output, but losing the output
		# silently would be worse than refunding it.
		for item in entry["inputs"]:
			inventory.add(item, int(entry["inputs"][item]))
		return false
	return true
