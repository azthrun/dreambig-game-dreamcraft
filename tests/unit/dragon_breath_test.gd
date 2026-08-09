extends "res://tests/test_case.gd"
## Fire breath in detail: cone hit detection, that the cone can be dodged once it is
## already firing, the cooldown, and telegraph timing. The state-machine shape (patrol
## through telegraph to breath and back) is covered in dragon_brain_test.gd; this file is
## about the mechanic those states carry.

const Brain := preload("res://scripts/creatures/dragon_brain.gd")

const ANCHOR := Vector3.ZERO
const DETECTION := 70.0
const TICK := 0.2


func _brain(seed_value: int = 11) -> RefCounted:
	return Brain.new(seed_value)


func _at(position: Vector3, player_offset: Vector3, present: bool = true) -> Dictionary:
	return {
		"position": position,
		"anchor": ANCHOR,
		"threat_position": position + player_offset,
		"threat_present": present,
		"detection_m": DETECTION,
	}


## Ticks a fresh brain through a full telegraph so the next tick is the first `breath`
## one, with the player held at `offset` throughout the windup.
func _telegraphed(offset: Vector3, seed_value: int = 11) -> RefCounted:
	var brain := _brain(seed_value)
	var position := Vector3.ZERO
	var steps := int(Brain.TELEGRAPH_SECONDS / TICK) + 2
	for _i in steps:
		brain.tick(TICK, _at(position, offset))
		if brain.state_name() == "breath":
			break
	return brain


func test_a_point_dead_ahead_within_range_is_in_the_cone() -> void:
	var brain := _telegraphed(Vector3(20.0, 0.0, 0.0))
	assert_eq(brain.state_name(), "breath")
	assert_true(brain.point_in_breath_cone(brain.breath_origin()
			+ brain.breath_direction() * 15.0))


func test_a_point_behind_the_dragon_is_not_in_the_cone() -> void:
	var brain := _telegraphed(Vector3(20.0, 0.0, 0.0))
	assert_false(brain.point_in_breath_cone(brain.breath_origin()
			- brain.breath_direction() * 10.0))


func test_a_point_past_the_range_is_not_in_the_cone() -> void:
	var brain := _telegraphed(Vector3(20.0, 0.0, 0.0))
	var just_short: Vector3 = brain.breath_origin() \
			+ brain.breath_direction() * (Brain.BREATH_RANGE_M - 1.0)
	var just_far: Vector3 = brain.breath_origin() \
			+ brain.breath_direction() * (Brain.BREATH_RANGE_M + 5.0)
	assert_true(brain.point_in_breath_cone(just_short))
	assert_false(brain.point_in_breath_cone(just_far))


func test_a_point_outside_the_half_angle_is_not_in_the_cone() -> void:
	var brain := _telegraphed(Vector3(20.0, 0.0, 0.0))
	# The aim direction is +X; well past the half-angle is +Z at the same range.
	var to_the_side: Vector3 = brain.breath_origin() + Vector3(0.0, 0.0, 15.0)
	assert_false(brain.point_in_breath_cone(to_the_side))


func test_a_point_just_inside_the_half_angle_is_in_the_cone() -> void:
	var brain := _telegraphed(Vector3(20.0, 0.0, 0.0))
	var half_angle := deg_to_rad(Brain.BREATH_HALF_ANGLE_DEGREES)
	var range_m := 15.0
	var just_inside: Vector3 = brain.breath_origin() + Vector3(
			cos(half_angle * 0.9) * range_m, 0.0, sin(half_angle * 0.9) * range_m)
	assert_true(brain.point_in_breath_cone(just_inside))


func test_the_cone_works_vertically_too_since_the_player_may_be_flying() -> void:
	var brain := _telegraphed(Vector3(20.0, 0.0, 0.0))
	var above: Vector3 = brain.breath_origin() + brain.breath_direction() * 15.0 + Vector3.UP * 3.0
	var far_above: Vector3 = brain.breath_origin() \
			+ brain.breath_direction() * 15.0 + Vector3.UP * 30.0
	assert_true(brain.point_in_breath_cone(above),
			"a small vertical offset at this range should still be inside the cone")
	assert_false(brain.point_in_breath_cone(far_above),
			"but climbing well clear of it should escape the cone, same as sidestepping")


