extends RefCounted
## The single authority for turning live game state into a save file and back.
##
## Two halves, deliberately kept apart. `capture`/`apply` move data between live systems
## — Player, Props, Weather, Sky, ItemPlacer — and a plain `SaveData`, taking those
## systems as explicit arguments rather than reaching into the scene tree itself, the
## same discipline every other bind() in this project follows. `write_file`/`read_file`
## move a `SaveData` to and from disk as JSON. `SaveData` itself has no Node dependency
## at all, which is what keeps a round trip testable without a scene — see
## `save_data_test.gd`. This file's own `capture`/`apply` are covered by the scene-based
## `save_load_test.gd` instead, for the same reason melee and firearm tests are: moving
## real state in and out of real Nodes is not reducible to a pure function.

const SaveData := preload("res://scripts/persistence/save_data.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")
const Campfire := preload("res://scripts/world/props/campfire.gd")

const SAVE_PATH := "user://save.json"


## Reads every live system's state into a fresh SaveData. Any argument may be null —
## a test capturing only props, say — and is simply skipped.
static func capture(world_seed: int, sky: Node, weather: Node, player: Node,
		props: Node, item_placer: Node) -> RefCounted:
	var save: RefCounted = SaveData.new()
	save.world_seed = world_seed
	if sky != null:
		save.time_of_day = sky.time_of_day()
	if weather != null:
		save.weather_state = weather.current()
		save.weather_remaining = weather.time_until_change()

	if player != null:
		save.player_position = player.global_position
		var stats: RefCounted = player.stats()
		save.player_health = stats.health()
		save.player_hunger = stats.hunger()
		save.player_stamina = stats.stamina()
		save.worn_item = player.worn_item()
		save.flight_suit_equipped = player.has_flight_suit()
		save.flight_fuel = player.flight_fuel().fuel()
		save.inventory_slots = _capture_inventory(player.inventory())
		save.selected_slot = player.inventory().selected_slot()

	if item_placer != null:
		save.campfires = _capture_campfires(item_placer)

	if props != null:
		save.looted_caches = _capture_looted_caches(props)
		save.depleted_props = _capture_depleted_props(props)

	return save


## Applies a SaveData to live systems. Refuses — returning false, changing nothing —
## when the save's world seed does not match the world already generated: replaying
## looted-cache and depleted-prop ids from a different island would corrupt it rather
## than restore it, since those ids only mean the same thing on the island they came
## from.
static func apply(save: RefCounted, world_seed: int, sky: Node, weather: Node,
		player: Node, props: Node, item_placer: Node, climate: Node = null) -> bool:
	if save == null or int(save.world_seed) != world_seed:
		return false

	if sky != null:
		sky.set_time_of_day(save.time_of_day)
	if weather != null:
		weather.restore(save.weather_state, save.weather_remaining)

	if player != null:
		player.global_position = save.player_position
		player.respawn_point = save.player_position
		player.stats().restore(save.player_health, save.player_hunger,
				save.player_stamina)
		player.set_worn(save.worn_item)
		player.set_flight_suit_equipped(save.flight_suit_equipped)
		player.flight_fuel().set_fuel(save.flight_fuel)
		player.inventory().restore(save.inventory_slots, save.selected_slot)

	if props != null:
		_apply_looted_caches(save.looted_caches, props)
		_apply_depleted_props(save.depleted_props, props)

	if item_placer != null and props != null:
		_apply_campfires(save.campfires, item_placer, props, climate)

	return true


## Writes a save to disk as human-readable JSON. Returns whether it succeeded.
static func write_file(save: RefCounted, path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(save.to_dict(), "\t"))
	return true


## Reads a save from disk. Returns null if the file is missing or the JSON is corrupt —
## refused rather than handing a caller a broken SaveData to act on.
static func read_file(path: String = SAVE_PATH) -> RefCounted:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		return null
	return SaveData.from_dict(parsed)


static func save_exists(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


static func delete_save(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _capture_inventory(inventory: RefCounted) -> Array:
	var slots: Array = []
	for i in inventory.capacity():
		var item: int = inventory.item_in_slot(i)
		if item == ItemKind.Kind.NONE:
			continue
		slots.append({"slot": i, "item": item, "count": inventory.count_in_slot(i)})
	return slots


static func _capture_campfires(item_placer: Node) -> Array:
	var fires: Array = []
	for fire in item_placer.placed_fires():
		if not is_instance_valid(fire):
			continue
		var at: Vector3 = fire.global_position
		fires.append({
			"x": at.x, "y": at.y, "z": at.z,
			"fuel": fire.fuel_remaining(),
			"cooking_count": fire.cooking_count(),
			"cook_elapsed": fire.cook_elapsed(),
		})
	return fires


static func _capture_looted_caches(props: Node) -> Array:
	var looted: Array = []
	for cache in props.caches():
		if not is_instance_valid(cache) or not cache.is_looted():
			continue
		looted.append({
			"cache_id": cache.cache_id,
			"remaining": cache.time_until_refill(),
			"refills": cache.refills_count(),
		})
	return looted


static func _capture_depleted_props(props: Node) -> Array:
	var depleted: Array = []
	for harvestable in props.harvestables():
		if not is_instance_valid(harvestable) or not harvestable.is_depleted():
			continue
		depleted.append({
			"prop_id": harvestable.prop_id,
			"remaining": harvestable.time_until_respawn(),
		})
	return depleted


static func _apply_looted_caches(looted_caches: Array, props: Node) -> void:
	var by_id: Dictionary = {}
	for entry in looted_caches:
		by_id[int(entry.get("cache_id", -1))] = entry
	for cache in props.caches():
		if not is_instance_valid(cache):
			continue
		var entry: Dictionary = by_id.get(cache.cache_id, {})
		if entry.is_empty():
			continue
		cache.restore_looted(float(entry.get("remaining", 0.0)),
				int(entry.get("refills", 0)))


static func _apply_depleted_props(depleted_props: Array, props: Node) -> void:
	var by_id: Dictionary = {}
	for entry in depleted_props:
		by_id[int(entry.get("prop_id", -1))] = entry
	for harvestable in props.harvestables():
		if not is_instance_valid(harvestable):
			continue
		var entry: Dictionary = by_id.get(harvestable.prop_id, {})
		if entry.is_empty():
			continue
		harvestable.restore_depleted(float(entry.get("remaining", 0.0)))


## Rebuilds every saved campfire fresh, the same way `item_placer.gd` builds one placed
## live: parented under Props, lit, its cooking state (if any) put back, made known to
## the placer so refuelling and cooking-nearby find it, and registered as a heat source.
static func _apply_campfires(campfires: Array, item_placer: Node, props: Node,
		climate: Node) -> void:
	for entry in campfires:
		var fire: Node3D = Campfire.new()
		props.add_child(fire)
		fire.global_position = Vector3(
				float(entry.get("x", 0.0)), float(entry.get("y", 0.0)),
				float(entry.get("z", 0.0)))
		fire.light(float(entry.get("fuel", 0.0)))
		var cooking_count := int(entry.get("cooking_count", 0))
		if cooking_count > 0:
			fire.restore_cooking(cooking_count, float(entry.get("cook_elapsed", 0.0)))
		item_placer.register_fire(fire)
		if climate != null and climate.has_method(&"add_heat_source"):
			climate.add_heat_source(fire, Campfire.HEAT_RADIUS_M, Campfire.HEAT_STRENGTH_C)
