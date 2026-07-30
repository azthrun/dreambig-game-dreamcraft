extends "res://tests/test_case.gd"
## Tests the day/night cycle: pacing, sun position, and phase progression.

const DayNight := preload("res://scripts/world/day_night_model.gd")

const CYCLE_SECONDS := 20.0 * 60.0

## Resolution for sampling the whole cycle when measuring proportions.
const SAMPLES := 20000


func test_time_wraps_once_per_cycle() -> void:
	assert_almost_eq(DayNight.normalized_time(0.0, CYCLE_SECONDS), 0.0, 0.0001)
	assert_almost_eq(DayNight.normalized_time(CYCLE_SECONDS * 0.5, CYCLE_SECONDS),
			0.5, 0.0001)
	# A full cycle returns to the start rather than running off the end.
	assert_almost_eq(DayNight.normalized_time(CYCLE_SECONDS, CYCLE_SECONDS),
			0.0, 0.0001)
	assert_almost_eq(DayNight.normalized_time(CYCLE_SECONDS * 2.25, CYCLE_SECONDS),
			0.25, 0.0001)


func test_time_handles_running_backwards() -> void:
	assert_almost_eq(DayNight.normalized_time(-CYCLE_SECONDS * 0.25, CYCLE_SECONDS),
			0.75, 0.0001)


func test_a_zero_length_cycle_does_not_divide_by_zero() -> void:
	assert_eq(DayNight.normalized_time(123.0, 0.0), 0.0)


func test_sun_is_up_at_noon_and_down_at_midnight() -> void:
	# The most basic thing that could be wrong, and invisible to any other test here.
	assert_true(DayNight.sun_elevation_rad(0.5) > 0.0, "noon sun should be up")
	assert_true(DayNight.sun_elevation_rad(0.0) < 0.0, "midnight sun should be down")
	assert_true(DayNight.is_daytime(0.5))
	assert_false(DayNight.is_daytime(0.0))


func test_sun_is_highest_at_noon() -> void:
	var noon := DayNight.sun_elevation_rad(0.5)
	assert_almost_eq(noon, DayNight.MAX_SUN_ELEVATION_RAD, 0.0001)
	assert_true(noon > DayNight.sun_elevation_rad(0.35))
	assert_true(noon > DayNight.sun_elevation_rad(0.65))


func test_sun_crosses_the_horizon_exactly_at_sunrise_and_sunset() -> void:
	# The two half-sines are joined here; a mismatch would show as the sun jumping.
	assert_almost_eq(DayNight.sun_elevation_rad(DayNight.SUNRISE_T), 0.0, 0.0001)
	assert_almost_eq(DayNight.sun_elevation_rad(DayNight.SUNSET_T), 0.0, 0.0001)


func test_day_lasts_fourteen_minutes_of_a_twenty_minute_cycle() -> void:
	# The agreed pacing, and the reason elevation is two half-sines rather than one
	# sine: a plain sine would split the cycle evenly at 10 minutes each.
	var daylight_samples := 0
	for i in SAMPLES:
		if DayNight.sun_elevation_rad(float(i) / float(SAMPLES)) > 0.0:
			daylight_samples += 1
	var day_fraction := float(daylight_samples) / float(SAMPLES)
	assert_almost_eq(day_fraction, DayNight.DAY_FRACTION, 0.005)
	assert_almost_eq(day_fraction * 20.0, 14.0, 0.1)
	assert_almost_eq((1.0 - day_fraction) * 20.0, 6.0, 0.1)


func test_sun_direction_points_downward_during_the_day() -> void:
	# Light travels from the sun towards the world, so at noon it must point down.
	var direction := DayNight.sun_direction(0.5)
	assert_almost_eq(direction.length(), 1.0, 0.0001)
	assert_true(direction.y < 0.0, "daytime sunlight should travel downward")


func test_sun_direction_points_upward_at_night() -> void:
	var direction := DayNight.sun_direction(0.0)
	assert_true(direction.y > 0.0,
			"with the sun below the horizon its light travels upward")


