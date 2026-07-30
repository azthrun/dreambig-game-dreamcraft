extends Node
## Captures the game's own viewport to PNG files, then quits.
##
## Added by main only when `--screenshot` is passed.
##
## Exists because some things genuinely cannot be verified headlessly — face winding
## being the standing example. A headless run has no rendering device, so nothing can be
## culled and nothing can be seen. Capturing the real viewport from a windowed run gets
## a rendering device involved while keeping the capture inside the game, rather than
## photographing the whole desktop.

const SETTLE_FRAMES := 45

## Views to capture: a label, a camera offset from the player's spawn, and a pitch.
## Ground level shows whether terrain renders at all; the lifted view shows the island
## silhouette, where inverted faces are unmistakable.
## `time` is a normalised time of day applied to the Sky before capturing, so each
## phase of the cycle can be inspected without waiting twenty minutes for it.
const VIEWS := [
	{"name": "ground", "offset": Vector3(0.0, 0.0, 0.0), "pitch_deg": -8.0,
			"time": 0.30},
	{"name": "lifted", "offset": Vector3(0.0, 120.0, 0.0), "pitch_deg": -32.0,
			"time": 0.30},
	{"name": "dawn", "offset": Vector3(0.0, 6.0, 0.0), "pitch_deg": -2.0,
			"time": 0.16},
	{"name": "noon", "offset": Vector3(0.0, 6.0, 0.0), "pitch_deg": -2.0,
			"time": 0.50},
	{"name": "dusk", "offset": Vector3(0.0, 6.0, 0.0), "pitch_deg": -2.0,
			"time": 0.84},
	{"name": "night", "offset": Vector3(0.0, 6.0, 0.0), "pitch_deg": 12.0,
			"time": 0.00},
	{"name": "rain", "offset": Vector3(0.0, 6.0, 0.0), "pitch_deg": -4.0,
			"time": 0.42, "weather": 3},
	{"name": "storm", "offset": Vector3(0.0, 6.0, 0.0), "pitch_deg": -4.0,
			"time": 0.42, "weather": 4},
	{"name": "fog", "offset": Vector3(0.0, 6.0, 0.0), "pitch_deg": -4.0,
			"time": 0.42, "weather": 5},
	# On the island's summit, in the same rain condition as the rain shot: the point is
	# that one global condition produces two different local results.
	{"name": "snow", "offset": Vector3(0.0, 2.0, 0.0), "pitch_deg": -4.0,
			"time": 0.42, "weather": 3, "summit": true},
	# The worst place on the island at the worst hour: exposure should be lethal here.
	{"name": "freezing", "offset": Vector3(0.0, 2.0, 0.0), "pitch_deg": 4.0,
			"time": 0.00, "weather": 4, "summit": true},
	{"name": "inventory", "offset": Vector3(0.0, 2.0, 0.0), "pitch_deg": -6.0,
			"time": 0.35, "weather": 0, "open_inventory": true},
]

## Sample contents so the hotbar and inventory screen show something. Harvesting does not
## exist yet, so without this every capture would show an empty bag.
const SAMPLE_ITEMS := [
	[1, 12],   # wood
	[2, 7],    # stone
	[3, 4],    # berries
	[7, 1],    # stone tool
]

var _player: Node3D
var _output_dir := "user://"


func start(player: Node3D, output_dir: String) -> void:
	_player = player
	_output_dir = output_dir
	if _player != null and _player.has_method(&"release_mouse"):
		_player.release_mouse()
	_capture_all.call_deferred()


