extends "res://tests/test_case.gd"
## The main menu's one piece of pure logic: whether Continue should be offered.
##
## `continue_available` is a static function independent of any Control instance or
## scene tree specifically so this is testable headlessly - see main_menu_screen.gd.
## The rest of the screen (layout, number-key selection, the overwrite prompt) is
## presentation and, per AGENTS.md, is verified with `./run_screenshot.sh` instead.

const MainMenuScreen := preload("res://scripts/ui/main_menu_screen.gd")
const SaveManager := preload("res://scripts/persistence/save_manager.gd")
const SaveData := preload("res://scripts/persistence/save_data.gd")

const TEST_PATH := "user://main_menu_screen_test.json"


func after_each() -> void:
	SaveManager.delete_save(TEST_PATH)


func test_continue_is_unavailable_with_no_save_on_disk() -> void:
	assert_false(MainMenuScreen.continue_available(TEST_PATH))


func test_continue_becomes_available_once_a_save_exists() -> void:
	SaveManager.write_file(SaveData.new(), TEST_PATH)
	assert_true(MainMenuScreen.continue_available(TEST_PATH))


func test_continue_is_unavailable_again_after_the_save_is_deleted() -> void:
	SaveManager.write_file(SaveData.new(), TEST_PATH)
	assert_true(MainMenuScreen.continue_available(TEST_PATH))
	SaveManager.delete_save(TEST_PATH)
	assert_false(MainMenuScreen.continue_available(TEST_PATH))
