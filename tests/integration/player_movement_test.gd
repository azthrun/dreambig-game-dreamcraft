extends "res://tests/test_case.gd"
## Integration tests for the player controller.
##
## These live at the secondary seam: step-up and ground contact are properties of the
## physics engine, not arithmetic, so they need a live SceneTree and real collision
## rather than a pure function.
##
## Collision is built from boxes rather than generated terrain, so the ledge height
## under test is exactly the number in the test and nothing else varies.

const PlayerScene := preload("res://scenes/player.tscn")
const Player := preload("res://scripts/player/player.gd")

## Frames to let the player settle onto the floor under gravity.
const SETTLE_TICKS := 30

var _world: Node3D
var _player: CharacterBody3D


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	_player = null


## Where the ledge face begins, in metres along +X.
const LEDGE_FACE_X := 2.0

## Player capsule radius, from player.tscn.
const PLAYER_RADIUS := 0.4

## Builds a floor with a step of `ledge_height` metres whose face is at
## LEDGE_FACE_X, drops the player right up against that face, and lets them settle.
##
## Standing the player adjacent to the face matters: step-up only engages when
## something actually blocks the probe motion, so a player parked far away would make
## every step-up test pass for the wrong reason — reporting "refused" when the truth
## is "never asked".
func _setup(ledge_height: float) -> void:
	_world = Node3D.new()
	scene_root().add_child(_world)

	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	if ledge_height > 0.0:
		# Box spans LEDGE_FACE_X .. LEDGE_FACE_X + 20, top exactly at ledge_height.
		_add_box(Vector3(LEDGE_FACE_X + 10.0, ledge_height * 0.5, 0.0),
				Vector3(20.0, ledge_height, 40.0))

	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	# A 0.1 m gap: close enough that a short probe is blocked, clear enough that the
	# capsule does not start intersecting the ledge.
	_player.global_position = Vector3(
			LEDGE_FACE_X - PLAYER_RADIUS - 0.1, 0.5, 0.0)

	await step_physics(SETTLE_TICKS)


func _add_box(centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	_world.add_child(body)
	body.global_position = centre


func test_player_settles_on_the_ground_and_does_not_fall_through() -> void:
	await _setup(0.0)
	assert_true(_player.is_on_floor(), "player should come to rest on the floor")
	# The capsule's origin is at the feet, so resting on a floor whose top is y = 0
	# puts the player at y = 0.
	assert_almost_eq(_player.global_position.y, 0.0, 0.05,
			"player should rest on the surface, not sink into or hover above it")


func test_player_steps_up_a_one_metre_ledge() -> void:
	await _setup(1.0)
	var before := _player.global_position.y
	var stepped: bool = _player.try_step_up(Vector3(0.25, 0.0, 0.0))
	assert_true(stepped, "a 1 m ledge is within step height and should be climbed")
	assert_true(_player.global_position.y > before + 0.5,
			"stepping up should raise the player")


func test_player_cannot_step_up_a_three_metre_wall() -> void:
	await _setup(3.0)
	var before := _player.global_position.y
	var stepped: bool = _player.try_step_up(Vector3(0.25, 0.0, 0.0))
	assert_false(stepped, "a 3 m face is a wall, not a step")
	assert_almost_eq(_player.global_position.y, before, 0.001,
			"a refused step must not move the player")


func test_step_up_does_nothing_when_the_way_is_clear() -> void:
	# Guards against the player being levitated on every frame of open ground.
	await _setup(0.0)
	var before := _player.global_position.y
	var stepped: bool = _player.try_step_up(Vector3(0.25, 0.0, 0.0))
	assert_false(stepped, "open ground is not a step")
	assert_almost_eq(_player.global_position.y, before, 0.001)


func test_step_up_is_refused_in_mid_air() -> void:
	await _setup(1.0)
	_player.global_position.y += 5.0
	await step_physics(2)
	assert_false(_player.is_on_floor(), "player should be airborne for this check")
	assert_false(_player.try_step_up(Vector3(0.25, 0.0, 0.0)),
			"step-up is a grounded move only")


func test_crouching_lowers_the_player_and_slows_them() -> void:
	await _setup(0.0)
	var standing_speed: float = _player.current_speed()
	_player.set_crouching(true)
	assert_true(_player.is_crouching())
	assert_true(_player.current_speed() < standing_speed,
			"crouching should be slower than walking")
	_player.set_crouching(false)
	assert_false(_player.is_crouching())
	assert_almost_eq(_player.current_speed(), standing_speed, 0.001)


func test_jump_velocity_clears_the_intended_height() -> void:
	# Derived from gravity rather than hand-tuned, so the two cannot drift apart.
	var expected := sqrt(2.0 * Player.GRAVITY * Player.JUMP_HEIGHT_M)
	await _setup(0.0)
	assert_almost_eq(_player._jump_velocity, expected, 0.001)
	assert_true(Player.JUMP_HEIGHT_M > Player.MAX_STEP_HEIGHT,
			"a jump should clear more than a free step-up, or jumping is pointless")


func test_max_step_height_admits_one_terrace_but_not_two() -> void:
	# The terrain is quantized to 1 m, so this constant is what decides that a
	# single terrace is walkable and a double terrace is a cliff.
	assert_true(Player.MAX_STEP_HEIGHT >= 1.0,
			"must clear a single 1 m terrace")
	assert_true(Player.MAX_STEP_HEIGHT < 2.0,
			"must not clear a 2 m terrace, or cliffs stop existing")
