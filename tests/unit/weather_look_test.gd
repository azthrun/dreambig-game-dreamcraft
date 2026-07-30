extends "res://tests/test_case.gd"
## Tests the weather look table and the generated audio.
##
## Appearance itself is judged from screenshots by a human; these assert only that the
## presentation reads the correct state and that the numbers are ordered sensibly.

const Weather := preload("res://scripts/world/weather_model.gd")
const Look := preload("res://scripts/world/weather_look.gd")
const Audio := preload("res://scripts/audio/procedural_audio.gd")


func test_every_condition_has_a_complete_look() -> void:
	# A condition added later must not arrive with half its presentation missing.
	for state in Weather.ALL:
		var look: Dictionary = Look.for_state(state)
		for key in Look.REQUIRED_KEYS:
			assert_true(look.has(key),
					"%s is missing '%s'" % [Weather.name_of(state), key])


func test_fog_measurably_reduces_visibility() -> void:
	# The whole point of the fog condition.
	var clear: float = Look.for_state(Weather.State.CLEAR)["visibility_m"]
	var foggy: float = Look.for_state(Weather.State.FOG)["visibility_m"]
	assert_true(foggy < clear * 0.25,
			"fog should cut visibility to a fraction of clear (%.0f vs %.0f)"
					% [foggy, clear])
	assert_true(Look.visibility_loss(Weather.State.FOG) > 0.75)
	assert_almost_eq(Look.visibility_loss(Weather.State.CLEAR), 0.0, 0.001)


func test_fog_is_the_thickest_condition() -> void:
	var foggy: float = Look.for_state(Weather.State.FOG)["volumetric_density"]
	for state in Weather.ALL:
		if state == Weather.State.FOG:
			continue
		assert_true(float(Look.for_state(state)["volumetric_density"]) < foggy,
				"%s should be thinner than fog" % Weather.name_of(state))


func test_cloud_cover_progressively_dims_the_sun() -> void:
	# Cloudy, overcast and storm should each be darker than the last, or the states are
	# not visually distinguishable.
	var order := [Weather.State.CLEAR, Weather.State.CLOUDY,
			Weather.State.OVERCAST, Weather.State.RAIN, Weather.State.THUNDERSTORM]
	for i in range(1, order.size()):
		var brighter: float = Look.for_state(order[i - 1])["sun_scale"]
		var dimmer: float = Look.for_state(order[i])["sun_scale"]
		assert_true(dimmer < brighter,
				"%s should dim the sun more than %s"
						% [Weather.name_of(order[i]), Weather.name_of(order[i - 1])])
		var less_dark: float = Look.for_state(order[i - 1])["sky_darken"]
		var more_dark: float = Look.for_state(order[i])["sky_darken"]
		assert_true(more_dark > less_dark, "sky should grey progressively")


func test_only_rain_and_storms_precipitate_and_are_audible() -> void:
	for state in Weather.ALL:
		var look: Dictionary = Look.for_state(state)
		var wet: bool = Weather.is_precipitating(state)
		assert_eq(float(look["precipitation"]) > 0.0, wet,
				"%s precipitation disagrees with the model"
						% Weather.name_of(state))
		assert_eq(float(look["rain_volume_db"]) > Look.SILENT_DB, wet,
				"%s audibility disagrees with the model" % Weather.name_of(state))


func test_only_thunderstorms_have_lightning() -> void:
	for state in Weather.ALL:
		assert_eq(bool(Look.for_state(state)["lightning"]),
				state == Weather.State.THUNDERSTORM,
				"%s lightning flag is wrong" % Weather.name_of(state))


func test_storms_rain_harder_than_rain() -> void:
	assert_true(
			float(Look.for_state(Weather.State.THUNDERSTORM)["precipitation"])
					> float(Look.for_state(Weather.State.RAIN)["precipitation"]))


func test_blending_moves_between_two_looks() -> void:
	# Weather must arrive over seconds rather than switching between frames.
	var clear: Dictionary = Look.for_state(Weather.State.CLEAR)
	var storm: Dictionary = Look.for_state(Weather.State.THUNDERSTORM)

	var at_start: Dictionary = Look.blend(clear, storm, 0.0)
	assert_almost_eq(float(at_start["visibility_m"]),
			float(clear["visibility_m"]), 0.001)

	var at_end: Dictionary = Look.blend(clear, storm, 1.0)
	assert_almost_eq(float(at_end["visibility_m"]),
			float(storm["visibility_m"]), 0.001)

	var halfway: Dictionary = Look.blend(clear, storm, 0.5)
	var expected := (float(clear["visibility_m"])
			+ float(storm["visibility_m"])) * 0.5
	assert_almost_eq(float(halfway["visibility_m"]), expected, 0.001)


func test_blend_weight_is_clamped() -> void:
	var clear: Dictionary = Look.for_state(Weather.State.CLEAR)
	var fog: Dictionary = Look.for_state(Weather.State.FOG)
	assert_almost_eq(float(Look.blend(clear, fog, -3.0)["visibility_m"]),
			float(clear["visibility_m"]), 0.001)
	assert_almost_eq(float(Look.blend(clear, fog, 9.0)["visibility_m"]),
			float(fog["visibility_m"]), 0.001)


func test_booleans_switch_rather_than_interpolate() -> void:
	# A half-lightning makes no sense, so booleans flip at the midpoint.
	var rain: Dictionary = Look.for_state(Weather.State.RAIN)
	var storm: Dictionary = Look.for_state(Weather.State.THUNDERSTORM)
	assert_false(bool(Look.blend(rain, storm, 0.2)["lightning"]))
	assert_true(bool(Look.blend(rain, storm, 0.8)["lightning"]))


func test_generated_rain_audio_is_a_seamless_loop() -> void:
	var stream: AudioStreamWAV = Audio.rain()
	assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD,
			"rain must loop or it stops mid-storm")
	assert_eq(stream.mix_rate, Audio.MIX_RATE)
	assert_eq(stream.data.size(), int(Audio.MIX_RATE * Audio.RAIN_SECONDS) * 2)
	assert_eq(stream.loop_end, int(Audio.MIX_RATE * Audio.RAIN_SECONDS))


func test_generated_thunder_is_a_one_shot() -> void:
	var stream: AudioStreamWAV = Audio.thunder()
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED,
			"thunder must not loop")
	assert_eq(stream.data.size(), int(Audio.MIX_RATE * Audio.THUNDER_SECONDS) * 2)


func test_generated_audio_is_deterministic() -> void:
	assert_eq(Audio.rain(999).data, Audio.rain(999).data)
	assert_ne(Audio.rain(1).data, Audio.rain(2).data)


func test_thunder_is_duller_than_rain() -> void:
	# Thunder reads as distant and heavy only because it is filtered far harder.
	assert_true(Audio.THUNDER_SMOOTHING > Audio.RAIN_SMOOTHING)
