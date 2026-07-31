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

enum State { PATROL, STALK, CHARGE, ATTACK, RETREAT }

## How long a bout of patrolling lasts before picking a new heading.
const PATROL_SECONDS := Vector2(3.0, 8.0)

## Stalking is deliberately slow: the approach is the warning.
const STALK_SPEED_SCALE := 0.42

## Ranges, in metres. Detection starts a stalk, charge range starts a run, attack range
## starts hitting.
const CHARGE_RANGE_M := 13.0
const ATTACK_RANGE_M := 2.6

## Hysteresis on every range, for the same reason the prey brain needs it: an animal
## sitting exactly on a boundary would otherwise switch state every frame.
const RELEASE_MULTIPLIER := 1.3

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

var _state := State.PATROL
var _timer := 0.0
var _recover := 0.0
var _direction := Vector3.ZERO
var _stuck_for := 0.0
var _rng := RandomNumberGenerator.new()

const STUCK_SECONDS := 1.2


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value
	_enter(State.PATROL)


func state() -> int:
	return _state


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
## threat_crouching, threat_sprinting, detection_m, health_fraction, made_progress.
func tick(delta: float, context: Dictionary) -> void:
	if delta <= 0.0:
		return

	_update_stuck(delta, context)

	var position: Vector3 = context.get("position", Vector3.ZERO)
	var threat: Vector3 = context.get("threat_position", Vector3.ZERO)
	var present: bool = context.get("threat_present", false)
	var distance := position.distance_to(threat) if present else INF
	var health: float = context.get("health_fraction", 1.0)

	# Wounded animals disengage from any state, including mid-swing.
	if health <= RETREAT_HEALTH_FRACTION and _state != State.RETREAT:
		_enter(State.RETREAT)

	if _state == State.RETREAT:
		_tick_retreat(delta, position, threat, present, distance)
		return

	if _recover > 0.0:
		# Recently beaten off: patrol, and ignore the player for a while.
		_recover -= delta
		_tick_patrol(delta, context)
		return

	var detection := detection_range(
			float(context.get("detection_m", 25.0)),
			bool(context.get("threat_crouching", false)),
			bool(context.get("threat_sprinting", false)))

	if not present or distance > detection * RELEASE_MULTIPLIER:
		if _state != State.PATROL:
			_enter(State.PATROL)
		_tick_patrol(delta, context)
		return

	# Close enough to strike.
	if distance <= ATTACK_RANGE_M:
		if _state != State.ATTACK:
			_enter(State.ATTACK)
		_direction = Vector3.ZERO
		return

	# Within a rush.
	if distance <= CHARGE_RANGE_M:
		if _state != State.CHARGE:
			_enter(State.CHARGE)
		_direction = _towards(position, threat)
		return

	# Seen, but far: close the distance slowly.
	if distance <= detection:
		if _state != State.STALK:
			_enter(State.STALK)
		_direction = _towards(position, threat)
		return

	# Between detection and its release margin: hold whatever was already happening.
	if _state == State.PATROL:
		_tick_patrol(delta, context)
	else:
		_direction = _towards(position, threat)


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
