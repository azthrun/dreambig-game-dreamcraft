extends RefCounted
## What is inside a supply cache.
##
## Pure and data-driven: a weighted table of possible contents, rolled from a seed and a
## cache id, so the same crate on the same island always holds the same thing and the
## whole distribution can be checked by rolling it ten thousand times in a headless test.
##
## Rarity here is the entire balance of the gadget tier. A pistol behind a common roll
## would be found in the first hour; ammunition behind a common roll would make the
## pistol the answer to everything. Both are deliberately uncommon, and neither can be
## crafted — see SPEC.

const ItemKind := preload("res://scripts/items/item_kind.gd")

## One entry per possible cache content: relative weight, and how many arrive.
##
## `count` is a range, inclusive, so a lucky crate is a real event rather than every
## crate being identical.
const TABLE := [
	## The common case, and deliberately so: most caches are a small consolation. A
	## crate that always held a gadget would make exploration a checklist.
	{"item": ItemKind.Kind.WOOD, "weight": 16.0, "count": Vector2i(4, 9)},
	{"item": ItemKind.Kind.STONE, "weight": 14.0, "count": Vector2i(3, 8)},
	{"item": ItemKind.Kind.BERRIES, "weight": 12.0, "count": Vector2i(2, 6)},
	{"item": ItemKind.Kind.COOKED_MEAT, "weight": 8.0, "count": Vector2i(1, 3)},
	{"item": ItemKind.Kind.HIDE, "weight": 7.0, "count": Vector2i(1, 3)},
	## Uncommon. Enough rounds to matter when found, rare enough that firing is a
	## decision rather than a habit.
	{"item": ItemKind.Kind.PISTOL_AMMO, "weight": 6.0, "count": Vector2i(3, 8)},
	{"item": ItemKind.Kind.FUEL, "weight": 4.0, "count": Vector2i(1, 2)},
	## Rarer still: an automatic weapon is only an emergency tool if its ammunition is
	## harder to come by than the pistol's, or holding the trigger down would always be
	## the better plan.
	{"item": ItemKind.Kind.MACHINE_GUN_AMMO, "weight": 2.5, "count": Vector2i(4, 10)},
	## Rare. One is enough for the whole game — a second is a spare, not an upgrade.
	{"item": ItemKind.Kind.PISTOL, "weight": 2.0, "count": Vector2i(1, 1)},
	## Rarer than the pistol: the escalation from "a ranged option" to "an answer to the
	## worst things on the island" has to be a later find, not an equally likely one.
	{"item": ItemKind.Kind.MACHINE_GUN, "weight": 1.0, "count": Vector2i(1, 1)},
]

## How many separate draws a cache makes. More than one, so a crate reads as a supply
## drop rather than as a single item on the floor.
const DRAWS := Vector2i(1, 3)


## Contents for one cache, as item-to-count.
##
## Deterministic from the world seed and the cache's own id: two caches on one island
## differ, and the same cache is the same on every visit. That is also what makes it
## safe for a save file to record only which caches were opened.
static func roll(seed_value: int, cache_id: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	# Mixed rather than added, so neighbouring cache ids do not produce neighbouring
	# streams and a row of crates does not hold a row of near-identical contents.
	rng.seed = hash(Vector2i(seed_value, cache_id))

	var contents := {}
	var draws := rng.randi_range(DRAWS.x, DRAWS.y)
	for _i in draws:
		var entry := _draw(rng)
		if entry.is_empty():
			continue
		var item := int(entry["item"])
		var count: Vector2i = entry["count"]
		contents[item] = int(contents.get(item, 0)) \
				+ rng.randi_range(count.x, count.y)
	return contents


## Relative likelihood of an item being drawn, for balance checks.
static func weight_of(item: int) -> float:
	for entry in TABLE:
		if int(entry["item"]) == item:
			return float(entry["weight"])
	return 0.0


## Chance that a single draw is this item.
static func chance_of(item: int) -> float:
	var total := 0.0
	for entry in TABLE:
		total += float(entry["weight"])
	return weight_of(item) / total if total > 0.0 else 0.0


static func _draw(rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for entry in TABLE:
		total += float(entry["weight"])
	if total <= 0.0:
		return {}

	var target := rng.randf() * total
	var accumulated := 0.0
	for entry in TABLE:
		accumulated += float(entry["weight"])
		if target <= accumulated:
			return entry
	return {}
