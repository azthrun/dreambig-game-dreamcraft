extends RefCounted
## What a predator decides to do: patrol, stalk, charge, attack, or break off.
##
## Pure of Node and SceneTree, like the prey brain, so an entire hunt — noticing, closing,
## striking, and giving up wounded — is simulated by injecting deltas with no scene and no
## animal.
##
## The five stages exist so a predator reads as deliberate rather than as a homing
## missile. Stalking at reduced speed is what gives the player time to notice they are
## being hunted; retreating when hurt is what makes a fight winnable without killing.

const Senses := preload("res://scripts/creatures/senses.gd")

enum State { PATROL, STALK, CHARGE, ATTACK, RETREAT }

## What the predator is currently hunting. The body reads this to know what its strike
## should land on, so one attack path serves both.
enum Target { NONE, PLAYER, QUARRY }

## How long a bout of patrolling lasts before picking a new heading.
const PATROL_SECONDS := Vector2(3.0, 8.0)

## Stalking is deliberately slow: the approach is the warning.
const STALK_SPEED_SCALE := 0.42

## Ranges, in metres. Detection starts a stalk, charge range starts a run, attack range
## starts hitting.
const CHARGE_RANGE_M := 13.0
const ATTACK_RANGE_M := 2.6

## How much further a predator tracks an animal than it notices a person.
##
## Not flavour — the island would not otherwise read as alive. Forty deer over two square
## kilometres puts roughly one animal inside a 30 m circle every thirteen minutes, so at
## player-detection range a hunt is something a player would almost never happen to see.
## Tracking prey to 75 m instead makes it a regular sight, and changes nothing about how
## dangerous a predator is to the player.
const PREY_SCENT_MULTIPLIER := 2.5

## Hysteresis on every range, for the same reason the prey brain needs it: an animal
## sitting exactly on a boundary would otherwise switch state every frame.
const RELEASE_MULTIPLIER := 1.3

## How much closer something new has to be before it steals the hunt.
##
## Range hysteresis alone does not cover this. Two targets both comfortably inside
## detection and a centimetre apart in distance would swap the hunt on every decision —
## measured at 39 swaps in 40 — and the predator would run at neither.
const TARGET_SWITCH_MARGIN := 1.25

## Crouching hides you; sprinting advertises you. Both modify the same detection range.
const CROUCH_DETECTION_FACTOR := 0.45
const SPRINT_DETECTION_FACTOR := 1.6

## Below this share of health a predator breaks off rather than fighting to the death.
const RETREAT_HEALTH_FRACTION := 0.3

## How far it runs before it stops fleeing, and how long before it will hunt again.
const RETREAT_DISTANCE_M := 32.0
const RECOVER_SECONDS := 14.0

## How far from its territory anchor a patrol will wander.
const TERRITORY_RADIUS_M := 45.0

## How long a predator stays with a kill before it will hunt an animal again.
##
## Without it, a leopard that killed a deer turns on the next one immediately and the
## island empties. It does not suppress the player: something that walks up to a feeding
## predator has earned what happens next.
const FEED_SECONDS := 25.0

var _state := State.PATROL
var _target := Target.NONE
var _timer := 0.0
var _recover := 0.0
var _feed := 0.0
var _direction := Vector3.ZERO
var _stuck_for := 0.0
var _rng := RandomNumberGenerator.new()

const STUCK_SECONDS := 1.2


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value
	_enter(State.PATROL)


func state() -> int:
	return _state


## What it is hunting right now: the player, an animal, or nothing.
func target() -> int:
	return _target


func is_hunting_quarry() -> bool:
	return _target == Target.QUARRY


## Told by the body when a strike killed what it was hunting.
##
## The brain cannot see the kill itself — it deals in positions, not health — so this is
## the one thing the body has to report back.
func note_kill() -> void:
	_feed = FEED_SECONDS
	_target = Target.NONE
	_enter(State.PATROL)


func state_name() -> String:
	match _state:
		State.PATROL:
			return "patrol"
		State.STALK:
			return "stalk"
		State.CHARGE:
			return "charge"
		State.ATTACK:
			return "attack"
		State.RETREAT:
			return "retreat"
	return "unknown"


func desired_direction() -> Vector3:
	return _direction


## True while close enough to strike. The body applies its own cooldown, so the brain does
## not have to know how fast this animal swings.
func is_attacking() -> bool:
	return _state == State.ATTACK


