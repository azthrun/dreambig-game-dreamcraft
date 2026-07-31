extends "res://tests/test_case.gd"
## Tests prey behaviour: grazing, wandering, fleeing, and stuck recovery.
##
## The whole feature is behavioural, so this is where it is actually verified. Minutes of
## animal behaviour are simulated by injecting deltas, with no scene and no animal.

const Brain := preload("res://scripts/creatures/prey_brain.gd")
const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")

const DETECTION := 20.0


func _brain(seed_value: int = 7) -> RefCounted:
	return Brain.new(seed_value)


## Context with no threat anywhere.
func _calm(position: Vector3 = Vector3.ZERO) -> Dictionary:
	return {
		"position": position,
		"threat_present": false,
		"detection_m": DETECTION,
		"made_progress": true,
	}


## Context with the player at a given distance along +X.
func _threatened(distance: float, crouching: bool = false) -> Dictionary:
	return {
		"position": Vector3.ZERO,
		"threat_position": Vector3(distance, 0.0, 0.0),
		"threat_present": true,
		"threat_crouching": crouching,
		"detection_m": DETECTION,
		"made_progress": true,
	}


func test_an_undisturbed_animal_grazes_and_wanders() -> void:
	var brain := _brain()
	var seen := {}
	for _i in 400:
		brain.tick(0.25, _calm())
		seen[brain.state()] = true
	assert_true(seen.has(Brain.State.GRAZE), "should graze")
	assert_true(seen.has(Brain.State.WANDER), "should wander")
	assert_false(seen.has(Brain.State.FLEE), "nothing to flee from")


func test_grazing_stands_still_and_wandering_moves() -> void:
	var brain := _brain()
	for _i in 400:
		brain.tick(0.25, _calm())
		if brain.state() == Brain.State.GRAZE:
			assert_almost_eq(brain.desired_direction().length(), 0.0, 0.001)
		elif brain.state() == Brain.State.WANDER:
			assert_almost_eq(brain.desired_direction().length(), 1.0, 0.001)


func test_a_nearby_player_causes_flight() -> void:
	var brain := _brain()
	brain.tick(0.1, _threatened(DETECTION * 0.5))
	assert_eq(brain.state(), Brain.State.FLEE)
	assert_true(brain.is_fleeing())


func test_a_distant_player_is_ignored() -> void:
	var brain := _brain()
	brain.tick(0.1, _threatened(DETECTION * 3.0))
	assert_false(brain.is_fleeing())


func test_flight_is_directly_away_from_the_player() -> void:
	var brain := _brain()
	brain.tick(0.1, _threatened(5.0))
	# Player is at +X, so the animal should run towards -X.
	assert_almost_eq(brain.desired_direction().x, -1.0, 0.001)
	assert_almost_eq(brain.desired_direction().y, 0.0, 0.001,
			"flight should stay horizontal, not aim into the sky")


func test_crouching_lets_the_player_get_much_closer() -> void:
	# The entire mechanical payoff of crouch.
	var standing := Brain.detection_range(DETECTION, false)
	var crouched := Brain.detection_range(DETECTION, true)
	assert_true(crouched < standing * 0.6,
			"crouching should roughly halve detection, got %.1f vs %.1f"
					% [crouched, standing])

	var brain := _brain()
	var distance := DETECTION * 0.7
	brain.tick(0.1, _threatened(distance, true))
	assert_false(brain.is_fleeing(),
			"a crouched player at %.0fm should go unnoticed" % distance)

	var upright := _brain()
	upright.tick(0.1, _threatened(distance, false))
	assert_true(upright.is_fleeing(),
			"the same distance standing up should be noticed")


func test_an_animal_keeps_running_briefly_after_the_threat_leaves() -> void:
	# Stopping dead the instant the player steps out of range looks mechanical.
	var brain := _brain()
	brain.tick(0.1, _threatened(5.0))
	assert_true(brain.is_fleeing())
	brain.tick(0.5, _calm())
	assert_true(brain.is_fleeing(), "should still be running moments later")


