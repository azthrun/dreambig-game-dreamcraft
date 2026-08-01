extends RefCounted
## Choosing between two things worth reacting to.
##
## Both brains face the same question and it is the same question in each direction: a
## deer has to decide whether the player or the leopard is the more pressing problem, and
## the leopard has to decide whether to hunt the deer or the player. Neither should fixate
## on the player merely because the player is the one holding the controller.
##
## Pure and static: candidates arrive as plain dictionaries, so this is tested by handing
## it positions rather than by staging an encounter.

## No candidate was noticed.
const NOTHING := -1


## Index of the nearest candidate that is both present and inside its own detection range,
## or `NOTHING`.
##
## Each candidate is `{position, present, detection}`. Detection is per candidate rather
## than per sense, because a crouching player is noticed later than a deer standing in the
## open at the same distance — that difference is the whole point of crouching.
static func nearest(position: Vector3, candidates: Array) -> int:
	var best := NOTHING
	var best_distance := INF
	for index in candidates.size():
		var candidate: Dictionary = candidates[index]
		if not bool(candidate.get("present", false)):
			continue
		var distance: float = position.distance_to(
				candidate.get("position", Vector3.ZERO))
		if distance > float(candidate.get("detection", 0.0)):
			continue
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


## Straight-line distance to a candidate, or INF when it is not there at all.
static func distance_to(position: Vector3, candidate: Dictionary) -> float:
	if not bool(candidate.get("present", false)):
		return INF
	return position.distance_to(candidate.get("position", Vector3.ZERO))
