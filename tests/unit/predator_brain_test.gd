extends "res://tests/test_case.gd"
## Tests predator behaviour: the full hunt, and knowing when to give up.

const Brain := preload("res://scripts/creatures/predator_brain.gd")
const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const Biome := preload("res://scripts/world/biome.gd")

const DETECTION := 25.0


func _brain(seed_value: int = 3) -> RefCounted:
	return Brain.new(seed_value)


## Context with the player at a distance along +X, and the predator unharmed.
func _at(distance: float, health := 1.0, crouching := false,
		sprinting := false) -> Dictionary:
	return {
		"position": Vector3.ZERO,
		"anchor": Vector3.ZERO,
		"threat_position": Vector3(distance, 0.0, 0.0),
		"threat_present": distance < 100000.0,
		"threat_crouching": crouching,
		"threat_sprinting": sprinting,
		"detection_m": DETECTION,
		"health_fraction": health,
		"made_progress": true,
	}


func _alone() -> Dictionary:
	var context := _at(999999.0)
	context["threat_present"] = false
	return context


func test_an_undisturbed_predator_patrols() -> void:
	var brain := _brain()
	for _i in 40:
		brain.tick(0.25, _alone())
	assert_eq(brain.state_name(), "patrol")


func test_a_distant_but_visible_player_is_stalked() -> void:
	var brain := _brain()
	brain.tick(0.2, _at(DETECTION * 0.8))
	assert_eq(brain.state_name(), "stalk")


func test_stalking_approaches_the_player_slowly() -> void:
	# The slow approach is the warning. A predator that sprinted from first sight would
	# give the player no chance to notice they are being hunted.
	var brain := _brain()
	brain.tick(0.2, _at(DETECTION * 0.8))
	assert_almost_eq(brain.desired_direction().x, 1.0, 0.001,
			"should move towards the player at +X")
	assert_true(brain.speed_scale() < 1.0, "stalking should be slower than patrol")
	assert_false(brain.is_running())


func test_closing_within_charge_range_starts_a_run() -> void:
	var brain := _brain()
	brain.tick(0.2, _at(Brain.CHARGE_RANGE_M * 0.7))
	assert_eq(brain.state_name(), "charge")
	assert_true(brain.is_running())
	assert_almost_eq(brain.speed_scale(), 1.0, 0.001)


func test_reaching_the_player_starts_attacking() -> void:
	var brain := _brain()
	brain.tick(0.2, _at(Brain.ATTACK_RANGE_M * 0.6))
	assert_eq(brain.state_name(), "attack")
	assert_true(brain.is_attacking())
	assert_almost_eq(brain.desired_direction().length(), 0.0, 0.001,
			"it should stand and strike rather than push through the player")


func test_the_full_hunt_runs_patrol_stalk_charge_attack() -> void:
	# Each stage in order, as the player walks in.
	var brain := _brain()
	brain.tick(0.2, _alone())
	assert_eq(brain.state_name(), "patrol")
	brain.tick(0.2, _at(DETECTION * 0.9))
	assert_eq(brain.state_name(), "stalk")
	brain.tick(0.2, _at(Brain.CHARGE_RANGE_M * 0.8))
	assert_eq(brain.state_name(), "charge")
	brain.tick(0.2, _at(Brain.ATTACK_RANGE_M * 0.5))
	assert_eq(brain.state_name(), "attack")


func test_a_player_who_escapes_is_no_longer_hunted() -> void:
	var brain := _brain()
	brain.tick(0.2, _at(Brain.ATTACK_RANGE_M * 0.5))
	assert_true(brain.is_attacking())
	brain.tick(0.2, _at(DETECTION * 4.0))
	assert_eq(brain.state_name(), "patrol")


func test_a_wounded_predator_breaks_off() -> void:
	# A fight the player can win without killing, which is what makes the difficulty
	# curve survivable.
	var brain := _brain()
	brain.tick(0.2, _at(Brain.ATTACK_RANGE_M * 0.5))
	assert_true(brain.is_attacking())
	brain.tick(0.2, _at(Brain.ATTACK_RANGE_M * 0.5,
			Brain.RETREAT_HEALTH_FRACTION - 0.05))
	assert_true(brain.is_retreating())
	assert_almost_eq(brain.desired_direction().x, -1.0, 0.001,
			"it should run away from the player, not towards")


func test_a_retreating_predator_stops_once_it_is_clear() -> void:
	var brain := _brain()
	brain.tick(0.2, _at(2.0, 0.1))
	assert_true(brain.is_retreating())
	brain.tick(0.2, _at(Brain.RETREAT_DISTANCE_M + 5.0, 0.1))
	assert_eq(brain.state_name(), "patrol")


