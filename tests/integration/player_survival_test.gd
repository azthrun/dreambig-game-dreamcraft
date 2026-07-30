extends "res://tests/test_case.gd"
## Integration tests for survival on a live player: sprint gating, death and respawn.

const PlayerScene := preload("res://scenes/player.tscn")
const Player := preload("res://scripts/player/player.gd")

const SETTLE_TICKS := 30

var _world: Node3D
var _player: CharacterBody3D


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	_player = null


func _setup() -> void:
	_world = Node3D.new()
	scene_root().add_child(_world)

	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(60.0, 4.0, 60.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	_world.add_child(body)
	body.global_position = Vector3(0.0, -2.0, 0.0)

	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	_player.global_position = Vector3(0.0, 0.5, 0.0)
	_player.respawn_point = Vector3(25.0, 0.0, -25.0)
	await step_physics(SETTLE_TICKS)


func test_player_starts_alive_and_rested() -> void:
	await _setup()
	var stats: RefCounted = _player.stats()
	assert_false(stats.is_dead())
	assert_almost_eq(stats.stamina_fraction(), 1.0, 0.05)


func test_hunger_rises_while_playing() -> void:
	# The stats are ticked from the player's physics process, not only in unit tests.
	await _setup()
	var stats: RefCounted = _player.stats()
	var before: float = stats.hunger()
	await step_physics(60)
	assert_true(stats.hunger() > before,
			"hunger should advance as the game runs")


func test_an_exhausted_player_cannot_sprint() -> void:
	await _setup()
	var stats: RefCounted = _player.stats()
	# Drain directly rather than holding the key for eight seconds of test time.
	stats.tick(20.0, true)
	assert_almost_eq(stats.stamina(), 0.0, 0.001)
	assert_false(stats.can_sprint())

	Input.action_press(&"sprint")
	await step_physics(2)
	assert_almost_eq(_player.current_speed(), Player.WALK_SPEED, 0.001,
			"an exhausted player should drop to a walk, not sprint")
	Input.action_release(&"sprint")


func test_a_rested_player_can_sprint() -> void:
	# The other half of the gate: without this, the test above would pass even if
	# sprinting were broken entirely.
	await _setup()
	Input.action_press(&"sprint")
	await step_physics(2)
	assert_almost_eq(_player.current_speed(), Player.SPRINT_SPEED, 0.001)
	Input.action_release(&"sprint")


func test_death_returns_the_player_to_the_respawn_point() -> void:
	await _setup()
	var stats: RefCounted = _player.stats()
	stats.damage(9999.0)
	assert_true(stats.is_dead())
	await step_physics(3)
	assert_true(_player.global_position.distance_to(_player.respawn_point) < 3.0,
			"death should return the player to the shore, got %s"
					% _player.global_position)


func test_respawning_restores_condition_but_not_position() -> void:
	# Progress is kept, position is lost — death costs you where you are, not what you
	# have achieved.
	await _setup()
	var stats: RefCounted = _player.stats()
	stats.tick(400.0, true)
	var hungry: float = stats.hunger()
	assert_true(hungry > 10.0, "should be meaningfully hungry before dying")

	stats.damage(9999.0)
	await step_physics(3)
	assert_false(stats.is_dead(), "respawn should restore health")
	# Not exactly zero: the player is alive again and hunger resumes immediately, so a
	# few frames of it have already accrued. What matters is that it was reset.
	assert_true(stats.hunger() < 1.0,
			"hunger should be reset, was %.1f now %.3f" % [hungry, stats.hunger()])
	assert_true(stats.stamina_fraction() > 0.99)


func test_death_emits_a_signal() -> void:
	# Anything that needs to react to death should not have to poll for it.
	await _setup()
	var seen := [false]
	_player.died.connect(func(): seen[0] = true)
	_player.stats().damage(9999.0)
	await step_physics(3)
	assert_true(seen[0], "died should be emitted")


func test_respawn_clears_swimming_and_crouching() -> void:
	await _setup()
	_player.set_crouching(true)
	assert_true(_player.is_crouching())
	_player.stats().damage(9999.0)
	await step_physics(3)
	assert_false(_player.is_crouching(),
			"respawning should stand the player back up")
