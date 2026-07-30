extends "res://tests/test_case.gd"
## Tests the survival pools: hunger, stamina, starvation and death.
##
## Advanced by injected deltas, so a full day of starvation is simulated in microseconds
## rather than waited out.

const Stats := preload("res://scripts/player/survival_stats.gd")


func _stats(rates: Dictionary = {}) -> RefCounted:
	return Stats.new(rates)


func test_starts_healthy_fed_and_rested() -> void:
	var s := _stats()
	assert_almost_eq(s.health(), s.rate("max_health"), 0.001)
	assert_almost_eq(s.hunger(), 0.0, 0.001)
	assert_almost_eq(s.stamina(), s.rate("max_stamina"), 0.001)
	assert_false(s.is_dead())
	assert_false(s.is_starving())


func test_hunger_rises_at_the_configured_rate() -> void:
	var s := _stats()
	s.tick(10.0, false)
	assert_almost_eq(s.hunger(), s.rate("hunger_per_second") * 10.0, 0.001)


func test_hunger_stops_at_full_rather_than_growing_without_bound() -> void:
	var s := _stats()
	for _i in 2000:
		s.tick(1.0, false)
	assert_almost_eq(s.hunger(), s.rate("max_hunger"), 0.001)
	assert_true(s.is_starving())


func test_starvation_damages_health_at_the_configured_rate() -> void:
	# Hunger is filled fast via a rate override rather than one enormous tick, which
	# would apply a whole lifetime of starvation damage at once and kill the player
	# before the interval being measured.
	var s := _stats({"hunger_per_second": 1000.0})
	s.tick(0.1, false)
	assert_true(s.is_starving())
	var before: float = s.health()
	s.tick(5.0, false)
	assert_almost_eq(before - s.health(),
			s.rate("starvation_damage_per_second") * 5.0, 0.01)


func test_starving_long_enough_kills() -> void:
	# Hunger takes about 714s to fill at the default rate, then another 50s to kill.
	var s := _stats()
	for _i in 1200:
		s.tick(1.0, false)
	assert_true(s.is_dead())
	assert_almost_eq(s.health(), 0.0, 0.001)


func test_health_never_goes_below_zero() -> void:
	var s := _stats()
	s.damage(99999.0)
	assert_almost_eq(s.health(), 0.0, 0.001)


func test_a_dead_player_stops_changing() -> void:
	# Otherwise hunger keeps climbing on a corpse and the respawn arrives starving.
	var s := _stats()
	s.damage(99999.0)
	var hunger_before: float = s.hunger()
	s.tick(60.0, false)
	assert_almost_eq(s.hunger(), hunger_before, 0.001)


func test_sprinting_drains_stamina_at_the_configured_rate() -> void:
	var s := _stats()
	s.tick(3.0, true)
	assert_almost_eq(s.stamina(),
			s.rate("max_stamina") - s.rate("stamina_sprint_drain_per_second") * 3.0,
			0.01)


func test_stamina_empties_but_does_not_go_negative() -> void:
	var s := _stats()
	s.tick(1000.0, true)
	assert_almost_eq(s.stamina(), 0.0, 0.001)
	assert_false(s.can_sprint(), "an exhausted player cannot sprint")


func test_stamina_regenerates_only_after_a_delay() -> void:
	# Without the delay, tapping sprint repeatedly would dodge the cost entirely.
	var s := _stats()
	s.tick(2.0, true)
	var drained: float = s.stamina()
	# Immediately after sprinting: still within the delay, so no recovery.
	s.tick(s.rate("stamina_regen_delay_seconds") * 0.5, false)
	assert_almost_eq(s.stamina(), drained, 0.001)
	# Past the delay, it comes back.
	s.tick(2.0, false)
	assert_true(s.stamina() > drained)


func test_stamina_refills_to_full_and_no_further() -> void:
	var s := _stats()
	s.tick(5.0, true)
	s.tick(1000.0, false)
	assert_almost_eq(s.stamina(), s.rate("max_stamina"), 0.001)


func test_health_recovers_only_while_well_fed() -> void:
	var s := _stats()
	s.damage(40.0)
	var wounded: float = s.health()
	# Well fed: hunger starts at zero, so health should come back.
	s.tick(4.0, false)
	assert_true(s.health() > wounded, "a fed player should heal")

	# Now hungry past the ceiling: healing stops.
	var hungry := _stats()
	hungry.damage(40.0)
	hungry.tick(hungry.rate("health_regen_hunger_ceiling")
			/ hungry.rate("hunger_per_second") + 1.0, false)
	var at_ceiling: float = hungry.health()
	hungry.tick(4.0, false)
	assert_almost_eq(hungry.health(), at_ceiling, 0.01,
			"a hungry player should not heal")


func test_eating_reduces_hunger_and_reports_what_was_used() -> void:
	var s := _stats()
	s.tick(200.0, false)
	var before: float = s.hunger()
	var used: float = s.eat(10.0)
	assert_almost_eq(s.hunger(), before - 10.0, 0.001)
	assert_almost_eq(used, 10.0, 0.001)


func test_eating_when_full_wastes_nothing_silently() -> void:
	# Reports how much was actually needed, so callers can refuse to consume the item.
	var s := _stats()
	assert_almost_eq(s.eat(50.0), 0.0, 0.001)
	assert_almost_eq(s.hunger(), 0.0, 0.001)


func test_reviving_restores_everything() -> void:
	var s := _stats()
	s.tick(1000.0, true)
	s.damage(50.0)
	s.revive()
	assert_almost_eq(s.health(), s.rate("max_health"), 0.001)
	assert_almost_eq(s.hunger(), 0.0, 0.001)
	assert_almost_eq(s.stamina(), s.rate("max_stamina"), 0.001)
	assert_false(s.is_dead())


func test_rates_are_data_and_can_be_overridden() -> void:
	# The point of keeping rates in a dictionary: balance is tunable without touching
	# any of the logic that applies it.
	var fast := _stats({"hunger_per_second": 10.0})
	fast.tick(1.0, false)
	assert_almost_eq(fast.hunger(), 10.0, 0.001)

	var slow := _stats({"hunger_per_second": 0.001})
	slow.tick(1.0, false)
	assert_almost_eq(slow.hunger(), 0.001, 0.0001)


func test_overriding_one_rate_leaves_the_rest_at_their_defaults() -> void:
	var s := _stats({"hunger_per_second": 5.0})
	assert_almost_eq(s.rate("max_health"),
			float(Stats.DEFAULT_RATES["max_health"]), 0.001)
	assert_almost_eq(s.rate("stamina_regen_per_second"),
			float(Stats.DEFAULT_RATES["stamina_regen_per_second"]), 0.001)


func test_ticking_by_nothing_changes_nothing() -> void:
	var s := _stats()
	s.tick(0.0, true)
	s.tick(-10.0, true)
	assert_almost_eq(s.hunger(), 0.0, 0.001)
	assert_almost_eq(s.stamina(), s.rate("max_stamina"), 0.001)


func test_fractions_track_the_pools() -> void:
	var s := _stats()
	assert_almost_eq(s.health_fraction(), 1.0, 0.001)
	assert_almost_eq(s.hunger_fraction(), 0.0, 0.001)
	s.damage(s.rate("max_health") * 0.5)
	assert_almost_eq(s.health_fraction(), 0.5, 0.001)
