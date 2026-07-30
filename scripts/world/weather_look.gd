extends RefCounted
## What each weather condition should look and sound like.
##
## Pure: a condition goes in, a set of numbers comes out. Nothing here touches fog,
## particles or audio — it only decides the targets, which is what makes the mapping
## testable even though everything it drives is visual.
##
## Effects blend towards these targets rather than snapping to them, so weather arrives
## over seconds instead of switching between frames.

const Weather := preload("res://scripts/world/weather_model.gd")

## Keys every look must define. Checked by a test, so a condition added later cannot
## silently arrive with half its presentation missing.
const REQUIRED_KEYS: Array[String] = [
	"volumetric_density",
	"sun_scale",
	"sky_darken",
	"precipitation",
	"visibility_m",
	"lightning",
	"rain_volume_db",
]

## Visibility with no weather at all, matching the configured view distance.
const CLEAR_VISIBILITY_M := 500.0

## Silence, for conditions with no rain. Godot treats this as inaudible.
const SILENT_DB := -80.0

const LOOKS := {
	Weather.State.CLEAR: {
		"volumetric_density": 0.0,
		"sun_scale": 1.0,
		"sky_darken": 0.0,
		"precipitation": 0.0,
		"visibility_m": CLEAR_VISIBILITY_M,
		"lightning": false,
		"rain_volume_db": SILENT_DB,
	},
	Weather.State.CLOUDY: {
		"volumetric_density": 0.004,
		"sun_scale": 0.78,
		"sky_darken": 0.16,
		"precipitation": 0.0,
		"visibility_m": 470.0,
		"lightning": false,
		"rain_volume_db": SILENT_DB,
	},
	Weather.State.OVERCAST: {
		"volumetric_density": 0.011,
		"sun_scale": 0.45,
		"sky_darken": 0.42,
		"precipitation": 0.0,
		"visibility_m": 400.0,
		"lightning": false,
		"rain_volume_db": SILENT_DB,
	},
	Weather.State.RAIN: {
		"volumetric_density": 0.020,
		"sun_scale": 0.30,
		"sky_darken": 0.56,
		"precipitation": 1.0,
		"visibility_m": 300.0,
		"lightning": false,
		"rain_volume_db": -12.0,
	},
	Weather.State.THUNDERSTORM: {
		"volumetric_density": 0.030,
		"sun_scale": 0.18,
		"sky_darken": 0.72,
		"precipitation": 1.7,
		"visibility_m": 220.0,
		"lightning": true,
		"rain_volume_db": -6.0,
	},
	Weather.State.FOG: {
		# The point of fog: you cannot see. Density is far above any other condition and
		# visibility collapses to under a fifth of clear.
		"volumetric_density": 0.075,
		"sun_scale": 0.52,
		"sky_darken": 0.30,
		"precipitation": 0.0,
		"visibility_m": 90.0,
		"lightning": false,
		"rain_volume_db": SILENT_DB,
	},
}


static func for_state(state: int) -> Dictionary:
	return LOOKS.get(state, LOOKS[Weather.State.CLEAR])


## Linear blend between two looks. Booleans switch at the halfway point rather than
## interpolating, since a half-lightning makes no sense.
static func blend(from: Dictionary, to: Dictionary, weight: float) -> Dictionary:
	var t := clampf(weight, 0.0, 1.0)
	var result := {}
	for key in REQUIRED_KEYS:
		var a: Variant = from.get(key)
		var b: Variant = to.get(key)
		if a is bool or b is bool:
			result[key] = b if t >= 0.5 else a
		else:
			result[key] = lerpf(float(a), float(b), t)
	return result


## How much of the visibility budget a condition takes away, 0..1. Used by anything that
## wants "how bad is it" without caring which condition it is.
static func visibility_loss(state: int) -> float:
	var look := for_state(state)
	return clampf(
			1.0 - float(look["visibility_m"]) / CLEAR_VISIBILITY_M, 0.0, 1.0)
