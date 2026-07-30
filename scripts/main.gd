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


const Config := preload("res://scripts/config.gd")
const PerfProbe := preload("res://scripts/perf_probe.gd")

## Sky horizon and distance fog share this colour, so terrain fading out at the far
## plane fades into the sky rather than into a differently-coloured wall. Deriving both
## from one constant is what stops them drifting apart.
const HORIZON_COLOUR := Color(0.66, 0.75, 0.84)

## Height above the terrace the player is dropped from, so they settle onto the
## surface under gravity rather than starting embedded in it.
const SPAWN_CLEARANCE_M := 1.5


func _ready() -> void:
	var missing := missing_actions()
	var lines := report_lines(missing)

	_configure_view()

	var terrain := get_node_or_null(^"Terrain")
	if terrain != null:
		lines.append_array(terrain.stat_lines())
		lines.append_array(_populate_props(terrain))
		lines.append(_place_player(terrain))

	for line in lines:
		print(line)

	var label := get_node_or_null(^"UI/BootLabel") as Label
	if label != null:
		label.text = "\n".join(lines)

	if not missing.is_empty():
		push_error("Input map incomplete, missing: %s" % ", ".join(missing))

	if OS.get_cmdline_user_args().has("--perf"):
		_start_perf_probe()


## Sets the far plane and distance fog from the configured budget, and matches the sky
## horizon to the fog so the two blend.
func _configure_view() -> void:
	var view := Config.view_distance_m()

	var camera := _player_camera()
	if camera != null:
		camera.far = view

	var world_env := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment

	env.fog_enabled = true
	# Depth fog rather than exponential: it can be made fully opaque exactly at the far
	# plane, which is what hides the plane instead of merely softening it.
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = view * Config.fog_start_fraction()
	env.fog_depth_end = view
	env.fog_depth_curve = 1.0
	env.fog_density = 1.0
	env.fog_light_color = HORIZON_COLOUR
	# The sky is the thing terrain fades into, so it must not itself be fogged.
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0

	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		var sky_material: ProceduralSkyMaterial = env.sky.sky_material
		sky_material.sky_horizon_color = HORIZON_COLOUR
		sky_material.ground_horizon_color = HORIZON_COLOUR


func _player_camera() -> Camera3D:
	var player := get_node_or_null(^"Player")
	if player == null:
		return null
	return player.get_node_or_null(^"Camera3D") as Camera3D


func _start_perf_probe() -> void:
	var probe := PerfProbe.new()
	probe.name = "PerfProbe"
	add_child(probe)
	probe.start(get_node_or_null(^"Player"))


## Builds the props. Driven from here rather than from the Props node's own _ready, so
## it cannot run before the terrain it needs exists.
func _populate_props(terrain: Node) -> PackedStringArray:
	var props := get_node_or_null(^"Props")
	var map: RefCounted = terrain.heightmap()
	if props == null or map == null:
		return PackedStringArray()
	props.populate(map, terrain.world_seed)
	return props.stat_lines()


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