func test_moon_is_opposite_the_sun() -> void:
	for t in [0.0, 0.25, 0.5, 0.75]:
		var sun: Vector3 = DayNight.sun_direction(t)
		var moon: Vector3 = DayNight.moon_direction(t)
		assert_almost_eq(sun.dot(moon), -1.0, 0.0001,
				"moon should sit opposite the sun at t=%f" % t)


func test_sun_sweeps_a_full_turn_across_the_cycle() -> void:
	# Sampled across the open interval: t = 1.0 wraps to t = 0.0 by design, so azimuth
	# there is midnight's azimuth again rather than a full turn on from it.
	var start := DayNight.sun_azimuth_rad(0.0)
	assert_almost_eq(DayNight.sun_azimuth_rad(0.25) - start, TAU * 0.25, 0.0001)
	assert_almost_eq(DayNight.sun_azimuth_rad(0.5) - start, TAU * 0.5, 0.0001)
	assert_almost_eq(DayNight.sun_azimuth_rad(0.999) - start, TAU * 0.999, 0.001)
	# And it does wrap, rather than growing without bound.
	assert_almost_eq(DayNight.sun_azimuth_rad(1.0), start, 0.0001)


func test_daylight_peaks_by_day_and_is_zero_at_night() -> void:
	assert_almost_eq(DayNight.daylight(0.5), 1.0, 0.0001)
	assert_eq(DayNight.daylight(0.0), 0.0)
	assert_true(DayNight.daylight(0.5) > DayNight.daylight(DayNight.SUNRISE_T))


func test_twilight_peaks_at_the_horizon_not_at_noon() -> void:
	# This is what produces warm dawn and dusk colour; at noon it must be absent.
	assert_almost_eq(DayNight.twilight(DayNight.SUNRISE_T), 1.0, 0.0001)
	assert_almost_eq(DayNight.twilight(DayNight.SUNSET_T), 1.0, 0.0001)
	assert_eq(DayNight.twilight(0.5), 0.0)


func test_moonlight_is_present_at_night_and_gone_by_midday() -> void:
	assert_true(DayNight.moonlight(0.0) > 0.5, "midnight should be moonlit")
	assert_eq(DayNight.moonlight(0.5), 0.0, "noon should have no moonlight")


func test_phases_progress_night_dawn_day_dusk() -> void:
	assert_eq(DayNight.phase(0.0), DayNight.Phase.NIGHT)
	assert_eq(DayNight.phase(DayNight.SUNRISE_T), DayNight.Phase.DAWN)
	assert_eq(DayNight.phase(0.5), DayNight.Phase.DAY)
	assert_eq(DayNight.phase(DayNight.SUNSET_T), DayNight.Phase.DUSK)


func test_every_phase_is_named() -> void:
	for value in [DayNight.Phase.NIGHT, DayNight.Phase.DAWN,
			DayNight.Phase.DAY, DayNight.Phase.DUSK]:
		assert_ne(DayNight.phase_name(value), "unknown")


func test_clock_reads_midnight_at_zero_and_midday_at_half() -> void:
	assert_eq(DayNight.clock_string(0.0), "00:00")
	assert_eq(DayNight.clock_string(0.5), "12:00")
	assert_eq(DayNight.clock_string(0.25), "06:00")


func test_elevation_is_continuous_across_the_whole_cycle() -> void:
	# A discontinuity would show in game as the sun teleporting. Checked by walking the
	# cycle and asserting no single step jumps.
	var previous := DayNight.sun_elevation_rad(0.0)
	var largest_step := 0.0
	for i in range(1, 2001):
		var t := float(i) / 2000.0
		var current := DayNight.sun_elevation_rad(t)
		largest_step = maxf(largest_step, absf(current - previous))
		previous = current
	assert_true(largest_step < 0.02,
			"elevation should move smoothly, largest step was %f" % largest_step)
