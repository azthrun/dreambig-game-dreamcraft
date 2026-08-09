extends RefCounted
## The plain-data shape of a save file: every field SPEC's Persistence section says gets
## saved, and nothing that is reproduced from the world seed instead.
##
## Pure: it knows nothing about Player, Props, or any live Node — see `save_manager.gd`
## for the half that reads and writes those. A round trip here is `to_dict()` followed by
## `from_dict()` on plain data, which is what makes it testable without a scene.

## Bumped only if the shape changes incompatibly. Not read on load yet — nothing has
## shipped a save file to migrate from — but this is what a future migration would key
## on, so it is part of the format from the start rather than added under pressure later.
const FORMAT_VERSION := 1

## The one thing that makes every other saved field meaningful: terrain, biomes, prop
## placement, and cache contents are all reproduced from this, never saved themselves.
var world_seed := 0

var time_of_day := 0.0
var weather_state := 0
var weather_remaining := 0.0

var player_position := Vector3.ZERO
var player_health := 0.0
var player_hunger := 0.0
var player_stamina := 0.0
var worn_item := 0
var flight_suit_equipped := false
var flight_fuel := 0.0

## Each entry: `{slot: int, item: int, count: int}`. Empty slots are omitted rather than
## written as `NONE` — the item table's own `Kind.NONE` is already the absence of a slot.
var inventory_slots: Array = []
var selected_slot := 0

## Each entry: `{x, y, z, fuel, cooking_count, cook_elapsed}` — every placed campfire,
## since a player's base is exactly what SPEC says has to persist.
var campfires: Array = []

## Each entry: `{cache_id, remaining, refills}`. Only ever holds *looted* caches — an
## unopened cache always regenerates identically from `(world_seed, cache_id)`, so
## recording it would be redundant, and this is also what keeps a save from growing with
## the size of the island rather than with what the player actually did to it.
var looted_caches: Array = []

## Each entry: `{prop_id, remaining}`. Only ever holds *depleted* harvestables, for the
## same reason.
var depleted_props: Array = []


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"world_seed": world_seed,
		"time_of_day": time_of_day,
		"weather_state": weather_state,
		"weather_remaining": weather_remaining,
		"player": {
			"position": [player_position.x, player_position.y, player_position.z],
			"health": player_health,
			"hunger": player_hunger,
			"stamina": player_stamina,
			"worn_item": worn_item,
			"flight_suit_equipped": flight_suit_equipped,
			"flight_fuel": flight_fuel,
			"inventory": inventory_slots.duplicate(true),
			"selected_slot": selected_slot,
		},
		"campfires": campfires.duplicate(true),
		"looted_caches": looted_caches.duplicate(true),
		"depleted_props": depleted_props.duplicate(true),
	}


## Builds a SaveData from plain data — the shape `JSON.parse_string` hands back, or a
## literal dictionary a test constructs by hand. Missing fields fall back to this class's
## own defaults rather than failing, so a save file only ever gets stricter over time
## through `FORMAT_VERSION`, not through every field becoming mandatory.
static func from_dict(data: Dictionary) -> RefCounted:
	var save := new()
	save.world_seed = int(data.get("world_seed", 0))
	save.time_of_day = float(data.get("time_of_day", 0.0))
	save.weather_state = int(data.get("weather_state", 0))
	save.weather_remaining = float(data.get("weather_remaining", 0.0))

	var player: Dictionary = data.get("player", {})
	var position: Array = player.get("position", [])
	save.player_position = Vector3(
			float(position[0]) if position.size() > 0 else 0.0,
			float(position[1]) if position.size() > 1 else 0.0,
			float(position[2]) if position.size() > 2 else 0.0)
	save.player_health = float(player.get("health", 0.0))
	save.player_hunger = float(player.get("hunger", 0.0))
	save.player_stamina = float(player.get("stamina", 0.0))
	save.worn_item = int(player.get("worn_item", 0))
	save.flight_suit_equipped = bool(player.get("flight_suit_equipped", false))
	save.flight_fuel = float(player.get("flight_fuel", 0.0))
	save.inventory_slots = player.get("inventory", [])
	save.selected_slot = int(player.get("selected_slot", 0))

	save.campfires = data.get("campfires", [])
	save.looted_caches = data.get("looted_caches", [])
	save.depleted_props = data.get("depleted_props", [])
	return save
