extends "res://tests/test_case.gd"
## Tests the harvestable component: yields, depletion and regrowth.
##
## The component is a Node but needs no SceneTree — regrowth is advanced by injected
## deltas, so a 150 second respawn is tested in microseconds.

const Harvestable := preload("res://scripts/world/props/harvestable.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")

const RESPAWN := 60.0

var _made: Array[Node] = []


func after_each() -> void:
	for node in _made:
		if is_instance_valid(node):
			node.free()
	_made.clear()


func _harvestable(amount: int = 3) -> Node:
	var component: Node = Harvestable.new()
	component.configure(ItemKind.Kind.WOOD, amount, RESPAWN, [])
	_made.append(component)
	return component


func test_an_intact_prop_can_be_harvested() -> void:
	var h := _harvestable()
	assert_true(h.can_harvest())
	assert_false(h.is_depleted())


func test_harvesting_yields_the_configured_amount() -> void:
	assert_eq(_harvestable(3).harvest(), 3)


func test_harvesting_depletes_the_prop() -> void:
	var h := _harvestable()
	h.harvest()
	assert_true(h.is_depleted())
	assert_false(h.can_harvest())


func test_a_depleted_prop_yields_nothing_on_a_second_harvest() -> void:
	# Otherwise the same bush is an infinite food supply.
	var h := _harvestable()
	h.harvest()
	assert_eq(h.harvest(), 0)


func test_regrowth_takes_the_configured_time() -> void:
	var h := _harvestable()
	h.harvest()
	assert_almost_eq(h.time_until_respawn(), RESPAWN, 0.001)
	h.tick(RESPAWN * 0.5)
	assert_true(h.is_depleted(), "still regrowing at the halfway point")
	h.tick(RESPAWN * 0.5 + 0.01)
	assert_false(h.is_depleted(), "should be back after the full interval")


func test_a_regrown_prop_can_be_harvested_again() -> void:
	var h := _harvestable(2)
	h.harvest()
	h.tick(RESPAWN + 1.0)
	assert_true(h.can_harvest())
	assert_eq(h.harvest(), 2)


func test_ticking_an_intact_prop_does_nothing() -> void:
	var h := _harvestable()
	h.tick(1000.0)
	assert_true(h.can_harvest())


func test_depleted_props_hide_their_yield_and_show_it_again() -> void:
	# A stripped tree keeps its trunk and loses its canopy, so depletion is visible
	# from a distance rather than only discovered by walking up to it.
	var canopy := Node3D.new()
	_made.append(canopy)
	var component: Node = Harvestable.new()
	component.configure(ItemKind.Kind.WOOD, 1, RESPAWN, [canopy])
	_made.append(component)

	assert_true(canopy.visible)
	component.harvest()
	assert_false(canopy.visible, "the harvested part should disappear")
	component.tick(RESPAWN + 1.0)
	assert_true(canopy.visible, "and come back with the prop")


func test_depletion_and_restoration_are_announced() -> void:
	var h := _harvestable()
	var events := {"depleted": 0, "restored": 0}
	h.depleted.connect(func(): events["depleted"] += 1)
	h.restored.connect(func(): events["restored"] += 1)
	h.harvest()
	h.tick(RESPAWN + 1.0)
	assert_eq(events["depleted"], 1)
	assert_eq(events["restored"], 1)


func test_processing_is_only_on_while_regrowing() -> void:
	# Thousands of props on the island: per-frame cost must be proportional to the few
	# that are depleted, not to all of them.
	var h := _harvestable()
	assert_false(h.is_processing(), "an intact prop should be idle")
	h.harvest()
	assert_true(h.is_processing(), "a regrowing prop needs ticking")
	h.tick(RESPAWN + 1.0)
	assert_false(h.is_processing(), "and should go idle again once restored")


func test_a_prop_with_nothing_to_give_cannot_be_harvested() -> void:
	var component: Node = Harvestable.new()
	component.configure(ItemKind.Kind.NONE, 0, RESPAWN, [])
	_made.append(component)
	assert_false(component.can_harvest())
	assert_eq(component.harvest(), 0)
