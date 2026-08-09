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


## Context with a predator at `distance` along +Z, and nothing else about.
func _with_predator(context: Dictionary, distance: float) -> Dictionary:
	var with := context.duplicate()
	with["predator_position"] = Vector3(0.0, 0.0, distance)
	with["predator_present"] = true
	return with


func test_a_deer_runs_from_a_leopard_with_no_player_involved() -> void:
	# Prey that only watched the player would graze while a predator closed on it, and
	# the hunt would be something the player never sees happen.
	var brain := _brain()
	brain.tick(0.2, _with_predator(_calm(), DETECTION * 0.5))
	assert_eq(brain.state_name(), "flee")
	assert_almost_eq(brain.desired_direction().z, -1.0, 0.001,
			"it should run away from the leopard at +Z")


func test_a_distant_leopard_is_not_noticed() -> void:
	var brain := _brain()
	for _i in 10:
		brain.tick(0.2, _with_predator(_calm(), DETECTION * 2.0))
	assert_ne(brain.state_name(), "flee")


func test_the_nearer_of_player_and_predator_is_what_it_runs_from() -> void:
	# Running from the player straight into a leopard would be worse than not fleeing.
	var from_leopard := _brain()
	from_leopard.tick(0.2, _with_predator(_threatened(DETECTION * 0.9), DETECTION * 0.3))
	assert_almost_eq(from_leopard.desired_direction().z, -1.0, 0.001,
			"the leopard is nearer, so run from the leopard")

	var from_player := _brain()
	from_player.tick(0.2, _with_predator(_threatened(DETECTION * 0.3), DETECTION * 0.9))
	assert_almost_eq(from_player.desired_direction().x, -1.0, 0.001,
			"and from the player when the player is nearer")


func test_a_deer_keeps_running_until_well_clear_of_a_leopard() -> void:
	# The same release margin the player gets. Without it a deer that had just escaped
	# detection would stop dead with the leopard a metre outside its notice.
	var brain := _brain()
	brain.tick(0.2, _with_predator(_calm(), DETECTION * 0.5))
	assert_eq(brain.state_name(), "flee")
	for _i in 20:
		brain.tick(0.2, _with_predator(_calm(), DETECTION * 1.1))
	assert_eq(brain.state_name(), "flee",
			"just outside detection is not far enough to calm down")

	for _i in 30:
		brain.tick(0.2, _with_predator(_calm(), DETECTION * 4.0))
	assert_ne(brain.state_name(), "flee", "but it does calm down eventually")


## A brain for a species that turns and fights, seeded the same way `_brain()` is.
func _retaliating_brain(seed_value: int = 7) -> RefCounted:
	return Brain.new(seed_value, true)


## A context reporting a strike from the player, at the given distance along +X.
func _struck_by_player(distance: float) -> Dictionary:
	return {
		"position": Vector3.ZERO,
		"threat_position": Vector3(distance, 0.0, 0.0),
		"threat_present": true,
		"threat_crouching": false,
		"detection_m": 100000.0,
		"made_progress": true,
		"struck": true,
	}


func test_boar_is_defined_as_a_retaliating_prey_species() -> void:
	assert_eq(CreatureKind.name_of(CreatureKind.Kind.BOAR), "boar")
	assert_eq(CreatureKind.role(CreatureKind.Kind.BOAR), CreatureKind.Role.PREY)
	assert_true(CreatureKind.retaliates(CreatureKind.Kind.BOAR))
	assert_false(CreatureKind.retaliates(CreatureKind.Kind.DEER),
			"a deer must never turn and fight")


func test_a_non_retaliating_animal_ignores_being_struck() -> void:
	# A deer that turned to fight when hit would not be a deer any more.
	var brain := _brain()
	brain.tick(0.1, _struck_by_player(5.0))
	assert_ne(brain.state_name(), "retaliate")
	assert_true(brain.is_fleeing(), "it should just be panicked, same as any other hit")


func test_a_struck_boar_retaliates_immediately() -> void:
	# The other half of "cornered, or has been struck": a hit alone is enough, with no
	# stuck timer required at all.
	var brain := _retaliating_brain()
	brain.tick(0.1, _struck_by_player(5.0))
	assert_eq(brain.state_name(), "retaliate")
	assert_almost_eq(brain.desired_direction().x, 1.0, 0.001,
			"it should turn towards the player at +X, not flee from them")


func test_a_boar_struck_by_a_predator_does_not_retaliate() -> void:
	# Scope is the player only: a boar mauled by a leopard should run from the leopard,
	# not turn and fight an animal three times its size.
	var brain := _retaliating_brain()
	var context := _struck_by_player(5.0)
	context["struck"] = false
	context["threat_present"] = false
	context["predator_position"] = Vector3(5.0, 0.0, 0.0)
	context["predator_present"] = true
	brain.tick(0.1, context)
	assert_ne(brain.state_name(), "retaliate")
	assert_true(brain.is_fleeing())


