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


## Height above the terrace the player is dropped from, so they settle onto the
## surface under gravity rather than starting embedded in it.
const SPAWN_CLEARANCE_M := 1.5


func _ready() -> void:
	var missing := missing_actions()
	var lines := report_lines(missing)

	var terrain := get_node_or_null(^"Terrain")
	if terrain != null:
		lines.append_array(terrain.stat_lines())
		lines.append(_place_player(terrain))

	for line in lines:
		print(line)

	var label := get_node_or_null(^"UI/BootLabel") as Label
	if label != null:
		label.text = "\n".join(lines)

	if not missing.is_empty():
		push_error("Input map incomplete, missing: %s" % ", ".join(missing))


## Drops the player onto the island centre, which the generator guarantees is land.
## Reads the terrace height from the heightmap rather than raycasting, since the
## heightmap is authoritative and already in memory.
func _place_player(terrain: Node) -> String:
	var player := get_node_or_null(^"Player") as CharacterBody3D
	if player == null:
		return "player: missing"

	var map: RefCounted = terrain.heightmap()
	if map == null:
		return "player: no heightmap, left at origin"

	# The player needs the sea's Y to know when it is swimming; it should not have to
	# know how the water was built.
	player.water_level_y = 0.0

	var ground: int = map.height_at_world(0.0, 0.0)
	player.global_position = Vector3(0.0, float(ground) + SPAWN_CLEARANCE_M, 0.0)
	return "player: spawned at ground %dm" % ground


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
