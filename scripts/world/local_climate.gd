extends RefCounted
## How the one global weather condition manifests at a particular place.
##
## The condition is global — it is raining, or it is not — but what that looks like where
## you are standing depends on altitude, biome, and whether there is water nearby. Rain
## falls as snow on the peaks while the beach below stays wet, wind picks up on an
## exposed coast, and fog settles into valleys and river basins.
##
## Every function here is pure: place and condition in, numbers out. That is what makes
## a system whose entire output is visual testable at all.

const Biome := preload("res://scripts/world/biome.gd")
const Weather := preload("res://scripts/world/weather_model.gd")

enum Precipitation { NONE, RAIN, SNOW }

## Altitude at and above which falling precipitation is snow rather than rain.
##
## Deliberately below the terrain mesher's permanent snow cap: snow falls well before it
## lies year-round, so the two are different lines and the lower one is this.
const SNOWLINE_M := 52

## Wind exposure per biome, 0..1 before altitude is taken into account.
##
## Forest is the outlier that matters: trees break the wind, so a storm is markedly
## calmer under canopy than on the beach a hundred metres away.
const BIOME_WIND := {
	Biome.Kind.OCEAN: 1.0,
	Biome.Kind.BEACH: 0.9,
	Biome.Kind.PLAINS: 0.5,
	Biome.Kind.FOREST: 0.22,
	Biome.Kind.MOUNTAINS: 0.7,
	Biome.Kind.RIVER: 0.45,
}

## Extra wind from altitude, added on top of the biome's exposure.
const WIND_ALTITUDE_REFERENCE_M := 70.0
const WIND_ALTITUDE_BONUS := 0.45

## Fog is thickest at sea level and thins with height, so valleys hold mist while peaks
## stand clear above it.
const FOG_SEA_LEVEL_MULTIPLIER := 1.7
const FOG_HIGH_MULTIPLIER := 0.45
const FOG_ALTITUDE_REFERENCE_M := 60.0

## Additional thickening near running water.
const FOG_RIVER_BONUS := 0.8


## What is actually falling here: nothing, rain, or snow.
static func precipitation_kind(state: int, altitude_m: int) -> int:
	if not Weather.is_precipitating(state):
		return Precipitation.NONE
	return Precipitation.SNOW if altitude_m >= SNOWLINE_M else Precipitation.RAIN


static func precipitation_name(kind: int) -> String:
	match kind:
		Precipitation.NONE:
			return "none"
		Precipitation.RAIN:
			return "rain"
		Precipitation.SNOW:
			return "snow"
	return "unknown"


## Wind exposure at a place, 0..1. Biome sets the baseline and altitude adds to it.
static func wind_strength(biome: int, altitude_m: int) -> float:
	var base: float = BIOME_WIND.get(biome, 0.5)
	var altitude := clampf(
			float(maxi(altitude_m, 0)) / WIND_ALTITUDE_REFERENCE_M, 0.0, 1.0)
	return clampf(base + altitude * WIND_ALTITUDE_BONUS, 0.0, 1.0)


## Multiplier applied to the condition's fog density. Above 1 thickens it.
static func fog_multiplier(altitude_m: int, near_river: bool) -> float:
	var altitude := clampf(
			float(maxi(altitude_m, 0)) / FOG_ALTITUDE_REFERENCE_M, 0.0, 1.0)
	var multiplier := lerpf(
			FOG_SEA_LEVEL_MULTIPLIER, FOG_HIGH_MULTIPLIER, altitude)
	if near_river:
		multiplier += FOG_RIVER_BONUS
	return multiplier


## Applies every local modulation to a blended look, returning a copy with the fog
## adjusted and the local precipitation kind and wind recorded.
static func modulate(look: Dictionary, state: int, biome: int, altitude_m: int,
		near_river: bool) -> Dictionary:
	var result := look.duplicate()
	result["volumetric_density"] = float(look.get("volumetric_density", 0.0)) \
			* fog_multiplier(altitude_m, near_river)
	result["precipitation_kind"] = precipitation_kind(state, altitude_m)
	result["wind"] = wind_strength(biome, altitude_m)
	return result


## Whether any cell within `radius` cells is a river, used for basin fog.
##
## Takes the world grid as data rather than reaching for a node, so it stays pure.
static func near_river(map: RefCounted, cx: int, cz: int, radius: int = 3) -> bool:
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if map.biome_at_cell(cx + dx, cz + dz) == Biome.Kind.RIVER:
				return true
	return false