func test_a_beaten_predator_does_not_immediately_re_engage() -> void:
	# Without the recovery window a wounded animal would turn around the moment it was
	# far enough away, and the fight would never actually end.
	var brain := _brain()
	brain.tick(0.2, _at(2.0, 0.1))
	brain.tick(0.2, _at(Brain.RETREAT_DISTANCE_M + 5.0, 0.1))
	assert_eq(brain.state_name(), "patrol")
	# Player walks straight back into range. Health is restored for this check so the
	# only thing that could hold the predator back is the recovery window — at 0.1 it
	# would simply retreat again, which would prove nothing about recovery.
	brain.tick(0.2, _at(Brain.ATTACK_RANGE_M * 0.5, 1.0))
	assert_eq(brain.state_name(), "patrol",
			"it should stay wary rather than pounce again immediately")


func test_it_hunts_again_once_recovered() -> void:
	var brain := _brain()
	brain.tick(0.2, _at(2.0, 0.1))
	brain.tick(0.2, _at(Brain.RETREAT_DISTANCE_M + 5.0, 0.1))
	# Wait out the recovery on full health.
	for _i in int(Brain.RECOVER_SECONDS / 0.2) + 4:
		brain.tick(0.2, _alone())
	# Beyond charge range, so a renewed hunt shows up as a stalk rather than a charge.
	brain.tick(0.2, _at(DETECTION * 0.9))
	assert_eq(brain.state_name(), "stalk", "it should be willing to hunt again")


func test_crouching_hides_you_and_sprinting_advertises_you() -> void:
	var base := Brain.detection_range(DETECTION, false, false)
	assert_true(Brain.detection_range(DETECTION, true, false) < base,
			"crouching should shorten detection")
	assert_true(Brain.detection_range(DETECTION, false, true) > base,
			"sprinting should lengthen it")

	# At a distance that is safe crouched and not safe sprinting.
	var distance := DETECTION * 1.3
	var quiet := _brain()
	quiet.tick(0.2, _at(distance, 1.0, true, false))
	assert_eq(quiet.state_name(), "patrol", "crouched, it should not notice")

	var loud := _brain()
	loud.tick(0.2, _at(distance, 1.0, false, true))
	assert_ne(loud.state_name(), "patrol", "sprinting, it should")


func test_patrol_stays_near_its_territory() -> void:
	# A predator that wandered the whole island would be neither findable nor avoidable.
	var brain := _brain()
	var far_from_home := _alone()
	far_from_home["position"] = Vector3(Brain.TERRITORY_RADIUS_M + 20.0, 0.0, 0.0)
	far_from_home["anchor"] = Vector3.ZERO
	brain.tick(0.3, far_from_home)
	assert_true(brain.desired_direction().x < 0.0,
			"it should head back towards its territory")


func test_state_never_flickers_on_a_range_boundary() -> void:
	var brain := _brain()
	brain.tick(0.2, _at(DETECTION * 0.95))
	var flips := 0
	var previous: int = brain.state()
	for _i in 60:
		brain.tick(0.05, _at(DETECTION * 1.05))
		if brain.state() != previous:
			flips += 1
			previous = brain.state()
	assert_eq(flips, 0, "hovering at the edge should not oscillate")


func test_every_state_is_named() -> void:
	for state in [Brain.State.PATROL, Brain.State.STALK, Brain.State.CHARGE,
			Brain.State.ATTACK, Brain.State.RETREAT]:
		var brain := _brain()
		brain._enter(state)
		assert_ne(brain.state_name(), "unknown")


func test_the_leopard_is_a_predator_that_lives_in_forest() -> void:
	var leopard := CreatureKind.Kind.LEOPARD
	assert_eq(CreatureKind.name_of(leopard), "leopard")
	assert_true(CreatureKind.is_predator(leopard))
	assert_true(CreatureKind.lives_in(leopard, Biome.Kind.FOREST))
	assert_false(CreatureKind.lives_in(leopard, Biome.Kind.OCEAN))


func test_a_leopard_is_a_real_step_up_from_a_deer() -> void:
	var leopard := CreatureKind.Kind.LEOPARD
	var deer := CreatureKind.Kind.DEER
	assert_true(CreatureKind.health(leopard) > CreatureKind.health(deer),
			"it should take longer to kill")
	assert_true(CreatureKind.run_speed(leopard) > CreatureKind.run_speed(deer),
			"and it should be able to catch you")
	assert_true(CreatureKind.attack_damage(leopard) > 0.0)
	assert_almost_eq(CreatureKind.attack_damage(deer), 0.0, 0.001,
			"prey do not hit back")