func test_an_animal_calms_down_once_well_clear() -> void:
	var brain := _brain()
	brain.tick(0.1, _threatened(5.0))
	brain.tick(Brain.FLEE_TAIL_SECONDS + 1.0, _calm())
	assert_false(brain.is_fleeing())


func test_flight_does_not_flicker_at_the_detection_boundary() -> void:
	# Without release hysteresis an animal sitting exactly at the edge would switch
	# between fleeing and grazing every single frame.
	var brain := _brain()
	brain.tick(0.1, _threatened(DETECTION * 0.99))
	assert_true(brain.is_fleeing())

	var flips := 0
	var was_fleeing := true
	for _i in 60:
		# Hovering just outside detection but inside the release margin.
		brain.tick(0.05, _threatened(DETECTION * 1.05))
		if brain.is_fleeing() != was_fleeing:
			flips += 1
			was_fleeing = brain.is_fleeing()
	assert_eq(flips, 0, "state should not oscillate on the boundary")


func test_being_stuck_re_rolls_the_direction() -> void:
	# Wedged against a rock, an animal must try somewhere else rather than press on.
	var brain := _brain()
	# Get it wandering.
	for _i in 200:
		brain.tick(0.25, _calm())
		if brain.state() == Brain.State.WANDER:
			break
	assert_eq(brain.state(), Brain.State.WANDER)

	var before: Vector3 = brain.desired_direction()
	var blocked := _calm()
	blocked["made_progress"] = false
	for _i in int(Brain.STUCK_SECONDS / 0.1) + 2:
		brain.tick(0.1, blocked)
	assert_true(brain.desired_direction().distance_to(before) > 0.01,
			"a stuck animal should choose a new direction")


func test_making_progress_never_triggers_stuck_recovery() -> void:
	var brain := _brain()
	for _i in 200:
		brain.tick(0.25, _calm())
		if brain.state() == Brain.State.WANDER:
			break
	var before: Vector3 = brain.desired_direction()
	for _i in 5:
		brain.tick(0.1, _calm())
	assert_almost_eq(brain.desired_direction().distance_to(before), 0.0, 0.001,
			"an animal moving freely should hold its course")


func test_standing_on_top_of_the_animal_still_produces_an_escape() -> void:
	# Degenerate case: a zero-length away vector must not leave it frozen.
	var brain := _brain()
	brain.tick(0.1, _threatened(0.0))
	assert_true(brain.is_fleeing())
	assert_almost_eq(brain.desired_direction().length(), 1.0, 0.001)


func test_every_state_is_named() -> void:
	var brain := _brain()
	for _i in 400:
		brain.tick(0.25, _calm())
		assert_ne(brain.state_name(), "unknown")


func test_deer_are_defined_and_live_where_they_should() -> void:
	const Biome := preload("res://scripts/world/biome.gd")
	assert_eq(CreatureKind.name_of(CreatureKind.Kind.DEER), "deer")
	assert_eq(CreatureKind.role(CreatureKind.Kind.DEER), CreatureKind.Role.PREY)
	assert_true(CreatureKind.lives_in(CreatureKind.Kind.DEER, Biome.Kind.PLAINS))
	assert_true(CreatureKind.lives_in(CreatureKind.Kind.DEER, Biome.Kind.FOREST))
	assert_false(CreatureKind.lives_in(CreatureKind.Kind.DEER, Biome.Kind.OCEAN),
			"deer should not spawn in the sea")
	assert_false(CreatureKind.lives_in(CreatureKind.Kind.DEER,
			Biome.Kind.MOUNTAINS))


func test_running_is_faster_than_walking_and_drops_are_declared() -> void:
	const ItemKind := preload("res://scripts/items/item_kind.gd")
	var deer := CreatureKind.Kind.DEER
	assert_true(CreatureKind.run_speed(deer) > CreatureKind.walk_speed(deer),
			"fleeing must outpace grazing or flight is pointless")
	var drops := CreatureKind.drops(deer)
	assert_true(drops.has(ItemKind.Kind.RAW_MEAT), "deer should yield meat")
	assert_true(drops.has(ItemKind.Kind.HIDE), "deer should yield hide")
