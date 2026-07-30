extends "res://tests/test_case.gd"
## Integration tests for the sheltered state.
##
## Area3D overlap is a physics property, so these build the real cover prop and walk a
## real player body into it rather than calling the accessors directly.

const PlayerScene := preload("res://scenes/player.tscn")
const PropFactory := preload("res://scripts/world/props/prop_factory.gd")
const PropKind := preload("res://scripts/world/props/prop_kind.gd")

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
	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	# Parked well away from any shelter to start.
	_player.global_position = Vector3(200.0, 0.0, 200.0)
	await step_physics(2)


func _add_cover(kind: int, at: Vector3) -> Node3D:
	var factory: RefCounted = PropFactory.new()
	var prop: Node3D = factory.build(kind)
	_world.add_child(prop)
	prop.global_position = at
	return prop


func test_player_starts_unsheltered() -> void:
	await _setup()
	assert_false(_player.is_sheltered())


func test_walking_into_cover_shelters_the_player() -> void:
	await _setup()
	for kind in PropKind.COVER:
		_add_cover(kind, Vector3.ZERO)
		await step_physics(2)
		_player.global_position = Vector3(0.0, 0.6, 0.0)
		await step_physics(4)
		assert_true(_player.is_sheltered(),
				"standing inside a %s should shelter the player"
						% PropKind.name_of(kind))
		# Move back out and reset for the next kind.
		_player.global_position = Vector3(200.0, 0.0, 200.0)
		await step_physics(4)
		assert_false(_player.is_sheltered(),
				"leaving a %s should clear shelter" % PropKind.name_of(kind))
		after_each()
		await _setup()


func test_leaving_cover_clears_shelter() -> void:
	await _setup()
	_add_cover(PropKind.Kind.CAVE_MOUTH, Vector3.ZERO)
	await step_physics(2)
	_player.global_position = Vector3(0.0, 0.6, 0.0)
	await step_physics(4)
	assert_true(_player.is_sheltered())
	_player.global_position = Vector3(60.0, 0.6, 60.0)
	await step_physics(4)
	assert_false(_player.is_sheltered())


func test_overlapping_cover_does_not_lose_shelter_on_leaving_one() -> void:
	# The reason shelter is a count and not a flag: two cover props can overlap, and
	# stepping out of one while still under the other must not expose the player.
	await _setup()
	_add_cover(PropKind.Kind.THICKET, Vector3.ZERO)
	_add_cover(PropKind.Kind.OVERHANG, Vector3(1.0, 0.0, 0.0))
	await step_physics(2)
	_player.global_position = Vector3(0.6, 0.6, 0.0)
	await step_physics(4)
	assert_true(_player.is_sheltered(), "should be inside both volumes")
	# Simulate leaving exactly one volume.
	_player.exit_shelter()
	assert_true(_player.is_sheltered(),
			"still inside the other volume, so still sheltered")
	_player.exit_shelter()
	assert_false(_player.is_sheltered())


func test_shelter_count_never_goes_negative() -> void:
	# A stray exit must not leave the player permanently unshelterable.
	await _setup()
	_player.exit_shelter()
	_player.exit_shelter()
	assert_false(_player.is_sheltered())
	_player.enter_shelter()
	assert_true(_player.is_sheltered(),
			"one enter should shelter, regardless of earlier stray exits")
