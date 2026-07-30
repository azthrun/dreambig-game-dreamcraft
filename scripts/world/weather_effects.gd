extends Node3D
## Applies the current weather's look: volumetric fog, precipitation, lightning, audio.
##
## Reads the condition from the Weather authority and the targets from the pure look
## table, then eases towards them. Nothing here decides what the weather is or what it
## should look like — it only makes it so.

const Weather := preload("res://scripts/world/weather_model.gd")
const WeatherLook := preload("res://scripts/world/weather_look.gd")
const ProceduralAudio := preload("res://scripts/audio/procedural_audio.gd")
const Config := preload("res://scripts/config.gd")
const Local := preload("res://scripts/world/local_climate.gd")

## How fast the look eases towards its target, in units per second of blend weight.
## Roughly four seconds for a full change, so weather rolls in rather than snapping.
const BLEND_RATE := 0.25

## Precipitation volume the emitter is sized for. `precipitation` scales this.
const RAIN_PARTICLES := 3200
const RAIN_AREA_M := 34.0
const RAIN_HEIGHT_M := 18.0
const RAIN_FALL_SPEED := 26.0

## Snow falls far slower and drifts, which is most of what distinguishes it from rain at
## a glance. Flakes are also chunkier, in keeping with the cuboid look.
const SNOW_FALL_SPEED := 4.5
const SNOW_DRIFT := 1.6

## How hard wind pushes precipitation sideways, in metres per second at full strength.
const WIND_PUSH := 9.0

## Local conditions are re-sampled this often rather than every frame. The player cannot
## cross a 4 m cell faster than this, so nothing is missed.
const LOCAL_SAMPLE_INTERVAL := 0.25

## Lightning timing, in seconds.
const LIGHTNING_MIN_GAP := 4.0
const LIGHTNING_MAX_GAP := 14.0
const LIGHTNING_FLASH_SECONDS := 0.18
const LIGHTNING_ENERGY := 3.2

## Delay between flash and thunder. Real distance would vary; a fixed short gap reads as
## a nearby storm without needing to model distance.
const THUNDER_DELAY := 0.9

var _weather: Node
var _sky: Node
var _environment: Environment
var _player: Node3D
var _map: RefCounted

## Local conditions where the player is standing, re-sampled periodically.
var _local: Dictionary = {}
var _precipitation_kind := Local.Precipitation.NONE
var _wind := 0.0
var _sample_countdown := 0.0
var _wind_direction := Vector3(1.0, 0.0, 0.35).normalized()

var _current: Dictionary = {}
var _blend := 1.0
var _from: Dictionary = {}
var _to: Dictionary = {}

var _rain: GPUParticles3D
var _flash: DirectionalLight3D
var _rain_audio: AudioStreamPlayer
var _thunder_audio: AudioStreamPlayer

var _rng := RandomNumberGenerator.new()
var _next_lightning := 0.0
var _flash_remaining := 0.0
var _thunder_countdown := -1.0


func bind(weather: Node, sky: Node, environment: Environment,
		player: Node3D, terrain: Node = null) -> void:
	_weather = weather
	_sky = sky
	_environment = environment
	_player = player
	if terrain != null and terrain.has_method(&"heightmap"):
		_map = terrain.heightmap()

	_rng.seed = 90210
	_build_nodes()

	if _weather != null:
		_weather.weather_changed.connect(_on_weather_changed)
		_from = WeatherLook.for_state(_weather.current())
		_to = _from.duplicate()
		_current = _from.duplicate()
		_blend = 1.0
		_apply(_current)


## The look currently in effect, after blending. Exposed so the overlay and tests can
## see what is actually applied rather than what was requested.
func current_look() -> Dictionary:
	return _current


func status_line() -> String:
	if _current.is_empty():
		return "effects: idle"
	var density := float(_local.get("volumetric_density",
			_current["volumetric_density"]))
	return "effects: %s, fog %.3f, wind %.2f, visibility %.0fm" % [
		Local.precipitation_name(_precipitation_kind),
		density,
		_wind,
		float(_current["visibility_m"]),
	]


## The locally modulated look. Exposed so tests and the overlay see what is applied
## rather than what the global condition asked for.
func local_look() -> Dictionary:
	return _local


