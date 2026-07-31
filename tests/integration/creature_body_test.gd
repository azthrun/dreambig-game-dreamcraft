extends "res://tests/test_case.gd"
## Integration tests for creature locomotion: grounding, slope refusal, and activity.
##
## Uses a hand-built heightmap rather than a generated island, so the cliff under test is
## exactly where the test put it.

const CreatureBody := preload("res://scripts/creatures/creature_body.gd")
const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const CreatureFactory := preload("res://scripts/creatures/creature_factory.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

const CELLS := 64
const CELL_SIZE := 4.0

var _world: Node3D
var _player: Node3D
var _creature: CharacterBody3D


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	_player = null
	_creature = null


## Flat land at `height`, with an optional wall of `wall_height` for x cells >= 40.
func _map(height: int, wall_height: int = -1) -> RefCounted:
	var map: RefCounted = Heightmap.new(CELLS, CELL_SIZE)
	for cz in CELLS:
		for cx in CELLS:
			var h := height
			if wall_height >= 0 and cx >= 40:
				h = wall_height
			map.set_height(cx, cz, h)
			map.set_biome(cx, cz, Biome.Kind.PLAINS)
	return map


func _spawn(map: RefCounted, at: Vector3, player_at: Vector3) -> void:
	_world = Node3D.new()
	scene_root().add_child(_world)

	_player = Node3D.new()
	_world.add_child(_player)
	_player.global_position = player_at

	_creature = CreatureBody.new()
	_world.add_child(_creature)
	_creature.global_position = at
	_creature.configure(CreatureKind.Kind.DEER, map, _player, 42)


## World position of a cell centre.
func _at_cell(map: RefCounted, cx: int, cz: int) -> Vector3:
	var half: float = map.size_m() * 0.5
	return Vector3(
			float(cx) * CELL_SIZE - half + CELL_SIZE * 0.5,
			float(map.height_at_cell(cx, cz)),
			float(cz) * CELL_SIZE - half + CELL_SIZE * 0.5)


func test_a_creature_stands_on_the_terrain() -> void:
	# Grounding is an O(1) heightmap lookup rather than a raycast or a navmesh.
	var map := _map(12)
	_spawn(map, _at_cell(map, 20, 20) + Vector3(0.0, 30.0, 0.0),
			_at_cell(map, 22, 20))
	await step_physics(20)
	assert_almost_eq(_creature.global_position.y, 12.0, 0.01,
			"should settle to the terrain height, not float or sink")


func test_a_creature_flees_a_nearby_player() -> void:
	var map := _map(10)
	var start := _at_cell(map, 20, 20)
	_spawn(map, start, start + Vector3(4.0, 0.0, 0.0))
	await step_physics(30)
	assert_eq(_creature.state_name(), "flee",
			"a player at arm's length should start a flight")
	assert_true(_creature.global_position.distance_to(start) > 1.0,
			"and it should actually be running")


func test_a_creature_will_not_climb_a_cliff() -> void:
	# The wall is 6m, far beyond the 1.05m step limit, so the deer must be stopped by it
	# even while fleeing straight at it.
	var map := _map(10, 16)
	var start := _at_cell(map, 38, 20)
	# Player on the open side, so the deer flees towards the wall.
	_spawn(map, start, start - Vector3(8.0, 0.0, 0.0))
	await step_physics(90)
	assert_true(_creature.global_position.y < 16.0,
			"the deer must not be standing on top of the cliff, got y=%.1f"
					% _creature.global_position.y)
	assert_almost_eq(_creature.global_position.y, 10.0, 0.5,
			"it should still be on the low ground")


func test_a_creature_can_cross_a_single_terrace_step() -> void:
	# The other half of slope refusal: a 1m step is walkable, or the island would be
	# impassable to everything.
	var map := _map(10, 11)
	var start := _at_cell(map, 38, 20)
	_spawn(map, start, start - Vector3(6.0, 0.0, 0.0))
	await step_physics(120)
	assert_true(_creature.global_position.y >= 10.0)
	assert_true(CreatureBody.MAX_CLIMB_M >= 1.0,
			"one terrace must be climbable")
	assert_true(CreatureBody.MAX_CLIMB_M < 2.0,
			"two terraces must not be")


func test_creatures_far_from_the_player_stop_thinking() -> void:
	# Dozens on the island: per-frame cost has to follow what the player can see.
	var map := _map(10)
	var start := _at_cell(map, 5, 5)
	_spawn(map, start, start + Vector3(CreatureBody.ACTIVE_RADIUS_M + 60.0,
			0.0, 0.0))
	await step_physics(30)
	assert_false(_creature.is_active(),
			"a distant animal should be idle, not simulating")


func test_creatures_near_the_player_do_think() -> void:
	var map := _map(10)
	var start := _at_cell(map, 20, 20)
	_spawn(map, start, start + Vector3(30.0, 0.0, 0.0))
	await step_physics(30)
	assert_true(_creature.is_active())


func test_a_creature_never_walks_into_the_sea() -> void:
	var map := _map(10)
	# Drown the far half of the map.
	for cz in CELLS:
		for cx in range(40, CELLS):
			map.set_height(cx, cz, -4)
			map.set_biome(cx, cz, Biome.Kind.OCEAN)
	var start := _at_cell(map, 38, 20)
	_spawn(map, start, start - Vector3(8.0, 0.0, 0.0))
	await step_physics(120)
	assert_true(_creature.global_position.y > 0.0,
			"a fleeing deer should stop at the shore, not swim out")


func test_a_creature_has_the_three_gaits() -> void:
	var map := _map(10)
	var start := _at_cell(map, 20, 20)
	_spawn(map, start, start + Vector3(60.0, 0.0, 0.0))
	await step_physics(4)
	var animator: AnimationPlayer = _creature.get_node(^"AnimationPlayer")
	for clip in [CreatureFactory.CLIP_IDLE, CreatureFactory.CLIP_WALK,
			CreatureFactory.CLIP_RUN]:
		assert_true(animator.has_animation(clip), "missing the %s clip" % clip)


func test_creatures_do_not_block_the_player() -> void:
	# Animals are on their own layer and collide with nothing: being shoved around by
	# wildlife would be worse than walking through it.
	var map := _map(10)
	var start := _at_cell(map, 20, 20)
	_spawn(map, start, start + Vector3(30.0, 0.0, 0.0))
	await step_physics(4)
	assert_eq(_creature.collision_mask, 0)
	assert_eq(_creature.collision_layer, CreatureBody.CREATURE_LAYER)
	assert_eq(_creature.collision_layer & 1, 0,
			"creatures must not sit on the world layer")
