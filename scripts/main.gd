extends Node3D
## The game's single scene: boot report, world, and shell.
##
## Confirms the project boots with the intended engine configuration and that the
## input map is fully registered, then shows the main menu. World population (props,
## creatures, the player) is deferred until New Game or Continue is chosen in
## `_begin_game`, rather than happening unconditionally in `_ready`, so a session never
## starts before the player has asked for one. Returning to the main menu reloads this
## scene outright (`_on_return_to_main_menu_requested`) rather than resetting state
## field by field, which is what guarantees a second session never inherits anything
## from the first.

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
	&"craft",
	&"hotbar_next",
	&"hotbar_prev",
	&"hotbar_1",
	&"hotbar_2",
	&"hotbar_3",
	&"hotbar_4",
	&"hotbar_5",
	&"pause",
	&"debug_time_scale",
	&"activate_flight",
]


const Config := preload("res://scripts/config.gd")
const Spawn := preload("res://scripts/world/spawn.gd")
const PerfProbe := preload("res://scripts/perf_probe.gd")
const ScreenshotProbe := preload("res://scripts/screenshot_probe.gd")
const SaveManager := preload("res://scripts/persistence/save_manager.gd")

## Height above the terrace the player is dropped from, so they settle onto the
## surface under gravity rather than starting embedded in it.
const SPAWN_CLEARANCE_M := 1.5

## Collected while placing the player, since creatures are spawned in that pass.
var _creature_lines := PackedStringArray()

## The boot report, captured once in `_ready` and reused as the base for `_begin_game`'s
## fuller report once a session actually starts.
var _boot_lines := PackedStringArray()


func _ready() -> void:
	var missing := missing_actions()
	_boot_lines = report_lines(missing)

	_configure_view()

	var terrain := get_node_or_null(^"Terrain")
	if terrain != null:
		_boot_lines.append_array(terrain.stat_lines())

	for line in _boot_lines:
		print(line)
	if not missing.is_empty():
		push_error("Input map incomplete, missing: %s" % ", ".join(missing))

	_wire_menus()

	var args := OS.get_cmdline_user_args()
	if args.has("--perf"):
		_begin_game(false)
		_start_perf_probe()
	elif args.has("--screenshot"):
		_begin_game(false)
		_start_screenshot_probe(args)
	else:
		var menu := get_node_or_null(^"UI/MainMenuScreen")
		if menu != null and menu.has_method(&"open"):
			menu.open()
		else:
			# No menu wired (a stripped-down scene, say) - fall back to the old
			# behaviour of starting straight into a fresh game.
			_begin_game(false)


## Connects the main menu and pause screen to the actions only `main.gd` can carry out:
## starting, saving, and tearing down a session.
func _wire_menus() -> void:
	var menu := get_node_or_null(^"UI/MainMenuScreen")
	var pause := get_node_or_null(^"UI/PauseScreen")
	var inventory := get_node_or_null(^"UI/InventoryScreen")
	var crafting := get_node_or_null(^"UI/CraftingScreen")

	if pause != null:
		if pause.has_method(&"bind"):
			pause.bind(inventory, crafting)
		pause.resume_requested.connect(_on_resume_requested)
		pause.save_requested.connect(_on_save_requested)
		pause.main_menu_requested.connect(_on_return_to_main_menu_requested)

	if menu != null:
		menu.new_game_requested.connect(_on_new_game_requested)
		menu.continue_requested.connect(_on_continue_requested)
		menu.quit_requested.connect(_on_quit_requested)


func _on_new_game_requested() -> void:
	SaveManager.delete_save()
	_begin_game(false)


func _on_continue_requested() -> void:
	_begin_game(true)


func _on_quit_requested() -> void:
	get_tree().quit()


func _on_resume_requested() -> void:
	var pause := get_node_or_null(^"UI/PauseScreen")
	if pause != null:
		pause.close()


func _on_save_requested() -> void:
	_save_game()


