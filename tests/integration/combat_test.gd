extends "res://tests/test_case.gd"
## Integration tests for hunting: swinging, killing, and looting what is left.

const PlayerScene := preload("res://scenes/player.tscn")
const CreatureBody := preload("res://scripts/creatures/creature_body.gd")
const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const Melee := preload("res://scripts/player/melee.gd")
const Harvester := preload("res://scripts/player/harvester.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")

const CELLS := 32
const CELL_SIZE := 4.0

var _world: Node3D
var _player: CharacterBody3D
var _melee: Node3D
var _creature: CharacterBody3D


func after_each() -> void:
	Input.action_release(&"interact")
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	_player = null
	_melee = null
	_creature = null


func _flat_map() -> RefCounted:
	var map: RefCounted = Heightmap.new(CELLS, CELL_SIZE)
	for cz in CELLS:
		for cx in CELLS:
			map.set_height(cx, cz, 10)
			map.set_biome(cx, cz, Biome.Kind.PLAINS)
	return map


## Player at the origin with a deer two metres ahead, in reach of a swing.
func _setup() -> void:
	_world = Node3D.new()
	scene_root().add_child(_world)

	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(60.0, 2.0, 60.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	_world.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, 9.0, 0.0)

	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	_player.global_position = Vector3(0.0, 10.0, 0.0)
	_melee = _player.get_node(^"Melee")

	_creature = CreatureBody.new()
	_world.add_child(_creature)
	# Straight ahead: the player faces -Z.
	_creature.global_position = Vector3(0.0, 10.0, -2.0)
	_creature.configure(CreatureKind.Kind.DEER, _flat_map(), _player, 11)

	await step_physics(6)


func test_a_creature_starts_at_its_species_health() -> void:
	await _setup()
	assert_almost_eq(_creature.health(),
			CreatureKind.health(CreatureKind.Kind.DEER), 0.001)
	assert_false(_creature.is_dead())


func test_swinging_at_a_creature_wounds_it() -> void:
	await _setup()
	var before: float = _creature.health()
	assert_true(_melee.swing(), "the swing should happen")
	assert_true(_creature.health() < before, "the deer should be wounded")


func test_damage_comes_from_the_held_item() -> void:
	await _setup()
	var inventory: RefCounted = _player.inventory()
	assert_almost_eq(_melee.damage(), ItemKind.BARE_HAND_DAMAGE, 0.001)

	inventory.add(ItemKind.Kind.STONE_TOOL, 1)
	inventory.select(0)
	assert_almost_eq(_melee.damage(),
			ItemKind.melee_damage(ItemKind.Kind.STONE_TOOL), 0.001)
	assert_true(_melee.damage() > ItemKind.BARE_HAND_DAMAGE)


func test_swings_are_rate_limited() -> void:
	# A swing is a commitment, which is what will make backing off matter once
	# predators can hit back.
	await _setup()
	assert_true(_melee.swing())
	assert_false(_melee.swing(), "a second swing immediately after should be refused")
	assert_false(_melee.is_ready())
	await step_physics(int(Melee.COOLDOWN_SECONDS * 60.0) + 6)
	assert_true(_melee.is_ready(), "and allowed again once the cooldown elapses")


func test_a_swing_at_nothing_still_costs_the_cooldown() -> void:
	await _setup()
	_creature.global_position = Vector3(0.0, 10.0, 40.0)
	await step_physics(4)
	assert_true(_melee.swing(), "swinging at air is still a swing")
	assert_false(_melee.is_ready())


func test_enough_hits_kill_the_creature_and_leave_a_corpse() -> void:
	await _setup()
	var at := _creature.global_position
	# Damage directly rather than waiting out a cooldown per swing.
	_creature.take_damage(CreatureKind.health(CreatureKind.Kind.DEER))
	await step_physics(4)

	var corpse: Node3D = null
	for child in _world.get_children():
		if child.get_script() == preload("res://scripts/creatures/corpse.gd"):
			corpse = child
	assert_true(corpse != null, "a kill should leave a corpse")
	assert_true(corpse.global_position.distance_to(at) < 1.0,
			"the corpse should be where the animal fell")


func test_death_is_announced_with_what_died_and_where() -> void:
	await _setup()
	var seen := {"kind": -1}
	_creature.died.connect(func(kind, _at): seen["kind"] = kind)
	_creature.take_damage(9999.0)
	assert_eq(seen["kind"], CreatureKind.Kind.DEER)


func test_a_dead_creature_cannot_be_hit_again() -> void:
	await _setup()
	_creature.take_damage(9999.0)
	assert_true(_creature.is_dead())
	_creature.take_damage(50.0)
	assert_almost_eq(_creature.health(), 0.0, 0.001,
			"health must not go negative on a corpse")


func test_being_struck_panics_an_animal_that_had_not_noticed() -> void:
	# Shot in the back from beyond detection range, it should still bolt.
	await _setup()
	_creature.global_position = Vector3(0.0, 10.0, -60.0)
	await step_physics(20)
	_creature.take_damage(1.0)
	assert_eq(_creature.state_name(), "flee",
			"a struck animal runs whether or not it saw you coming")


func test_looting_a_corpse_yields_the_species_drops() -> void:
	await _setup()
	_creature.take_damage(9999.0)
	await step_physics(6)

	var inventory: RefCounted = _player.inventory()
	var harvester: Node3D = _player.get_node(^"Harvester")
	Input.action_press(&"interact")
	await step_physics(int(Harvester.HOLD_SECONDS * 60.0) + 14)
	Input.action_release(&"interact")
	await step_physics(2)

	assert_true(inventory.total_of(ItemKind.Kind.RAW_MEAT) > 0,
			"looting should yield meat, prompt was '%s'" % harvester.prompt())
	assert_true(inventory.total_of(ItemKind.Kind.HIDE) > 0,
			"and hide")