func _on_weather_changed(state: int) -> void:
	# Blend from wherever the look actually is, not from the previous condition's
	# target, so a change part-way through a blend continues smoothly.
	_from = _current.duplicate()
	_to = WeatherLook.for_state(state)
	_blend = 0.0


func _process(delta: float) -> void:
	if _to.is_empty():
		return

	if _blend < 1.0:
		_blend = minf(_blend + BLEND_RATE * delta, 1.0)
		_current = WeatherLook.blend(_from, _to, _blend)
		_apply(_current)

	_sample_countdown -= delta
	if _sample_countdown <= 0.0:
		_sample_countdown = LOCAL_SAMPLE_INTERVAL
		_sample_local()

	_update_lightning(delta)


## Re-reads where the player is and applies the local modulation on top of the global
## condition. The heightmap lookup is O(1), so this costs nothing worth throttling for
## beyond avoiding pointless work.
func _sample_local() -> void:
	if _map == null or _player == null or _current.is_empty():
		return

	var position := _player.global_position
	var cell: Vector2i = _map.world_to_cell(position.x, position.z)
	var biome: int = _map.biome_at_cell(cell.x, cell.y)
	# The player's own altitude, not the ground beneath them, so precipitation is right
	# when they are up a mountain and later when they are flying over one.
	var altitude := int(round(position.y))
	var near_river: bool = Local.near_river(_map, cell.x, cell.y)

	var state: int = _weather.current() if _weather != null else 0
	_local = Local.modulate(_current, state, biome, altitude, near_river)

	var kind := int(_local["precipitation_kind"])
	var wind := float(_local["wind"])
	if kind != _precipitation_kind:
		_precipitation_kind = kind
		_apply_precipitation_kind(kind)
	if absf(wind - _wind) > 0.02:
		_wind = wind
		_apply_wind(wind)

	if _environment != null:
		_environment.volumetric_fog_density = float(
				_local["volumetric_density"])


func _apply(look: Dictionary) -> void:
	if _environment != null:
		_environment.volumetric_fog_enabled = float(
				look["volumetric_density"]) > 0.0001
		_environment.volumetric_fog_density = float(look["volumetric_density"])
		_environment.volumetric_fog_length = Config.view_distance_m() * 0.5

		# Weather shortens the view on top of the budget's far plane, so fog is not
		# only thicker but genuinely blinding.
		var visibility := float(look["visibility_m"])
		_environment.fog_depth_end = visibility
		_environment.fog_depth_begin = visibility * Config.fog_start_fraction()

	if _sky != null:
		_sky.set_weather_attenuation(
				float(look["sun_scale"]), float(look["sky_darken"]))

	if _rain != null:
		var precipitation := float(look["precipitation"])
		_rain.emitting = precipitation > 0.01
		_rain.amount_ratio = clampf(precipitation, 0.0, 1.0)

	if _rain_audio != null:
		var db := float(look["rain_volume_db"])
		_rain_audio.volume_db = db
		var audible := db > WeatherLook.SILENT_DB + 1.0
		if audible and not _rain_audio.playing:
			_rain_audio.play()
		elif not audible and _rain_audio.playing:
			_rain_audio.stop()


func _physics_process(_delta: float) -> void:
	# Precipitation follows the player rather than filling the island: 3200 particles
	# overhead look like rain everywhere, and cost nothing beyond the camera.
	if _rain != null and _player != null:
		_rain.global_position = _player.global_position \
				+ Vector3(0.0, RAIN_HEIGHT_M, 0.0)


func _update_lightning(delta: float) -> void:
	if _flash_remaining > 0.0:
		_flash_remaining -= delta
		if _flash != null:
			# Decay across the flash rather than a square pulse, so it reads as a strike.
			var strength := clampf(
					_flash_remaining / LIGHTNING_FLASH_SECONDS, 0.0, 1.0)
			_flash.light_energy = LIGHTNING_ENERGY * strength
			_flash.visible = strength > 0.01

	if _thunder_countdown > 0.0:
		_thunder_countdown -= delta
		if _thunder_countdown <= 0.0 and _thunder_audio != null:
			_thunder_audio.play()

	if not bool(_current.get("lightning", false)):
		_next_lightning = 0.0
		return

	_next_lightning -= delta
	if _next_lightning <= 0.0:
		_strike()