func _capture_all() -> void:
	var camera: Camera3D = null
	if _player != null:
		camera = _player.get_node_or_null(^"Camera3D") as Camera3D
	if camera == null:
		printerr("screenshot: no camera")
		get_tree().quit(1)
		return

	# Let terrain, props and fog settle before the first capture.
	for _i in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw

	# Physics off for the duration: the player is teleported between views, and gravity
	# would drag them back to the ground before the frame is captured — which silently
	# made an above-the-snowline shot into a ground-level one.
	_player.set_physics_process(false)

	if _player.has_method(&"inventory"):
		var inventory: RefCounted = _player.inventory()
		for entry in SAMPLE_ITEMS:
			inventory.add(int(entry[0]), int(entry[1]))

	var base := _player.global_position
	var summit := _find_summit(base)
	# Far plane is raised for the lifted views only, so the island silhouette is
	# actually in frame rather than swallowed by the 500 m budget.
	var original_far := camera.far

	# Freezing the clock keeps each capture at exactly the intended hour rather than
	# drifting through it while frames settle.
	var sky := get_parent().get_node_or_null(^"Sky")
	if sky != null:
		sky.paused = true

	# Weather is frozen too, and effects are given time to blend before capture —
	# otherwise every weather shot catches the transition rather than the condition.
	var weather := get_parent().get_node_or_null(^"Weather")
	var effects := get_parent().get_node_or_null(^"WeatherEffects")
	if weather != null:
		weather.paused = true

	for view in VIEWS:
		# Move first: local modulation is sampled from where the player is, so blending
		# before the move would read conditions for the previous position.
		var offset: Vector3 = view["offset"]
		var origin: Vector3 = summit if bool(view.get("summit", false)) else base
		_player.global_position = origin + offset
		camera.rotation.x = deg_to_rad(float(view["pitch_deg"]))

		if sky != null and view.has("time"):
			sky.set_time_of_day(float(view["time"]))
		if weather != null:
			weather.set_state(int(view.get("weather", 0)))
			# Effects ease towards their target over several seconds, so let the blend
			# finish rather than photographing it halfway.
			if effects != null:
				for _b in 260:
					effects._process(0.02)
		camera.far = maxf(original_far, offset.y * 6.0 + 500.0)

		# Precipitation spawns high above the player and falls, so a capture taken
		# immediately after switching shows an empty sky. Waiting covers the fall time.
		var screen := get_parent().get_node_or_null(^"UI/InventoryScreen")
		if screen != null and screen.has_method(&"is_open"):
			var want_open: bool = bool(view.get("open_inventory", false))
			if screen.is_open() != want_open:
				screen.toggle()

		var settle: int = 90 if view.has("weather") else 6
		for _i in settle:
			await RenderingServer.frame_post_draw

		var image := get_viewport().get_texture().get_image()
		var path: String = "%s/dreamcraft_%s.png" % [_output_dir, view["name"]]
		var error := image.save_png(path)
		if error != OK:
			printerr("screenshot: failed to write %s (%d)" % [path, error])
		else:
			print("screenshot: wrote %s (%dx%d)"
					% [ProjectSettings.globalize_path(path),
					image.get_width(), image.get_height()])

	camera.far = original_far
	_player.set_physics_process(true)
	get_tree().quit(0)


## Highest point on the island, as a world position. Falls back to the given position
## when there is no terrain to search.
func _find_summit(fallback: Vector3) -> Vector3:
	var terrain := get_parent().get_node_or_null(^"Terrain")
	if terrain == null or not terrain.has_method(&"heightmap"):
		return fallback
	var map: RefCounted = terrain.heightmap()
	if map == null:
		return fallback

	var best := Vector2i.ZERO
	var best_height := -9999
	for cz in map.cells_per_axis:
		for cx in map.cells_per_axis:
			var height: int = map.height_at_cell(cx, cz)
			if height > best_height:
				best_height = height
				best = Vector2i(cx, cz)

	var half: float = map.size_m() * 0.5
	var cell_size: float = map.cell_size_m
	print("screenshot: summit at cell %s, %dm" % [best, best_height])
	return Vector3(
			float(best.x) * cell_size - half + cell_size * 0.5,
			float(best_height),
			float(best.y) * cell_size - half + cell_size * 0.5)
