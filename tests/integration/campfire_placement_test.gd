extends "res://tests/test_case.gd"
## Integration tests for building and feeding a campfire.

const PlayerScene := preload("res://scenes/player.tscn")
const Campfire := preload("res://scripts/world/props/campfire.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")

var _world: Node3D
var _player: CharacterBody3D
var _placer: Node3D


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	_player = null
	_placer = null


func _setup() -> void:
	_world = Node3D.new()
	scene_root().add_child(_world)

	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40.0, 2.0, 40.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	_world.add_child(floor_body)
	# Top at y = 10, well above sea level so placement is legal.
	floor_body.global_position = Vector3(0.0, 9.0, 0.0)

	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	_player.global_position = Vector3(0.0, 10.5, 0.0)

	_placer = _player.get_node(^"ItemPlacer")
	_placer.bind(_player, _player.get_node(^"Camera3D"), _world, null)
	await step_physics(20)


func test_placing_a_campfire_consumes_it_and_lights_a_fire() -> void:
	await _setup()
	var inventory: RefCounted = _player.inventory()
	inventory.add(ItemKind.Kind.CAMPFIRE, 1)
	inventory.select(0)

	assert_true(_placer.use_held_item(), "placing should succeed on level ground")
	assert_eq(inventory.total_of(ItemKind.Kind.CAMPFIRE), 0,
			"the campfire item should be consumed")
	assert_eq(_placer.placed_fires().size(), 1)
	assert_true(_placer.placed_fires()[0].is_burning())


func test_a_placed_fire_stays_where_it_was_built() -> void:
	# Parented to the world, not the player: walking away must not take the fire along.
	await _setup()
	var inventory: RefCounted = _player.inventory()
	inventory.add(ItemKind.Kind.CAMPFIRE, 1)
	inventory.select(0)
	_placer.use_held_item()

	var fire: Node3D = _placer.placed_fires()[0]
	var built_at := fire.global_position
	_player.global_position += Vector3(12.0, 0.0, 0.0)
	await step_physics(4)
	assert_almost_eq(fire.global_position.distance_to(built_at), 0.0, 0.001)


func test_holding_nothing_places_nothing() -> void:
	await _setup()
	assert_false(_placer.use_held_item())
	assert_eq(_placer.placed_fires().size(), 0)


func test_wood_feeds_a_nearby_fire_rather_than_being_wasted() -> void:
	await _setup()
	var inventory: RefCounted = _player.inventory()
	inventory.add(ItemKind.Kind.CAMPFIRE, 1)
	inventory.select(0)
	_placer.use_held_item()

	var fire: Node3D = _placer.placed_fires()[0]
	fire.tick(100.0)
	var before: float = fire.fuel_remaining()

	inventory.add(ItemKind.Kind.WOOD, 1)
	inventory.select(0)
	assert_eq(inventory.selected_item(), ItemKind.Kind.WOOD)
	assert_true(_placer.use_held_item(), "wood beside a fire should be fuel")
	assert_true(fire.fuel_remaining() > before, "the fire should burn longer")
	assert_eq(inventory.total_of(ItemKind.Kind.WOOD), 0, "the log is consumed")


func test_eating_held_food_works_through_the_same_action() -> void:
	await _setup()
	var inventory: RefCounted = _player.inventory()
	var stats: RefCounted = _player.stats()
	stats.tick(300.0, false)
	var hungry: float = stats.hunger()

	inventory.add(ItemKind.Kind.BERRIES, 2)
	inventory.select(0)
	assert_true(_placer.use_held_item())
	assert_true(stats.hunger() < hungry, "eating should reduce hunger")
	assert_eq(inventory.total_of(ItemKind.Kind.BERRIES), 1)


func test_eating_with_nothing_to_gain_is_refused() -> void:
	# Refused only when there is no benefit at all. A partial top-up is allowed on
	# purpose: blocking it because some nutrition would be wasted would stop a player
	# eating before heading somewhere dangerous, which is worse than the waste.
	#
	# Hunger has to be reset immediately before the attempt: the settle frames above tick
	# it up, so a freshly spawned player is already slightly hungry.
	await _setup()
	var inventory: RefCounted = _player.inventory()
	_player.stats().revive()
	inventory.add(ItemKind.Kind.BERRIES, 1)
	inventory.select(0)
	assert_false(_placer.use_held_item(), "nothing to gain, so nothing is eaten")
	assert_eq(inventory.total_of(ItemKind.Kind.BERRIES), 1, "food is not consumed")


func test_eating_while_slightly_hungry_is_allowed() -> void:
	await _setup()
	var inventory: RefCounted = _player.inventory()
	var stats: RefCounted = _player.stats()
	stats.revive()
	stats.tick(20.0, false)
	inventory.add(ItemKind.Kind.BERRIES, 1)
	inventory.select(0)
	assert_true(_placer.use_held_item(),
			"a partial top-up is the player's call to make")
