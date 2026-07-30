extends "res://tests/test_case.gd"
## Tests the campfire: fuel burn-down, refuelling, warmth, and where it may be built.
##
## Fuel is advanced by injected deltas, so a three-minute burn is tested in microseconds.

const Campfire := preload("res://scripts/world/props/campfire.gd")
const TemperatureModel := preload("res://scripts/world/temperature_model.gd")
const Weather := preload("res://scripts/world/weather_model.gd")
const Biome := preload("res://scripts/world/biome.gd")

var _made: Array[Node] = []


func after_each() -> void:
	for node in _made:
		if is_instance_valid(node):
			node.free()
	_made.clear()


## A campfire outside the tree: _ready has not run, so it is unlit until told otherwise.
func _fire(fuel: float = Campfire.INITIAL_FUEL_SECONDS) -> Node3D:
	var fire: Node3D = Campfire.new()
	_made.append(fire)
	fire.light(fuel)
	return fire


func test_a_lit_fire_burns() -> void:
	var fire := _fire()
	assert_true(fire.is_burning())
	assert_almost_eq(fire.fuel_remaining(), Campfire.INITIAL_FUEL_SECONDS, 0.001)


func test_fuel_burns_down_in_real_time() -> void:
	var fire := _fire(100.0)
	fire.tick(30.0)
	assert_almost_eq(fire.fuel_remaining(), 70.0, 0.001)


func test_a_fire_goes_out_when_its_fuel_is_spent() -> void:
	var fire := _fire(10.0)
	fire.tick(11.0)
	assert_false(fire.is_burning())
	assert_almost_eq(fire.fuel_remaining(), 0.0, 0.001)


func test_going_out_is_announced() -> void:
	var fire := _fire(5.0)
	var seen := [false]
	fire.went_out.connect(func(): seen[0] = true)
	fire.tick(6.0)
	assert_true(seen[0])


func test_adding_fuel_extends_a_burning_fire() -> void:
	var fire := _fire(30.0)
	assert_true(fire.add_fuel(Campfire.FUEL_PER_WOOD_SECONDS))
	assert_almost_eq(fire.fuel_remaining(),
			30.0 + Campfire.FUEL_PER_WOOD_SECONDS, 0.001)


func test_fuel_is_capped_and_a_full_fire_refuses_more() -> void:
	# Refusing matters: silently accepting would eat the wood for nothing.
	var fire := _fire(Campfire.MAX_FUEL_SECONDS)
	assert_false(fire.add_fuel(100.0))
	assert_almost_eq(fire.fuel_remaining(), Campfire.MAX_FUEL_SECONDS, 0.001)


func test_adding_fuel_relights_a_dead_fire() -> void:
	var fire := _fire(1.0)
	fire.tick(2.0)
	assert_false(fire.is_burning())
	assert_true(fire.add_fuel(60.0))
	assert_true(fire.is_burning())


func test_a_burning_fire_warms_what_is_near_it() -> void:
	var fire := _fire()
	assert_almost_eq(fire.heat_at(Vector3.ZERO), Campfire.HEAT_STRENGTH_C, 0.001)
	var near: float = fire.heat_at(Vector3(2.0, 0.0, 0.0))
	var far: float = fire.heat_at(Vector3(5.0, 0.0, 0.0))
	assert_true(near > far and far > 0.0, "warmth should fall off with distance")


func test_warmth_stops_at_the_radius() -> void:
	var fire := _fire()
	assert_almost_eq(
			fire.heat_at(Vector3(Campfire.HEAT_RADIUS_M, 0.0, 0.0)), 0.0, 0.001)
	assert_almost_eq(fire.heat_at(Vector3(50.0, 0.0, 0.0)), 0.0, 0.001)


func test_an_extinguished_fire_gives_no_warmth_at_all() -> void:
	# Not merely less warmth: a dead fire must stop helping entirely.
	var fire := _fire(5.0)
	assert_true(fire.heat_at(Vector3.ZERO) > 0.0)
	fire.tick(6.0)
	assert_almost_eq(fire.heat_at(Vector3.ZERO), 0.0, 0.001)


func test_a_fire_rescues_a_night_that_would_otherwise_kill_you() -> void:
	# The whole point of the ticket. Cold was given two answers in place of building:
	# shelter, and this.
	var exposed := TemperatureModel.temperature_c(
			Biome.Kind.MOUNTAINS, 60, 0.0, Weather.State.THUNDERSTORM, false)
	assert_true(TemperatureModel.cold_damage_per_second(exposed) > 0.0,
			"the scenario must be lethal without a fire")

	var fire := _fire()
	var beside := TemperatureModel.temperature_c(
			Biome.Kind.MOUNTAINS, 60, 0.0, Weather.State.THUNDERSTORM, false,
			fire.heat_at(Vector3.ZERO))
	assert_false(TemperatureModel.is_cold(beside),
			"standing at the fire should be survivable, got %.1f C" % beside)


func test_a_fire_does_not_rescue_you_from_across_the_island() -> void:
	var fire := _fire()
	var far_away := TemperatureModel.temperature_c(
			Biome.Kind.MOUNTAINS, 60, 0.0, Weather.State.THUNDERSTORM, false,
			fire.heat_at(Vector3(30.0, 0.0, 0.0)))
	assert_true(TemperatureModel.is_cold(far_away),
			"warmth must be somewhere you go, not a global buff")


func test_ticking_a_dead_fire_does_nothing() -> void:
	var fire := _fire(1.0)
	fire.tick(5.0)
	fire.tick(100.0)
	assert_almost_eq(fire.fuel_remaining(), 0.0, 0.001)


func test_level_dry_ground_is_buildable() -> void:
	assert_true(Campfire.is_valid_ground(Vector3(0.0, 12.0, 0.0), Vector3.UP, 0.0))


func test_a_fire_cannot_be_built_in_the_sea() -> void:
	assert_false(Campfire.is_valid_ground(Vector3(0.0, -3.0, 0.0), Vector3.UP, 0.0))
	assert_false(Campfire.is_valid_ground(Vector3(0.0, 0.0, 0.0), Vector3.UP, 0.0),
			"the waterline itself is not dry ground")


func test_a_fire_cannot_be_built_on_a_terrace_face() -> void:
	# A vertical skirt would leave the fire half-buried in the cliff.
	var vertical := Vector3(1.0, 0.0, 0.0)
	assert_false(Campfire.is_valid_ground(Vector3(0.0, 12.0, 0.0), vertical, 0.0))


func test_a_gentle_slope_is_still_buildable() -> void:
	var gentle := Vector3(0.2, 1.0, 0.0).normalized()
	assert_true(Campfire.is_valid_ground(Vector3(0.0, 12.0, 0.0), gentle, 0.0))
