extends "res://tests/test_case.gd"
## Tests local weather modulation: snowline, wind exposure, and basin fog.
##
## Each modulation is asserted independently and directionally — the numbers themselves
## are tuning, but which way they move is the design.

const Local := preload("res://scripts/world/local_climate.gd")
const Biome := preload("res://scripts/world/biome.gd")
const Weather := preload("res://scripts/world/weather_model.gd")
const Look := preload("res://scripts/world/weather_look.gd")
const IslandGenerator := preload("res://scripts/world/island_generator.gd")


func test_rain_falls_as_snow_above_the_snowline() -> void:
	var state := Weather.State.RAIN
	assert_eq(Local.precipitation_kind(state, Local.SNOWLINE_M - 1),
			Local.Precipitation.RAIN)
	assert_eq(Local.precipitation_kind(state, Local.SNOWLINE_M),
			Local.Precipitation.SNOW)
	assert_eq(Local.precipitation_kind(state, Local.SNOWLINE_M + 20),
			Local.Precipitation.SNOW)


func test_a_single_rain_state_gives_snow_on_the_peak_and_rain_on_the_beach() -> void:
	# The headline behaviour: one global condition, two different experiences of it.
	var state := Weather.State.RAIN
	assert_eq(Local.precipitation_kind(state, 2), Local.Precipitation.RAIN,
			"the beach should be rained on")
	assert_eq(Local.precipitation_kind(state, 70), Local.Precipitation.SNOW,
			"the peak should be snowed on at the same moment")


func test_storms_also_turn_to_snow_at_altitude() -> void:
	assert_eq(Local.precipitation_kind(Weather.State.THUNDERSTORM, 70),
			Local.Precipitation.SNOW)


func test_dry_conditions_precipitate_nothing_at_any_altitude() -> void:
	for state in [Weather.State.CLEAR, Weather.State.CLOUDY,
			Weather.State.OVERCAST, Weather.State.FOG]:
		for altitude in [0, 30, 80]:
			assert_eq(Local.precipitation_kind(state, altitude),
					Local.Precipitation.NONE,
					"%s should not precipitate at %dm"
							% [Weather.name_of(state), altitude])


func test_snow_falls_below_the_permanent_snow_cap() -> void:
	# Snow should fall well before it lies year-round, so the falling-snow line sits
	# below the terrain's permanent white cap.
	const TerrainMesher := preload("res://scripts/world/terrain_mesher.gd")
	assert_true(Local.SNOWLINE_M < TerrainMesher.SNOW_LINE_M,
			"falling snow should start lower than permanent snow")


func test_the_coast_is_windier_than_the_forest() -> void:
	# Trees break the wind, which is most of why a storm feels different under canopy.
	var beach := Local.wind_strength(Biome.Kind.BEACH, 2)
	var forest := Local.wind_strength(Biome.Kind.FOREST, 2)
	assert_true(beach > forest * 2.0,
			"beach %.2f should be far windier than forest %.2f" % [beach, forest])
	assert_true(Local.wind_strength(Biome.Kind.OCEAN, 0)
			>= Local.wind_strength(Biome.Kind.PLAINS, 0))


func test_wind_increases_with_altitude() -> void:
	var low := Local.wind_strength(Biome.Kind.MOUNTAINS, 0)
	var high := Local.wind_strength(Biome.Kind.MOUNTAINS, 70)
	assert_true(high > low, "exposure should rise with height")


func test_wind_stays_within_zero_and_one() -> void:
	for biome in Biome.ALL:
		for altitude in [-10, 0, 40, 200]:
			assert_in_range(Local.wind_strength(biome, altitude), 0.0, 1.0)


func test_fog_pools_low_and_thins_with_height() -> void:
	var valley := Local.fog_multiplier(0, false)
	var peak := Local.fog_multiplier(70, false)
	assert_true(valley > 1.0, "sea level should thicken fog")
	assert_true(peak < 1.0, "peaks should stand clear of it")
	assert_true(valley > peak * 2.0)


func test_fog_thickens_near_rivers() -> void:
	var away := Local.fog_multiplier(20, false)
	var beside := Local.fog_multiplier(20, true)
	assert_true(beside > away, "river basins should hold mist")
	assert_almost_eq(beside - away, Local.FOG_RIVER_BONUS, 0.001)


func test_modulation_thickens_the_condition_fog_rather_than_replacing_it() -> void:
	var look: Dictionary = Look.for_state(Weather.State.FOG)
	var base: float = look["volumetric_density"]
	var valley: Dictionary = Local.modulate(
			look, Weather.State.FOG, Biome.Kind.PLAINS, 0, true)
	var peak: Dictionary = Local.modulate(
			look, Weather.State.FOG, Biome.Kind.MOUNTAINS, 70, false)
	assert_true(float(valley["volumetric_density"]) > base)
	assert_true(float(peak["volumetric_density"]) < base)


func test_modulation_records_local_precipitation_and_wind() -> void:
	var look: Dictionary = Look.for_state(Weather.State.RAIN)
	var beach: Dictionary = Local.modulate(
			look, Weather.State.RAIN, Biome.Kind.BEACH, 1, false)
	var summit: Dictionary = Local.modulate(
			look, Weather.State.RAIN, Biome.Kind.MOUNTAINS, 70, false)
	assert_eq(int(beach["precipitation_kind"]), Local.Precipitation.RAIN)
	assert_eq(int(summit["precipitation_kind"]), Local.Precipitation.SNOW)
	assert_true(float(beach["wind"]) > 0.0)
	assert_true(float(summit["wind"]) > 0.0)


func test_modulation_leaves_the_original_look_untouched() -> void:
	# It returns a copy; mutating the shared look table would corrupt every later frame.
	var look: Dictionary = Look.for_state(Weather.State.RAIN)
	var before: float = look["volumetric_density"]
	Local.modulate(look, Weather.State.RAIN, Biome.Kind.PLAINS, 0, true)
	assert_almost_eq(float(look["volumetric_density"]), before, 0.00001)


func test_every_precipitation_kind_is_named() -> void:
	for kind in [Local.Precipitation.NONE, Local.Precipitation.RAIN,
			Local.Precipitation.SNOW]:
		assert_ne(Local.precipitation_name(kind), "unknown")


func test_river_proximity_finds_water_on_a_real_island() -> void:
	# Checked against generated terrain rather than a hand-built grid, so the search
	# radius is proven useful at the scale rivers actually occur.
	var generator: RefCounted = IslandGenerator.new()
	var map: RefCounted = generator.generate(20260729)
	var found_near := 0
	var found_far := 0
	for cz in range(0, map.cells_per_axis, 7):
		for cx in range(0, map.cells_per_axis, 7):
			if map.biome_at_cell(cx, cz) == Biome.Kind.RIVER:
				if Local.near_river(map, cx, cz):
					found_near += 1
			elif not Local.near_river(map, cx, cz):
				found_far += 1
	assert_true(found_near > 0, "a river cell must count as near a river")
	assert_true(found_far > 0, "most of the island must not count as near a river")