func is_retreating() -> bool:
	return _state == State.RETREAT


## Movement speed multiplier for the current state. Stalking is slow, everything else runs.
func speed_scale() -> float:
	match _state:
		State.PATROL:
			return 1.0
		State.STALK:
			return STALK_SPEED_SCALE
		State.ATTACK:
			return 0.0
	return 1.0


## Whether the current state uses the running gait rather than the walking one.
func is_running() -> bool:
	return _state == State.CHARGE or _state == State.RETREAT


## Range at which a predator tracks an animal, which is further than it notices a person.
static func quarry_range(base_m: float) -> float:
	return base_m * PREY_SCENT_MULTIPLIER


## Range at which a predator notices the player, given how the player is moving.
static func detection_range(base_m: float, crouching: bool,
		sprinting: bool) -> float:
	var range_m := base_m
	if crouching:
		range_m *= CROUCH_DETECTION_FACTOR
	elif sprinting:
		range_m *= SPRINT_DETECTION_FACTOR
	return range_m


## Advances the decision.
##
## `context` carries: position, anchor, threat_position, threat_present,
## threat_crouching, threat_sprinting, quarry_position, quarry_present, detection_m,
## health_fraction, made_progress.
##
## "Threat" is the player; "quarry" is the nearest prey animal. Everything after the
## choice between them is the same code, which is the point: a leopard hunts a deer with
## the tree it uses on the player, and the player watching it happen is watching the same
## five stages they will be on the receiving end of.
func tick(delta: float, context: Dictionary) -> void:
	if delta <= 0.0:
		return

	_update_stuck(delta, context)
	if _feed > 0.0:
		_feed -= delta

	var position: Vector3 = context.get("position", Vector3.ZERO)
	var health: float = context.get("health_fraction", 1.0)
	var base_detection: float = float(context.get("detection_m", 25.0))

	var player := {
		"position": context.get("threat_position", Vector3.ZERO),
		"present": bool(context.get("threat_present", false)),
		"detection": detection_range(base_detection,
				bool(context.get("threat_crouching", false)),
				bool(context.get("threat_sprinting", false))),
	}
	# Animals neither crouch nor sprint, and are tracked further off than a person. One
	# that has just been killed and fed on is not hunted again for a while.
	var quarry := {
		"position": context.get("quarry_position", Vector3.ZERO),
		"present": bool(context.get("quarry_present", false)) and _feed <= 0.0,
		"detection": quarry_range(base_detection),
	}

	# Wounded animals disengage from any state, including mid-swing.
	if health <= RETREAT_HEALTH_FRACTION and _state != State.RETREAT:
		_enter(State.RETREAT)

	if _state == State.RETREAT:
		# Runs from whatever it was dealing with, falling back to the player: something
		# hurt it, and the player is the only thing on the island that can.
		var from: Dictionary = quarry if _target == Target.QUARRY else player
		if not bool(from["present"]):
			from = player
		_tick_retreat(delta, position, from["position"], bool(from["present"]),
				Senses.distance_to(position, from))
		return

	if _recover > 0.0:
		# Recently beaten off: patrol, and ignore everything for a while.
		_recover -= delta
		_target = Target.NONE
		_tick_patrol(delta, context)
		return

	var chosen := _choose(position, player, quarry)
	if chosen.is_empty():
		if _state != State.PATROL:
			_enter(State.PATROL)
		_tick_patrol(delta, context)
		return

	var at: Vector3 = chosen["position"]
	var distance := position.distance_to(at)
	var detection: float = chosen["detection"]

	# A hunted animal is rushed from much further out than the player is.
	#
	# Not for drama: a stalk covers 1.1 m/s and a fleeing deer covers 8.4, so a predator
	# that held its stalk to 13 m would be left behind the moment the deer noticed it at
	# 26 m, and no hunt would ever conclude. Charging from its own detection range means
	# the rush starts before the deer breaks — which is what a real ambush is.
	var charge_range := CHARGE_RANGE_M
	if _target == Target.QUARRY:
		charge_range = maxf(CHARGE_RANGE_M, base_detection)

	# Close enough to strike.
	if distance <= ATTACK_RANGE_M:
		if _state != State.ATTACK:
			_enter(State.ATTACK)
		_direction = Vector3.ZERO
		return

	# Within a rush.
	if distance <= charge_range:
		if _state != State.CHARGE:
			_enter(State.CHARGE)
		_direction = _towards(position, at)
		return

	# Seen, but far: close the distance slowly.
	if distance <= detection:
		if _state != State.STALK:
			_enter(State.STALK)
		_direction = _towards(position, at)
		return

	# Between detection and its release margin: hold whatever was already happening.
	if _state == State.PATROL:
		_tick_patrol(delta, context)
	else:
		_direction = _towards(position, at)


