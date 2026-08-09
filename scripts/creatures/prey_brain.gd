extends RefCounted
## What a prey animal decides to do: graze, wander, run, or — for a species that can —
## turn and fight.
##
## Pure of Node and SceneTree. It is given a picture of the world each tick — where it is,
## where the threat is, whether it is stuck — and returns a state and a direction. The
## body then does the moving.
##
## Keeping the decision separate from the movement is what makes an entirely behavioural
## feature testable: a whole minute of grazing, panicking and calming down is simulated by
## injecting deltas, with no scene and no animal.
##
## Every prey species shares this one brain, retaliation included. Whether it ever
## actually retaliates is a constructor flag read from the species table
## (`CreatureKind.retaliates`), not a second brain — a deer and a boar ask the same
## questions and only differ in what they do with the answer.

const Senses := preload("res://scripts/creatures/senses.gd")

enum State { GRAZE, WANDER, FLEE, RETALIATE }

## How long a bout of grazing or wandering lasts before re-rolling.
const GRAZE_SECONDS := Vector2(3.0, 9.0)
const WANDER_SECONDS := Vector2(2.5, 6.0)

## A fleeing animal keeps running until the threat is this much further away than the
## distance that started the flight.
##
## The margin is required, not cosmetic: without it an animal at exactly the detection
## boundary flips between fleeing and grazing every frame.
const FLEE_RELEASE_MULTIPLIER := 1.45

## How long it keeps running after the threat is out of range, so it does not stop dead
## the instant it is safe.
const FLEE_TAIL_SECONDS := 2.2

## Crouching cuts the range at which the player is noticed. This is the entire mechanical
## payoff of crouch, so it is a large factor rather than a token one.
const CROUCH_DETECTION_FACTOR := 0.45

## Re-roll the wander direction after this long with no progress. For a retaliating
## species this is also what "cornered" means: fleeing without making progress this
## long is what tells the brain there is nowhere left to run.
const STUCK_SECONDS := 1.2

## How close a retaliating animal has to be before it stops closing and starts striking.
const RETALIATE_RANGE_M := 2.2

var _state := State.GRAZE
var _timer := 0.0
var _flee_tail := 0.0
var _direction := Vector3.ZERO
var _stuck_for := 0.0
var _rng := RandomNumberGenerator.new()

## Whether this species turns and fights at all. False makes every retaliation branch
## below unreachable, which is what makes a deer a deer and a boar a boar off one flag.
var _can_retaliate := false


func _init(seed_value: int = 0, can_retaliate: bool = false) -> void:
	_rng.seed = seed_value
	_can_retaliate = can_retaliate
	_enter(State.GRAZE)


func state() -> int:
	return _state


func state_name() -> String:
	match _state:
		State.GRAZE:
			return "graze"
		State.WANDER:
			return "wander"
		State.FLEE:
			return "flee"
		State.RETALIATE:
			return "retaliate"
	return "unknown"


## Unit vector the body should move along. Zero while grazing or while braced to strike.
func desired_direction() -> Vector3:
	return _direction


func is_fleeing() -> bool:
	return _state == State.FLEE


## True while close enough to land a strike. The body applies its own damage and
## cooldown from the species table, the same way it does for a predator — this only
## says when a hit should land.
func is_attacking() -> bool:
	return _state == State.RETALIATE and _direction.length_squared() < 0.0001


## Fleeing and closing to retaliate are both a run; only grazing, wandering and bracing
## to strike are not. The body asks this before `is_fleeing()` for gait, so a charging
## boar plays its run clip rather than its walk.
func is_running() -> bool:
	return _state == State.FLEE or _state == State.RETALIATE


## Range at which this animal notices a threat, given how the threat is moving.
static func detection_range(base_m: float, crouching: bool) -> float:
	return base_m * (CROUCH_DETECTION_FACTOR if crouching else 1.0)


