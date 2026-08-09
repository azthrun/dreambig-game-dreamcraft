extends RefCounted
## What the dragon decides to do: circle its territory at altitude, dive on the player,
## telegraph and breathe fire in a cone, or land.
##
## Pure of Node and SceneTree, like every other brain, so a whole encounter — spotted at
## range, dived on, telegraphed, breathed at, driven off past the nest's territory — is
## simulated by injecting deltas with no scene and no dragon.
##
## Extends the predator tree with flight the way SPEC calls for: the same shape (seen at
## range, closes in, strikes, breaks off) with altitude and three-dimensional steering
## substituted for the ground stalk-and-charge, and a ranged, positional cone in place of
## a melee strike — the one attack nothing else on the island has. It never hunts other
## animals — only the player is worth a dragon's attention — so unlike `PredatorBrain`
## there is no quarry.

enum State { PATROL, DIVE, TELEGRAPH, BREATH, LANDED }

## Height above the nest a patrol cruises at, and how wide a circle it flies.
const CRUISE_ALTITUDE_M := 34.0
const PATROL_RADIUS_M := 70.0

## Radians per second the patrol circle advances. A full lap take a little under 35 s.
const PATROL_ANGULAR_SPEED := 0.18

## How far from the nest a dragon will fly at all. Crossed while chasing, retreating
## towards the nest overrides the chase outright — the acceptance criterion this whole
## file exists to satisfy: the dragon does not pursue indefinitely across the island.
const TERRITORY_RADIUS_M := 140.0

## Hysteresis so a target sitting exactly on a boundary does not flicker between states
## every decision, the same reasoning `PredatorBrain` uses its own release margin for.
const RELEASE_MULTIPLIER := 1.3

## How long an uninterrupted patrol runs before the dragon lands to rest, and how long it
## stays down once it has.
const LAND_IDLE_SECONDS := 20.0
const LAND_DURATION_SECONDS := Vector2(6.0, 14.0)

# --- fire breath ----------------------------------------------------------------------
##
## Ranged and positional, not a melee strike: the whole point per SPEC. The cone is
## aimed once, at the moment the telegraph ends, and held fixed for the whole breath —
## a player who was in the telegraph's aim can still step out of a fixed cone, which is
## what "avoided by moving out of it" actually means. A cone that kept re-aiming at a
## live position could never be dodged, only outrun.

## How far the cone reaches, and its half-angle from the aimed direction.
const BREATH_RANGE_M := 30.0
const BREATH_HALF_ANGLE_DEGREES := 22.0

## The telegraph: aim tracks the player, no damage yet, plenty of time to read it and
## get clear before it commits.
const TELEGRAPH_SECONDS := 0.9

## How long the cone stays live once it fires, and how hard it hits per second spent
## inside it — a duration, not an instant, so standing in it costs progressively more
## the longer the player stays.
const BREATH_DURATION_SECONDS := 1.6
const BREATH_DAMAGE_PER_SECOND := 18.0

## Cannot be chained: this much has to pass after one breath ends before the next
## telegraph can begin.
const BREATH_COOLDOWN_SECONDS := 4.0

var _state := State.PATROL
var _direction := Vector3.ZERO
var _patrol_angle := 0.0
var _idle_timer := 0.0
var _land_timer := 0.0
var _rng := RandomNumberGenerator.new()

var _telegraph_timer := 0.0
var _aim_direction := Vector3.ZERO
var _breath_timer := 0.0
var _breath_cooldown := 0.0
var _breath_origin := Vector3.ZERO
var _breath_direction := Vector3.ZERO
var _hitting_player := false


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
		State.TELEGRAPH:
			return "telegraph"
		State.BREATH:
			return "breath"
		State.LANDED:
			return "landed"
	return "unknown"


func desired_direction() -> Vector3:
	return _direction


## True across the whole breath sequence — telegraph and breath both — for anything that
## just wants to know the dragon is mid-attack.
func is_attacking() -> bool:
	return _state == State.TELEGRAPH or _state == State.BREATH


func is_telegraphing() -> bool:
	return _state == State.TELEGRAPH


## Where the telegraph is currently tracking the player. Read by the body for the
## warning cue a player needs in order to read the telegraph and get clear — a cone with
## no visible aim could not be "avoided by moving out of it".
func aim_direction() -> Vector3:
	return _aim_direction


