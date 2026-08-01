extends RefCounted
## Who else is nearby, and what they are.
##
## A predator needs to find a deer and a deer needs to find the predator, and neither can
## walk the scene tree to do it — the whole creature simulation is pure, and a query that
## touched nodes would drag the SceneTree back into the brains.
##
## A flat array scanned linearly rather than a spatial index. Sixty animals, queried by
## the handful that are awake, five times a second: the scan is a rounding error next to
## the machinery a grid would need, and a grid would have to be kept correct as sixty
## animals move. Revisit this if the roster ever grows by an order of magnitude.

const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")

var _entries: Dictionary = {}


## Adds a creature, or replaces an entry with the same id.
##
## `ref` is whatever the caller wants handed back by a query — the body, in the game, and
## nothing at all in a test that only cares about positions.
func add(id: int, kind: int, position: Vector3, ref: Variant = null) -> void:
	_entries[id] = {
		"id": id,
		"kind": kind,
		"role": CreatureKind.role(kind),
		"position": position,
		"ref": ref,
	}


func remove(id: int) -> void:
	_entries.erase(id)


func has(id: int) -> bool:
	return _entries.has(id)


func count() -> int:
	return _entries.size()


## Moves an existing creature. Silently ignores an unknown id, so a body that has already
## died and been removed cannot resurrect itself by reporting a position.
func move(id: int, position: Vector3) -> void:
	if _entries.has(id):
		_entries[id]["position"] = position


## Nearest creature of a role within `max_range`, as an entry dictionary, or `{}`.
##
## The searcher passes its own id to exclude, because otherwise every predator's nearest
## predator is itself.
func nearest_of_role(from: Vector3, role: int, max_range: float,
		exclude_id: int = 0) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := max_range
	for id in _entries:
		if id == exclude_id:
			continue
		var entry: Dictionary = _entries[id]
		if int(entry["role"]) != role:
			continue
		var distance: float = from.distance_to(entry["position"])
		if distance <= best_distance:
			best_distance = distance
			best = entry
	return best


## Everything currently registered, for reporting and for tests.
func entries() -> Array:
	return _entries.values()
