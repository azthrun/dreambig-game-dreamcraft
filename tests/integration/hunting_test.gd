extends "res://tests/test_case.gd"
## Integration tests for the ecosystem: a predator hunting an animal, start to finish.
##
## The brains are tested headlessly elsewhere. What only a scene can show is the whole
## thing joined up — the registry finding the deer, the leopard closing on it over real
## terrain, the strike landing, the corpse appearing and the leopard walking away.

const CreatureBody := preload("res://scripts/creatures/creature_body.gd")
const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const CreatureRegistry := preload("res://scripts/creatures/creature_registry.gd")
const PredatorBrain := preload("res://scripts/creatures/predator_brain.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

const CELLS := 64
const CELL_SIZE := 4.0

## Long enough for a leopard to close on a fleeing deer and land three strikes. The
## closing speed is only 1.2 m/s, so a hunt is not a quick thing.
const HUNT_TICKS := 900

var _world: Node3D
var _player: Node3D
var _registry: RefCounted
var _map: RefCounted


func before_each() -> void:
	_registry = CreatureRegistry.new()
	_map = Heightmap.new(CELLS, CELL_SIZE)
	for cz in CELLS:
		for cx in CELLS:
			_map.set_height(cx, cz, 10)
			_map.set_biome(cx, cz, Biome.Kind.PLAINS)

	_world = Node3D.new()
	scene_root().add_child(_world)
	_player = Node3D.new()
	_world.add_child(_player)
	# Far enough that the player is not what anything reacts to, near enough that both
	# animals are inside the active radius and therefore thinking at all.
	_player.global_position = Vector3(0.0, 10.0, 90.0)


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	_player = null
	_registry = null
	_map = null


func _spawn(kind: int, at: Vector3) -> CharacterBody3D:
	var creature := CreatureBody.new()
	_world.add_child(creature)
	creature.global_position = at
	creature.configure(kind, _map, _player, 11, _registry)
	return creature


## Every corpse currently in the world.
func _corpses() -> Array:
	var found: Array = []
	for child in _world.get_children():
		if child is Node3D and child.has_method(&"configure") \
				and child.get_node_or_null(^"Body/Lootable") != null:
			found.append(child)
	return found


func test_a_predator_finds_and_kills_a_deer_on_its_own() -> void:
	var deer := _spawn(CreatureKind.Kind.DEER, Vector3(0.0, 10.0, 0.0))
	var leopard := _spawn(CreatureKind.Kind.LEOPARD, Vector3(6.0, 10.0, 0.0))

	var hunted := false
	for _i in HUNT_TICKS:
		await step_physics(1)
		if is_instance_valid(leopard) and leopard.state_name() != "patrol":
			hunted = true
		if not is_instance_valid(deer) or deer.is_dead():
			break

	assert_true(hunted, "the leopard should have engaged rather than patrolled past")
	assert_true(not is_instance_valid(deer) or deer.is_dead(),
			"the deer should be dead without the player having done anything")
	assert_eq(_corpses().size(), 1, "and it should have left a corpse to loot")


func test_the_predator_disengages_after_the_kill() -> void:
	var deer := _spawn(CreatureKind.Kind.DEER, Vector3(0.0, 10.0, 0.0))
	var leopard := _spawn(CreatureKind.Kind.LEOPARD, Vector3(6.0, 10.0, 0.0))

	for _i in HUNT_TICKS:
		await step_physics(1)
		if not is_instance_valid(deer) or deer.is_dead():
			break
	# A few more decisions, so "disengaged" means it settled rather than that the kill
	# was still in progress when the loop ended.
	await step_physics(30)

	assert_false(leopard.brain().is_attacking(),
			"it should not still be swinging at a carcass")
	assert_eq(leopard.brain().target(), PredatorBrain.Target.NONE,
			"and it should be hunting nothing at all")


func test_the_deer_runs_rather_than_standing_and_being_eaten() -> void:
	var deer := _spawn(CreatureKind.Kind.DEER, Vector3(0.0, 10.0, 0.0))
	_spawn(CreatureKind.Kind.LEOPARD, Vector3(8.0, 10.0, 0.0))
	var start := deer.global_position

	var fled := false
	for _i in 120:
		await step_physics(1)
		if not is_instance_valid(deer) or deer.is_dead():
			break
		if deer.state_name() == "flee":
			fled = true

	assert_true(fled, "the deer should notice the leopard, not just the player")
	assert_true(deer.global_position.distance_to(start) > 2.0,
			"and it should actually be running away")


func test_a_predator_with_nothing_to_hunt_just_patrols() -> void:
	# The other half: engagement has to be caused by the deer being there.
	var leopard := _spawn(CreatureKind.Kind.LEOPARD, Vector3(0.0, 10.0, 0.0))
	for _i in 120:
		await step_physics(1)
		assert_eq(leopard.brain().target(), PredatorBrain.Target.NONE)
		if leopard.brain().target() != PredatorBrain.Target.NONE:
			break
	assert_eq(leopard.state_name(), "patrol")


func test_the_player_is_preferred_when_the_player_is_closer() -> void:
	# Two things worth hunting, and the nearer one wins — the player standing next to a
	# leopard is not made safe by a deer being somewhere on the island.
	_player.global_position = Vector3(4.0, 10.0, 0.0)
	_spawn(CreatureKind.Kind.DEER, Vector3(-20.0, 10.0, 0.0))
	var leopard := _spawn(CreatureKind.Kind.LEOPARD, Vector3(0.0, 10.0, 0.0))

	await step_physics(20)
	assert_eq(leopard.brain().target(), PredatorBrain.Target.PLAYER)


func test_a_dead_animal_stops_being_a_target() -> void:
	# A stale registry entry would leave every predator hunting a corpse that is no
	# longer there, and no predator would ever find a live deer again.
	var deer := _spawn(CreatureKind.Kind.DEER, Vector3(0.0, 10.0, 0.0))
	_spawn(CreatureKind.Kind.LEOPARD, Vector3(6.0, 10.0, 0.0))
	await step_physics(4)
	assert_eq(_registry.count(), 2)

	deer.take_damage(9999.0)
	await step_physics(4)
	assert_eq(_registry.count(), 1, "the dead deer should be out of the registry")
	assert_true(_registry.nearest_of_role(Vector3.ZERO,
			CreatureKind.Role.PREY, 100.0).is_empty())