func test_a_leopard_cannot_kill_a_healthy_player_instantly() -> void:
	# It should be dangerous, not a one-shot: the player needs time to react or run.
	const Stats := preload("res://scripts/player/survival_stats.gd")
	var stats: RefCounted = Stats.new()
	var hits: float = stats.rate("max_health") \
			/ CreatureKind.attack_damage(CreatureKind.Kind.LEOPARD)
	assert_true(hits >= 4.0,
			"a leopard should need several hits, needs %.1f" % hits)


## The same context, with a deer at `distance` along +Z. The player and the animal are on
## perpendicular axes so which one is being chased is visible in the direction alone.
func _with_quarry(context: Dictionary, distance: float) -> Dictionary:
	var with := context.duplicate()
	with["quarry_position"] = Vector3(0.0, 0.0, distance)
	with["quarry_present"] = true
	return with


func test_a_predator_hunts_prey_with_no_player_anywhere() -> void:
	# The island has to be alive when nobody is watching the player-facing half of it.
	# Stalking range for an animal starts beyond the range a person is noticed at, so
	# the distance here is measured against the scent range rather than detection.
	var brain := _brain()
	brain.tick(0.2, _with_quarry(_alone(), Brain.quarry_range(DETECTION) * 0.8))
	assert_eq(brain.state_name(), "stalk")
	assert_eq(brain.target(), Brain.Target.QUARRY)
	assert_almost_eq(brain.desired_direction().z, 1.0, 0.001,
			"it should be closing on the deer at +Z")


func test_prey_is_hunted_through_the_same_five_stages() -> void:
	# Not a second code path: the stages the player experiences are the stages a deer
	# experiences, which is what makes watching a hunt a warning.
	var brain := _brain()
	brain.tick(0.2, _with_quarry(_alone(), Brain.quarry_range(DETECTION) * 0.8))
	assert_eq(brain.state_name(), "stalk")
	brain.tick(0.2, _with_quarry(_alone(), DETECTION * 0.8))
	assert_eq(brain.state_name(), "charge")
	assert_true(brain.is_running(), "a charge at a deer is still a run")
	brain.tick(0.2, _with_quarry(_alone(), Brain.ATTACK_RANGE_M * 0.6))
	assert_eq(brain.state_name(), "attack")
	assert_true(brain.is_attacking())
	assert_true(brain.is_hunting_quarry(),
			"the body has to know the strike lands on the deer, not the player")


func test_the_closer_of_player_and_prey_is_chosen() -> void:
	# Both halves, because a predator that always preferred the player would make the
	# island a set of threats aimed at one person, and one that always preferred prey
	# could be walked up to.
	var hunting_deer := _brain()
	hunting_deer.tick(0.2, _with_quarry(_at(DETECTION * 0.9), DETECTION * 0.3))
	assert_eq(hunting_deer.target(), Brain.Target.QUARRY,
			"the deer is nearer, so the deer is the one being hunted")

	var hunting_player := _brain()
	hunting_player.tick(0.2, _with_quarry(_at(DETECTION * 0.3), DETECTION * 0.9))
	assert_eq(hunting_player.target(), Brain.Target.PLAYER)
	assert_almost_eq(hunting_player.desired_direction().x, 1.0, 0.001,
			"and it moves at the player, not the deer")


func test_an_unnoticed_deer_is_not_hunted() -> void:
	var brain := _brain()
	brain.tick(0.2, _with_quarry(_alone(), DETECTION * 3.0))
	assert_eq(brain.state_name(), "patrol")
	assert_eq(brain.target(), Brain.Target.NONE)


func test_a_crouching_player_can_be_passed_over_for_a_deer() -> void:
	# Crouching shortens the range at which the player is noticed, so a crouched player
	# nearer than the deer can still be the one that goes unhunted. This is the mechanic
	# paying off against a target that did not exist when it was written.
	var context := _with_quarry(_at(DETECTION * 0.5, 1.0, true), DETECTION * 0.7)
	var brain := _brain()
	brain.tick(0.2, context)
	assert_eq(brain.target(), Brain.Target.QUARRY,
			"the nearer crouching player should go unnoticed")

	# The same distances standing up, to show the crouch is what did it.
	var standing := _brain()
	standing.tick(0.2, _with_quarry(_at(DETECTION * 0.5), DETECTION * 0.7))
	assert_eq(standing.target(), Brain.Target.PLAYER)


