extends "res://tests/test_case.gd"
## Integration tests for the boar's retaliation: a real player, real terrain, and real
## physics driving the transition a unit test cannot — whether a boar cornered against
## an actual cliff turns to fight, and whether it actually lands a hit on the player.
##
## Uses a hand-built heightmap with a cliff, the same technique
## `creature_body_test.gd` uses for slope refusal, so the corner under test is exactly
## where the test put it.

const PlayerScene := preload("res://scenes/player.tscn")
const CreatureBody := preload("res://scripts/creatures/creature_body.gd")
const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

const CELLS := 64
const CELL_SIZE := 4.0

var _world: Node3D
var _player: CharacterBody3D
var _boar: CharacterBody3D


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	_player = null
	_boar = null


## Flat land at `height`, with an optional wall of `wall_height` for x cells >= 40.
func _map(height: int, wall_height: int = -1) -> RefCounted:
	var map: RefCounted = Heightmap.new(CELLS, CELL_SIZE)
	for cz in CELLS:
		for cx in CELLS:
			var h := height
			if wall_height >= 0 and cx >= 40:
				h = wall_height
			map.set_height(cx, cz, h)
			map.set_biome(cx, cz, Biome.Kind.PLAINS)
	return map


func _at_cell(map: RefCounted, cx: int, cz: int) -> Vector3:
	var half: float = map.size_m() * 0.5
	return Vector3(
			float(cx) * CELL_SIZE - half + CELL_SIZE * 0.5,
			float(map.height_at_cell(cx, cz)),
			float(cz) * CELL_SIZE - half + CELL_SIZE * 0.5)


func _spawn(map: RefCounted, boar_at: Vector3, player_at: Vector3) -> void:
	_world = Node3D.new()
	scene_root().add_child(_world)

	# The boar settles onto the heightmap by direct lookup, bypassing physics — but the
	# player is a real CharacterBody3D and needs an actual floor or it free-falls under
	# gravity, drifting out of retaliation range over the course of the test.
	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200.0, 2.0, 200.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	_world.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, player_at.y - 1.0, 0.0)

	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	_player.global_position = player_at

	_boar = CreatureBody.new()
	_world.add_child(_boar)
	_boar.global_position = boar_at
	_boar.configure(CreatureKind.Kind.BOAR, map, _player, 5)


func test_a_boar_struck_in_melee_range_turns_and_fights() -> void:
	var map := _map(10)
	var start := _at_cell(map, 20, 20)
	_spawn(map, start, start + Vector3(1.5, 0.0, 0.0))
	await step_physics(6)

	_boar.take_damage(6.0)
	await step_physics(2)
	assert_eq(_boar.state_name(), "retaliate",
			"a boar hit at melee range should turn and fight rather than flee")
	assert_false(_boar.is_dead())


func test_a_retaliating_boar_actually_damages_the_player() -> void:
	var map := _map(10)
	var start := _at_cell(map, 20, 20)
	_spawn(map, start, start + Vector3(1.5, 0.0, 0.0))
	await step_physics(6)

	var stats: RefCounted = _player.stats()
	var before: float = stats.health()
	_boar.take_damage(6.0)

	var interval := CreatureKind.attack_interval(CreatureKind.Kind.BOAR)
	await step_physics(int(interval * 60.0) + 10)
	assert_true(stats.health() < before,
			"a boar that turned to fight should actually land a hit")


func test_a_retaliating_boar_hits_on_a_cooldown_not_every_frame() -> void:
	# The acceptance criterion in full: "on a cooldown" is a claim a single hit cannot
	# prove — it takes catching the health bar hold roughly steady between hits and
	# then drop by a full hit's worth once the interval actually elapses. Health also
	# regenerates slowly and continuously (0.45/s) whether or not anything is fighting
	# it, so thresholds below are sized against the boar's 8.0-damage hit, not against
	# an exact, unmoving number.
	var map := _map(10)
	var start := _at_cell(map, 20, 20)
	_spawn(map, start, start + Vector3(1.5, 0.0, 0.0))
	await step_physics(6)

	var stats: RefCounted = _player.stats()
	var damage := CreatureKind.attack_damage(CreatureKind.Kind.BOAR)
	_boar.take_damage(6.0)

	# The first strike lands as soon as it is in range — there is nothing to cool down
	# from yet — so let that one happen before measuring the cooldown itself.
	await step_physics(20)
	var after_first_hit: float = stats.health()
	assert_true(after_first_hit < 100.0 - damage * 0.5,
			"the first strike should already have landed")

	var interval := CreatureKind.attack_interval(CreatureKind.Kind.BOAR)
	# Well short of a full attack interval: no second hit should have landed yet, so
	# whatever moved the number since the first hit is at most regen's tiny drift.
	await step_physics(int(interval * 60.0 * 0.4))
	var still_cooling_down: float = stats.health()
	assert_true(after_first_hit - still_cooling_down < damage * 0.5,
			"a second hit should not land before the cooldown elapses")

	# Past the full interval, the next hit should have landed: down by most of another
	# full hit's worth, not just regen's tiny drift.
	await step_physics(int(interval * 60.0 * 0.8) + 6)
	assert_true(after_first_hit - stats.health() > damage * 0.5,
			"and should land once the cooldown actually elapses")


func test_a_cornered_boar_turns_to_fight() -> void:
	# The wall is 6m, far beyond the 1.05m step a boar can climb, so fleeing straight at
	# it makes no progress — which is what "cornered" means with no obstacle avoidance
	# beyond terrain height.
	var map := _map(10, 16)
	var start := _at_cell(map, 38, 20)
	# Player on the open side and beyond melee reach, so the boar's first response is
	# to flee — straight into the wall — rather than being struck directly.
	_spawn(map, start, start - Vector3(10.0, 0.0, 0.0))
	await step_physics(6)
	assert_eq(_boar.state_name(), "flee", "it should try to run first")

	await step_physics(600)
	assert_eq(_boar.state_name(), "retaliate",
			"blocked by the cliff with nowhere to run, it should turn and fight")


func test_a_boar_breaks_off_once_the_player_backs_well_away() -> void:
	var map := _map(10)
	var start := _at_cell(map, 20, 20)
	_spawn(map, start, start + Vector3(1.5, 0.0, 0.0))
	await step_physics(6)
	_boar.take_damage(6.0)
	assert_eq(_boar.state_name(), "retaliate")

	var detection := CreatureKind.detection_m(CreatureKind.Kind.BOAR)
	_player.global_position = _boar.global_position + Vector3(detection * 3.0, 0.0, 0.0)
	await step_physics(20)
	assert_ne(_boar.state_name(), "retaliate",
			"with the player well clear, it should have broken off")


func test_a_retaliating_boar_can_still_be_killed() -> void:
	# Turning to fight does not make a boar invincible — the whole point is that this
	# fight is winnable.
	var map := _map(10)
	var start := _at_cell(map, 20, 20)
	_spawn(map, start, start + Vector3(1.5, 0.0, 0.0))
	await step_physics(6)

	_boar.take_damage(6.0)
	assert_eq(_boar.state_name(), "retaliate")
	_boar.take_damage(9999.0)
	assert_true(_boar.is_dead())
