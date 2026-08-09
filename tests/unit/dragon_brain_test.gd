extends "res://tests/test_case.gd"
## The dragon's flight AI: patrol, dive, strike, land, and giving up at the edge of its
## territory.

const Brain := preload("res://scripts/creatures/dragon_brain.gd")

const ANCHOR := Vector3(200.0, 60.0, -400.0)
const DETECTION := 70.0


func _brain(seed_value: int = 7) -> RefCounted:
	return Brain.new(seed_value)


## Context with the dragon patrolling above the anchor and the player somewhere near it.
func _at(position: Vector3, player_offset: Vector3, present: bool = true) -> Dictionary:
	return {
		"position": position,
		"anchor": ANCHOR,
		"threat_position": position + player_offset,
		"threat_present": present,
		"detection_m": DETECTION,
	}


func _alone(position: Vector3) -> Dictionary:
	return _at(position, Vector3.ZERO, false)


func test_an_undisturbed_dragon_patrols() -> void:
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M
	for _i in 40:
		brain.tick(0.25, _alone(position))
	assert_eq(brain.state_name(), "patrol")


func test_patrol_circles_rather_than_holding_still() -> void:
	# The acceptance criterion itself: a patrol that always pointed the same way would be
	# a straight line, not a circle around the nest.
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M
	brain.tick(0.25, _alone(position))
	var first: Vector3 = brain.desired_direction()
	for _i in 20:
		brain.tick(0.25, _alone(position))
	var later: Vector3 = brain.desired_direction()
	assert_true(first.distance_to(later) > 0.2,
			"the heading should have turned as the circle advanced")


func test_patrol_stays_within_its_territory() -> void:
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M
	var max_distance := 0.0
	for _i in 400:
		brain.tick(0.25, _alone(position))
		position += brain.desired_direction() * 6.0 * 0.25
		max_distance = maxf(max_distance,
				Vector2(position.x - ANCHOR.x, position.z - ANCHOR.z).length())
	assert_true(max_distance <= Brain.TERRITORY_RADIUS_M + 1.0,
			"a patrol should never wander past the territory bound, reached %.1f m"
					% max_distance)


func test_a_player_within_detection_starts_a_dive() -> void:
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M
	brain.tick(0.2, _at(position, Vector3(DETECTION * 0.6, -20.0, 0.0)))
	assert_eq(brain.state_name(), "dive")
	assert_true(brain.is_running(), "a dive should use the fast gait")


func test_the_dive_steers_towards_the_player_in_three_dimensions() -> void:
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M
	brain.tick(0.2, _at(position, Vector3(40.0, -30.0, 0.0)))
	var direction: Vector3 = brain.desired_direction()
	assert_true(direction.x > 0.0, "should steer towards the player horizontally")
	assert_true(direction.y < 0.0,
			"should also steer downward, since the player is below cruise altitude")


func test_reaching_breath_range_starts_the_telegraph() -> void:
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M
	brain.tick(0.2, _at(position, Vector3(Brain.BREATH_RANGE_M * 0.6, 0.0, 0.0)))
	assert_eq(brain.state_name(), "telegraph")
	assert_true(brain.is_attacking())
	assert_true(brain.is_telegraphing())
	assert_almost_eq(brain.desired_direction().length(), 0.0, 0.001,
			"the windup holds still rather than flying through the player")


func test_the_full_encounter_runs_patrol_dive_telegraph() -> void:
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M

	brain.tick(0.25, _alone(position))
	assert_eq(brain.state_name(), "patrol")

	brain.tick(0.2, _at(position, Vector3(DETECTION * 0.5, -10.0, 0.0)))
	assert_eq(brain.state_name(), "dive")

	brain.tick(0.2, _at(position, Vector3(Brain.BREATH_RANGE_M * 0.5, 0.0, 0.0)))
	assert_eq(brain.state_name(), "telegraph")


func test_the_player_escaping_the_dive_returns_it_to_patrol() -> void:
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M
	brain.tick(0.2, _at(position, Vector3(DETECTION * 0.5, -10.0, 0.0)))
	assert_eq(brain.state_name(), "dive")

	brain.tick(0.2, _alone(position))
	assert_eq(brain.state_name(), "patrol")


