extends "res://tests/test_case.gd"
## Integration tests for the pistol: spending rounds, refusing when empty, hitting things
## at a distance, and showing up in the player's hands.
##
## A scene rather than a pure test because a shot is a raycast against real colliders —
## the question "does the round reach a deer thirty metres away" cannot be asked of a
## dictionary.

const PlayerScene := preload("res://scenes/player.tscn")
const CreatureBody := preload("res://scripts/creatures/creature_body.gd")
const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

const CELLS := 32
const CELL_SIZE := 4.0

var _world: Node3D
var _player: CharacterBody3D
var _firearm: Node3D
var _viewmodel: Node3D
var _inventory: RefCounted
var _creature: CharacterBody3D


func after_each() -> void:
	# The automatic-fire tests hold the action down; releasing it here stops that from
	# leaking into whichever test runs next.
	Input.action_release(&"fire")
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	_player = null
	_firearm = null
	_viewmodel = null
	_inventory = null
	_creature = null


func _flat_map() -> RefCounted:
	var map: RefCounted = Heightmap.new(CELLS, CELL_SIZE)
	for cz in CELLS:
		for cx in CELLS:
			map.set_height(cx, cz, 10)
			map.set_biome(cx, cz, Biome.Kind.PLAINS)
	return map


## Player armed with `weapon` and `rounds` of its ammunition, with an animal `distance`
## ahead.
##
## A leopard rather than a deer by default: one round kills a deer outright, and a test
## that then reads the animal's health is reading a freed node. That is asserted on its
## own below instead.
func _setup(rounds: int = 6, distance: float = 8.0,
		kind: int = CreatureKind.Kind.LEOPARD,
		weapon: int = ItemKind.Kind.PISTOL) -> void:
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
	_firearm = _player.get_node(^"Firearm")
	_viewmodel = _player.get_node(^"Camera3D/Viewmodel")

	_inventory = _player.inventory()
	_inventory.add(weapon, 1)
	if rounds > 0:
		_inventory.add(ItemKind.ammo_for(weapon), rounds)
	_select(weapon)

	_creature = CreatureBody.new()
	_world.add_child(_creature)
	# Straight ahead: the player faces -Z.
	_creature.global_position = Vector3(0.0, 10.0, -distance)
	_creature.configure(kind, _flat_map(), _player, 11)

	# Aimed at the animal rather than held level. The eye is at 1.65 m and a big cat's
	# back is at 1.05, so a level shot passes over it at any range — the same geometry
	# that made melee use a sphere instead of a ray. A bullet is not given that
	# tolerance, so the test has to aim the way a player would.
	var body: Dictionary = CreatureKind.body(kind)
	_aim_at(_creature.global_position
			+ Vector3(0.0, float(body.get("height", 1.2)) * 0.5, 0.0))

	await step_physics(6)


## Points the camera at a world position.
func _aim_at(target: Vector3) -> void:
	var camera: Camera3D = _player.get_node(^"Camera3D")
	var to := target - camera.global_position
	camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


func _select(item: int) -> void:
	for slot in 5:
		if _inventory.item_in_slot(slot) == item:
			_inventory.select(slot)
			return


func test_the_pistol_is_a_firearm_and_a_stone_tool_is_not() -> void:
	# One entry in the item table decides this, so nothing keeps a list of guns.
	assert_true(ItemKind.is_firearm(ItemKind.Kind.PISTOL))
	assert_eq(ItemKind.ammo_for(ItemKind.Kind.PISTOL), ItemKind.Kind.PISTOL_AMMO)
	assert_false(ItemKind.is_firearm(ItemKind.Kind.STONE_TOOL))
	assert_false(ItemKind.is_firearm(ItemKind.Kind.BERRIES))
	assert_eq(ItemKind.ammo_for(ItemKind.Kind.STONE_TOOL), ItemKind.Kind.NONE)


func test_firing_spends_exactly_one_round() -> void:
	await _setup(6)
	assert_eq(_firearm.rounds_remaining(), 6)
	assert_true(_firearm.fire(), "a loaded pistol should fire")
	assert_eq(_firearm.rounds_remaining(), 5)
	assert_eq(_inventory.total_of(ItemKind.Kind.PISTOL_AMMO), 5,
			"the round comes out of the pack, since there is no magazine to reload")


func test_an_empty_pistol_refuses_out_loud() -> void:
	# Failing silently would be indistinguishable from a broken gun or a missed click.
	await _setup(0)
	var refusals: Array[String] = []
	_firearm.refused.connect(func(reason: String): refusals.append(reason))

	assert_false(_firearm.fire(), "an empty pistol must not fire")
	assert_eq(refusals.size(), 1, "and must say why")
	assert_has(refusals[0], "ammo")
	assert_eq(_firearm.rounds_remaining(), 0)


