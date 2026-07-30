extends "res://tests/test_case.gd"
## Tests the temperature model: each input's direction, and what the cold costs.
##
## Every contribution is asserted on its own before any are asserted in combination,
## because a model that is only ever checked as a whole can be wrong in two directions
## at once and still look right.

const Temp := preload("res://scripts/world/temperature_model.gd")
const Biome := preload("res://scripts/world/biome.gd")
const Weather := preload("res://scripts/world/weather_model.gd")
const DayNight := preload("res://scripts/world/day_night_model.gd")

const NOON := 0.5
const MIDNIGHT := 0.0


## A default reading: plains, sea level, noon, clear, exposed.
func _baseline() -> float:
	return Temp.temperature_c(Biome.Kind.PLAINS, 0, NOON,
			Weather.State.CLEAR, false)


func test_night_is_colder_than_day() -> void:
	var day := _baseline()
	var night := Temp.temperature_c(Biome.Kind.PLAINS, 0, MIDNIGHT,
			Weather.State.CLEAR, false)
	assert_true(night < day, "night %.1f should be colder than day %.1f"
			% [night, day])
	assert_almost_eq(day - night, Temp.NIGHT_DROP_C, 0.01)


func test_dusk_is_between_day_and_night() -> void:
	# Cooling is a fraction of daylight rather than a switch, so evening gets colder
	# gradually instead of the temperature dropping off a cliff at sunset.
	var dusk := Temp.temperature_c(Biome.Kind.PLAINS, 0, DayNight.SUNSET_T,
			Weather.State.CLEAR, false)
	var night := Temp.temperature_c(Biome.Kind.PLAINS, 0, MIDNIGHT,
			Weather.State.CLEAR, false)
	assert_true(dusk < _baseline())
	assert_true(dusk >= night)


func test_temperature_falls_with_altitude() -> void:
	var low := _baseline()
	var high := Temp.temperature_c(Biome.Kind.PLAINS, 70, NOON,
			Weather.State.CLEAR, false)
	assert_true(high < low)
	assert_almost_eq(low - high, Temp.LAPSE_RATE_C_PER_M * 70.0, 0.01)


func test_altitude_below_sea_level_does_not_warm_you() -> void:
	# Swimming should not be tropical because the position is negative.
	assert_almost_eq(
			Temp.temperature_c(Biome.Kind.OCEAN, -20, NOON,
					Weather.State.CLEAR, false),
			Temp.temperature_c(Biome.Kind.OCEAN, 0, NOON,
					Weather.State.CLEAR, false), 0.01)


func test_bad_weather_is_colder_than_clear() -> void:
	var previous := 999.0
	# Ordered worst-last: each condition must be colder than the one before it.
	for state in [Weather.State.CLEAR, Weather.State.CLOUDY,
			Weather.State.OVERCAST, Weather.State.RAIN,
			Weather.State.THUNDERSTORM]:
		var celsius := Temp.temperature_c(Biome.Kind.PLAINS, 0, NOON, state, false)
		assert_true(celsius < previous,
				"%s should be colder than the condition before it"
						% Weather.name_of(state))
		previous = celsius


func test_mountains_are_colder_than_the_beach_before_altitude() -> void:
	# Biome alone, both at sea level, so this isolates exposure from height.
	var beach := Temp.temperature_c(Biome.Kind.BEACH, 0, NOON,
			Weather.State.CLEAR, false)
	var mountain := Temp.temperature_c(Biome.Kind.MOUNTAINS, 0, NOON,
			Weather.State.CLEAR, false)
	assert_true(mountain < beach)


func test_shelter_warms_you() -> void:
	var exposed := Temp.temperature_c(Biome.Kind.PLAINS, 0, MIDNIGHT,
			Weather.State.RAIN, false)
	var sheltered := Temp.temperature_c(Biome.Kind.PLAINS, 0, MIDNIGHT,
			Weather.State.RAIN, true)
	assert_almost_eq(sheltered - exposed, Temp.SHELTER_BONUS_C, 0.01)


func test_heat_sources_warm_you() -> void:
	var without := _baseline()
	var beside_fire := Temp.temperature_c(Biome.Kind.PLAINS, 0, NOON,
			Weather.State.CLEAR, false, 8.0)
	assert_almost_eq(beside_fire - without, 8.0, 0.01)


func test_negative_heat_cannot_chill_you() -> void:
	# A malformed heat source should be ignored, not act as a freezer.
	assert_almost_eq(
			Temp.temperature_c(Biome.Kind.PLAINS, 0, NOON,
					Weather.State.CLEAR, false, -50.0),
			_baseline(), 0.01)


