extends Node3D
## Scaffold smoke scene.
##
## Confirms the project boots with the intended engine configuration and that the
## input map is fully registered. This scene is a placeholder: ticket #3 replaces
## it with the generated island.

## Every action the input map is expected to declare. Kept here so a missing or
## renamed action fails loudly at boot rather than silently doing nothing when a
## later ticket reads it.
const EXPECTED_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"jump",
	&"sprint",
	&"crouch",
	&"interact",
	&"fire",
	&"aim",
	&"inventory",
	&"hotbar_next",
	&"hotbar_prev",
	&"hotbar_1",
	&"hotbar_2",
	&"hotbar_3",
	&"hotbar_4",
	&"hotbar_5",
	&"pause",
	&"debug_time_scale",
]


## Overview camera framing, used until the first-person controller replaces it.
## Deliberately exceeds the 500 m view budget: the point of this scene is to show
## the whole island at once. The real budget applies once the camera is on the
## ground.
const OVERVIEW_FOV := 70.0
const OVERVIEW_FAR := 4000.0


func _ready() -> void:
	var missing := missing_actions()
	var lines := report_lines(missing)

	var terrain := get_node_or_null(^"Terrain")
	if terrain != null:
		lines.append_array(terrain.stat_lines())
		_frame_island(terrain)

	for line in lines:
		print(line)

	var label := get_node_or_null(^"UI/BootLabel") as Label
	if label != null:
		label.text = "\n".join(lines)

	if not missing.is_empty():
		push_error("Input map incomplete, missing: %s" % ", ".join(missing))


## Pulls the camera back far enough to see the whole island, derived from its actual
## extent rather than a hard-coded distance.
func _frame_island(terrain: Node) -> void:
	var camera := get_node_or_null(^"Camera3D") as Camera3D
	if camera == null:
		return

	var extent := 2048.0
	var map: RefCounted = terrain.heightmap()
	if map != null:
		extent = map.size_m()

	camera.fov = OVERVIEW_FOV
	camera.far = OVERVIEW_FAR
	# Distance needed to fit `extent` across the vertical field of view, with a
	# little margin, then lifted to look down on the terraces from an angle.
	var distance := (extent * 0.5) / tan(deg_to_rad(OVERVIEW_FOV * 0.5))
	camera.position = Vector3(0.0, distance * 0.62, distance * 0.78)
	camera.look_at(Vector3.ZERO)


## Returns the names of expected actions that the input map does not declare.
func missing_actions() -> PackedStringArray:
	var missing := PackedStringArray()
	for action in EXPECTED_ACTIONS:
		if not InputMap.has_action(action):
			missing.append(String(action))
	return missing


## Human-readable boot report. Shared by stdout and the on-screen label so the
## headless run and the windowed run report identically.
func report_lines(missing: PackedStringArray) -> PackedStringArray:
	var registered := EXPECTED_ACTIONS.size() - missing.size()
	var lines := PackedStringArray()
	lines.append("Dreamcraft - scaffold OK")
	lines.append("godot: %s" % Engine.get_version_info()["string"])
	lines.append("renderer: %s" % ProjectSettings.get_setting(
			"rendering/renderer/rendering_method", "<unset>"))
	lines.append("physics 3d: %s" % ProjectSettings.get_setting(
			"physics/3d/physics_engine", "<unset>"))
	lines.append("input actions: %d/%d" % [registered, EXPECTED_ACTIONS.size()])
	if not missing.is_empty():
		lines.append("MISSING: %s" % ", ".join(missing))
	return lines
