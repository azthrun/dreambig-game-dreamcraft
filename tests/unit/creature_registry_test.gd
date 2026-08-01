extends "res://tests/test_case.gd"
## Tests the lookup that lets one animal find another.

const CreatureRegistry := preload("res://scripts/creatures/creature_registry.gd")
const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")

const PREY := CreatureKind.Role.PREY
const PREDATOR := CreatureKind.Role.PREDATOR

var _registry: RefCounted


func before_each() -> void:
	_registry = CreatureRegistry.new()


func _at(id: int, kind: int, x: float, z: float) -> void:
	_registry.add(id, kind, Vector3(x, 0.0, z), "body_%d" % id)


func test_an_empty_island_offers_nothing() -> void:
	assert_eq(_registry.count(), 0)
	assert_true(_registry.nearest_of_role(Vector3.ZERO, PREY, 100.0).is_empty())


func test_the_nearest_of_a_role_is_found() -> void:
	_at(1, CreatureKind.Kind.DEER, 30.0, 0.0)
	_at(2, CreatureKind.Kind.DEER, 8.0, 0.0)
	_at(3, CreatureKind.Kind.DEER, 60.0, 0.0)
	var found: Dictionary = _registry.nearest_of_role(Vector3.ZERO, PREY, 100.0)
	assert_eq(int(found["id"]), 2, "the deer at 8m, not the one at 30m")
	assert_eq(found["ref"], "body_2", "the query hands back whatever was registered")


func test_the_other_role_is_not_offered() -> void:
	# A leopard looking for dinner must not find another leopard.
	_at(1, CreatureKind.Kind.LEOPARD, 5.0, 0.0)
	_at(2, CreatureKind.Kind.DEER, 40.0, 0.0)
	var found: Dictionary = _registry.nearest_of_role(Vector3.ZERO, PREY, 100.0)
	assert_eq(int(found["id"]), 2)
	assert_true(_registry.nearest_of_role(Vector3.ZERO, PREDATOR, 3.0).is_empty(),
			"and range still applies to the role that is wanted")


func test_nothing_outside_the_range_is_found() -> void:
	_at(1, CreatureKind.Kind.DEER, 41.0, 0.0)
	assert_true(_registry.nearest_of_role(Vector3.ZERO, PREY, 40.0).is_empty())
	assert_false(_registry.nearest_of_role(Vector3.ZERO, PREY, 42.0).is_empty(),
			"and it is found once the range covers it")


func test_a_searcher_does_not_find_itself() -> void:
	# Without the exclusion every animal's nearest neighbour is the one at zero metres:
	# itself.
	_at(7, CreatureKind.Kind.DEER, 0.0, 0.0)
	_at(8, CreatureKind.Kind.DEER, 12.0, 0.0)
	var found: Dictionary = _registry.nearest_of_role(Vector3.ZERO, PREY, 100.0, 7)
	assert_eq(int(found["id"]), 8)


func test_animals_move() -> void:
	_at(1, CreatureKind.Kind.DEER, 50.0, 0.0)
	assert_true(_registry.nearest_of_role(Vector3.ZERO, PREY, 20.0).is_empty())
	_registry.move(1, Vector3(4.0, 0.0, 0.0))
	var found: Dictionary = _registry.nearest_of_role(Vector3.ZERO, PREY, 20.0)
	assert_eq(int(found["id"]), 1, "it should be found where it now is")


func test_a_dead_animal_is_gone_and_cannot_report_a_position() -> void:
	_at(1, CreatureKind.Kind.DEER, 4.0, 0.0)
	_registry.remove(1)
	assert_false(_registry.has(1))
	assert_eq(_registry.count(), 0)

	# The other half: a body that dies mid-decision must not be able to put itself back.
	_registry.move(1, Vector3(1.0, 0.0, 0.0))
	assert_eq(_registry.count(), 0, "moving an unknown id must not create one")
	assert_true(_registry.nearest_of_role(Vector3.ZERO, PREY, 100.0).is_empty())


func test_registering_the_same_animal_twice_does_not_duplicate_it() -> void:
	_at(1, CreatureKind.Kind.DEER, 4.0, 0.0)
	_at(1, CreatureKind.Kind.DEER, 9.0, 0.0)
	assert_eq(_registry.count(), 1)
	var found: Dictionary = _registry.nearest_of_role(Vector3.ZERO, PREY, 100.0)
	assert_almost_eq(float(found["position"].x), 9.0, 0.001,
			"the later registration wins")


func test_the_role_comes_from_the_species() -> void:
	# The caller passes a species, not a role: one source of truth for what a tiger is.
	_at(1, CreatureKind.Kind.TIGER, 3.0, 0.0)
	_at(2, CreatureKind.Kind.DEER, 3.0, 0.0)
	assert_eq(int(_registry.nearest_of_role(Vector3.ZERO, PREDATOR, 10.0)["id"]), 1)
	assert_eq(int(_registry.nearest_of_role(Vector3.ZERO, PREY, 10.0)["id"]), 2)
