extends Node
## Automated frame-time measurement: walks the player across the island and reports.
##
## Added by main only when `--perf` is passed, so it costs nothing in a normal run.
##
## Drives the real input actions rather than teleporting the camera, so the measurement
## includes collision, step-up and prop culling under actual movement — the thing the
## budget is supposed to hold during.
##
## Vsync is disabled while measuring. Left on, every reading would be pinned to the
## display refresh rate and "60 FPS" would say nothing about headroom.

const Config := preload("res://scripts/config.gd")

## Discarded before sampling begins: the first frames include shader compilation and
## the initial visibility pass, which are not representative of steady state.
const WARMUP_SECONDS := 3.0
const MEASURE_SECONDS := 20.0

## Slow yaw sweep while walking, so the measurement covers varied terrain and varied
## numbers of visible props rather than one lucky sightline.
const TURN_RATE_DEG_PER_SEC := 9.0

var _player: Node3D
var _elapsed := 0.0
var _frame_times: PackedFloat32Array = PackedFloat32Array()
var _peak_objects := 0
var _peak_primitives := 0
var _peak_draw_calls := 0
var _done := false


## Weather forced while measuring.
##
## Measuring in fair weather would flatter the result: the budget has to hold in the
## worst conditions the game can produce, which is a thunderstorm — volumetric fog,
## full precipitation and lightning at once.
const MEASURE_WEATHER := 4  # WeatherModel.State.THUNDERSTORM


func start(player: Node3D) -> void:
	_player = player
	var weather := get_parent().get_node_or_null(^"Weather")
	if weather != null:
		weather.set_state(MEASURE_WEATHER)
		weather.paused = true
		print("perf: weather forced to %s (worst case)" % weather.current_name())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if _player != null and _player.has_method(&"release_mouse"):
		_player.release_mouse()
	Input.action_press(&"move_forward")
	print("perf: measuring %.0fs after %.0fs warmup, vsync off"
			% [MEASURE_SECONDS, WARMUP_SECONDS])


func _process(delta: float) -> void:
	if _done:
		return

	_elapsed += delta
	if _player != null:
		_player.rotate_y(deg_to_rad(TURN_RATE_DEG_PER_SEC) * delta)

	if _elapsed < WARMUP_SECONDS:
		return

	_frame_times.append(delta)
	_peak_objects = maxi(_peak_objects, int(Performance.get_monitor(
			Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	_peak_primitives = maxi(_peak_primitives, int(Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	_peak_draw_calls = maxi(_peak_draw_calls, int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

	if _elapsed >= WARMUP_SECONDS + MEASURE_SECONDS:
		_finish()


func _finish() -> void:
	_done = true
	Input.action_release(&"move_forward")
	for line in report_lines():
		print(line)
	get_tree().quit(0 if meets_target() else 1)


## True when the slowest 1% of frames still clear the target. Average FPS alone hides
## stutter, and stutter is what a player actually notices.
func meets_target() -> bool:
	if _frame_times.is_empty():
		return false
	return one_percent_low_fps() >= float(Config.target_fps())


func average_fps() -> float:
	return average_fps_of(_frame_times)


func one_percent_low_fps() -> float:
	return one_percent_low_fps_of(_frame_times)


## Mean frames per second across a set of frame durations.
##
## Static and pure so the arithmetic is testable without running the game — an
## off-by-one in the percentile below would silently misreport the budget.
static func average_fps_of(times: PackedFloat32Array) -> float:
	if times.is_empty():
		return 0.0
	var total := 0.0
	for t in times:
		total += t
	return float(times.size()) / total


## FPS at the 99th percentile frame time: the slowest 1% of frames.
##
## Reported alongside the average because the average hides stutter, and stutter is
## what a player actually notices.
static func one_percent_low_fps_of(times: PackedFloat32Array) -> float:
	if times.is_empty():
		return 0.0
	var sorted := Array(times)
	sorted.sort()
	var index := clampi(int(float(sorted.size()) * 0.99), 0, sorted.size() - 1)
	var worst: float = sorted[index]
	return 1.0 / maxf(worst, 0.000001)


func report_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var size := Config.viewport_size()
	lines.append("perf: %dx%d, view %.0fm, props culled at %.0fm"
			% [size.x, size.y, Config.view_distance_m(),
			Config.prop_cull_distance_m()])
	lines.append("perf: frames sampled %d over %.0fs"
			% [_frame_times.size(), MEASURE_SECONDS])
	lines.append("perf: avg %.1f fps, 1%% low %.1f fps, target %d"
			% [average_fps(), one_percent_low_fps(), Config.target_fps()])
	lines.append("perf: peak objects %d, primitives %d, draw calls %d"
			% [_peak_objects, _peak_primitives, _peak_draw_calls])
	lines.append("perf: %s" % ("PASS" if meets_target() else "BELOW TARGET"))
	return lines
