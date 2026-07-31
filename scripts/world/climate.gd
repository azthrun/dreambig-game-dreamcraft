extends Node
## Samples the player's surroundings and applies what the cold does to them.
##
## The one place that knows how to gather every input the temperature model needs —
## terrain, sky, weather, shelter, heat sources — so nothing else has to hold references
## to all five. The model itself stays pure; this only feeds it and acts on the answer.

const TemperatureModel := preload("res://scripts/world/temperature_model.gd")

## Heat sources register themselves rather than being looked up by type, so campfires
## can arrive later without this file learning what a campfire is.
class HeatSource:
	var node: Node3D
	var radius_m: float
	var strength_c: float

	func _init(p_node: Node3D, p_radius: float, p_strength: float) -> void:
		node = p_node
		radius_m = p_radius
		strength_c = p_strength

var _player: Node
var _terrain: Node
var _sky: Node
var _weather: Node
var _map: RefCounted

var _sources: Array[HeatSource] = []
var _temperature := TemperatureModel.BASE_C


func bind(player: Node, terrain: Node, sky: Node, weather: Node) -> void:
	_player = player
	_terrain = terrain
	_sky = sky
	_weather = weather
	if _terrain != null and _terrain.has_method(&"heightmap"):
		_map = _terrain.heightmap()


## Registers a warmth source. Returns it so the caller can unregister on removal.
func add_heat_source(node: Node3D, radius_m: float,
		strength_c: float) -> HeatSource:
	var source := HeatSource.new(node, radius_m, strength_c)
	_sources.append(source)
	return source


func remove_heat_source(source: HeatSource) -> void:
	_sources.erase(source)


func temperature_c() -> float:
	return _temperature


func is_cold() -> bool:
	return TemperatureModel.is_cold(_temperature)


func status_line() -> String:
	return "climate: %.1f C%s" % [
		_temperature, " COLD" if is_cold() else ""]


func _physics_process(delta: float) -> void:
	if _player == null or _map == null:
		return

	_temperature = _sample()

	# Cold damage goes through the same health pool as everything else, so dying of
	# exposure and dying of starvation are the same death.
	var damage := TemperatureModel.cold_damage_per_second(_temperature)
	if damage > 0.0 and _player.has_method(&"stats"):
		var stats: RefCounted = _player.stats()
		if stats != null and not stats.is_dead():
			stats.damage(damage * delta)


func _sample() -> float:
	var position: Vector3 = _player.global_position
	var cell: Vector2i = _map.world_to_cell(position.x, position.z)
	var biome: int = _map.biome_at_cell(cell.x, cell.y)
	var altitude := int(round(position.y))

	var time_of_day := 0.5
	if _sky != null and _sky.has_method(&"time_of_day"):
		time_of_day = _sky.time_of_day()

	var weather_state := 0
	if _weather != null and _weather.has_method(&"current"):
		weather_state = _weather.current()

	var sheltered := false
	if _player.has_method(&"is_sheltered"):
		sheltered = _player.is_sheltered()

	var insulation := 0.0
	if _player.has_method(&"insulation_c"):
		insulation = _player.insulation_c()

	return TemperatureModel.temperature_c(
			biome, altitude, time_of_day, weather_state, sheltered,
			heat_at(position), insulation)


## Total warmth from every registered source at a position. Sources that have been freed
## are dropped as they are found, so nothing has to track their lifetime.
func heat_at(position: Vector3) -> float:
	var total := 0.0
	var stale: Array[HeatSource] = []
	for source in _sources:
		if source.node == null or not is_instance_valid(source.node):
			stale.append(source)
			continue
		total += TemperatureModel.heat_from_source(
				position.distance_to(source.node.global_position),
				source.radius_m, source.strength_c)
	for source in stale:
		_sources.erase(source)
	return total
