extends "res://tests/test_case.gd"
## Integration tests for the flying suit: equip, refuel, flight steering, and the
## fuel-exhaustion transition back to falling.
##
## A scene rather than a pure test because the transition has to be observed through
## real physics (`move_and_slide`, gravity, `is_on_floor`) the same way the swim
## transition is — see AGENTS.md's testing section.

const PlayerScene := preload("res://scenes/player.tscn")
const ItemKind := preload("res://scripts/items/item_kind.gd")
const FlightFuel := preload("res://scripts/player/flight_fuel.gd")

var _world: Node3D
var _player: CharacterBody3D
var _inventory: RefCounted


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	_player = null
	_inventory = null


func _setup(with_suit: bool = true, fuel_items: int = 0) -> void:
	_world = Node3D.new()
	scene_root().add_child(_world)

	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	_player.global_position = Vector3(0.0, 40.0, 0.0)

	_inventory = _player.inventory()
	if with_suit:
		_inventory.add(ItemKind.Kind.FLYING_SUIT, 1)
		_select(ItemKind.Kind.FLYING_SUIT)
		_placer().use_held_item()
	if fuel_items > 0:
		_inventory.add(ItemKind.Kind.FUEL, fuel_items)
		for _i in fuel_items:
			_select(ItemKind.Kind.FUEL)
			_placer().use_held_item()

	await step_physics(2)


func _placer() -> Node:
	var placer: Node = _player.get_node(^"ItemPlacer")
	placer.bind(_player, _player.get_node(^"Camera3D"), _world, null)
	return placer


func _select(item: int) -> void:
	for slot in 5:
		if _inventory.item_in_slot(slot) == item:
			_inventory.select(slot)
			return


func test_using_the_suit_equips_it_and_consumes_it_from_the_pack() -> void:
	await _setup(true)
	assert_true(_player.has_flight_suit())
	assert_eq(_inventory.total_of(ItemKind.Kind.FLYING_SUIT), 0,
			"the equipped suit should leave the pack, the way armour does")


func test_using_it_twice_refuses_the_second_time() -> void:
	await _setup(true)
	_inventory.add(ItemKind.Kind.FLYING_SUIT, 1)
	_select(ItemKind.Kind.FLYING_SUIT)
	assert_false(_player.equip_selected_flight_suit(),
			"a second suit should not stack a second equip")


func test_fuel_can_be_added_to_the_equipped_suit() -> void:
	await _setup(true, 1)
	assert_true(_player.flight_fuel().fuel() > 0.0)
	assert_eq(_inventory.total_of(ItemKind.Kind.FUEL), 0)


func test_fuel_is_useless_without_an_equipped_suit() -> void:
	await _setup(false)
	_inventory.add(ItemKind.Kind.FUEL, 1)
	_select(ItemKind.Kind.FUEL)
	assert_false(_player.refuel_flight_suit())


func test_activating_flight_without_a_suit_does_nothing() -> void:
	await _setup(false)
	_player.toggle_flight()
	assert_false(_player.is_flying())


func test_activating_flight_without_fuel_refuses() -> void:
	await _setup(true, 0)
	var messages: Array[String] = []
	_player.message.connect(func(text: String): messages.append(text))
	_player.toggle_flight()
	assert_false(_player.is_flying())
	assert_eq(messages.size(), 1)
	assert_has(messages[0], "fuel")


func test_activating_flight_with_fuel_starts_flying() -> void:
	await _setup(true, 2)
	_player.toggle_flight()
	assert_true(_player.is_flying())


func test_toggling_again_lands_deliberately() -> void:
	await _setup(true, 2)
	_player.toggle_flight()
	assert_true(_player.is_flying())
	_player.toggle_flight()
	assert_false(_player.is_flying(),
			"the player should be able to end flight on purpose, with fuel still left")
	assert_true(_player.flight_fuel().fuel() > 0.0)


func test_flying_drains_fuel_over_time() -> void:
	await _setup(true, 2)
	_player.toggle_flight()
	var before: float = _player.flight_fuel().fuel()
	await step_physics(30)
	assert_true(_player.flight_fuel().fuel() < before,
			"fuel should be spent while airborne")


func test_flying_moves_the_player_upward_when_looking_up_and_holding_forward() -> void:
	await _setup(true, 2)
	var camera: Camera3D = _player.get_node(^"Camera3D")
	camera.rotation.x = deg_to_rad(45.0)
	_player.toggle_flight()

	var start_y := _player.global_position.y
	Input.action_press(&"move_forward")
	await step_physics(30)
	Input.action_release(&"move_forward")

	assert_true(_player.global_position.y > start_y,
			"holding forward while looking up should climb, since flight steers by "
			+ "mouselook in three dimensions")


func test_fuel_exhaustion_ends_flight_and_returns_to_falling() -> void:
	# A small tank drained by direct injection, so the test does not have to sit through
	# a real full flight to reach exhaustion.
	await _setup(true, 0)
	_player.flight_fuel().add(FlightFuel.DRAIN_PER_SECOND * 0.5)
	_player.toggle_flight()
	assert_true(_player.is_flying())

	await step_physics(90)

	assert_false(_player.is_flying(),
			"flight should end once the tank is empty")
	assert_true(_player.flight_fuel().is_empty())

	var falling_velocity_y := _player.velocity.y
	await step_physics(10)
	assert_true(_player.velocity.y < falling_velocity_y,
			"gravity should resume and pull the player down after flight ends")


func test_running_out_of_fuel_does_not_kill_the_player() -> void:
	await _setup(true, 0)
	_player.flight_fuel().add(FlightFuel.DRAIN_PER_SECOND * 0.5)
	_player.toggle_flight()
	var health_before: float = _player.stats().health()

	await step_physics(90)

	assert_false(_player.is_flying())
	assert_eq(_player.stats().health(), health_before,
			"exhausting the tank must not be instant death")
	assert_false(_player.stats().is_dead())
