extends "res://tests/test_case.gd"
## Integration tests for save/load: a full round trip through real Player, Props,
## Weather and Sky nodes, since moving state in and out of real Nodes is not reducible to
## a pure function the way `SaveData`'s own encode/decode is — see `save_data_test.gd`
## for that half.
##
## Each test builds a first world, mutates it away from its spawn defaults, captures a
## save, tears the world down completely, builds a second fresh world from the same
## seed, applies the save, and compares. The second world is never told anything about
## the first except the save data itself — the same shape "quit and resume" actually is.

const PlayerScene := preload("res://scenes/player.tscn")
const PropsScript := preload("res://scripts/world/props.gd")
const SkyScript := preload("res://scripts/world/sky.gd")
const WeatherScript := preload("res://scripts/world/weather.gd")
const WeatherModel := preload("res://scripts/world/weather_model.gd")
const Campfire := preload("res://scripts/world/props/campfire.gd")
const SaveManager := preload("res://scripts/persistence/save_manager.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")

## Mountains only: caches are at their densest here and rock outcrops are a common
## harvestable, without the tree flood a forest map would build thousands of nodes for.
const CELLS := 64
const CELL_SIZE := 4.0
const WORLD_SEED := 4242

var _worlds: Array[Node3D] = []


func after_each() -> void:
	for world in _worlds:
		if is_instance_valid(world):
			world.free()
	_worlds.clear()


func _map() -> RefCounted:
	var map: RefCounted = Heightmap.new(CELLS, CELL_SIZE)
	for cz in CELLS:
		for cx in CELLS:
			map.set_height(cx, cz, 20)
			map.set_biome(cx, cz, Biome.Kind.MOUNTAINS)
	return map


## A fresh world, wired the way `main.gd` wires it: floor, player, props populated from
## the seed, sky, weather, and the player's item placer bound to props as its world root.
func _build_world() -> Dictionary:
	var world := Node3D.new()
	scene_root().add_child(world)
	_worlds.append(world)

	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(300.0, 2.0, 300.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	world.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, 19.0, 0.0)

	var player: CharacterBody3D = PlayerScene.instantiate()
	world.add_child(player)
	player.global_position = Vector3(0.0, 20.0, 0.0)

	var props: Node3D = PropsScript.new()
	world.add_child(props)
	props.populate(_map(), WORLD_SEED)

	var sky: Node = SkyScript.new()
	world.add_child(sky)

	var weather: Node = WeatherScript.new()
	weather.weather_seed = WORLD_SEED
	world.add_child(weather)

	var item_placer: Node = player.item_placer()
	item_placer.bind(player, player.get_node(^"Camera3D"), props, null)

	return {
		"player": player, "props": props, "sky": sky,
		"weather": weather, "item_placer": item_placer,
	}


func _snapshot_inventory(inventory: RefCounted) -> Array:
	var snapshot: Array = []
	for i in inventory.capacity():
		snapshot.append([inventory.item_in_slot(i), inventory.count_in_slot(i)])
	return snapshot


