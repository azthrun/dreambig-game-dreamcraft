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


func _ready() -> void:
	var missing := missing_actions()
	for line in report_lines(missing):
		print(line)

	var label := get_node_or_null(^"UI/BootLabel") as Label
	if label != null:
		label.text = "\n".join(report_lines(missing))

	if not missing.is_empty():
		push_error("Input map incomplete, missing: %s" % ", ".join(missing))


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
