extends "res://tests/test_case.gd"
## Integration tests for fighting the dragon: damage from melee and firearms, both of
## which it shares unchanged with every other creature, and that neither is disturbed by
## the player being airborne.

const PlayerScene := preload("res://scenes/player.tscn")
const DragonBody := preload("res://scripts/creatures/dragon_body.gd")
const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")
const FlightFuel := preload("res://scripts/player/flight_fuel.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

const CELLS := 32
const CELL_SIZE := 4.0

var _world: Node3D
var _player: CharacterBody3D
var _dragon: CharacterBody3D
var _inventory: RefCounted


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	_player = null
	_dragon = null
	_inventory = null


## Used only by the dragon's own `_move` override for its ground-clearance clamp, not by
## physics — the player's actual footing is the separate `floor_body` below. Kept well
## under the fight's altitude so that clamp never engages and moves the target out from
## under a shot this test has already aimed.
func _flat_map() -> RefCounted:
	var map: RefCounted = Heightmap.new(CELLS, CELL_SIZE)
	for cz in CELLS:
		for cx in CELLS:
			map.set_height(cx, cz, 0)
			map.set_biome(cx, cz, Biome.Kind.MOUNTAINS)
	return map


func _setup(distance: float = 2.0) -> void:
	_world = Node3D.new()
	scene_root().add_child(_world)

	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(120.0, 2.0, 120.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	_world.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, 9.0, 0.0)

	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	_player.global_position = Vector3(0.0, 10.0, 0.0)
	_inventory = _player.inventory()

	_dragon = DragonBody.new()
	_world.add_child(_dragon)
	_dragon.global_position = Vector3(0.0, 10.0, -distance)
	_dragon.configure(CreatureKind.Kind.DRAGON, _flat_map(), _player, 5)

	# Aimed at the middle of a body far taller than the player's eye line, the same
	# reason every other creature test aims rather than looking level.
	var body: Dictionary = CreatureKind.body(CreatureKind.Kind.DRAGON)
	_aim_at(_dragon.global_position + Vector3(0.0, float(body.get("height", 3.0)) * 0.5,
			0.0))

	await step_physics(4)


func _aim_at(target: Vector3) -> void:
	var camera: Camera3D = _player.get_node(^"Camera3D")
	var to := target - camera.global_position
	camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


func _select(item: int) -> void:
	for slot in 5:
		if _inventory.item_in_slot(slot) == item:
			_inventory.select(slot)
			return


func test_the_dragon_has_a_far_larger_health_pool_than_the_player_can_out_hit_at_once() -> void:
	await _setup()
	assert_eq(_dragon.health(), CreatureKind.health(CreatureKind.Kind.DRAGON))
	assert_true(_dragon.health() > 400.0)


func test_melee_damages_the_dragon() -> void:
	await _setup(2.0)
	var melee: Node = _player.get_node(^"Melee")
	melee.bind(_player, _player.get_node(^"Camera3D"))
	var before: float = _dragon.health()
	assert_true(melee.swing())
	assert_true(_dragon.health() < before,
			"a swing within reach should wound even something this large")


func test_firearms_damage_the_dragon() -> void:
	await _setup(20.0)
	var firearm: Node = _player.get_node(^"Firearm")
	_inventory.add(ItemKind.Kind.PISTOL, 1)
	_inventory.add(ItemKind.Kind.PISTOL_AMMO, 6)
	_select(ItemKind.Kind.PISTOL)

	var before: float = _dragon.health()
	assert_true(firearm.fire())
	assert_true(_dragon.health() < before)


func test_the_dragon_can_be_fought_while_the_player_is_flying() -> void:
	await _setup(20.0)
	_inventory.add(ItemKind.Kind.FLYING_SUIT, 1)
	_select(ItemKind.Kind.FLYING_SUIT)
	assert_true(_player.equip_selected_flight_suit())
	_player.flight_fuel().add(FlightFuel.CAPACITY)
	_player.toggle_flight()
	assert_true(_player.is_flying())

	var firearm: Node = _player.get_node(^"Firearm")
	_inventory.add(ItemKind.Kind.PISTOL, 1)
	_inventory.add(ItemKind.Kind.PISTOL_AMMO, 6)
	_select(ItemKind.Kind.PISTOL)

	var before: float = _dragon.health()
	assert_true(firearm.fire())
	assert_true(_dragon.health() < before,
			"a shot should still land while the shooter is airborne")
	assert_true(_player.is_flying(), "firing must not itself end flight")


func test_fire_breath_costs_health_over_the_duration_of_a_live_cone() -> void:
	# Well inside breath range: `_setup`'s own settling frames are enough for the very
	# first decision to have already started a telegraph.
	await _setup(10.0)
	assert_eq(_dragon.brain().state_name(), "telegraph")

	var stats: RefCounted = _player.stats()
	# Full health is a fixed ceiling `SurvivalStats` regen cannot cross, so this stays
	# exact even though the player is passively regenerating throughout this test.
	assert_almost_eq(stats.health(), 100.0, 0.001, "the telegraph must not deal damage")

	# Still well under the telegraph's declared duration.
	await step_physics(20)
	assert_eq(_dragon.brain().state_name(), "telegraph")
	assert_almost_eq(stats.health(), 100.0, 0.001,
			"no damage should land before the cone actually fires")

	# Comfortably past both the telegraph and into a live breath.
	await step_physics(90)
	assert_eq(_dragon.brain().state_name(), "breath",
			"should have committed to breathing by now")
	assert_true(stats.health() < 100.0,
			"standing in a live cone should cost health over its duration")


func test_stepping_out_of_the_cone_mid_breath_stops_the_damage() -> void:
	await _setup(10.0)
	await step_physics(91)
	assert_eq(_dragon.brain().state_name(), "breath")

	# The cone is fixed at this point, aimed at roughly (0,10,0) from the dragon — well
	# clear of it, not just further along the same line.
	_player.global_position = Vector3(60.0, 10.0, 0.0)
	# One decision interval's worth of frames, so the brain has actually re-evaluated
	# the dodge before the health snapshot below is taken.
	await step_physics(15)

	var stats: RefCounted = _player.stats()
	var health_after_dodging: float = stats.health()
	await step_physics(90)
	# Not exact equality: `SurvivalStats` passively regenerates a well-fed player, so a
	# successful dodge should see health hold steady or climb, never fall further.
	assert_true(stats.health() >= health_after_dodging - 0.001,
			"stepping clear of the fixed cone should stop it costing health")