func _on_return_to_main_menu_requested() -> void:
	# A full scene reload rather than resetting fields one at a time: it is the only
	# way to guarantee nothing from the previous session - inventory, campfires,
	# looted caches, hunger - survives into the next, since every node is freed and
	# rebuilt from scratch rather than mutated back towards defaults.
	get_tree().paused = false
	get_tree().reload_current_scene()


## Builds the props, places the player, spawns creatures, and - when `load_save` is
## true - restores a save on top of that freshly built world. Shared by New Game,
## Continue, and the `--perf`/`--screenshot` probes, which skip the menu entirely.
func _begin_game(load_save: bool) -> void:
	var terrain := get_node_or_null(^"Terrain")
	if terrain == null:
		return

	var lines := _boot_lines.duplicate()
	lines.append_array(_populate_props(terrain))
	lines.append(_place_player(terrain))
	lines.append_array(_creature_lines)
	for line in lines:
		print(line)

	var label := get_node_or_null(^"UI/BootLabel")
	if label != null and label.has_method(&"configure"):
		var sources: Array[Node] = []
		for path in [^"Sky", ^"Weather", ^"WeatherEffects", ^"Climate", ^"Props",
				^"Creatures", ^"Player"]:
			var node := get_node_or_null(path)
			if node != null:
				sources.append(node)
		label.configure(lines, sources)

	if load_save:
		var save := SaveManager.read_file()
		SaveManager.apply(save, terrain.world_seed, get_node_or_null(^"Sky"),
				get_node_or_null(^"Weather"), get_node_or_null(^"Player"),
				get_node_or_null(^"Props"), _item_placer(), get_node_or_null(^"Climate"))

	var menu := get_node_or_null(^"UI/MainMenuScreen")
	if menu != null:
		menu.close()

	var pause := get_node_or_null(^"UI/PauseScreen")
	if pause != null and pause.has_method(&"set_active"):
		pause.set_active(true)

	var player := get_node_or_null(^"Player")
	if player != null and player.has_method(&"capture_mouse"):
		player.capture_mouse()

	get_tree().paused = false


## Captures every live system into a `SaveData` and writes it to disk. Used by the
## pause menu's Save option.
func _save_game() -> void:
	var terrain := get_node_or_null(^"Terrain")
	if terrain == null:
		return
	var save := SaveManager.capture(terrain.world_seed, get_node_or_null(^"Sky"),
			get_node_or_null(^"Weather"), get_node_or_null(^"Player"),
			get_node_or_null(^"Props"), _item_placer())
	SaveManager.write_file(save)


func _item_placer() -> Node:
	var player := get_node_or_null(^"Player")
	if player == null or not player.has_method(&"item_placer"):
		return null
	return player.item_placer()


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

	# Climate needs the player and the terrain, so it is bound here rather than in its
	# own _ready, which would run before either exists.
	var climate := get_node_or_null(^"Climate")
	if climate != null:
		climate.bind(player, terrain, get_node_or_null(^"Sky"),
				get_node_or_null(^"Weather"))

	# Fires are parented to the world rather than to the player, so they stay where they
	# were built, and registered with the climate as heat sources.
	var placer: Node = player.item_placer()
	if placer != null and placer.has_method(&"bind"):
		placer.bind(player, _player_camera(), get_node_or_null(^"Props"), climate)

	# Animals need the player to react to, so they are spawned after the player exists.
	var creatures := get_node_or_null(^"Creatures")
	if creatures != null:
		creatures.populate(map, player, terrain.world_seed)
		_creature_lines = creatures.stat_lines()

	var hud := get_node_or_null(^"UI/Hud")
	if hud != null and hud.has_method(&"bind"):
		hud.bind(player, climate)

	for screen_path in [^"UI/InventoryScreen", ^"UI/CraftingScreen"]:
		var screen := get_node_or_null(screen_path)
		if screen != null and screen.has_method(&"bind"):
			screen.bind(player)

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