## Picks between the player and the nearest animal, and sets `_target`. Returns the
## chosen candidate, or `{}` when neither has been noticed.
##
## Nearest wins. A predator that always preferred the player would make the island a set
## of threats aimed at one person rather than an ecosystem; one that always preferred
## prey could be walked up to.
##
## What it is already hunting is noticed a little further out than something new, which
## is the same hysteresis the ranges use — without it, two candidates at nearly equal
## distance would swap the target every decision and the animal would run at neither.
func _choose(position: Vector3, player: Dictionary,
		quarry: Dictionary) -> Dictionary:
	var candidates: Array = [player.duplicate(), quarry.duplicate()]
	if _target == Target.PLAYER:
		candidates[0]["detection"] = float(player["detection"]) * RELEASE_MULTIPLIER
	elif _target == Target.QUARRY:
		candidates[1]["detection"] = float(quarry["detection"]) * RELEASE_MULTIPLIER

	var pick := Senses.nearest(position, candidates)
	if pick == Senses.NOTHING:
		_target = Target.NONE
		return {}

	# Stickiness in distance as well as in range: whatever is already being hunted keeps
	# the hunt unless the other is meaningfully closer.
	var previous := -1
	if _target == Target.PLAYER:
		previous = 0
	elif _target == Target.QUARRY:
		previous = 1
	if previous >= 0 and previous != pick:
		var held := Senses.distance_to(position, candidates[previous])
		if held <= float(candidates[previous]["detection"]) \
				and held <= Senses.distance_to(position, candidates[pick]) \
						* TARGET_SWITCH_MARGIN:
			pick = previous

	_target = Target.PLAYER if pick == 0 else Target.QUARRY
	# The plain range is returned, not the sticky one: stickiness decides what is being
	# hunted, and the stages of the hunt are measured against the real range.
	return player if pick == 0 else quarry


func _tick_patrol(delta: float, context: Dictionary) -> void:
	_timer -= delta
	var position: Vector3 = context.get("position", Vector3.ZERO)
	var anchor: Vector3 = context.get("anchor", position)

	# Turned back at the edge of its territory, so a predator stays somewhere findable
	# rather than wandering the whole island.
	if position.distance_to(anchor) > TERRITORY_RADIUS_M:
		_direction = _towards(position, anchor)
		_timer = _rng.randf_range(PATROL_SECONDS.x, PATROL_SECONDS.y)
		return

	if _timer <= 0.0:
		_direction = _random_direction()
		_timer = _rng.randf_range(PATROL_SECONDS.x, PATROL_SECONDS.y)


func _tick_retreat(delta: float, position: Vector3, threat: Vector3,
		present: bool, distance: float) -> void:
	if present:
		_direction = _away_from(position, threat)
	if not present or distance >= RETREAT_DISTANCE_M:
		# Far enough to stop running, but it will not hunt again for a while.
		_recover = RECOVER_SECONDS
		_enter(State.PATROL)


func _towards(position: Vector3, target: Vector3) -> Vector3:
	var to := target - position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return _random_direction()
	return to.normalized()


func _away_from(position: Vector3, threat: Vector3) -> Vector3:
	return -_towards(position, threat)


func _update_stuck(delta: float, context: Dictionary) -> void:
	if _state == State.ATTACK:
		_stuck_for = 0.0
		return
	if bool(context.get("made_progress", true)):
		_stuck_for = 0.0
		return
	_stuck_for += delta
	if _stuck_for >= STUCK_SECONDS:
		_stuck_for = 0.0
		_direction = _random_direction()


func _enter(state: int) -> void:
	_state = state
	_stuck_for = 0.0
	match state:
		State.PATROL:
			_direction = _random_direction()
			_timer = _rng.randf_range(PATROL_SECONDS.x, PATROL_SECONDS.y)
		State.ATTACK:
			_direction = Vector3.ZERO


func _random_direction() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	return Vector3(cos(angle), 0.0, sin(angle))
