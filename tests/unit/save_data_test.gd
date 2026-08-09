extends "res://tests/test_case.gd"
## SaveData's own round trip: `to_dict()` followed by `from_dict()` on plain data, with
## no Node, no Player, no scene — the primary seam this project's testing strategy is
## built around. See `save_load_test.gd` for the scene-based half that actually moves
## state in and out of live systems.

const SaveData := preload("res://scripts/persistence/save_data.gd")


func _filled() -> RefCounted:
	var save: RefCounted = SaveData.new()
	save.world_seed = 20260729
	save.time_of_day = 0.4125
	save.weather_state = 3
	save.weather_remaining = 271.5
	save.player_position = Vector3(12.5, 8.0, -340.25)
	save.player_health = 63.0
	save.player_hunger = 22.5
	save.player_stamina = 88.0
	save.worn_item = 9
	save.flight_suit_equipped = true
	save.flight_fuel = 47.5
	save.inventory_slots = [
		{"slot": 0, "item": 1, "count": 5},
		{"slot": 3, "item": 12, "count": 1},
	]
	save.selected_slot = 3
	save.campfires = [
		{"x": 1.0, "y": 2.0, "z": 3.0, "fuel": 150.0, "cooking_count": 1,
				"cook_elapsed": 4.0},
	]
	save.looted_caches = [
		{"cache_id": 512, "remaining": 340.0, "refills": 2},
	]
	save.depleted_props = [
		{"prop_id": 99, "remaining": 12.0},
	]
	return save


func test_a_filled_save_round_trips_to_an_equivalent_state() -> void:
	var original := _filled()
	var restored: RefCounted = SaveData.from_dict(original.to_dict())

	assert_eq(restored.world_seed, original.world_seed)
	assert_almost_eq(restored.time_of_day, original.time_of_day, 0.0001)
	assert_eq(restored.weather_state, original.weather_state)
	assert_almost_eq(restored.weather_remaining, original.weather_remaining, 0.0001)
	assert_almost_eq(
			restored.player_position.distance_to(original.player_position), 0.0, 0.0001)
	assert_almost_eq(restored.player_health, original.player_health, 0.0001)
	assert_almost_eq(restored.player_hunger, original.player_hunger, 0.0001)
	assert_almost_eq(restored.player_stamina, original.player_stamina, 0.0001)
	assert_eq(restored.worn_item, original.worn_item)
	assert_eq(restored.flight_suit_equipped, original.flight_suit_equipped)
	assert_almost_eq(restored.flight_fuel, original.flight_fuel, 0.0001)
	assert_eq(restored.inventory_slots, original.inventory_slots)
	assert_eq(restored.selected_slot, original.selected_slot)
	assert_eq(restored.campfires, original.campfires)
	assert_eq(restored.looted_caches, original.looted_caches)
	assert_eq(restored.depleted_props, original.depleted_props)


func test_the_round_trip_survives_actual_json_text() -> void:
	# `to_dict()` alone cannot catch a value JSON cannot represent — this is what
	# actually proves the format is what SPEC calls for: human-readable JSON.
	#
	# Compared field by field with an explicit cast, not raw dictionary equality: JSON
	# has no integer type, so `cache_id: 7` survives as `7.0` — still the same value, a
	# different Variant type. Consumers already read these back through `int(...)`/
	# `float(...)` rather than assuming a type, so that is what this test does too.
	var original := _filled()
	var text := JSON.stringify(original.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary)
	var restored: RefCounted = SaveData.from_dict(parsed)

	assert_eq(restored.world_seed, original.world_seed)
	assert_almost_eq(
			restored.player_position.distance_to(original.player_position), 0.0, 0.0001)
	assert_eq(restored.looted_caches.size(), original.looted_caches.size())
	var restored_cache: Dictionary = restored.looted_caches[0]
	var original_cache: Dictionary = original.looted_caches[0]
	assert_eq(int(restored_cache["cache_id"]), int(original_cache["cache_id"]))
	assert_almost_eq(
			float(restored_cache["remaining"]), float(original_cache["remaining"]), 0.001)
	assert_eq(int(restored_cache["refills"]), int(original_cache["refills"]))


func test_an_empty_dict_produces_sensible_defaults_rather_than_erroring() -> void:
	var restored: RefCounted = SaveData.from_dict({})
	assert_eq(restored.world_seed, 0)
	assert_almost_eq(restored.player_position.distance_to(Vector3.ZERO), 0.0, 0.0001)
	assert_eq(restored.inventory_slots, [])
	assert_eq(restored.looted_caches, [])
	assert_eq(restored.depleted_props, [])
	assert_eq(restored.campfires, [])
	assert_false(restored.flight_suit_equipped)


func test_only_looted_caches_and_depleted_props_are_expected_to_be_recorded() -> void:
	# Not a hard constraint the class enforces — the discipline lives in what
	# `save_manager.gd` chooses to capture — but this documents the intent: an unlooted
	# island's worth of caches must never bloat a save file.
	var save := _filled()
	assert_eq(save.looted_caches.size(), 1,
			"a save should record individual looted caches, not the whole island")


func test_world_seed_is_what_a_load_checks_before_touching_anything() -> void:
	var save := _filled()
	var data: Dictionary = save.to_dict()
	assert_eq(int(data["world_seed"]), save.world_seed,
			"the seed has to survive encoding intact — everything else is refused "
			+ "against it")