func test_hitting_the_player_tracks_their_live_position_during_the_breath() -> void:
	var brain := _telegraphed(Vector3(20.0, 0.0, 0.0))
	assert_true(brain.is_hitting_player(),
			"the player has not moved since the telegraph locked the aim")

	# Ticking again with the player now well outside the fixed cone: this is the
	# acceptance criterion itself, the cone can be avoided by moving out of it, even
	# after it has already started firing.
	brain.tick(TICK, _at(Vector3.ZERO, Vector3(0.0, 0.0, 25.0)))
	assert_eq(brain.state_name(), "breath", "dodging should not cut the breath short")
	assert_false(brain.is_hitting_player(),
			"stepping clear of the fixed cone should stop it landing")


func test_the_cone_direction_is_fixed_once_the_breath_begins() -> void:
	var brain := _telegraphed(Vector3(20.0, 0.0, 0.0))
	var locked: Vector3 = brain.breath_direction()
	# The player moves; the brain is still fed their live position, as the body would.
	brain.tick(TICK, _at(Vector3.ZERO, Vector3(0.0, 0.0, 25.0)))
	assert_eq(brain.breath_direction(), locked,
			"the cone must not keep re-aiming at a moving target mid-breath")


func test_telegraph_lasts_about_its_declared_duration() -> void:
	var brain := _brain()
	var offset := Vector3(20.0, 0.0, 0.0)
	brain.tick(TICK, _at(Vector3.ZERO, offset))
	assert_eq(brain.state_name(), "telegraph")

	# Must not commit before roughly its declared windup has actually been counted down.
	var decremented := 0.0
	while decremented + TICK < Brain.TELEGRAPH_SECONDS:
		brain.tick(TICK, _at(Vector3.ZERO, offset))
		decremented += TICK
		assert_eq(brain.state_name(), "telegraph",
				"should still be telegraphing after %.2fs of its %.2fs windup"
						% [decremented, Brain.TELEGRAPH_SECONDS])

	# A few more ticks are enough margin to be certain it has committed by now.
	for _i in 3:
		brain.tick(TICK, _at(Vector3.ZERO, offset))
	assert_eq(brain.state_name(), "breath")


func test_a_lost_player_cancels_the_telegraph_rather_than_firing_blind() -> void:
	var brain := _brain()
	var offset := Vector3(20.0, 0.0, 0.0)
	brain.tick(TICK, _at(Vector3.ZERO, offset))
	assert_eq(brain.state_name(), "telegraph")

	brain.tick(TICK, _at(Vector3.ZERO, Vector3.ZERO, false))
	assert_eq(brain.state_name(), "patrol")


func test_the_breath_cannot_be_chained_within_its_cooldown() -> void:
	var brain := _telegraphed(Vector3(20.0, 0.0, 0.0))
	_run_out_the_breath(brain, Vector3(20.0, 0.0, 0.0))
	assert_eq(brain.state_name(), "patrol", "the breath should have ended by now")

	# Still within range, still present — everything a fresh trigger would need, except
	# the cooldown has not run out.
	brain.tick(TICK, _at(Vector3.ZERO, Vector3(20.0, 0.0, 0.0)))
	assert_ne(brain.state_name(), "telegraph",
			"a second breath should not start immediately after the first")


func test_the_breath_can_fire_again_once_its_cooldown_elapses() -> void:
	var brain := _telegraphed(Vector3(20.0, 0.0, 0.0))
	var offset := Vector3(20.0, 0.0, 0.0)
	_run_out_the_breath(brain, offset)
	assert_eq(brain.state_name(), "patrol")

	var through_cooldown := int(Brain.BREATH_COOLDOWN_SECONDS / TICK) + 2
	for _i in through_cooldown:
		brain.tick(TICK, _at(Vector3.ZERO, offset))
	assert_eq(brain.state_name(), "telegraph",
			"once the cooldown has elapsed, being in range should trigger another")


## Ticks a breathing brain forward until the breath ends, stopping on the exact tick it
## does — one tick further and the cascade would already have re-evaluated into `dive`
## against this same still-present, still-in-range threat, which is a different thing
## than the breath itself ending.
func _run_out_the_breath(brain: RefCounted, offset: Vector3) -> void:
	var steps := int(Brain.BREATH_DURATION_SECONDS / TICK) + 2
	for _i in steps:
		brain.tick(TICK, _at(Vector3.ZERO, offset))
		if brain.state_name() != "breath":
			return
