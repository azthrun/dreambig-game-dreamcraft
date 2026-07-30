extends "res://tests/test_case.gd"
## Integration tests for prop collision.
##
## Solidity is a physics property, so it is checked by building the prop and asking the
## physics space, rather than by trusting the factory's intent.

const PropFactory := preload("res://scripts/world/props/prop_factory.gd")
const PropKind := preload("res://scripts/world/props/prop_kind.gd")

var _world: Node3D


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null


func _spawn(kind: int) -> Node3D:
	_world = Node3D.new()
	scene_root().add_child(_world)
	var factory: RefCounted = PropFactory.new()
	var prop: Node3D = factory.build(kind)
	_world.add_child(prop)
	prop.global_position = Vector3.ZERO
	return prop


func test_solid_props_are_physics_bodies_with_a_shape() -> void:
	for kind in [PropKind.Kind.TREE, PropKind.Kind.ROCK_OUTCROP]:
		var prop := _spawn(kind)
		assert_true(prop is StaticBody3D,
				"%s should be solid" % PropKind.name_of(kind))
		var shapes := 0
		for child in prop.get_children():
			if child is CollisionShape3D:
				shapes += 1
		assert_true(shapes > 0,
				"%s has no collision shape" % PropKind.name_of(kind))
		after_each()


func test_bushes_have_no_collision_at_all() -> void:
	var prop := _spawn(PropKind.Kind.BERRY_BUSH)
	assert_false(prop is CollisionObject3D,
			"a bush should be scenery the player walks through")
	for child in prop.get_children():
		assert_false(child is CollisionShape3D, "a bush should have no shape")


func test_props_are_built_with_their_base_at_the_origin() -> void:
	# The placer puts the root exactly on the terrace top, so anything extending below
	# the root would sink into the ground.
	for kind in PropKind.ALL:
		var prop := _spawn(kind)
		var lowest := 1000.0
		for child in prop.get_children():
			if child is MeshInstance3D:
				var box := (child as MeshInstance3D).mesh as BoxMesh
				lowest = minf(lowest, child.position.y - box.size.y * 0.5)
		assert_almost_eq(lowest, 0.0, 0.05,
				"%s should sit on its base" % PropKind.name_of(kind))
		after_each()


func test_solid_props_block_a_shape_query() -> void:
	# The point of collision: something trying to occupy the trunk is refused.
	var prop := _spawn(PropKind.Kind.TREE)
	await step_physics(2)
	var body := CharacterBody3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.9
	body.add_child(collider)
	_world.add_child(body)
	body.global_position = Vector3(4.0, 0.0, 0.0)
	await step_physics(2)
	# Moving into the trunk should be reported as blocked.
	assert_true(body.test_move(body.global_transform, Vector3(-4.0, 0.0, 0.0)),
			"a tree trunk should block movement through it")
	assert_false(body.test_move(body.global_transform, Vector3(4.0, 0.0, 0.0)),
			"open ground away from the tree should be clear")
	prop.queue_free()