## Advances the decision.
##
## `context` carries: position, threat_position, threat_present, threat_crouching,
## predator_position, predator_present, detection_m, made_progress, and struck.
##
## Two things are worth running from and the nearer one wins. A deer that only ever
## watched the player would graze while a leopard closed on it, which would make the
## hunt something the player reads about in a log rather than watches.
func tick(delta: float, context: Dictionary) -> void:
	if delta <= 0.0:
		return

	_update_stuck(delta, context)

	var position: Vector3 = context.get("position", Vector3.ZERO)

	# Struck by the player: a retaliating species turns and fights on the spot, whatever
	# state it was in a moment ago — including mid-swing of its own. Checked before
	# anything else, the same way a predator's wound check pre-empts its own states.
	if _can_retaliate and bool(context.get("struck", false)):
		var struck_at: Vector3 = context.get("threat_position", Vector3.ZERO)
		_enter(State.RETALIATE)
		_direction = Vector3.ZERO if position.distance_to(struck_at) <= RETALIATE_RANGE_M \
				else _towards(position, struck_at)
		return

	if _state == State.RETALIATE:
		_tick_retaliate(position, context)
		return

	var base_detection: float = float(context.get("detection_m", 20.0))
	var candidates: Array = [
		{
			"position": context.get("threat_position", Vector3.ZERO),
			"present": bool(context.get("threat_present", false)),
			"detection": detection_range(base_detection,
					bool(context.get("threat_crouching", false))),
		},
		# A stalking predator does not crouch, but it is what a deer is built to watch
		# for: noticed at the flat range, and no further off than the player standing up.
		{
			"position": context.get("predator_position", Vector3.ZERO),
			"present": bool(context.get("predator_present", false)),
			"detection": base_detection,
		},
	]

	var pick := Senses.nearest(position, candidates)
	# Whichever was noticed. When neither was, the release margin below still has to
	# measure against something, or an animal fleeing a leopard that slipped just outside
	# its detection would calm down instead of clearing the margin first.
	var chosen: Dictionary = candidates[pick] if pick != Senses.NOTHING \
			else _nearest_present(position, candidates)
	var threat_present: bool = bool(chosen["present"])
	var threat: Vector3 = chosen["position"]
	var detection: float = chosen["detection"]
	var distance := position.distance_to(threat) if threat_present else INF

	if pick != Senses.NOTHING:
		# Cornered: already fleeing the player specifically (index 0 — a predator does
		# not draw retaliation, only the player does) and making no progress for long
		# enough that there is evidently nowhere left to run.
		if _can_retaliate and pick == 0 and _state == State.FLEE \
				and _stuck_for >= STUCK_SECONDS:
			_enter(State.RETALIATE)
			_direction = Vector3.ZERO if distance <= RETALIATE_RANGE_M \
					else _towards(position, threat)
			return

		_flee_tail = FLEE_TAIL_SECONDS
		if _state != State.FLEE:
			_enter(State.FLEE)
		_direction = _away_from(position, threat)
		return

	if _state == State.FLEE:
		# Out of range, but keep running for a moment, and only calm down once well
		# clear — otherwise the animal oscillates on the detection boundary.
		_flee_tail -= delta
		var released := not threat_present \
				or distance > detection * FLEE_RELEASE_MULTIPLIER
		if _flee_tail > 0.0 or not released:
			if threat_present:
				_direction = _away_from(position, threat)
			return
		_enter(State.WANDER)
		return

	_timer -= delta
	if _timer <= 0.0:
		_enter(State.WANDER if _state == State.GRAZE else State.GRAZE)


## Closes on the player while out of strike range, holds and strikes once inside it, and
## breaks off — back to fleeing, still rattled rather than instantly calm — once the
## player is gone or has pulled well clear. Nothing here ever targets a predator: scope
## is deliberately just the player, per the ticket this behaviour was built for.
func _tick_retaliate(position: Vector3, context: Dictionary) -> void:
	var present: bool = bool(context.get("threat_present", false))
	if not present:
		_enter(State.FLEE)
		return

	var threat: Vector3 = context.get("threat_position", Vector3.ZERO)
	var distance := position.distance_to(threat)

	# The same release margin fleeing already uses, not a fixed distance: a fixed
	# number small enough to matter at melee range would be smaller than the distance
	# a boar had just closed from to get cornered in the first place, breaking off the
	# charge the instant it began. Scaling with detection means a boar shot from far
	# outside it simply cannot catch up and gives up on its own, which is correct — a
	# rifle round from fifty metres should not summon a dead sprint across the island.
	var detection: float = float(context.get("detection_m", 20.0))
	if distance > detection * FLEE_RELEASE_MULTIPLIER:
		_enter(State.FLEE)
		# Set immediately rather than left for the next tick to discover: otherwise a
		# boar that had just broken off would stand still, direction still zero from
		# the moment it was in strike range, for one whole decision interval.
		_direction = _away_from(position, threat)
		return

	_direction = Vector3.ZERO if distance <= RETALIATE_RANGE_M \
			else _towards(position, threat)


## Direction towards a target, kept horizontal. The mirror of `_away_from`, needed once
## retaliation means closing distance rather than only opening it.
func _towards(position: Vector3, target: Vector3) -> Vector3:
	var to := target - position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return _random_direction()
	return to.normalized()


## Nearest candidate that exists at all, detected or not. Falls back to the first, which
## is the player, so there is always something to measure against.
func _nearest_present(position: Vector3, candidates: Array) -> Dictionary:
	var best: Dictionary = candidates[0]
	var best_distance := INF
	for candidate in candidates:
		var distance: float = Senses.distance_to(position, candidate)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## Direction away from a threat, kept horizontal so animals do not try to flee upwards.
func _away_from(position: Vector3, threat: Vector3) -> Vector3:
	var away := position - threat
	away.y = 0.0
	if away.length_squared() < 0.0001:
		# Standing exactly on top of the threat: any direction beats none.
		return _random_direction()
	return away.normalized()


func _update_stuck(delta: float, context: Dictionary) -> void:
	if _state == State.GRAZE:
		_stuck_for = 0.0
		return
	if bool(context.get("made_progress", true)):
		_stuck_for = 0.0
		return
	_stuck_for += delta

	# Wedged against a rock or a cliff: pick somewhere else rather than pressing on.
	# Not while fleeing — FLEE's direction is recomputed fresh from the threat's
	# position every tick regardless of this, so resetting the counter here would only
	# ever discard it before `tick()`'s own cornered check (a retaliating species) gets
	# to read it. Nothing in FLEE needs the reroll; only WANDER does.
	if _stuck_for >= STUCK_SECONDS and _state != State.FLEE:
		_stuck_for = 0.0
		_direction = _random_direction()


func _enter(state: int) -> void:
	_state = state
	match state:
		State.GRAZE:
			_direction = Vector3.ZERO
			_timer = _rng.randf_range(GRAZE_SECONDS.x, GRAZE_SECONDS.y)
		State.WANDER:
			_direction = _random_direction()
			_timer = _rng.randf_range(WANDER_SECONDS.x, WANDER_SECONDS.y)
		State.FLEE:
			_timer = 0.0
	_stuck_for = 0.0


func _random_direction() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	return Vector3(cos(angle), 0.0, sin(angle))
