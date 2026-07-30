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
const VIEWS := [
	{"name": "ground", "offset": Vector3(0.0, 0.0, 0.0), "pitch_deg": -8.0},
	{"name": "lifted", "offset": Vector3(0.0, 120.0, 0.0), "pitch_deg": -32.0},
	{"name": "high", "offset": Vector3(0.0, 420.0, 0.0), "pitch_deg": -55.0},
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

	var base := _player.global_position
	# Far plane is raised for the lifted views only, so the island silhouette is
	# actually in frame rather than swallowed by the 500 m budget.
	var original_far := camera.far

	for view in VIEWS:
		var offset: Vector3 = view["offset"]
		_player.global_position = base + offset
		camera.rotation.x = deg_to_rad(float(view["pitch_deg"]))
		camera.far = maxf(original_far, offset.y * 6.0 + 500.0)

		for _i in 6:
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
	get_tree().quit(0)
