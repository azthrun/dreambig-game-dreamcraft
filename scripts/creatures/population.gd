extends RefCounted
## Which species a cell gets, and how many of each the island may hold.
##
## Pure of Node and SceneTree, so the whole question of "where do lions live and how many
## are there" is answered by rolling this thousands of times in a headless test rather
## than by spawning an island and counting animals.
##
## Two limits, and they do different jobs. The **total** cap bounds per-frame cost — the
## island is a fixed size, so a number is easier to reason about than a density. The
## **per-species** caps shape the encounter: without them one biome-heavy island could
## roll four lions in the first clearing, and a total cap alone would not notice.

const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")

var _counts: Dictionary = {}
var _total := 0
var _total_cap := 0
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int, total_cap: int) -> void:
	_rng.seed = seed_value
	_total_cap = total_cap


func counts() -> Dictionary:
	return _counts.duplicate()


func count_of(kind: int) -> int:
	return int(_counts.get(kind, 0))


func total() -> int:
	return _total


func is_full() -> bool:
	return _total >= _total_cap


## Whether another of this species would fit, under both its own cap and the total.
func has_room_for(kind: int) -> bool:
	return not is_full() and count_of(kind) < CreatureKind.max_population(kind)


## Relative likelihoods for a biome, species that do not live there omitted.
##
## Static, and separate from the roll, so the weighting can be inspected without
## consuming randomness or filling the island.
static func weights_in(biome: int) -> Dictionary:
	var weights := {}
	for kind in CreatureKind.ALL:
		var weight := CreatureKind.biome_weight(kind, biome)
		if weight > 0.0:
			weights[kind] = weight
	return weights


## Picks a species for a biome, weighted, or -1 for nothing here.
##
## Species already at their cap are dropped before the roll rather than rejected after,
## so a full deer population leaves the cats their proper share of the remaining places
## instead of wasting attempts.
func roll(biome: int) -> int:
	var total := 0.0
	var weights := weights_in(biome)
	for kind in weights:
		if has_room_for(kind):
			total += float(weights[kind])
	if total <= 0.0:
		return -1

	var target := _rng.randf() * total
	var accumulated := 0.0
	for kind in weights:
		if not has_room_for(kind):
			continue
		accumulated += float(weights[kind])
		if target <= accumulated:
			return kind
	return -1


## Records a placement. Separate from the roll so a caller that fails to place an animal
## does not spend its allowance.
func record(kind: int) -> void:
	_counts[kind] = count_of(kind) + 1
	_total += 1