func _strike() -> void:
	_next_lightning = _rng.randf_range(LIGHTNING_MIN_GAP, LIGHTNING_MAX_GAP)
	_flash_remaining = LIGHTNING_FLASH_SECONDS
	_thunder_countdown = THUNDER_DELAY
	if _flash != null:
		# Each strike comes from a different quarter of the sky.
		_flash.rotation = Vector3(
				deg_to_rad(_rng.randf_range(-70.0, -25.0)),
				_rng.randf_range(0.0, TAU), 0.0)


func _build_nodes() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Precipitation"
	_rain.amount = RAIN_PARTICLES
	_rain.lifetime = RAIN_HEIGHT_M / RAIN_FALL_SPEED
	_rain.emitting = false
	_rain.local_coords = false
	_rain.draw_pass_1 = _build_raindrop_mesh()
	_rain.process_material = _build_rain_process()
	# Rain is drawn without shadows or culling surprises: it is above the player and
	# always in view when it exists.
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Particles are frustum-culled against this box, not against where they actually
	# are. The default is a few metres, so rain falling 18 m from its emitter is culled
	# entirely and the sky stays empty however hard it is raining.
	_rain.visibility_aabb = AABB(
			Vector3(-RAIN_AREA_M, -RAIN_HEIGHT_M * 1.5, -RAIN_AREA_M),
			Vector3(RAIN_AREA_M * 2.0, RAIN_HEIGHT_M * 2.0, RAIN_AREA_M * 2.0))
	add_child(_rain)

	_flash = DirectionalLight3D.new()
	_flash.name = "LightningFlash"
	_flash.light_color = Color(0.86, 0.92, 1.0)
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_flash.visible = false
	add_child(_flash)

	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.name = "RainAudio"
	_rain_audio.stream = ProceduralAudio.rain()
	_rain_audio.volume_db = WeatherLook.SILENT_DB
	add_child(_rain_audio)

	_thunder_audio = AudioStreamPlayer.new()
	_thunder_audio.name = "ThunderAudio"
	_thunder_audio.stream = ProceduralAudio.thunder()
	_thunder_audio.volume_db = -4.0
	add_child(_thunder_audio)


## Swaps the emitter between rain and snow. Same particle system, different appearance
## and fall behaviour, so no second emitter is needed.
func _apply_precipitation_kind(kind: int) -> void:
	if _rain == null:
		return
	var snowing := kind == Local.Precipitation.SNOW
	_rain.draw_pass_1 = _build_snowflake_mesh() if snowing \
			else _build_raindrop_mesh()
	var speed := SNOW_FALL_SPEED if snowing else RAIN_FALL_SPEED
	_rain.lifetime = RAIN_HEIGHT_M / speed
	var material: ParticleProcessMaterial = _rain.process_material
	if material != null:
		material.initial_velocity_min = speed * 0.8
		material.initial_velocity_max = speed
		material.spread = SNOW_DRIFT * 10.0 if snowing else 0.0
	_apply_wind(_wind)


## Wind pushes precipitation sideways by biasing gravity, so a storm on the beach
## visibly slants while the same storm under forest canopy falls straight.
func _apply_wind(strength: float) -> void:
	if _rain == null:
		return
	var material: ParticleProcessMaterial = _rain.process_material
	if material == null:
		return
	var fall := -9.8 if _precipitation_kind != Local.Precipitation.SNOW else -2.0
	material.gravity = Vector3(0.0, fall, 0.0) \
			+ _wind_direction * WIND_PUSH * strength


func _build_snowflake_mesh() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.16, 0.16)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.96, 0.97, 1.0, 0.9)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	return mesh


func _build_raindrop_mesh() -> Mesh:
	# A thin vertical box, in keeping with the cuboid look, stretched so it reads as a
	# streak rather than a dot.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035, 0.55, 0.035)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.62, 0.74, 0.88, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	return mesh


func _build_rain_process() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(RAIN_AREA_M, 0.5, RAIN_AREA_M)
	material.direction = Vector3(0.0, -1.0, 0.0)
	material.spread = 0.0
	material.initial_velocity_min = RAIN_FALL_SPEED * 0.85
	material.initial_velocity_max = RAIN_FALL_SPEED
	material.gravity = Vector3(0.0, -9.8, 0.0)
	material.scale_min = 0.7
	material.scale_max = 1.4
	return material