func test_a_player_far_beyond_territory_is_not_pursued() -> void:
	# The other acceptance criterion: bounded territory beats even a visible player. A
	# dragon lured to the edge of its ground must turn back rather than keep closing.
	var brain := _brain()
	var far_position := ANCHOR + Vector3(Brain.TERRITORY_RADIUS_M + 40.0, 20.0, 0.0)
	brain.tick(0.2, _at(far_position, Vector3(5.0, 0.0, 0.0)))
	assert_eq(brain.state_name(), "patrol",
			"beyond its territory, the dragon should be heading home, not diving")
	var direction: Vector3 = brain.desired_direction()
	assert_true(direction.x < 0.0, "home is back towards the anchor, at -X from here")


func test_a_mid_chase_dragon_still_turns_back_at_the_boundary() -> void:
	# Bounding has to override an in-progress dive too, not only patrol's own wander.
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M
	brain.tick(0.2, _at(position, Vector3(DETECTION * 0.5, -10.0, 0.0)))
	assert_eq(brain.state_name(), "dive")

	# The player keeps retreating, dragging the chase out past the territory edge. Kept
	# outside breath range throughout, or the chase would end in a telegraph instead of
	# at the territory boundary this test is actually about.
	var chase_position := position
	for _i in 60:
		chase_position += brain.desired_direction() * 16.0 * 0.2
		brain.tick(0.2, _at(chase_position, Vector3(50.0, 0.0, 0.0)))

	var distance := Vector2(chase_position.x - ANCHOR.x,
			chase_position.z - ANCHOR.z).length()
	assert_true(distance <= Brain.TERRITORY_RADIUS_M + 20.0,
			"the chase should have been abandoned at the territory edge, reached %.1f m"
					% distance)


func test_landing_holds_still_and_eventually_takes_off_again() -> void:
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M

	# An uninterrupted patrol long enough to land.
	for _i in int(Brain.LAND_IDLE_SECONDS / 0.25) + 4:
		brain.tick(0.25, _alone(position))
	assert_eq(brain.state_name(), "landed")
	assert_true(brain.is_landed())
	assert_almost_eq(brain.desired_direction().length(), 0.0, 0.001)

	for _i in int(Brain.LAND_DURATION_SECONDS.y / 0.25) + 4:
		brain.tick(0.25, _alone(position))
	assert_eq(brain.state_name(), "patrol",
			"a landed dragon should take off again rather than staying down forever")


func test_a_landed_dragon_is_spooked_back_into_the_air() -> void:
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M
	for _i in int(Brain.LAND_IDLE_SECONDS / 0.25) + 4:
		brain.tick(0.25, _alone(position))
	assert_eq(brain.state_name(), "landed")

	brain.tick(0.2, _at(position, Vector3(10.0, 0.0, 0.0)))
	assert_ne(brain.state_name(), "landed",
			"a nearby player should interrupt a landing rather than wait it out")


func test_a_dragon_never_hunts_other_animals() -> void:
	# Only the player is worth a dragon's attention — see SPEC and the file header.
	var brain := _brain()
	assert_false(brain.is_hunting_quarry())


func test_the_telegraph_commits_to_a_breath_once_its_timer_runs_out() -> void:
	# The state-machine shape of fire breath; see dragon_breath_test.gd for the cone,
	# damage-over-time and cooldown detail this only sets up.
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M
	var offset := Vector3(Brain.BREATH_RANGE_M * 0.5, 0.0, 0.0)
	brain.tick(0.2, _at(position, offset))
	assert_eq(brain.state_name(), "telegraph")

	for _i in int(Brain.TELEGRAPH_SECONDS / 0.2) + 2:
		brain.tick(0.2, _at(position, offset))
	assert_eq(brain.state_name(), "breath")
	assert_true(brain.is_breathing())


func test_a_breath_ends_and_returns_to_patrol() -> void:
	var brain := _brain()
	var position := ANCHOR + Vector3.UP * Brain.CRUISE_ALTITUDE_M
	var offset := Vector3(Brain.BREATH_RANGE_M * 0.5, 0.0, 0.0)
	for _i in int(Brain.TELEGRAPH_SECONDS / 0.2) + 2:
		brain.tick(0.2, _at(position, offset))
	assert_eq(brain.state_name(), "breath")

	# Stops on the exact tick the breath ends — one tick further and the cascade would
	# already have re-evaluated into "dive" against this same still-present threat.
	for _i in int(Brain.BREATH_DURATION_SECONDS / 0.2) + 2:
		brain.tick(0.2, _at(position, offset))
		if brain.state_name() != "breath":
			break
	assert_eq(brain.state_name(), "patrol",
			"a finished breath should not linger, it should hand back to patrol")
