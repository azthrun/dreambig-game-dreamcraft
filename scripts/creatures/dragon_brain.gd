extends RefCounted
## What the dragon decides to do: circle its territory at altitude, dive on the player,
## strike, or land.
##
## Pure of Node and SceneTree, like every other brain, so a whole encounter — spotted at
## range, dived on, driven off past the nest's territory — is simulated by injecting
## deltas with no scene and no dragon.
##
## Extends the predator tree with flight the way SPEC calls for: the same shape (seen at
## range, closes in, strikes, breaks off) with altitude and three-dimensional steering
## substituted for the ground stalk-and-charge. It never hunts other animals — only the
## player is worth a dragon's attention — so unlike `PredatorBrain` there is no quarry.

enum State { PATROL, DIVE, ATTACK, LANDED }

## Height above the nest a patrol cruises at, and how wide a circle it flies.
const CRUISE_ALTITUDE_M := 34.0
const PATROL_RADIUS_M := 70.0

## Radians per second the patrol circle advances. A full lap take a little under 35 s.
const PATROL_ANGULAR_SPEED := 0.18

## How far from the nest a dragon will fly at all. Crossed while chasing, retreating
## towards the nest overrides the chase outright — the acceptance criterion this whole
## file exists to satisfy: the dragon does not pursue indefinitely across the island.
const TERRITORY_RADIUS_M := 140.0

## How close a strike needs, in metres — melee-scale reach for a very large animal.
const ATTACK_RANGE_M := 5.0

## Hysteresis so a target sitting exactly on a boundary does not flicker between states
## every decision, the same reasoning `PredatorBrain` uses its own release margin for.
const RELEASE_MULTIPLIER := 1.3

## How long an uninterrupted patrol runs before the dragon lands to rest, and how long it
## stays down once it has.
const LAND_IDLE_SECONDS := 20.0
const LAND_DURATION_SECONDS := Vector2(6.0, 14.0)

var _state := State.PATROL
var _direction := Vector3.ZERO
var _patrol_angle := 0.0
var _idle_timer := 0.0
var _land_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value
	_patrol_angle = _rng.randf_range(0.0, TAU)


func state() -> int:
	return _state


func state_name() -> String:
	match _state:
		State.PATROL:
			return "patrol"
		State.DIVE:
			return "dive"
		State.ATTACK:
			return "attack"
		State.LANDED:
			return "landed"
	return "unknown"


func desired_direction() -> Vector3:
	return _direction


func is_attacking() -> bool:
	return _state == State.ATTACK


func is_landed() -> bool:
	return _state == State.LANDED


## A dragon has no quarry among the other animals — only ever the player — so the body's
## generic attack path always lands on `stats().damage()` rather than another creature.
func is_hunting_quarry() -> bool:
	return false


## Only the dive uses the fast gait; patrol cruises, and a strike holds still.
func is_running() -> bool:
	return _state == State.DIVE


## Advances the decision.
##
## `context` carries: position, anchor (the nest), threat_position, threat_present,
## detection_m.
func tick(delta: float, context: Dictionary) -> void:
	if delta <= 0.0:
		return

	var position: Vector3 = context.get("position", Vector3.ZERO)
	var anchor: Vector3 = context.get("anchor", position)
	var threat_present: bool = bool(context.get("threat_present", false))
	var threat_position: Vector3 = context.get("threat_position", Vector3.ZERO)
	var detection: float = float(context.get("detection_m", 60.0))

	if _state == State.LANDED:
		_tick_landed(delta, position, threat_present, threat_position, detection)
		return

	# Territory bounding overrides whatever else is happening: too far from the nest and
	# the dragon turns for home regardless of what it was chasing. Checked and acted on
	# in the same tick, not deferred, or a chase caught right at the edge would take one
	# more decision to actually turn around.
	var anchor_distance := _horizontal_distance(position, anchor)
	if anchor_distance > TERRITORY_RADIUS_M:
		if _state != State.PATROL:
			_enter(State.PATROL)
		_direction = _seek(position, _cruise_point(anchor))
		return

	var threat_distance := position.distance_to(threat_position) if threat_present \
			else INF

	# Cascading thresholds, closest first, each carrying its own state's release margin
	# when that is the state already held — the same shape `PredatorBrain` uses, and for
	# the same reason: state and direction are decided together, in this one tick, so a
	# fresh transition steers correctly on the very tick it happens rather than a tick
	# behind it.
	var attack_range := ATTACK_RANGE_M * (RELEASE_MULTIPLIER if _state == State.ATTACK \
			else 1.0)
	if threat_present and threat_distance <= attack_range:
		if _state != State.ATTACK:
			_enter(State.ATTACK)
		_direction = Vector3.ZERO
		return

	var dive_range := detection \
			* (RELEASE_MULTIPLIER if _state == State.DIVE or _state == State.ATTACK \
					else 1.0)
	if threat_present and threat_distance <= dive_range:
		if _state != State.DIVE:
			_enter(State.DIVE)
		_direction = _seek(position, threat_position)
		return

	if _state != State.PATROL:
		_enter(State.PATROL)
	_tick_patrol(delta, position, anchor)
	_tick_idle_timer(delta, threat_present)


func _tick_landed(delta: float, position: Vector3, threat_present: bool,
		threat_position: Vector3, detection: float) -> void:
	_direction = Vector3.ZERO
	_land_timer -= delta
	# Spooked into the air the moment the player is close enough to notice, whatever is
	# left of the rest.
	if threat_present and position.distance_to(threat_position) <= detection:
		_enter(State.PATROL)
		return
	if _land_timer <= 0.0:
		_enter(State.PATROL)


func _tick_patrol(delta: float, position: Vector3, anchor: Vector3) -> void:
	_patrol_angle = fmod(_patrol_angle + PATROL_ANGULAR_SPEED * delta, TAU)
	_direction = _seek(position, _circle_point(anchor, _patrol_angle))


func _tick_idle_timer(delta: float, threat_present: bool) -> void:
	if threat_present:
		_idle_timer = 0.0
		return
	_idle_timer += delta
	if _idle_timer >= LAND_IDLE_SECONDS:
		_idle_timer = 0.0
		_enter(State.LANDED)


func _circle_point(anchor: Vector3, angle: float) -> Vector3:
	return anchor + Vector3(cos(angle), 0.0, sin(angle)) * PATROL_RADIUS_M \
			+ Vector3.UP * CRUISE_ALTITUDE_M


func _cruise_point(anchor: Vector3) -> Vector3:
	return _circle_point(anchor, _patrol_angle)


## Full three-dimensional direction towards `target` — altitude is part of steering here,
## unlike the ground brains, which flatten to the horizontal plane.
func _seek(position: Vector3, target: Vector3) -> Vector3:
	var to := target - position
	if to.length_squared() < 0.0001:
		return Vector3.ZERO
	return to.normalized()


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _enter(state: int) -> void:
	_state = state
	match state:
		State.ATTACK:
			_direction = Vector3.ZERO
		State.LANDED:
			_direction = Vector3.ZERO
			_land_timer = _rng.randf_range(
					LAND_DURATION_SECONDS.x, LAND_DURATION_SECONDS.y)
