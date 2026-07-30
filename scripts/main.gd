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
const Spawn := preload("res://scripts/world/spawn.gd")
const PerfProbe := preload("res://scripts/perf_probe.gd")
const ScreenshotProbe := preload("res://scripts/screenshot_probe.gd")

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

	# Sky and weather are live, so the overlay re-reads them each frame rather than
	# being handed a snapshot that goes stale the moment it is drawn.
	var label := get_node_or_null(^"UI/BootLabel")
	if label != null and label.has_method(&"configure"):
		var sources: Array[Node] = []
		for path in [^"Sky", ^"Weather", ^"WeatherEffects", ^"Player"]:
			var node := get_node_or_null(path)
			if node != null:
				sources.append(node)
		label.configure(lines, sources)

	if not missing.is_empty():
		push_error("Input map incomplete, missing: %s" % ", ".join(missing))

	var args := OS.get_cmdline_user_args()
	if args.has("--perf"):
		_start_perf_probe()
	elif args.has("--screenshot"):
		_start_screenshot_probe(args)


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
	# Fog colour is not set here: the Sky node drives it from the time of day, so
	# distant terrain fades into whatever colour the horizon actually is at that hour.
	# The sky is the thing terrain fades into, so it must not itself be fogged.
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0

	var sky := get_node_or_null(^"Sky")
	if sky != null:
		sky.bind_environment(env)

	var effects := get_node_or_null(^"WeatherEffects")
	if effects != null:
		effects.bind(get_node_or_null(^"Weather"), sky, env,
				get_node_or_null(^"Player") as Node3D,
				get_node_or_null(^"Terrain"))


func _player_camera() -> Camera3D:
	var player := get_node_or_null(^"Player")
	if player == null:
		return null
	return player.get_node_or_null(^"Camera3D") as Camera3D


## Captures viewport PNGs and exits. Output directory is taken from the argument after
## --screenshot, defaulting to user:// when none is given.
func _start_screenshot_probe(args: PackedStringArray) -> void:
	var output_dir := "user://"
	var index := args.find("--screenshot")
	if index >= 0 and index + 1 < args.size():
		output_dir = args[index + 1]
	var probe := ScreenshotProbe.new()
	probe.name = "ScreenshotProbe"
	add_child(probe)
	probe.start(get_node_or_null(^"Player"), output_dir)


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

	# Weather is seeded from the world, so a given island always gets the same weather.
	var weather := get_node_or_null(^"Weather")
	if weather != null:
		weather.weather_seed = terrain.world_seed

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

	# Washed up on the shore, and returned there on death. The spawn is derived from the
	# seed, so a given island always starts you in the same place.
	var spawn: RefCounted = Spawn.new()
	var shore: Vector3 = spawn.shore_spawn(map, terrain.world_seed)
	player.respawn_point = shore
	player.global_position = shore

	var hud := get_node_or_null(^"UI/Hud")
	if hud != null and hud.has_method(&"bind"):
		hud.bind(player)

	return "player: shore spawn at %.0f, %.0f (ground %dm)" % [
		shore.x, shore.z, map.height_at_world(shore.x, shore.z)]


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
