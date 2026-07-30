extends Node3D
## Drives the sun, moon, sky and fog colour from the time of day.
##
## Presentation only: every number it applies comes from the pure day/night model. It
## owns the clock, the lights and the sky material, and nothing else reads them.
##
## The moon is a real DirectionalLight3D rather than a decorative mesh, because Godot's
## procedural sky draws a disc for each directional light — so one node gives both
## moonlight and a visible moon.

const DayNight := preload("res://scripts/world/day_night_model.gd")

## Real seconds for one full day and night. Tunable from the inspector; 20 minutes is
## the agreed pacing.
@export var cycle_minutes: float = 20.0

## Where the cycle starts. Mid-morning by default, so a fresh run opens in daylight
## rather than in the dark.
@export_range(0.0, 1.0) var starting_time: float = 0.30

## Multiplier applied while the debug time-scale action is held, so a full cycle can be
## watched in seconds instead of twenty minutes.
@export var debug_time_scale: float = 60.0

@export var paused: bool = false

# Sky palette, blended by daylight and twilight from the model.
const SKY_TOP_DAY := Color(0.24, 0.44, 0.78)
const SKY_HORIZON_DAY := Color(0.66, 0.75, 0.84)
const SKY_TOP_NIGHT := Color(0.015, 0.025, 0.075)
const SKY_HORIZON_NIGHT := Color(0.05, 0.07, 0.15)
const SKY_TOP_TWILIGHT := Color(0.19, 0.20, 0.44)
const SKY_HORIZON_TWILIGHT := Color(0.96, 0.52, 0.28)

const SUN_COLOUR_DAY := Color(1.0, 0.97, 0.90)
const SUN_COLOUR_TWILIGHT := Color(1.0, 0.62, 0.35)
const MOON_COLOUR := Color(0.62, 0.70, 0.92)

## Ambient fill, driven explicitly rather than inherited from the sky.
const AMBIENT_DAY := Color(0.55, 0.63, 0.75)
const AMBIENT_NIGHT := Color(0.10, 0.13, 0.24)
const AMBIENT_TWILIGHT := Color(0.42, 0.30, 0.32)

const SUN_ENERGY_MAX := 1.15
const MOON_ENERGY_MAX := 0.09

## Stars are drawn as a generated sky-cover texture, faded in at night.
const STAR_TEXTURE_SIZE := 1024
const STAR_COUNT := 1800
const STAR_SEED := 8675309

## Weather dimming, applied on top of the time of day. 1.0 is a clear sky.
var _weather_sun_scale := 1.0
var _weather_darken := 0.0

var _time := 0.0
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _environment: Environment
var _sky_material: ProceduralSkyMaterial


func _ready() -> void:
	_sun = get_node_or_null(^"Sun") as DirectionalLight3D
	_moon = get_node_or_null(^"Moon") as DirectionalLight3D
	_time = starting_time
	_apply()


## Applied by the weather effects. Kept separate from the time of day so the two
## compose: an overcast noon is dim, and an overcast midnight is not somehow brighter.
func set_weather_attenuation(sun_scale: float, darken: float) -> void:
	_weather_sun_scale = clampf(sun_scale, 0.0, 1.0)
	_weather_darken = clampf(darken, 0.0, 1.0)
	_apply()


## Connects the sky to the world environment it should drive.
func bind_environment(environment: Environment) -> void:
	_environment = environment
	if _environment != null and _environment.sky != null \
			and _environment.sky.sky_material is ProceduralSkyMaterial:
		_sky_material = _environment.sky.sky_material
		_sky_material.sky_cover = _build_star_texture()
	_apply()


func cycle_seconds() -> float:
	return maxf(cycle_minutes, 0.01) * 60.0


## Normalised time of day, 0..1 with midnight at 0.
func time_of_day() -> float:
	return _time


func set_time_of_day(value: float) -> void:
	_time = fposmod(value, 1.0)
	_apply()


func _process(delta: float) -> void:
	if paused:
		return
	var scale := debug_time_scale if Input.is_action_pressed(&"debug_time_scale") \
			else 1.0
	_time = fposmod(_time + (delta * scale) / cycle_seconds(), 1.0)
	_apply()


