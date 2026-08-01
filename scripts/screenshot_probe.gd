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
	{"name": "crafting", "offset": Vector3(0.0, 2.0, 0.0), "pitch_deg": -6.0,
			"time": 0.35, "weather": 0, "open_crafting": true},
	# Crouched, so the deer does not bolt before the shutter: crouching cuts detection
	# from 26m to under 12m, which is the whole point of the mechanic.
	{"name": "deer", "offset": Vector3(0.0, 0.0, 0.0), "pitch_deg": -4.0,
			"time": 0.35, "weather": 0, "near_creature": "deer", "crouch": true},
	# One shot per cat, because the three are meant to be told apart on sight and
	# nothing headless can check whether they actually are.
	{"name": "leopard", "offset": Vector3(0.0, 0.0, 0.0), "pitch_deg": -4.0,
			"time": 0.35, "weather": 0, "near_creature": "leopard", "crouch": true},
	{"name": "tiger", "offset": Vector3(0.0, 0.0, 0.0), "pitch_deg": -4.0,
			"time": 0.35, "weather": 0, "near_creature": "tiger", "crouch": true},
	{"name": "lion", "offset": Vector3(0.0, 0.0, 0.0), "pitch_deg": -4.0,
			"time": 0.35, "weather": 0, "near_creature": "lion", "crouch": true},
	# The M3 loop in one frame: the summit at midnight in a storm, which kills an exposed
	# player, made survivable by a fire built from gathered wood.
	# Feet on the ground, not hovering: the placement ray reaches only a few metres
	# down, so a player floating above the terrain cannot reach it to build on.
	{"name": "campfire", "offset": Vector3(0.0, 0.0, 0.0), "pitch_deg": -14.0,
			"time": 0.00, "weather": 4, "summit": true, "light_fire": true},
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

## Set when a view aims at something specific, overriding the view's fixed pitch.
var _aim_pitch := INF


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
		if _player.has_method(&"set_crouching"):
			_player.set_crouching(bool(view.get("crouch", false)))
		if view.has("near_creature"):
			origin = _beside_a_creature(origin, String(view["near_creature"]))
		_player.global_position = origin + offset
		# The view's fixed pitch first, then the aim, which overrides it when the shot is
		# of something in particular. These were the other way round, so every creature
		# shot was framed by the fixed pitch and the animal was wherever it happened to
		# be — which is why the deer was a speck.
		camera.rotation.x = deg_to_rad(float(view["pitch_deg"]))
		if _aim_pitch < INF:
			camera.rotation.x = _aim_pitch
		_aim_pitch = INF

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
		for entry in [[^"UI/InventoryScreen", "open_inventory"],
				[^"UI/CraftingScreen", "open_crafting"]]:
			var screen := get_parent().get_node_or_null(entry[0])
			if screen != null and screen.has_method(&"is_open"):
				var want_open: bool = bool(view.get(entry[1], false))
				if screen.is_open() != want_open:
					screen.toggle()

		if bool(view.get("light_fire", false)):
			_light_fire_in_front()

		var settle: int = 90 if view.has("weather") else 6
		if view.has("near_creature"):
			# An animal beyond the active radius is not drawn at all, and it only
			# notices the camera has arrived on its next decision — a fifth of a second
			# away. Six frames photographed an empty field.
			settle = maxi(settle, 40)
		for _i in settle:
			await RenderingServer.frame_post_draw

		if view.has("near_creature"):
			# It has been awake and walking for that whole settle, so stand and aim
			# again rather than photographing where it used to be.
			_player.global_position = _beside_a_creature(origin,
					String(view["near_creature"])) + offset
			if _aim_pitch < INF:
				camera.rotation.x = _aim_pitch
			_aim_pitch = INF
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


## Stands the player a few metres from an animal of the named species, facing it.
##
## Animals are scattered across plains and forest while the player spawns on a beach, so
## without this a capture would almost never contain one. The species is named because
## the point of the cat shots is comparing one against another, and "whichever animal
## spawned first" would give three pictures of the same deer.
func _beside_a_creature(fallback: Vector3, species: String) -> Vector3:
	var creatures := get_parent().get_node_or_null(^"Creatures")
	if creatures == null or not creatures.has_method(&"creatures"):
		return fallback

	const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
	var list: Array = []
	for candidate in creatures.creatures():
		if is_instance_valid(candidate) \
				and CreatureKind.name_of(candidate.kind) == species:
			list.append(candidate)
	if list.is_empty():
		printerr("screenshot: no %s on this island" % species)
		return fallback

	# Prefer an animal standing on open plains. Most deer are in forest, where any shot
	# is either a tree trunk at eye height or a canopy from above.
	var target: Node3D = list[0]
	var terrain := get_parent().get_node_or_null(^"Terrain")
	if terrain != null and terrain.has_method(&"heightmap"):
		var map: RefCounted = terrain.heightmap()
		const Biome := preload("res://scripts/world/biome.gd")
		for candidate in list:
			var at: Vector3 = candidate.global_position
			if map.biome_at_world(at.x, at.z) == Biome.Kind.PLAINS:
				target = candidate
				break
	var stand := target.global_position + Vector3(0.0, 1.6, 11.0)

	# Aim at the animal rather than using the view's fixed pitch, so it is centred
	# wherever it has wandered to.
	var to_target := target.global_position + Vector3(0.0, 0.8, 0.0) - stand
	_player.rotation.y = atan2(-to_target.x, -to_target.z)
	_aim_pitch = atan2(to_target.y, Vector2(to_target.x, to_target.z).length())

	print("screenshot: standing beside %s, %.1fm away"
			% [target.name, stand.distance_to(target.global_position)])
	return stand


## Builds a fire just in front of the player, as though they had placed one.
func _light_fire_in_front() -> void:
	var placer := _player.get_node_or_null(^"ItemPlacer")
	if placer == null:
		return
	var inventory: RefCounted = _player.inventory()
	inventory.add(3, 6)  # berries, so the hotbar is not empty in shot
	inventory.add(8, 1)  # campfire
	# Select the campfire slot, then use it.
	for slot in 5:
		if inventory.item_in_slot(slot) == 8:
			inventory.select(slot)
			break
	placer.use_held_item()


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