func test_the_last_round_fires_and_the_next_click_does_not() -> void:
	# Both halves of the gate, which is where an off-by-one would hide.
	await _setup(1)
	assert_true(_firearm.fire())
	assert_eq(_firearm.rounds_remaining(), 0)
	await step_physics(60)
	assert_false(_firearm.fire())


func test_a_shot_wounds_a_creature_at_range() -> void:
	# Well beyond a swing: the whole reason to want one.
	await _setup(6, 30.0)
	const Melee := preload("res://scripts/player/melee.gd")
	assert_true(30.0 > Melee.REACH_M * 4.0, "the leopard is out of melee reach")

	var before: float = _creature.health()
	assert_true(_firearm.fire())
	assert_true(_creature.health() < before,
			"a round should reach a leopard thirty metres away")


func test_one_round_kills_a_deer_outright() -> void:
	# What the pistol is worth against the animal the player has been clubbing: a hunt
	# that took several swings and a chase becomes one shot.
	await _setup(6, 20.0, CreatureKind.Kind.DEER)
	assert_true(ItemKind.ranged_damage(ItemKind.Kind.PISTOL)
					>= CreatureKind.health(CreatureKind.Kind.DEER),
			"a round should be enough for a deer")
	assert_true(_firearm.fire())
	assert_true(not is_instance_valid(_creature) or _creature.is_dead())


func test_the_hardest_animal_survives_a_single_round() -> void:
	# The other end of it. A pistol is an answer to predators, not an execution: a lion
	# takes several rounds, which is what leaves the machine gun somewhere to go.
	await _setup(6, 20.0, CreatureKind.Kind.LION)
	var rounds := CreatureKind.health(CreatureKind.Kind.LION) \
			/ ItemKind.ranged_damage(ItemKind.Kind.PISTOL)
	assert_true(rounds > 2.0, "a lion should need several rounds, needs %.1f" % rounds)
	assert_true(_firearm.fire())
	assert_false(_creature.is_dead())


func test_a_round_hits_harder_than_a_stone_tool() -> void:
	assert_true(ItemKind.ranged_damage(ItemKind.Kind.PISTOL)
					> ItemKind.melee_damage(ItemKind.Kind.STONE_TOOL),
			"finding a pistol has to be an upgrade over the first craft")


func test_nothing_beyond_the_pistols_range_is_hit() -> void:
	var reach := ItemKind.ranged_reach_m(ItemKind.Kind.PISTOL)
	await _setup(6, reach + 20.0)
	var before: float = _creature.health()
	assert_true(_firearm.fire(), "the round is still spent")
	assert_almost_eq(_creature.health(), before, 0.001,
			"but it should not reach something past the gun's range")


func test_a_shot_stops_at_the_wall_in_front_of_the_deer() -> void:
	# Rounds are stopped by the world, or a pistol would shoot through the island.
	await _setup(6, 20.0)
	var wall := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8.0, 6.0, 0.5)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	_world.add_child(wall)
	wall.global_position = Vector3(0.0, 11.5, -8.0)
	await step_physics(4)

	var before: float = _creature.health()
	assert_true(_firearm.fire())
	assert_almost_eq(_creature.health(), before, 0.001,
			"the round should be stopped by the wall, not pass through it")


func test_firing_has_a_cadence() -> void:
	# A pistol emptied in one frame would make the scarcity of ammunition meaningless.
	await _setup(6)
	assert_true(_firearm.fire())
	assert_false(_firearm.fire(), "a second shot in the same frame should be refused")
	assert_eq(_firearm.rounds_remaining(), 5, "and must not have cost a round")


func test_firing_kicks_the_aim_upwards() -> void:
	await _setup(6)
	var camera: Camera3D = _player.get_node(^"Camera3D")
	var before: float = camera.rotation.x
	assert_true(_firearm.fire())
	assert_true(camera.rotation.x > before,
			"the barrel should rise, so a second shot costs the player something")


func test_recoil_does_not_fully_recover_on_its_own() -> void:
	# Recoil that returned exactly to where it was aimed would be a visual effect
	# rather than a cost.
	await _setup(6)
	var camera: Camera3D = _player.get_node(^"Camera3D")
	var before: float = camera.rotation.x
	_firearm.fire()
	await step_physics(60)
	assert_true(camera.rotation.x > before,
			"some of the kick should still be there to pull back down")


func test_recoil_cannot_roll_the_view_over() -> void:
	# Emptying a pistol at the sky must not flip the camera past vertical.
	await _setup(24)
	var camera: Camera3D = _player.get_node(^"Camera3D")
	camera.rotation.x = deg_to_rad(88.0)
	for _i in 12:
		_firearm.fire()
		await step_physics(40)
	assert_true(camera.rotation.x <= deg_to_rad(89.001),
			"pitch should stay inside the look limit, got %.1f deg"
					% rad_to_deg(camera.rotation.x))


