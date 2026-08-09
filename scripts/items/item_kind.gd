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
	BURNT_MEAT,
	PISTOL,
	PISTOL_AMMO,
	FUEL,
	MACHINE_GUN,
	MACHINE_GUN_AMMO,
	FLYING_SUIT,
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
	## Edible, but it costs you: raw meat is what you eat when the alternative is
	## starving, not a substitute for building a fire.
	Kind.RAW_MEAT: {
		"name": "raw meat", "stack": 8, "nutrition": 10.0, "health_cost": 9.0,
	},
	Kind.COOKED_MEAT: {"name": "cooked meat", "stack": 8, "nutrition": 34.0},
	Kind.HIDE: {"name": "hide", "stack": 8, "nutrition": 0.0},
	Kind.STONE_TOOL: {
		"name": "stone tool", "stack": 1, "nutrition": 0.0, "damage": 13.0,
	},
	Kind.CAMPFIRE: {"name": "campfire", "stack": 4, "nutrition": 0.0},
	## Worn rather than carried. Insulation is degrees added to the temperature model, so
	## armour is a third answer to cold alongside shelter and fire.
	Kind.HIDE_ARMOUR: {
		"name": "hide armour", "stack": 1, "nutrition": 0.0, "insulation": 5.0,
	},
	## What happens when meat is left on the fire. Still edible, barely.
	Kind.BURNT_MEAT: {"name": "burnt meat", "stack": 8, "nutrition": 3.0},
	## Found, never crafted. `firearm` carries what firing costs and what a round does;
	## an item without that entry cannot be fired, which is what keeps the check in one
	## place rather than at every trigger pull.
	##
	## A round does rather more than a stone tool swing and reaches across a clearing,
	## which is the whole point of finding one — but there is no recipe for the bullets,
	## so it does not replace hunting with a club.
	Kind.PISTOL: {
		"name": "pistol", "stack": 1, "nutrition": 0.0,
		"firearm": {
			"ammo": Kind.PISTOL_AMMO,
			"damage": 34.0,
			"range_m": 60.0,
			"interval": 0.45,
			"recoil_degrees": 2.4,
		},
	},
	## Uncommon in caches and impossible to make. This is the balancing decision the
	## whole gadget tier rests on: a pistol with unlimited ammunition would make hunger,
	## warmth, armour and stalking irrelevant the moment it was found.
	Kind.PISTOL_AMMO: {"name": "pistol ammo", "stack": 24, "nutrition": 0.0},
	## For the flying suit, which arrives with its own ticket. Found here so the cache
	## table is the real one rather than one that has to be revisited.
	Kind.FUEL: {"name": "fuel", "stack": 8, "nutrition": 0.0},
	## The answer to the worst threats, not a replacement for the pistol: weaker per
	## round, shorter ranged, and only worth it because `automatic` lets the trigger
	## stay down. `automatic` is the one flag `firearm()`'s cadence check does not read
	## for itself — Firearm asks `ItemKind.is_automatic` before it lets holding the key
	## substitute for clicking it, so a pistol answers "no" without needing a value here.
	Kind.MACHINE_GUN: {
		"name": "machine gun", "stack": 1, "nutrition": 0.0,
		"firearm": {
			"ammo": Kind.MACHINE_GUN_AMMO,
			"damage": 11.0,
			"range_m": 45.0,
			"interval": 0.08,
			"recoil_degrees": 0.85,
			"automatic": true,
		},
	},
	## Rarer than pistol ammunition, which is the whole point: an automatic weapon with
	## as-common ammunition as a semi-automatic one would make the pistol pointless and
	## the machine gun a default rather than an emergency tool.
	Kind.MACHINE_GUN_AMMO: {
		"name": "machine-gun ammo", "stack": 40, "nutrition": 0.0,
	},
	## Rarer than either gun: see `flight_fuel.gd` for the tank it fills once equipped.
	## Equipping and refuelling are both the primary action, mirroring how armour is worn
	## and a fire is fed — one verb per item type, not a second key.
	Kind.FLYING_SUIT: {"name": "flying suit", "stack": 1, "nutrition": 0.0},
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
	Kind.BURNT_MEAT,
	Kind.PISTOL,
	Kind.PISTOL_AMMO,
	Kind.FUEL,
	Kind.MACHINE_GUN,
	Kind.MACHINE_GUN_AMMO,
	Kind.FLYING_SUIT,
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


## Health lost from eating this, if any. Raw meat is the only thing that costs anything.
static func health_cost(item: int) -> float:
	var entry: Dictionary = ITEMS.get(item, {})
	return float(entry.get("health_cost", 0.0))


## Degrees of warmth this adds while worn. Zero means it is not armour.
static func insulation(item: int) -> float:
	var entry: Dictionary = ITEMS.get(item, {})
	return float(entry.get("insulation", 0.0))


static func is_wearable(item: int) -> bool:
	return insulation(item) > 0.0


## Whether the item is a better weapon than bare hands.
static func is_weapon(item: int) -> bool:
	return melee_damage(item) > BARE_HAND_DAMAGE


## Firearm facts, or `{}` for anything that is not one. One entry decides whether an
## item can be fired at all, so nothing has to keep a list of guns.
static func firearm(item: int) -> Dictionary:
	var entry: Dictionary = ITEMS.get(item, {})
	return entry.get("firearm", {})


static func is_firearm(item: int) -> bool:
	return not firearm(item).is_empty()


## The item a firearm spends when it fires. NONE for anything that is not a firearm,
## which is also what makes "do I have ammunition" a question with one answer.
static func ammo_for(item: int) -> int:
	return int(firearm(item).get("ammo", Kind.NONE))


## Damage one round does. Distinct from `melee_damage`, because pistol-whipping a deer
## is not what the pistol is for.
static func ranged_damage(item: int) -> float:
	return float(firearm(item).get("damage", 0.0))


static func ranged_reach_m(item: int) -> float:
	return float(firearm(item).get("range_m", 0.0))


static func fire_interval(item: int) -> float:
	return float(firearm(item).get("interval", 0.5))


## How far the barrel kicks up per shot. Recovery is the shooter's problem, which is
## what makes a second shot cost something.
static func recoil_degrees(item: int) -> float:
	return float(firearm(item).get("recoil_degrees", 0.0))


## Whether holding the trigger keeps firing, rather than one round per click.
static func is_automatic(item: int) -> bool:
	return bool(firearm(item).get("automatic", false))


static func is_flight_suit(item: int) -> bool:
	return item == Kind.FLYING_SUIT