func test_a_full_round_trip_restores_an_equivalent_game_state() -> void:
	var w1 := await _setup_and_mutate()
	var player1: CharacterBody3D = w1["player"]
	var props1: Node3D = w1["props"]
	var sky1: Node = w1["sky"]
	var weather1: Node = w1["weather"]
	var item_placer1: Node = w1["item_placer"]

	var expected_position: Vector3 = player1.global_position
	var expected_health: float = player1.stats().health()
	var expected_hunger: float = player1.stats().hunger()
	var expected_stamina: float = player1.stats().stamina()
	var expected_worn: int = player1.worn_item()
	var expected_suit: bool = player1.has_flight_suit()
	var expected_fuel: float = player1.flight_fuel().fuel()
	var expected_inventory := _snapshot_inventory(player1.inventory())
	var expected_selected: int = player1.inventory().selected_slot()
	var expected_time: float = sky1.time_of_day()
	var expected_weather_state: int = weather1.current()
	var expected_weather_remaining: float = weather1.time_until_change()
	var placed_fire: Node3D = item_placer1.placed_fires()[0]
	var expected_fire_position: Vector3 = placed_fire.global_position
	var expected_fire_fuel: float = placed_fire.fuel_remaining()
	var expected_fire_cooking: int = placed_fire.cooking_count()

	var looted_cache: Node = w1["looted_cache"]
	var expected_cache_id: int = looted_cache.cache_id
	var depleted_prop: Node = w1["depleted_harvestable"]
	var expected_prop_id: int = depleted_prop.prop_id

	var save: RefCounted = SaveManager.capture(
			WORLD_SEED, sky1, weather1, player1, props1, item_placer1)

	# Torn down entirely — the second world learns everything it knows from `save` alone.
	for world in _worlds:
		if is_instance_valid(world):
			world.free()
	_worlds.clear()

	var w2 := _build_world()
	await step_physics(2)
	var player2: CharacterBody3D = w2["player"]
	var props2: Node3D = w2["props"]
	var sky2: Node = w2["sky"]
	var weather2: Node = w2["weather"]
	var item_placer2: Node = w2["item_placer"]

	var ok := SaveManager.apply(save, WORLD_SEED, sky2, weather2, player2, props2,
			item_placer2)
	assert_true(ok, "a matching seed should be accepted")

	assert_almost_eq(player2.global_position.distance_to(expected_position), 0.0, 0.001)
	assert_almost_eq(player2.stats().health(), expected_health, 0.001)
	assert_almost_eq(player2.stats().hunger(), expected_hunger, 0.001)
	assert_almost_eq(player2.stats().stamina(), expected_stamina, 0.001)
	assert_eq(player2.worn_item(), expected_worn)
	assert_eq(player2.has_flight_suit(), expected_suit)
	assert_almost_eq(player2.flight_fuel().fuel(), expected_fuel, 0.001)
	assert_eq(_snapshot_inventory(player2.inventory()), expected_inventory,
			"inventory should restore to the exact same slots, not just the same totals")
	assert_eq(player2.inventory().selected_slot(), expected_selected)

	assert_almost_eq(sky2.time_of_day(), expected_time, 0.0001)
	assert_eq(weather2.current(), expected_weather_state)
	assert_almost_eq(weather2.time_until_change(), expected_weather_remaining, 0.001)

	assert_eq(item_placer2.placed_fires().size(), 1,
			"the placed campfire should still exist after reload")
	var restored_fire: Node3D = item_placer2.placed_fires()[0]
	assert_almost_eq(restored_fire.global_position.distance_to(expected_fire_position),
			0.0, 0.001)
	assert_almost_eq(restored_fire.fuel_remaining(), expected_fire_fuel, 0.001)
	assert_eq(restored_fire.cooking_count(), expected_fire_cooking)

	var restored_cache := _find_by_id(props2.caches(), "cache_id", expected_cache_id)
	assert_true(restored_cache != null, "the looted cache should exist in the new world")
	assert_true(restored_cache.is_looted(),
			"looted caches must remain looted across a save/load cycle")

	var restored_prop := _find_by_id(props2.harvestables(), "prop_id", expected_prop_id)
	assert_true(restored_prop != null, "the depleted prop should exist in the new world")
	assert_true(restored_prop.is_depleted(),
			"a depleted prop should still be depleted after reload")


func test_looted_caches_survive_a_reload_and_cannot_be_farmed() -> void:
	var w1 := await _setup_and_mutate()
	var props1: Node3D = w1["props"]
	var looted_cache: Node = w1["looted_cache"]
	var cache_id: int = looted_cache.cache_id

	var save: RefCounted = SaveManager.capture(WORLD_SEED, w1["sky"], w1["weather"],
			w1["player"], props1, w1["item_placer"])

	for world in _worlds:
		if is_instance_valid(world):
			world.free()
	_worlds.clear()

	var w2 := _build_world()
	await step_physics(2)
	SaveManager.apply(save, WORLD_SEED, w2["sky"], w2["weather"], w2["player"],
			w2["props"], w2["item_placer"])

	var restored := _find_by_id(w2["props"].caches(), "cache_id", cache_id)
	assert_true(restored != null)
	assert_true(restored.is_looted(),
			"reloading must not un-loot a cache — that is exactly how ammo would be farmed")
	assert_eq(restored.loot(w2["player"].inventory()), {},
			"an already-looted cache should still refuse to give anything up")


