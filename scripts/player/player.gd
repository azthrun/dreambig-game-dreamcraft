extends CharacterBody3D
## First-person player controller.
##
## Terraced terrain makes step-up load-bearing rather than a nicety: every slope on
## this island is either flat or a vertical face, so without automatic step-up the
## player would have to jump at every single 1 m terrace edge. With it, 1 m ledges
## are walked over and anything taller is a genuine wall — which is also how slope
## refusal manifests here, since there are no intermediate gradients to refuse.
##
## No player model or animation: the first-person decision means there is no body to
## see, so there is nothing to animate.

## Movement speeds in metres per second.
const WALK_SPEED := 4.6
const SPRINT_SPEED := 7.8
const CROUCH_SPEED := 2.1

## Ground acceleration and air control, in metres per second squared.
const ACCELERATION := 45.0
const AIR_ACCELERATION := 8.0
const FRICTION := 55.0

const GRAVITY := 24.0
const JUMP_HEIGHT_M := 1.25

## Tallest ledge the player walks up without jumping. Just over a terrace so a 1 m
## step always clears and a 2 m step never does.
const MAX_STEP_HEIGHT := 1.05

## Steepest walkable surface. Terrace tops are flat and skirts are vertical, so this
## chiefly decides that skirts are walls rather than ramps.
const MAX_SLOPE_DEGREES := 50.0

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const STAND_EYE_HEIGHT := 1.65
const CROUCH_EYE_HEIGHT := 1.05

const MOUSE_SENSITIVITY := 0.0022
const PITCH_LIMIT_DEGREES := 89.0

var _jump_velocity: float = sqrt(2.0 * GRAVITY * JUMP_HEIGHT_M)
var _crouching := false

var _camera: Camera3D
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D


func _ready() -> void:
	_camera = get_node_or_null(^"Camera3D") as Camera3D
	_collision = get_node_or_null(^"Collision") as CollisionShape3D

	# Sub-resources are shared between scene instances unless duplicated, and
	# crouching mutates the capsule. Without this, two players would resize each
	# other.
	if _collision != null and _collision.shape is CapsuleShape3D:
		_capsule = _collision.shape.duplicate()
		_collision.shape = _capsule

	floor_max_angle = deg_to_rad(MAX_SLOPE_DEGREES)
	# Long enough to settle onto a terrace after a step-up, and to hold the player
	# on the ground when walking off a 1 m lip rather than launching them.
	floor_snap_length = 0.6

	capture_mouse()


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func is_crouching() -> bool:
	return _crouching


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if mouse_captured():
			release_mouse()
		else:
			capture_mouse()
		return

	# Clicking back into the window recaptures, so the player is not stuck with a
	# free cursor after alt-tabbing.
	if event is InputEventMouseButton and not mouse_captured():
		capture_mouse()
		return

	if event is InputEventMouseMotion and mouse_captured():
		_look(event.relative)


func _look(relative: Vector2) -> void:
	rotate_y(-relative.x * MOUSE_SENSITIVITY)
	if _camera == null:
		return
	var limit := deg_to_rad(PITCH_LIMIT_DEGREES)
	_camera.rotation.x = clampf(
			_camera.rotation.x - relative.y * MOUSE_SENSITIVITY, -limit, limit)


func _physics_process(delta: float) -> void:
	_update_crouch(delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed(&"jump") and not _crouching:
		velocity.y = _jump_velocity

	var wish := _wish_direction()
	var target := wish * current_speed()
	var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish.is_zero_approx() and is_on_floor():
		horizontal = horizontal.move_toward(Vector3.ZERO, FRICTION * delta)
	else:
		horizontal = horizontal.move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	try_step_up(horizontal * delta)
	move_and_slide()


## Movement input as a unit vector in world space, relative to where the player is
## facing.
func _wish_direction() -> Vector3:
	var input := Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	if input.is_zero_approx():
		return Vector3.ZERO
	# Godot's -Z is forward, and get_vector's Y axis is forward/back.
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y))
	direction.y = 0.0
	return direction.normalized()


func current_speed() -> float:
	if _crouching:
		return CROUCH_SPEED
	if Input.is_action_pressed(&"sprint") and is_on_floor():
		return SPRINT_SPEED
	return WALK_SPEED


func _update_crouch(_delta: float) -> void:
	var wants_crouch := Input.is_action_pressed(&"crouch")
	if wants_crouch == _crouching:
		return
	if not wants_crouch and not _has_headroom():
		return  # stuck under something; stay down
	set_crouching(wants_crouch)


func set_crouching(crouching: bool) -> void:
	_crouching = crouching
	var height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	if _capsule != null:
		_capsule.height = height
	if _collision != null:
		_collision.position.y = height * 0.5
	if _camera != null:
		_camera.position.y = CROUCH_EYE_HEIGHT if crouching else STAND_EYE_HEIGHT


func _has_headroom() -> bool:
	var needed := STAND_HEIGHT - CROUCH_HEIGHT
	return not test_move(global_transform, Vector3.UP * needed)


## Lifts the body onto a ledge when one is blocking the way and is low enough to
## step. Returns true when a step was taken.
##
## Runs before move_and_slide so the horizontal move happens from the raised
## position, and floor snapping settles the player back down onto the terrace.
func try_step_up(motion: Vector3) -> bool:
	if not is_on_floor():
		return false

	var horizontal := Vector3(motion.x, 0.0, motion.z)
	if horizontal.length() < 0.0001:
		return false

	# Only intervene when something is genuinely in the way.
	if not test_move(global_transform, horizontal):
		return false

	# Would the same move be clear from a step higher up? If not, this is a wall,
	# not a step, and refusing it is what makes tall terraces into cliffs.
	var lifted := global_transform
	lifted.origin.y += MAX_STEP_HEIGHT
	if test_move(lifted, horizontal):
		return false

	# There has to be ground to land on, or the player would be stepping into air.
	var landed := lifted
	landed.origin += horizontal
	if not test_move(landed, Vector3.DOWN * (MAX_STEP_HEIGHT + 0.05)):
		return false

	global_position.y += MAX_STEP_HEIGHT
	if velocity.y < 0.0:
		velocity.y = 0.0
	return true
