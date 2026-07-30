extends "res://tests/test_case.gd"
## Tests the view/performance budget configuration and the frame-time statistics.

const Config := preload("res://scripts/config.gd")
const PerfProbe := preload("res://scripts/perf_probe.gd")


func test_budget_comes_from_project_settings_not_code() -> void:
	# The whole point of the [dreamcraft] section: the envelope is tunable per machine
	# without editing three different files.
	assert_true(ProjectSettings.has_setting(Config.VIEW_DISTANCE),
			"view distance should be a project setting")
	assert_true(ProjectSettings.has_setting(Config.PROP_CULL_DISTANCE))
	assert_true(ProjectSettings.has_setting(Config.TARGET_FPS))


func test_configured_budget_matches_the_agreed_envelope() -> void:
	assert_almost_eq(Config.view_distance_m(), 500.0, 0.001)
	assert_almost_eq(Config.prop_cull_distance_m(), 150.0, 0.001)
	assert_eq(Config.target_fps(), 60)
	assert_eq(Config.viewport_size(), Vector2i(1600, 900))


func test_props_are_culled_well_inside_the_view_distance() -> void:
	# Terrain must read to the horizon while props do not, or the far plane fills with
	# thousands of trees for no visual gain.
	assert_true(Config.prop_cull_distance_m() < Config.view_distance_m(),
			"prop cull must be nearer than the far plane")


func test_fog_starts_before_the_far_plane_and_is_clamped() -> void:
	# Fog has to be fully opaque by the far plane, or the plane shows as a hard edge.
	var fraction := Config.fog_start_fraction()
	assert_in_range(fraction, 0.05, 0.95)
	assert_true(fraction < 1.0, "fog must begin before the far plane")


func test_average_fps_is_the_mean_of_frame_durations() -> void:
	var times := PackedFloat32Array([0.01, 0.01, 0.01, 0.01])
	assert_almost_eq(PerfProbe.average_fps_of(times), 100.0, 0.01)


func test_one_percent_low_reports_the_slow_frames_not_the_average() -> void:
	# 99 fast frames and one very slow one: the average stays high while the 1% low
	# collapses. That difference is the entire reason both are reported.
	var times := PackedFloat32Array()
	for _i in 99:
		times.append(0.004)
	times.append(0.05)
	assert_true(PerfProbe.average_fps_of(times) > 150.0,
			"average should stay high")
	assert_almost_eq(PerfProbe.one_percent_low_fps_of(times), 20.0, 0.5,
			"1% low should surface the 50ms frame")


func test_frame_statistics_handle_an_empty_sample() -> void:
	var empty := PackedFloat32Array()
	assert_eq(PerfProbe.average_fps_of(empty), 0.0)
	assert_eq(PerfProbe.one_percent_low_fps_of(empty), 0.0)


func test_uniform_frame_times_give_equal_average_and_low() -> void:
	var times := PackedFloat32Array()
	for _i in 200:
		times.append(1.0 / 60.0)
	assert_almost_eq(PerfProbe.average_fps_of(times), 60.0, 0.1)
	assert_almost_eq(PerfProbe.one_percent_low_fps_of(times), 60.0, 0.1)