func test_prop_depletion_survives_a_reload() -> void:
	var w1 := await _setup_and_mutate()
	var depleted_prop: Node = w1["depleted_harvestable"]
	var prop_id: int = depleted_prop.prop_id
	var remaining_before: float = depleted_prop.time_until_respawn()

	var save: RefCounted = SaveManager.capture(WORLD_SEED, w1["sky"], w1["weather"],
			w1["player"], w1["props"], w1["item_placer"])

	for world in _worlds:
		if is_instance_valid(world):
			world.free()
	_worlds.clear()

	var w2 := _build_world()
	await step_physics(2)
	SaveManager.apply(save, WORLD_SEED, w2["sky"], w2["weather"], w2["player"],
			w2["props"], w2["item_placer"])

	var restored := _find_by_id(w2["props"].harvestables(), "prop_id", prop_id)
	assert_true(restored != null)
	assert_true(restored.is_depleted())
	assert_almost_eq(restored.time_until_respawn(), remaining_before, 0.001,
			"the regrow countdown should pick up where it left off, not restart")
	assert_eq(restored.harvest(), 0,
			"a depleted prop should still refuse to be harvested again")


func test_a_mismatched_seed_is_refused_rather_than_applied() -> void:
	var w1 := await _setup_and_mutate()
	var save: RefCounted = SaveManager.capture(WORLD_SEED, w1["sky"], w1["weather"],
			w1["player"], w1["props"], w1["item_placer"])

	var w2 := _build_world()
	await step_physics(2)
	var player2: CharacterBody3D = w2["player"]
	var position_before: Vector3 = player2.global_position
	var health_before: float = player2.stats().health()

	var ok := SaveManager.apply(save, WORLD_SEED + 1, w2["sky"], w2["weather"], player2,
			w2["props"], w2["item_placer"])

	assert_false(ok, "a save from a different island must be refused")
	assert_almost_eq(player2.global_position.distance_to(position_before), 0.0, 0.001,
			"a refused load must not have touched anything")
	assert_almost_eq(player2.stats().health(), health_before, 0.001)


## Builds a world, mutates it away from spawn defaults across every saved system, and
## returns the live nodes plus the specific cache/harvestable that were touched.
func _setup_and_mutate() -> Dictionary:
	var w := _build_world()
	await step_physics(2)
	var player: CharacterBody3D = w["player"]
	var props: Node3D = w["props"]
	var sky: Node = w["sky"]
	var weather: Node = w["weather"]
	var item_placer: Node = w["item_placer"]
	var inventory: RefCounted = player.inventory()

	player.global_position = Vector3(37.0, 20.0, -19.0)
	player.stats().restore(63.0, 22.0, 55.0)

	inventory.add(ItemKind.Kind.WOOD, 5)
	inventory.add(ItemKind.Kind.PISTOL, 1)
	inventory.add(ItemKind.Kind.PISTOL_AMMO, 12)

	inventory.add(ItemKind.Kind.HIDE_ARMOUR, 1)
	inventory.select(_slot_of(inventory, ItemKind.Kind.HIDE_ARMOUR))
	player.wear_selected()

	inventory.add(ItemKind.Kind.FLYING_SUIT, 1)
	inventory.select(_slot_of(inventory, ItemKind.Kind.FLYING_SUIT))
	player.equip_selected_flight_suit()
	player.flight_fuel().add(50.0)

	var fire: Node3D = Campfire.new()
	props.add_child(fire)
	fire.global_position = Vector3(5.0, 20.0, 3.0)
	fire.add_raw_meat(2)
	item_placer.register_fire(fire)

	var looted_cache: Node = props.caches()[0]
	looted_cache.loot(inventory)
	assert_true(looted_cache.is_looted(), "test setup: the cache should now be looted")

	var depleted_harvestable: Node = props.harvestables()[0]
	depleted_harvestable.harvest()
	assert_true(depleted_harvestable.is_depleted(),
			"test setup: the prop should now be depleted")

	sky.set_time_of_day(0.73)
	weather.set_state(WeatherModel.State.THUNDERSTORM)

	return {
		"player": player, "props": props, "sky": sky, "weather": weather,
		"item_placer": item_placer,
		"looted_cache": looted_cache, "depleted_harvestable": depleted_harvestable,
	}


func _slot_of(inventory: RefCounted, item: int) -> int:
	for i in inventory.capacity():
		if inventory.item_in_slot(i) == item:
			return i
	return 0


func _find_by_id(nodes: Array, id_field: String, id: int) -> Node:
	for node in nodes:
		if is_instance_valid(node) and int(node.get(id_field)) == id:
			return node
	return null