func test_the_pistol_is_drawn_in_the_players_hands() -> void:
	# There is no player body, so the viewmodel is the only way to know what is held.
	await _setup(6)
	await step_physics(2)
	assert_eq(_viewmodel.shown_item(), ItemKind.Kind.PISTOL)
	assert_true(_viewmodel.is_visible_model())


func test_putting_the_pistol_away_takes_it_off_the_screen() -> void:
	await _setup(6)
	_inventory.add(ItemKind.Kind.WOOD, 3)
	_select(ItemKind.Kind.WOOD)
	await step_physics(2)
	assert_eq(_viewmodel.shown_item(), ItemKind.Kind.NONE)
	assert_false(_viewmodel.is_visible_model(),
			"holding a log should not draw a gun")


func test_a_holstered_pistol_cannot_be_fired() -> void:
	await _setup(6)
	_inventory.add(ItemKind.Kind.WOOD, 3)
	_select(ItemKind.Kind.WOOD)
	assert_false(_firearm.is_holding_firearm())
	assert_false(_firearm.fire())
	assert_eq(_inventory.total_of(ItemKind.Kind.PISTOL_AMMO), 6,
			"and must not have spent a round")


func test_the_primary_action_shoots_rather_than_swinging() -> void:
	# One click, one verb. The pistol has to take the click from melee, or firing would
	# need its own key.
	await _setup(6, 30.0)
	var placer := _bound_placer()
	var before: float = _creature.health()
	placer._unhandled_input(_press(&"fire"))
	assert_eq(_firearm.rounds_remaining(), 5, "the click should have fired the pistol")
	assert_true(_creature.health() < before)


func test_an_empty_pistol_still_takes_the_click_rather_than_pistol_whipping() -> void:
	await _setup(0, 2.0)
	var placer := _bound_placer()
	var before: float = _creature.health()
	placer._unhandled_input(_press(&"fire"))
	assert_almost_eq(_creature.health(), before, 0.001,
			"an empty gun clicks; it does not become a club")


func test_the_machine_gun_is_a_firearm_distinct_from_the_pistol() -> void:
	assert_true(ItemKind.is_firearm(ItemKind.Kind.MACHINE_GUN))
	assert_eq(ItemKind.ammo_for(ItemKind.Kind.MACHINE_GUN),
			ItemKind.Kind.MACHINE_GUN_AMMO)
	assert_ne(ItemKind.ammo_for(ItemKind.Kind.MACHINE_GUN),
			ItemKind.ammo_for(ItemKind.Kind.PISTOL),
			"the two guns must not draw from the same ammunition")


func test_only_the_machine_gun_is_automatic() -> void:
	# What actually distinguishes it from the pistol mechanically: everything else —
	## damage, range, recoil — is just a different number in the same table.
	assert_true(ItemKind.is_automatic(ItemKind.Kind.MACHINE_GUN))
	assert_false(ItemKind.is_automatic(ItemKind.Kind.PISTOL))
	assert_false(ItemKind.is_automatic(ItemKind.Kind.STONE_TOOL))


func test_clicking_once_fires_the_machine_gun_once() -> void:
	# Automatic does not mean it cannot also be tapped.
	await _setup(30, 8.0, CreatureKind.Kind.LEOPARD, ItemKind.Kind.MACHINE_GUN)
	assert_true(_firearm.fire())
	assert_eq(_firearm.rounds_remaining(), 29)
	await step_physics(2)
	assert_eq(_firearm.rounds_remaining(), 29,
			"a single call to fire() must not keep firing on its own")


func test_holding_fire_keeps_the_machine_gun_firing_on_its_own() -> void:
	# The acceptance criterion itself: holding the key, not clicking it, is what
	# produces sustained fire. is_automatic_firearm() is what lets the primary action
	# step out of the way and leave this to Firearm's own polling.
	await _setup(60, 8.0, CreatureKind.Kind.LEOPARD, ItemKind.Kind.MACHINE_GUN)
	assert_true(_firearm.is_automatic_firearm())
	var before: int = _firearm.rounds_remaining()

	Input.action_press(&"fire")
	await step_physics(60)
	Input.action_release(&"fire")

	assert_true(_firearm.rounds_remaining() < before - 5,
			"holding the trigger for a second should have spent well more than a single click's worth of rounds, spent %d"
					% (before - _firearm.rounds_remaining()))