func is_breathing() -> bool:
	return _state == State.BREATH


## The fixed direction the cone was aimed in, locked at the moment the telegraph ended.
## Meaningless outside `is_breathing()`.
func breath_direction() -> Vector3:
	return _breath_direction


## Where the cone's apex sits — the dragon's own position when the breath began, since it
## holds still to breathe rather than continuing to close.
func breath_origin() -> Vector3:
	return _breath_origin


## Whether whatever position was last tested with `tick()` fell inside the live cone.
## The body reads this each frame to apply damage over the duration of contact, rather
## than in a single instant.
func is_hitting_player() -> bool:
	return _hitting_player


func is_landed() -> bool:
	return _state == State.LANDED


## A dragon has no quarry among the other animals — only ever the player.
func is_hunting_quarry() -> bool:
	return false


## Only the dive uses the fast gait; everything else holds position or cruises.
func is_running() -> bool:
	return _state == State.DIVE


## Whether a fixed point in space falls inside the live, fixed-direction cone. Pure
## geometry — no state read or changed — which is what makes cone hit detection testable
## on its own, against plain positions, the way `Senses` tests distance and range.
func point_in_breath_cone(point: Vector3) -> bool:
	var to_point := point - _breath_origin
	var distance := to_point.length()
	if distance < 0.0001 or distance > BREATH_RANGE_M:
		return false
	if _breath_direction.length_squared() < 0.0001:
		return false
	var angle := to_point.normalized().angle_to(_breath_direction)
	return angle <= deg_to_rad(BREATH_HALF_ANGLE_DEGREES)


## Advances the decision.
##
## `context` carries: position, anchor (the nest), threat_position, threat_present,
## detection_m.
func tick(delta: float, context: Dictionary) -> void:
	if delta <= 0.0:
		return

	if _breath_cooldown > 0.0:
		_breath_cooldown -= delta

	var position: Vector3 = context.get("position", Vector3.ZERO)
	var anchor: Vector3 = context.get("anchor", position)
	var threat_present: bool = bool(context.get("threat_present", false))
	var threat_position: Vector3 = context.get("threat_position", Vector3.ZERO)
	var detection: float = float(context.get("detection_m", 60.0))

	if _state == State.LANDED:
		_tick_landed(delta, position, threat_present, threat_position, detection)
		return

	if _state == State.TELEGRAPH:
		_tick_telegraph(delta, position, threat_present, threat_position)
		return

	if _state == State.BREATH:
		_tick_breath(delta, threat_present, threat_position)
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

	# The cone takes priority over closing distance further: once in range and off
	# cooldown, a dragon that keeps diving instead of breathing would never use its own
	# attack.
	if threat_present and threat_distance <= BREATH_RANGE_M and _breath_cooldown <= 0.0:
		_telegraph_timer = TELEGRAPH_SECONDS
		_aim_direction = _seek(position, threat_position)
		_state = State.TELEGRAPH
		_direction = Vector3.ZERO
		return

	var dive_range := detection * (RELEASE_MULTIPLIER if _state == State.DIVE else 1.0)
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


## The windup: holds position, tracks the player so the aim is readable, and commits to
## a strike direction the instant the timer runs out. Cancelled only if the player is
## lost entirely — a fleeing player still inside the range that started this is exactly
## what the telegraph is for warning about.
func _tick_telegraph(delta: float, position: Vector3, threat_present: bool,
		threat_position: Vector3) -> void:
	if not threat_present:
		_enter(State.PATROL)
		return

	_aim_direction = _seek(position, threat_position)
	_telegraph_timer -= delta
	if _telegraph_timer > 0.0:
		return

	_breath_origin = position
	_breath_direction = _aim_direction
	_breath_timer = BREATH_DURATION_SECONDS
	_hitting_player = point_in_breath_cone(threat_position)
	_state = State.BREATH


func _tick_breath(delta: float, threat_present: bool, threat_position: Vector3) -> void:
	_breath_timer -= delta
	_hitting_player = threat_present and point_in_breath_cone(threat_position)
	if _breath_timer <= 0.0:
		_hitting_player = false
		_breath_cooldown = BREATH_COOLDOWN_SECONDS
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
	if state == State.LANDED:
		_direction = Vector3.ZERO
		_land_timer = _rng.randf_range(LAND_DURATION_SECONDS.x, LAND_DURATION_SECONDS.y)
