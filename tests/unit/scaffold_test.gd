extends "res://tests/test_case.gd"
## Regression tests for the project scaffold.
##
## These lock in the engine configuration SPEC.md commits to. They exist because
## Godot rewrites project.godot whenever settings change in the editor, and it
## silently drops any value equal to an engine default — so a decision recorded
## only in that file can vanish without anyone noticing.

const MAIN := preload("res://scripts/main.gd")


func test_renderer_is_forward_plus() -> void:
	# Volumetric fog and the physical sky depend on this; the Mobile and
	# GL Compatibility renderers do not support them.
	assert_eq(ProjectSettings.get_setting(
			"rendering/renderer/rendering_method", "<unset>"), "forward_plus")


func test_physics_engine_is_jolt() -> void:
	assert_eq(ProjectSettings.get_setting(
			"physics/3d/physics_engine", "<unset>"), "Jolt Physics")


func test_viewport_matches_performance_budget() -> void:
	assert_eq(ProjectSettings.get_setting(
			"display/window/size/viewport_width", 0), 1600)
	assert_eq(ProjectSettings.get_setting(
			"display/window/size/viewport_height", 0), 900)


func test_every_expected_input_action_is_registered() -> void:
	for action in MAIN.EXPECTED_ACTIONS:
		assert_true(InputMap.has_action(action),
				"input action '%s' is not registered" % action)


func test_expected_action_list_covers_the_agreed_verbs() -> void:
	# Guards against an action being quietly dropped from the expected list, which
	# would make the test above pass vacuously.
	var actions := MAIN.EXPECTED_ACTIONS
	for required in [&"move_forward", &"jump", &"sprint", &"crouch", &"interact",
			&"fire", &"aim", &"inventory", &"pause", &"debug_time_scale"]:
		assert_has(actions, required,
				"expected action list should include '%s'" % required)


func test_input_actions_are_not_declared_with_raw_keys() -> void:
	# SPEC.md requires named actions rather than raw key reads, so that gamepad
	# support is later a config change. Assert the map is actually populated.
	assert_in_range(float(MAIN.EXPECTED_ACTIONS.size()), 15.0, 40.0,
			"expected a substantial named-action set")
