extends RefCounted
## Every item the player can carry, and what each one is worth.
##
## One table, consulted by the inventory, the harvest interaction, crafting and eating —
## so an item's stack size or nutrition is stated once rather than re-decided at each
## place that handles it.
##
## Values are stored as ints in the inventory, so the order here becomes part of the save
## format once persistence exists: append, never reorder.

enum Kind {
	NONE,
	WOOD,
	STONE,
	BERRIES,
	RAW_MEAT,
	COOKED_MEAT,
	HIDE,
	STONE_TOOL,
	CAMPFIRE,
	HIDE_ARMOUR,
}

## Damage dealt swinging nothing at all. Enough to kill a deer eventually, so the game is
## playable before the first tool, and slow enough that the tool is worth making.
const BARE_HAND_DAMAGE := 4.0

## Per-item facts. `nutrition` is how much hunger eating it removes; zero means it is not
## food. `stack` is how many fit in one slot — bulky things stack less. `damage` is what
## swinging it does, absent meaning it is no better than a fist.
const ITEMS := {
	Kind.WOOD: {"name": "wood", "stack": 32, "nutrition": 0.0},
	Kind.STONE: {"name": "stone", "stack": 32, "nutrition": 0.0},
	Kind.BERRIES: {"name": "berries", "stack": 16, "nutrition": 6.0},
	## Deliberately poor food: berries keep you alive until you can hunt, and are not
	## meant to be a substitute for it.
	Kind.RAW_MEAT: {"name": "raw meat", "stack": 8, "nutrition": 10.0},
	Kind.COOKED_MEAT: {"name": "cooked meat", "stack": 8, "nutrition": 34.0},
	Kind.HIDE: {"name": "hide", "stack": 8, "nutrition": 0.0},
	Kind.STONE_TOOL: {
		"name": "stone tool", "stack": 1, "nutrition": 0.0, "damage": 13.0,
	},
	Kind.CAMPFIRE: {"name": "campfire", "stack": 4, "nutrition": 0.0},
	Kind.HIDE_ARMOUR: {"name": "hide armour", "stack": 1, "nutrition": 0.0},
}

const ALL: Array[int] = [
	Kind.WOOD,
	Kind.STONE,
	Kind.BERRIES,
	Kind.RAW_MEAT,
	Kind.COOKED_MEAT,
	Kind.HIDE,
	Kind.STONE_TOOL,
	Kind.CAMPFIRE,
	Kind.HIDE_ARMOUR,
]


static func name_of(item: int) -> String:
	if item == Kind.NONE:
		return "empty"
	var entry: Dictionary = ITEMS.get(item, {})
	return String(entry.get("name", "unknown"))


## How many of this item fit in one slot. Unknown items stack alone, which is the safe
## direction to be wrong in.
static func stack_limit(item: int) -> int:
	if item == Kind.NONE:
		return 0
	var entry: Dictionary = ITEMS.get(item, {})
	return int(entry.get("stack", 1))


static func nutrition(item: int) -> float:
	var entry: Dictionary = ITEMS.get(item, {})
	return float(entry.get("nutrition", 0.0))


static func is_food(item: int) -> bool:
	return nutrition(item) > 0.0


## What swinging this item does. Anything without a declared damage is a fist.
static func melee_damage(item: int) -> float:
	var entry: Dictionary = ITEMS.get(item, {})
	return float(entry.get("damage", BARE_HAND_DAMAGE))


## Whether the item is a better weapon than bare hands.
static func is_weapon(item: int) -> bool:
	return melee_damage(item) > BARE_HAND_DAMAGE
