extends "res://tests/test_case.gd"
## Integration tests for the walk/swim transition.
##
## Water has no collision anywhere in this game, so these use a seabed box below sea
## level and a nominal water level on the player. That mirrors the real setup exactly:
## nothing about swimming depends on the water mesh existing.

const PlayerScene := preload("res://scenes/player.tscn")
const Player := preload("res://scripts/player/player.gd")

const WATER_LEVEL := 0.0
const SETTLE_TICKS := 30

var _world: Node3D
var _player: CharacterBody3D


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	_player = null


## Seabed whose top sits at `bed_y`, with the player dropped just above it.
func _setup(bed_y: float, drop_from: float) -> void:
	_world = Node3D.new()
	scene_root().add_child(_world)

	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(60.0, 4.0, 60.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	_world.add_child(body)
	body.global_position = Vector3(0.0, bed_y - 2.0, 0.0)

	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	_player.water_level_y = WATER_LEVEL
	_player.global_position = Vector3(0.0, drop_from, 0.0)

	await step_physics(SETTLE_TICKS)


func test_standing_on_dry_land_is_not_swimming() -> void:
	await _setup(6.0, 7.0)
	assert_false(_player.is_swimming(), "land above the waterline is walking")
	assert_true(_player.is_on_floor())


func test_wading_in_shallow_water_is_still_walking() -> void:
	# Feet under the surface but chest clear. This is what keeps a beach walkable and
	# a river crossable rather than turning every puddle into a swim.
	await _setup(-0.8, 0.5)
	assert_false(_player.submerged(),
			"chest above water should not count as submerged")
	assert_false(_player.is_swimming())
	assert_true(_player.is_on_floor(), "shallow water still has a floor underfoot")


func test_entering_deep_water_switches_to_swimming() -> void:
	await _setup(-20.0, -6.0)
	assert_true(_player.is_swimming(),
			"a player well below the surface should be swimming")
	assert_true(_player.current_speed() < Player.WALK_SPEED,
			"swimming should be slower than walking")


func test_swimming_floats_the_player_up_to_the_surface() -> void:
	# Buoyancy, not collision: there is nothing solid at the waterline to stop on.
	await _setup(-20.0, -12.0)
	assert_true(_player.is_swimming())
	await step_physics(180)
	var expected := WATER_LEVEL - Player.SWIM_FLOAT_DEPTH
	assert_almost_eq(_player.global_position.y, expected, 0.4,
			"player should settle at floating depth with their head clear")


func test_leaving_the_water_returns_to_walking() -> void:
	await _setup(-20.0, -6.0)
	assert_true(_player.is_swimming())
	# Lift onto dry land; the state is derived from position, so it should follow.
	_player.global_position = Vector3(0.0, 10.0, 0.0)
	await step_physics(2)
	assert_false(_player.is_swimming(), "out of the water is walking again")


func test_player_cannot_stand_on_the_water_surface() -> void:
	# Dropped from high above deep water, the player must end up below the surface
	# rather than resting on it.
	await _setup(-20.0, 12.0)
	await step_physics(150)
	assert_true(_player.global_position.y < WATER_LEVEL,
			"the sea is not walkable, so the player must sink into it")
	assert_true(_player.is_swimming())


func test_swimming_ignores_crouch() -> void:
	await _setup(-20.0, -6.0)
	_player.set_crouching(true)
	await step_physics(2)
	assert_false(_player.is_crouching(),
			"crouching underwater has no meaning and should be cleared")