func test_a_kill_ends_the_hunt() -> void:
	var brain := _brain()
	brain.tick(0.2, _with_quarry(_alone(), Brain.ATTACK_RANGE_M * 0.6))
	assert_eq(brain.state_name(), "attack")

	brain.note_kill()
	assert_eq(brain.state_name(), "patrol", "it should break off, not keep swinging")
	assert_eq(brain.target(), Brain.Target.NONE)


func test_a_fed_predator_leaves_the_next_deer_alone_for_a_while() -> void:
	# Without this a leopard walks from carcass to carcass and the island empties.
	var brain := _brain()
	brain.tick(0.2, _with_quarry(_alone(), Brain.ATTACK_RANGE_M * 0.6))
	brain.note_kill()

	for _i in 20:
		brain.tick(0.2, _with_quarry(_alone(), DETECTION * 0.5))
	assert_eq(brain.target(), Brain.Target.NONE,
			"still feeding, so the next deer is not hunted")

	# Both halves of the gate: it must start hunting again once the window passes.
	for _i in int(Brain.FEED_SECONDS / 0.2) + 2:
		brain.tick(0.2, _with_quarry(_alone(), DETECTION * 0.5))
	assert_eq(brain.target(), Brain.Target.QUARRY,
			"and it should hunt again afterwards, not retire")


func test_feeding_does_not_make_a_predator_safe_to_approach() -> void:
	# The feed timer suppresses hunting animals, not defending itself. Walking up to a
	# leopard on a carcass should not be free.
	var brain := _brain()
	brain.tick(0.2, _with_quarry(_alone(), Brain.ATTACK_RANGE_M * 0.6))
	brain.note_kill()
	brain.tick(0.2, _with_quarry(_at(DETECTION * 0.4), DETECTION * 0.2))
	assert_eq(brain.target(), Brain.Target.PLAYER)


func test_a_hunted_deer_is_not_swapped_for_an_equally_close_one() -> void:
	# Two candidates at nearly the same distance would otherwise change the target every
	# decision, and the animal would run at neither.
	var brain := _brain()
	var swaps := 0
	var previous := Brain.Target.NONE
	for i in 40:
		# The player and the deer trade places by centimetres, either side of equal.
		var jitter := 0.02 * (1.0 if i % 2 == 0 else -1.0)
		var context := _with_quarry(_at(DETECTION * 0.5 + jitter),
				DETECTION * 0.5 - jitter)
		brain.tick(0.2, context)
		if previous != Brain.Target.NONE and brain.target() != previous:
			swaps += 1
		previous = brain.target()
	assert_true(swaps <= 1, "target flipped %d times over a centimetre" % swaps)


func test_a_wounded_predator_breaks_off_a_hunt_too() -> void:
	var brain := _brain()
	brain.tick(0.2, _with_quarry(_alone(), Brain.ATTACK_RANGE_M * 0.6))
	assert_eq(brain.state_name(), "attack")
	var hurt := _with_quarry(_alone(), Brain.ATTACK_RANGE_M * 0.6)
	hurt["health_fraction"] = 0.1
	brain.tick(0.2, hurt)
	assert_eq(brain.state_name(), "retreat")
	assert_almost_eq(brain.desired_direction().z, -1.0, 0.001,
			"it should run from the animal it was fighting, at -Z")


func test_an_animal_is_rushed_from_further_out_than_a_person() -> void:
	# Both halves of the asymmetry, at one distance. A predator stalks a player at 20m
	# and is still deciding; at the same 20m it is already running at a deer, because a
	# stalk covers 1.1 m/s and a deer that breaks covers 8.4.
	var stalking_player := _brain()
	stalking_player.tick(0.2, _at(DETECTION * 0.8))
	assert_eq(stalking_player.state_name(), "stalk")

	var charging_deer := _brain()
	charging_deer.tick(0.2, _with_quarry(_alone(), DETECTION * 0.8))
	assert_eq(charging_deer.state_name(), "charge")


func test_prey_is_tracked_further_than_a_player_is_noticed() -> void:
	assert_true(Brain.quarry_range(DETECTION)
					> Brain.detection_range(DETECTION, false, true),
			"even a sprinting player should not be noticed further than prey is tracked")
	var brain := _brain()
	# A deer at a distance where a standing player would go entirely unnoticed.
	brain.tick(0.2, _with_quarry(_alone(), DETECTION * 1.8))
	assert_eq(brain.target(), Brain.Target.QUARRY)

	var ignoring_player := _brain()
	ignoring_player.tick(0.2, _at(DETECTION * 1.8))
	assert_eq(ignoring_player.target(), Brain.Target.NONE)
