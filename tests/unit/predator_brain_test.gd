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
