extends "res://tests/test_case.gd"
## The flying suit's fuel tank: drain rate, capping, and exhaustion.

const FlightFuel := preload("res://scripts/player/flight_fuel.gd")


func test_starts_empty() -> void:
	var tank: RefCounted = FlightFuel.new()
	assert_true(tank.is_empty())
	assert_false(tank.can_fly())
	assert_eq(tank.fuel(), 0.0)


func test_adding_fuel_fills_the_tank() -> void:
	var tank: RefCounted = FlightFuel.new()
	var added: float = tank.add(FlightFuel.FUEL_PER_ITEM)
	assert_almost_eq(added, FlightFuel.FUEL_PER_ITEM, 0.001)
	assert_almost_eq(tank.fuel(), FlightFuel.FUEL_PER_ITEM, 0.001)
	assert_true(tank.can_fly())


func test_adding_fuel_is_capped_at_capacity() -> void:
	var tank: RefCounted = FlightFuel.new(50.0)
	var added: float = tank.add(1000.0)
	assert_almost_eq(added, 50.0, 0.001,
			"only enough to fill the tank should be reported as added")
	assert_almost_eq(tank.fuel(), 50.0, 0.001)
	assert_true(tank.is_full())

	var second: float = tank.add(10.0)
	assert_eq(second, 0.0, "a full tank should accept nothing more")


func test_drain_rate_matches_the_declared_constant() -> void:
	var tank: RefCounted = FlightFuel.new()
	tank.add(FlightFuel.CAPACITY)
	tank.drain(2.0)
	var expected := FlightFuel.CAPACITY - FlightFuel.DRAIN_PER_SECOND * 2.0
	assert_almost_eq(tank.fuel(), expected, 0.001)


func test_draining_more_than_the_tank_holds_stops_at_zero() -> void:
	var tank: RefCounted = FlightFuel.new()
	tank.add(10.0)
	tank.drain(100.0)
	assert_eq(tank.fuel(), 0.0, "fuel must not go negative")
	assert_true(tank.is_empty())


func test_exhaustion_flips_can_fly_to_false() -> void:
	var tank: RefCounted = FlightFuel.new()
	tank.add(FlightFuel.DRAIN_PER_SECOND * 1.0)
	assert_true(tank.can_fly())
	tank.drain(1.0)
	assert_false(tank.can_fly(), "the tank should be unable to fly once it hits zero")


func test_zero_or_negative_delta_drains_nothing() -> void:
	var tank: RefCounted = FlightFuel.new()
	tank.add(20.0)
	tank.drain(0.0)
	tank.drain(-5.0)
	assert_almost_eq(tank.fuel(), 20.0, 0.001)


func test_fraction_tracks_the_fill_level() -> void:
	var tank: RefCounted = FlightFuel.new(40.0)
	assert_almost_eq(tank.fraction(), 0.0, 0.001)
	tank.add(20.0)
	assert_almost_eq(tank.fraction(), 0.5, 0.001)
	tank.add(20.0)
	assert_almost_eq(tank.fraction(), 1.0, 0.001)