func test_the_beach_at_noon_is_safe() -> void:
	# The opening minutes of the game must not be a race against exposure.
	var celsius := Temp.temperature_c(Biome.Kind.BEACH, 1, NOON,
			Weather.State.CLEAR, false)
	assert_false(Temp.is_cold(celsius),
			"a clear day on the beach should be survivable, got %.1f" % celsius)
	assert_almost_eq(Temp.cold_damage_per_second(celsius), 0.0, 0.001)


func test_a_stormy_night_on_the_summit_is_lethal() -> void:
	# The other end of the range: the island should be able to kill you.
	var celsius := Temp.temperature_c(Biome.Kind.MOUNTAINS, 74, MIDNIGHT,
			Weather.State.THUNDERSTORM, false)
	assert_true(Temp.is_cold(celsius))
	assert_true(Temp.cold_damage_per_second(celsius) > 1.5,
			"exposure up there should be seriously dangerous, got %.1f/s"
					% Temp.cold_damage_per_second(celsius))


func test_shelter_meaningfully_improves_a_deadly_night() -> void:
	# Cover is the counter-play cold damage was given in place of building, so it has to
	# actually change the outcome rather than merely soften it.
	var exposed := Temp.temperature_c(Biome.Kind.PLAINS, 20, MIDNIGHT,
			Weather.State.THUNDERSTORM, false)
	var sheltered := Temp.temperature_c(Biome.Kind.PLAINS, 20, MIDNIGHT,
			Weather.State.THUNDERSTORM, true)
	assert_true(Temp.cold_damage_per_second(exposed) > 0.0,
			"the point of the scenario is that exposure hurts")
	assert_true(Temp.cold_damage_per_second(sheltered)
			< Temp.cold_damage_per_second(exposed) * 0.5,
			"shelter should at least halve the damage")


func test_no_damage_at_or_above_the_threshold() -> void:
	assert_almost_eq(Temp.cold_damage_per_second(Temp.COLD_THRESHOLD_C), 0.0, 0.001)
	assert_almost_eq(
			Temp.cold_damage_per_second(Temp.COLD_THRESHOLD_C + 10.0), 0.0, 0.001)
	assert_false(Temp.is_cold(Temp.COLD_THRESHOLD_C))


func test_damage_scales_with_how_far_below_the_threshold() -> void:
	var mild := Temp.cold_damage_per_second(Temp.COLD_THRESHOLD_C - 1.0)
	var severe := Temp.cold_damage_per_second(Temp.COLD_THRESHOLD_C - 10.0)
	assert_true(mild > 0.0)
	assert_true(severe > mild * 5.0, "being very cold should be far worse")
	assert_almost_eq(mild, Temp.COLD_DAMAGE_PER_DEGREE, 0.001)


func test_warming_back_up_stops_the_damage() -> void:
	# The criterion in both directions: crossing the threshold downwards starts damage,
	# crossing it upwards must stop it entirely rather than leaving a trickle.
	var freezing := Temp.COLD_THRESHOLD_C - 8.0
	assert_true(Temp.cold_damage_per_second(freezing) > 0.0)
	var warmed := freezing + Temp.SHELTER_BONUS_C + 6.0
	assert_true(warmed > Temp.COLD_THRESHOLD_C)
	assert_almost_eq(Temp.cold_damage_per_second(warmed), 0.0, 0.001)


func test_heat_falls_off_with_distance_and_stops_at_the_radius() -> void:
	var at_fire := Temp.heat_from_source(0.0, 6.0, 12.0)
	var halfway := Temp.heat_from_source(3.0, 6.0, 12.0)
	assert_almost_eq(at_fire, 12.0, 0.001)
	assert_true(halfway < at_fire and halfway > 0.0)
	assert_almost_eq(Temp.heat_from_source(6.0, 6.0, 12.0), 0.0, 0.001,
			"no warmth at the edge")
	assert_almost_eq(Temp.heat_from_source(20.0, 6.0, 12.0), 0.0, 0.001,
			"and none beyond it")


func test_heat_source_with_no_radius_gives_nothing() -> void:
	assert_almost_eq(Temp.heat_from_source(0.0, 0.0, 12.0), 0.0, 0.001)


func test_every_biome_and_condition_has_an_offset() -> void:
	# A biome or condition added later must not silently default to neutral.
	for biome in Biome.ALL:
		assert_true(Temp.BIOME_OFFSET_C.has(biome),
				"%s has no temperature offset" % Biome.name_of(biome))
	for state in Weather.ALL:
		assert_true(Temp.WEATHER_OFFSET_C.has(state),
				"%s has no temperature offset" % Weather.name_of(state))
