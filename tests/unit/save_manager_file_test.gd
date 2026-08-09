extends "res://tests/test_case.gd"
## SaveManager's file half: writing and reading JSON from disk. No scene needed — this is
## `FileAccess` and `JSON`, not a live game system — so it sits beside `save_data_test.gd`
## on the primary seam rather than with `save_load_test.gd`'s scene-based round trip.

const SaveManager := preload("res://scripts/persistence/save_manager.gd")
const SaveData := preload("res://scripts/persistence/save_data.gd")

const TEST_PATH := "user://save_manager_test.json"


func after_each() -> void:
	SaveManager.delete_save(TEST_PATH)


func _filled() -> RefCounted:
	var save: RefCounted = SaveData.new()
	save.world_seed = 20260729
	save.player_position = Vector3(4.0, 5.0, 6.0)
	save.looted_caches = [{"cache_id": 7, "remaining": 90.0, "refills": 0}]
	return save


func test_no_save_exists_until_one_is_written() -> void:
	assert_false(SaveManager.save_exists(TEST_PATH))


func test_writing_then_reading_round_trips_to_disk() -> void:
	var original := _filled()
	assert_true(SaveManager.write_file(original, TEST_PATH))
	assert_true(SaveManager.save_exists(TEST_PATH))

	var restored := SaveManager.read_file(TEST_PATH)
	assert_true(restored != null)
	assert_eq(restored.world_seed, original.world_seed)
	assert_almost_eq(
			restored.player_position.distance_to(original.player_position), 0.0, 0.0001)
	# Compared field by field, not raw dictionary equality: JSON has no integer type, so
	# `cache_id: 7` survives the round trip as `7.0` — the same value, a different
	# Variant type, and consumers already read these back through int()/float().
	var restored_cache: Dictionary = restored.looted_caches[0]
	var original_cache: Dictionary = original.looted_caches[0]
	assert_eq(int(restored_cache["cache_id"]), int(original_cache["cache_id"]))


func test_the_file_on_disk_is_actually_human_readable_json() -> void:
	SaveManager.write_file(_filled(), TEST_PATH)
	var file := FileAccess.open(TEST_PATH, FileAccess.READ)
	var text := file.get_as_text()
	assert_has(text, "world_seed")
	assert_has(text, "20260729")
	# Pretty-printed, not a single unreadable line — "human-readable" is the word SPEC
	# uses for this format specifically.
	assert_has(text, "\n")


func test_reading_a_missing_file_returns_null_rather_than_erroring() -> void:
	assert_false(SaveManager.save_exists(TEST_PATH))
	assert_eq(SaveManager.read_file(TEST_PATH), null)


func test_reading_corrupt_json_is_refused_rather_than_producing_a_broken_save() -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{ this is not valid json")
	file.close()

	assert_eq(SaveManager.read_file(TEST_PATH), null)


func test_deleting_a_save_removes_it() -> void:
	SaveManager.write_file(_filled(), TEST_PATH)
	assert_true(SaveManager.save_exists(TEST_PATH))
	SaveManager.delete_save(TEST_PATH)
	assert_false(SaveManager.save_exists(TEST_PATH))