func test_automatic_fire_stops_the_instant_the_trigger_is_released() -> void:
	await _setup(60, 8.0, CreatureKind.Kind.LEOPARD, ItemKind.Kind.MACHINE_GUN)
	Input.action_press(&"fire")
	await step_physics(20)
	Input.action_release(&"fire")
	var after_release: int = _firearm.rounds_remaining()
	await step_physics(30)
	assert_eq(_firearm.rounds_remaining(), after_release,
			"no more rounds should be spent once the key is up")


func test_the_machine_gun_fires_at_its_own_defined_rate() -> void:
	# 0.08s between rounds quantizes to 12 over one second of physics ticks at 60 Hz;
	# the exact count matters less than it being far faster than the pistol's own
	# interval could ever produce and matching what the table declares.
	await _setup(40, 8.0, CreatureKind.Kind.LEOPARD, ItemKind.Kind.MACHINE_GUN)
	var start: int = _firearm.rounds_remaining()
	Input.action_press(&"fire")
	await step_physics(60)
	Input.action_release(&"fire")
	var fired: int = start - _firearm.rounds_remaining()

	var nominal := 1.0 / ItemKind.fire_interval(ItemKind.Kind.MACHINE_GUN)
	assert_in_range(float(fired), nominal - 3.0, nominal + 1.0,
			"fired %d rounds in one second against a declared %.1f rounds/sec"
					% [fired, nominal])
	var pistol_max := int(1.0 / ItemKind.fire_interval(ItemKind.Kind.PISTOL)) + 1
	assert_true(fired > pistol_max * 3,
			"the machine gun should fire far faster than the pistol ever could")


func test_holding_fire_empty_refuses_repeatedly_rather_than_jamming() -> void:
	# Both halves: it has to try again at its own cadence rather than latching a single
	# refusal, and it must not spend ammunition it does not have.
	await _setup(0, 8.0, CreatureKind.Kind.LEOPARD, ItemKind.Kind.MACHINE_GUN)
	var refusals: Array[String] = []
	_firearm.refused.connect(func(reason: String): refusals.append(reason))

	Input.action_press(&"fire")
	await step_physics(30)
	Input.action_release(&"fire")

	assert_true(refusals.size() > 1,
			"an empty automatic weapon should keep clicking while held, refused %d times"
					% refusals.size())
	assert_eq(_inventory.total_of(ItemKind.Kind.MACHINE_GUN_AMMO), 0)


func test_recoil_climbs_during_a_sustained_burst() -> void:
	# The other acceptance criterion: recoil has to visibly build the longer the
	# trigger stays down, not just repeat the same single-shot kick each round.
	await _setup(60, 8.0, CreatureKind.Kind.LEOPARD, ItemKind.Kind.MACHINE_GUN)
	var camera: Camera3D = _player.get_node(^"Camera3D")
	var start := camera.rotation.x

	Input.action_press(&"fire")
	await step_physics(6)
	var after_a_few_rounds := camera.rotation.x
	await step_physics(24)
	Input.action_release(&"fire")
	var after_a_longer_burst := camera.rotation.x

	assert_true(after_a_few_rounds > start, "the first rounds should kick the aim up")
	assert_true(after_a_longer_burst > after_a_few_rounds,
			"more sustained fire should have kicked it up further still")


func test_recoil_settles_back_down_once_the_trigger_is_released() -> void:
	await _setup(60, 8.0, CreatureKind.Kind.LEOPARD, ItemKind.Kind.MACHINE_GUN)
	var camera: Camera3D = _player.get_node(^"Camera3D")

	Input.action_press(&"fire")
	await step_physics(30)
	Input.action_release(&"fire")
	var peak := camera.rotation.x

	await step_physics(60)
	assert_true(camera.rotation.x < peak,
			"recoil should recover once the trigger stops being held")


func test_the_machine_gun_is_drawn_differently_from_the_pistol() -> void:
	await _setup(6, 8.0, CreatureKind.Kind.LEOPARD, ItemKind.Kind.MACHINE_GUN)
	await step_physics(2)
	assert_eq(_viewmodel.shown_item(), ItemKind.Kind.MACHINE_GUN)
	assert_true(_viewmodel.is_visible_model())

	_inventory.add(ItemKind.Kind.PISTOL, 1)
	_select(ItemKind.Kind.PISTOL)
	await step_physics(2)
	assert_eq(_viewmodel.shown_item(), ItemKind.Kind.PISTOL,
			"switching to the pistol should show the pistol, not both")


## The primary-action dispatcher, wired the way the world wires it. Without the bind it
## holds no inventory and ignores every click, which is not what is under test here.
func _bound_placer() -> Node:
	var placer: Node = _player.get_node(^"ItemPlacer")
	placer.bind(_player, _player.get_node(^"Camera3D"), _world, null)
	return placer


## A synthetic press of a named action, so an input path can be exercised without a
## real key.
func _press(action: StringName) -> InputEvent:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event
