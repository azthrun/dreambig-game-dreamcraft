extends RefCounted
## How cold it is where the player is standing, and what that costs them.
##
## This is the module where the whole climate milestone becomes mechanical. Day/night,
## weather, altitude, biome and shelter have all existed as visuals; here they add up to
## a single number that can hurt you.
##
## Pure: place and conditions in, degrees out. Every contribution is separable, so each
## can be asserted on its own rather than only in combination.

const Biome := preload("res://scripts/world/biome.gd")
const Weather := preload("res://scripts/world/weather_model.gd")
const DayNight := preload("res://scripts/world/day_night_model.gd")

## Temperature at sea level, at noon, in clear weather, on open ground.
const BASE_C := 22.0

## Cooling with height. About 11 degrees per 100 m — steeper than the real lapse rate,
## because an island 74 m tall would otherwise have no meaningful altitude gradient.
const LAPSE_RATE_C_PER_M := 0.11

## How much colder full night is than full day.
const NIGHT_DROP_C := 14.0

## Per-biome adjustment. Forest is shaded, mountains are exposed, the sea takes heat.
const BIOME_OFFSET_C := {
	Biome.Kind.OCEAN: -2.0,
	Biome.Kind.BEACH: 1.0,
	Biome.Kind.PLAINS: 0.0,
	Biome.Kind.FOREST: -1.0,
	Biome.Kind.MOUNTAINS: -3.0,
	Biome.Kind.RIVER: -1.5,
}

## Per-condition adjustment. Rain and storms are what turn a survivable night lethal.
const WEATHER_OFFSET_C := {
	Weather.State.CLEAR: 2.0,
	Weather.State.CLOUDY: 0.0,
	Weather.State.OVERCAST: -2.0,
	Weather.State.RAIN: -5.0,
	Weather.State.THUNDERSTORM: -7.0,
	Weather.State.FOG: -3.0,
}

## Being out of the weather. Sized so that shelter alone rescues a storm-swept night on
## open ground, which is what makes cover worth running for.
const SHELTER_BONUS_C := 6.0

## Below this, the player starts losing health.
const COLD_THRESHOLD_C := 4.0

## Damage per second for each degree below the threshold. At roughly -9 degrees this is
## about 2.6 health a second: dangerous, but with most a minute to do something.
const COLD_DAMAGE_PER_DEGREE := 0.2


## Temperature in degrees, from everything that affects it.
##
## `heat_c` is warmth from nearby sources — campfires — passed in rather than looked up,
## so this stays a function of its arguments.
## `insulation_c` is warmth carried on the body — armour — kept separate from `heat_c`
## so the two can be asserted independently. Shelter, fire and clothing are the three
## answers to cold, and each has to be shown to work on its own.
static func temperature_c(biome: int, altitude_m: int, time_of_day: float,
		weather_state: int, sheltered: bool, heat_c: float = 0.0,
		insulation_c: float = 0.0) -> float:
	var celsius := BASE_C
	celsius += float(BIOME_OFFSET_C.get(biome, 0.0))
	celsius -= LAPSE_RATE_C_PER_M * float(maxi(altitude_m, 0))
	# Night is a fraction rather than a switch, so dusk cools gradually.
	celsius -= NIGHT_DROP_C * (1.0 - DayNight.daylight(time_of_day))
	celsius += float(WEATHER_OFFSET_C.get(weather_state, 0.0))
	if sheltered:
		celsius += SHELTER_BONUS_C
	return celsius + maxf(heat_c, 0.0) + maxf(insulation_c, 0.0)


static func is_cold(celsius: float) -> bool:
	return celsius < COLD_THRESHOLD_C


## Health lost per second at a given temperature. Zero at or above the threshold, then
## scaling with how far below it is — being slightly cold is survivable, being very cold
## is not.
static func cold_damage_per_second(celsius: float) -> float:
	if celsius >= COLD_THRESHOLD_C:
		return 0.0
	return (COLD_THRESHOLD_C - celsius) * COLD_DAMAGE_PER_DEGREE


## Warmth contributed by a heat source, falling off with distance and reaching zero at
## its radius. Campfires use this; nothing else does yet.
static func heat_from_source(distance_m: float, radius_m: float,
		strength_c: float) -> float:
	if distance_m >= radius_m or radius_m <= 0.0:
		return 0.0
	var closeness := 1.0 - distance_m / radius_m
	# Squared so warmth concentrates near the fire rather than spreading evenly.
	return strength_c * closeness * closeness
