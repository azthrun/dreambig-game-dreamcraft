extends "res://tests/test_case.gd"
## Integration tests for harvesting: aiming, holding, cancelling and refusal.
##
## Uses the real player, a real prop from the factory, and real physics, because the whole
## interaction is a raycast against a collider — none of which a pure test can reach.

const PlayerScene := preload("res://scenes/player.tscn")
const PropFactory := preload("res://scripts/world/props/prop_factory.gd")
const PropKind := preload("res://scripts/world/props/prop_kind.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")
const Harvester := preload("res://scripts/player/harvester.gd")

var _world: Node3D
var _player: CharacterBody3D
var _harvester: Node3D
var _prop: Node3D


func after_each() -> void:
	Input.action_release(&"interact")
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	_player = null
	_harvester = null
	_prop = null


## Player on a floor with a prop two metres in front, camera aimed at it.
func _setup(kind: int) -> void:
	_world = Node3D.new()
	scene_root().add_child(_world)

	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40.0, 2.0, 40.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	_world.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, -1.0, 0.0)

	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	_player.global_position = Vector3.ZERO

	var factory: RefCounted = PropFactory.new()
	_prop = factory.build(kind)
	_world.add_child(_prop)
	# Straight ahead: the player faces -Z by default.
	_prop.global_position = Vector3(0.0, 0.0, -2.0)

	_harvester = _player.get_node(^"Harvester")
	await step_physics(20)


func _harvestable() -> Node:
	return _prop.get_node(^"Harvestable")


## Holds interact long enough to finish, then releases.
func _hold_to_completion() -> void:
	Input.action_press(&"interact")
	await step_physics(int(Harvester.HOLD_SECONDS * 60.0) + 12)
	Input.action_release(&"interact")
	await step_physics(2)


func test_looking_at_a_tree_offers_a_prompt() -> void:
	await _setup(PropKind.Kind.TREE)
	assert_eq(_harvester.target(), _harvestable(),
			"should have acquired the tree in front of the player")
	assert_has(_harvester.prompt(), "wood",
			"the prompt should say what is on offer, got '%s'"
					% _harvester.prompt())


func test_looking_at_nothing_offers_no_prompt() -> void:
	await _setup(PropKind.Kind.TREE)
	_prop.global_position = Vector3(0.0, 0.0, 40.0)
	await step_physics(12)
	assert_eq(_harvester.target(), null)
	assert_eq(_harvester.prompt(), "")


func test_holding_interact_harvests_into_the_inventory() -> void:
	await _setup(PropKind.Kind.TREE)
	var inventory: RefCounted = _player.inventory()
	assert_eq(inventory.total_of(ItemKind.Kind.WOOD), 0)
	await _hold_to_completion()
	assert_true(inventory.total_of(ItemKind.Kind.WOOD) > 0,
			"a completed harvest should yield wood")
	assert_true(_harvestable().is_depleted())


func test_releasing_early_yields_nothing() -> void:
	# Harvesting is a commitment: letting go part-way must not bank partial progress.
	await _setup(PropKind.Kind.TREE)
	Input.action_press(&"interact")
	await step_physics(int(Harvester.HOLD_SECONDS * 60.0 * 0.4))
	Input.action_release(&"interact")
	await step_physics(4)
	assert_eq(_player.inventory().total_of(ItemKind.Kind.WOOD), 0)
	assert_false(_harvestable().is_depleted())
	assert_almost_eq(_harvester.progress(), 0.0, 0.001,
			"progress should be abandoned, not paused")


func test_a_depleted_prop_cannot_be_harvested_again() -> void:
	await _setup(PropKind.Kind.TREE)
	await _hold_to_completion()
	var after_first: int = _player.inventory().total_of(ItemKind.Kind.WOOD)
	await _hold_to_completion()
	assert_eq(_player.inventory().total_of(ItemKind.Kind.WOOD), after_first,
			"a stripped tree should give nothing more")


func test_a_full_inventory_is_refused_before_any_time_is_spent() -> void:
	# The refusal path the inventory was built for: the tree must still be standing.
	await _setup(PropKind.Kind.TREE)
	var inventory: RefCounted = _player.inventory()
	# Fill every slot with something that is not wood.
	inventory.add(ItemKind.Kind.STONE,
			ItemKind.stack_limit(ItemKind.Kind.STONE) * inventory.capacity())
	assert_true(inventory.is_full())

	Input.action_press(&"interact")
	await step_physics(12)
	assert_eq(_harvester.prompt(), "inventory full",
			"the player should be told why nothing is happening")
	assert_almost_eq(_harvester.progress(), 0.0, 0.001,
			"no time should be invested in a harvest that cannot succeed")
	Input.action_release(&"interact")
	assert_false(_harvestable().is_depleted(), "the tree should still be standing")


func test_berry_bushes_are_harvestable_despite_not_blocking_movement() -> void:
	# Bushes sit on the interaction layer precisely so this works; without a body the
	# ray would pass straight through and berries would be unreachable.
	await _setup(PropKind.Kind.BERRY_BUSH)
	assert_eq(_harvester.target(), _harvestable())
	await _hold_to_completion()
	assert_true(_player.inventory().total_of(ItemKind.Kind.BERRIES) > 0)


func test_rock_outcrops_yield_stone() -> void:
	await _setup(PropKind.Kind.ROCK_OUTCROP)
	await _hold_to_completion()
	assert_true(_player.inventory().total_of(ItemKind.Kind.STONE) > 0)


func test_cover_props_are_not_harvestable() -> void:
	# Shelter is worth standing under, not taking apart.
	await _setup(PropKind.Kind.CAVE_MOUTH)
	assert_eq(_prop.get_node_or_null(^"Harvestable"), null)
	assert_eq(_harvester.target(), null)