func status_line() -> String:
	return "sky: %s %s, cycle %.0f min (day %.0f min, night %.0f min)" % [
		DayNight.clock_string(_time),
		DayNight.phase_name(DayNight.phase(_time)),
		cycle_minutes,
		cycle_minutes * DayNight.DAY_FRACTION,
		cycle_minutes * (1.0 - DayNight.DAY_FRACTION),
	]


## Pushes the model's numbers onto the lights, sky and fog.
func _apply() -> void:
	var daylight := DayNight.daylight(_time)
	var twilight := DayNight.twilight(_time)
	var moonlight := DayNight.moonlight(_time)

	if _sun != null:
		_sun.look_at_from_position(
				Vector3.ZERO, DayNight.sun_direction(_time), Vector3.UP)
		_sun.light_energy = SUN_ENERGY_MAX * daylight * _weather_sun_scale
		_sun.light_color = SUN_COLOUR_DAY.lerp(SUN_COLOUR_TWILIGHT, twilight)
		# Shadows off entirely once the sun is down, rather than a shadow from a light
		# with no energy.
		_sun.shadow_enabled = daylight > 0.01
		_sun.visible = daylight > 0.001 or twilight > 0.001

	if _moon != null:
		_moon.look_at_from_position(
				Vector3.ZERO, DayNight.moon_direction(_time), Vector3.UP)
		_moon.light_energy = MOON_ENERGY_MAX * moonlight
		_moon.light_color = MOON_COLOUR
		_moon.shadow_enabled = false
		_moon.visible = moonlight > 0.001

	var top := SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, daylight)
	var horizon := SKY_HORIZON_NIGHT.lerp(SKY_HORIZON_DAY, daylight)
	top = top.lerp(SKY_TOP_TWILIGHT, twilight)
	horizon = horizon.lerp(SKY_HORIZON_TWILIGHT, twilight)

	# Cloud cover greys the sky towards overcast rather than merely darkening it, so
	# an overcast day reads as flat and colourless instead of as dusk.
	if _weather_darken > 0.0:
		var grey := Color(0.42, 0.44, 0.47).lerp(Color(0.10, 0.11, 0.13),
				1.0 - daylight)
		top = top.lerp(grey, _weather_darken)
		horizon = horizon.lerp(grey, _weather_darken * 0.8)

	if _sky_material != null:
		_sky_material.sky_top_color = top
		_sky_material.sky_horizon_color = horizon
		_sky_material.ground_horizon_color = horizon
		_sky_material.ground_bottom_color = horizon.darkened(0.35)
		# Stars fade in as daylight goes, so they never wash out a blue sky.
		var star_alpha := clampf(1.0 - daylight * 3.0, 0.0, 1.0)
		_sky_material.sky_cover_modulate = Color(1.0, 1.0, 1.0, star_alpha)

	if _environment != null:
		# Fog tracks the horizon so distant terrain always fades into the sky it is
		# actually standing in front of, at every hour rather than only at noon.
		_environment.fog_light_color = horizon

		# Ambient is driven explicitly rather than taken from the sky.
		#
		# With AMBIENT_SOURCE_SKY, ambient comes from the procedural sky's lower
		# hemisphere, and ambient_light_color is ignored entirely. That left night-time
		# terrain lit amber by the sky material's default brown ground colour — the
		# scene was being lit by a value never chosen for it. Sourcing from COLOR makes
		# the ambient exactly the palette colour picked here.
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_environment.ambient_light_color = AMBIENT_NIGHT.lerp(AMBIENT_DAY, daylight) \
				.lerp(AMBIENT_TWILIGHT, twilight)
		_environment.ambient_light_energy = lerpf(0.35, 1.0, daylight) \
				* lerpf(1.0, 0.55, _weather_darken)


## Random points on a dark panorama, used as the sky's cover layer.
func _build_star_texture() -> ImageTexture:
	var image := Image.create(
			STAR_TEXTURE_SIZE, STAR_TEXTURE_SIZE / 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	for _i in STAR_COUNT:
		var x := rng.randi_range(0, image.get_width() - 1)
		# Biased towards the upper half so stars cluster overhead rather than in the
		# ground half of the panorama, which is never seen.
		var y := rng.randi_range(0, int(float(image.get_height()) * 0.72))
		var brightness := rng.randf_range(0.35, 1.0)
		image.set_pixel(x, y, Color(brightness, brightness, brightness, brightness))

	return ImageTexture.create_from_image(image)