func test_a_cornered_boar_turns_to_fight() -> void:
	# "Cornered" without ever being struck: fleeing the player and making no progress
	# for long enough is what tells the brain there is nowhere left to run.
	var brain := _retaliating_brain()
	brain.tick(0.1, _threatened(15.0))
	assert_eq(brain.state_name(), "flee")

	var blocked := _threatened(15.0)
	blocked["made_progress"] = false
	for _i in int(Brain.STUCK_SECONDS / 0.1) + 2:
		brain.tick(0.1, blocked)
	assert_eq(brain.state_name(), "retaliate",
			"a boar stuck while fleeing the player should turn and fight")


func test_a_boar_cornered_by_a_predator_does_not_retaliate() -> void:
	# The same stuck timer, but fleeing a leopard rather than the player — out of scope
	# for this behaviour, so it should keep trying to flee rather than turn on the cat.
	var brain := _retaliating_brain()
	var fleeing := _with_predator(_calm(), 15.0)
	brain.tick(0.1, fleeing)
	assert_eq(brain.state_name(), "flee")

	var blocked := _with_predator(_calm(), 15.0)
	blocked["made_progress"] = false
	for _i in int(Brain.STUCK_SECONDS / 0.1) + 2:
		brain.tick(0.1, blocked)
	assert_eq(brain.state_name(), "flee",
			"retaliation is scoped to the player, not to predators")


func test_a_non_retaliating_animal_never_gets_cornered_into_fighting() -> void:
	var brain := _brain()
	brain.tick(0.1, _threatened(15.0))
	var blocked := _threatened(15.0)
	blocked["made_progress"] = false
	for _i in int(Brain.STUCK_SECONDS / 0.1) + 2:
		brain.tick(0.1, blocked)
	assert_ne(brain.state_name(), "retaliate")
	assert_true(brain.is_fleeing(), "a deer that cannot outrun the player just keeps trying")


func test_retaliation_closes_the_distance_before_striking() -> void:
	var brain := _retaliating_brain()
	brain.tick(0.1, _struck_by_player(Brain.RETALIATE_RANGE_M * 3.0))
	assert_almost_eq(brain.desired_direction().x, 1.0, 0.001,
			"out of range, it should be closing in")
	assert_false(brain.is_attacking(), "and not yet landing anything")
	assert_true(brain.is_running(), "closing the distance is still a run")


func test_retaliation_holds_and_strikes_once_in_range() -> void:
	var brain := _retaliating_brain()
	brain.tick(0.1, _struck_by_player(Brain.RETALIATE_RANGE_M * 0.5))
	assert_almost_eq(brain.desired_direction().length(), 0.0, 0.001,
			"braced to strike, not still closing")
	assert_true(brain.is_attacking())


func test_retaliation_breaks_off_once_the_player_is_well_clear() -> void:
	var brain := _retaliating_brain()
	brain.tick(0.1, _struck_by_player(1.0))
	assert_eq(brain.state_name(), "retaliate")

	# Still within the release margin of turning to fight again — must not have calmed.
	var clear_distance := DETECTION * Brain.FLEE_RELEASE_MULTIPLIER
	brain.tick(0.1, _threatened(clear_distance * 0.8))
	assert_eq(brain.state_name(), "retaliate", "not clear yet")

	brain.tick(0.1, _threatened(clear_distance * 1.5))
	assert_eq(brain.state_name(), "flee",
			"well clear, it should break off — still rattled, not instantly calm")


func test_a_boar_calms_down_after_breaking_off_a_fight() -> void:
	# The whole promise of the ticket: a fight the player can choose to walk away from,
	# not one that never really ends.
	var brain := _retaliating_brain()
	brain.tick(0.1, _struck_by_player(1.0))
	brain.tick(0.1, _threatened(DETECTION * Brain.FLEE_RELEASE_MULTIPLIER * 1.5))
	assert_eq(brain.state_name(), "flee")

	brain.tick(Brain.FLEE_TAIL_SECONDS + 1.0, _calm())
	assert_false(brain.is_fleeing(), "and it should eventually settle, same as any flee")


func test_retaliation_ends_if_the_player_is_gone() -> void:
	var brain := _retaliating_brain()
	brain.tick(0.1, _struck_by_player(1.0))
	assert_eq(brain.state_name(), "retaliate")
	brain.tick(0.1, _calm())
	assert_ne(brain.state_name(), "retaliate",
			"nothing to fight, so it should not still be braced")


func test_being_struck_interrupts_a_boar_mid_retaliation() -> void:
	# A wounded predator disengages mid-swing; a boar being hit again should not have to
	# finish whatever it was doing first either.
	var brain := _retaliating_brain()
	brain.tick(0.1, _struck_by_player(Brain.RETALIATE_RANGE_M * 3.0))
	assert_false(brain.is_attacking())
	brain.tick(0.1, _struck_by_player(0.5))
	assert_true(brain.is_attacking(), "a second, closer strike should still register")
