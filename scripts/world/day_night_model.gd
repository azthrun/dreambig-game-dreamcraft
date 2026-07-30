extends RefCounted
## Time of day: where the sun is, how bright it is, and what colour the sky should be.
##
## Pure. Takes a normalised time and returns numbers — no Node, no lights, no sky. The
## presentation side reads these and applies them, which is what makes the whole cycle
## testable headlessly despite being an entirely visual feature.
##
## Time runs 0..1 with 0 at midnight. Day is deliberately longer than night: night is an
## event to get through, not half of every play session.

## Fraction of the cycle the sun spends above the horizon.
##
## 0.7 of a 20 minute cycle is 14 minutes of day and 6 of night. This is why elevation
## is not a plain sine wave — a sine would put the sun up for exactly half the cycle.
const DAY_FRACTION := 0.7

const SUNRISE_T := (1.0 - DAY_FRACTION) * 0.5
const SUNSET_T := SUNRISE_T + DAY_FRACTION

## Highest the sun climbs, and how far below the horizon it dips at midnight. The dip is
## shallower than the climb so nights are dark but not pitch black.
const MAX_SUN_ELEVATION_RAD := 1.15
const MAX_SUN_DEPRESSION_RAD := 0.62

## Sun and moon rise in the east and set in the west, sweeping a full turn per cycle.
const AZIMUTH_OFFSET_RAD := 0.6

## Elevation band, in radians either side of the horizon, over which dawn and dusk
## colour appears. Wider than the sun takes to cross it, so twilight lingers.
const TWILIGHT_BAND_RAD := 0.30

enum Phase { NIGHT, DAWN, DAY, DUSK }


## Wraps elapsed seconds into 0..1. Any elapsed time is valid, including negative.
static func normalized_time(elapsed_seconds: float, cycle_seconds: float) -> float:
	if cycle_seconds <= 0.0:
		return 0.0
	return fposmod(elapsed_seconds / cycle_seconds, 1.0)


## Sun height above the horizon in radians. Positive by day, negative by night.
##
## Two half-sines joined at sunrise and sunset rather than one full sine, so the day arc
## can be stretched over 70% of the cycle while still crossing zero exactly at the
## horizon.
static func sun_elevation_rad(t: float) -> float:
	var time := fposmod(t, 1.0)
	if time >= SUNRISE_T and time <= SUNSET_T:
		var day_progress := (time - SUNRISE_T) / DAY_FRACTION
		return MAX_SUN_ELEVATION_RAD * sin(PI * day_progress)
	# Night runs from sunset, through midnight, to sunrise.
	var night_length := 1.0 - DAY_FRACTION
	var since_sunset := fposmod(time - SUNSET_T, 1.0)
	var night_progress := since_sunset / night_length
	return -MAX_SUN_DEPRESSION_RAD * sin(PI * night_progress)


static func sun_azimuth_rad(t: float) -> float:
	return AZIMUTH_OFFSET_RAD + TAU * fposmod(t, 1.0)


## Unit vector along which sunlight travels, for a directional light to point down.
static func sun_direction(t: float) -> Vector3:
	var elevation := sun_elevation_rad(t)
	var azimuth := sun_azimuth_rad(t)
	# Position of the sun on the celestial sphere, then negated: light travels from the
	# sun towards the world.
	var to_sun := Vector3(
			cos(elevation) * sin(azimuth),
			sin(elevation),
			cos(elevation) * cos(azimuth))
	return -to_sun.normalized()


## The moon sits opposite the sun, so it is up exactly when the sun is not.
static func moon_direction(t: float) -> Vector3:
	return -sun_direction(t)


static func is_daytime(t: float) -> bool:
	return sun_elevation_rad(t) > 0.0


## How much of full daylight is in effect, 0 at night and 1 with the sun well up. Used
## for sun brightness and for blending the sky towards its daytime colours.
static func daylight(t: float) -> float:
	var elevation := sun_elevation_rad(t)
	if elevation <= 0.0:
		return 0.0
	return clampf(sin(elevation) / sin(MAX_SUN_ELEVATION_RAD * 0.55), 0.0, 1.0)


## Peaks while the sun is near the horizon, either side. Drives the warm dawn and dusk
## colour, which is the thing worth stopping to look at.
static func twilight(t: float) -> float:
	var elevation := sun_elevation_rad(t)
	return clampf(1.0 - absf(elevation) / TWILIGHT_BAND_RAD, 0.0, 1.0)


## Moonlight strength. Fades out as dawn arrives rather than snapping off at sunrise.
static func moonlight(t: float) -> float:
	return clampf(1.0 - daylight(t) - twilight(t) * 0.5, 0.0, 1.0)


static func phase(t: float) -> int:
	var elevation := sun_elevation_rad(t)
	if elevation > TWILIGHT_BAND_RAD:
		return Phase.DAY
	if elevation < -TWILIGHT_BAND_RAD:
		return Phase.NIGHT
	# Near the horizon: rising or setting decides which.
	var time := fposmod(t, 1.0)
	return Phase.DAWN if time < 0.5 else Phase.DUSK


static func phase_name(value: int) -> String:
	match value:
		Phase.NIGHT:
			return "night"
		Phase.DAWN:
			return "dawn"
		Phase.DAY:
			return "day"
		Phase.DUSK:
			return "dusk"
	return "unknown"


## 24-hour clock reading, with midnight at t = 0.
static func clock_string(t: float) -> String:
	var hours := fposmod(t, 1.0) * 24.0
	var hour := int(hours)
	var minute := int((hours - float(hour)) * 60.0)
	return "%02d:%02d" % [hour, minute]
