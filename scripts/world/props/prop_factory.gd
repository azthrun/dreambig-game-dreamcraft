extends RefCounted
## Builds prop bodies from box meshes.
##
## Constructed in code rather than authored as .tscn files, for the same reason the
## creatures will be: there is no 3D art in this project and the aesthetic is cuboid,
## so a handful of boxes assembled to known proportions is both the cheapest and the
## most stylistically correct option. Each kind is still a self-contained scene
## subtree, just built rather than loaded.
##
## Solid props carry collision so the player cannot walk through a trunk. Bushes do
## not — being blocked by a berry bush would be annoying rather than realistic.

const PropKind := preload("res://scripts/world/props/prop_kind.gd")

const COLOUR_TRUNK := Color(0.34, 0.24, 0.16)
const COLOUR_LEAVES := Color(0.16, 0.34, 0.18)
const COLOUR_ROCK := Color(0.46, 0.45, 0.43)
const COLOUR_BERRY_LEAF := Color(0.28, 0.45, 0.24)
const COLOUR_BERRY := Color(0.62, 0.16, 0.24)


## Builds a prop rooted at its base, so the root can be placed directly on the terrace
## surface with no vertical fudging.
func build(kind: int) -> Node3D:
	match kind:
		PropKind.Kind.TREE:
			return _build_tree()
		PropKind.Kind.ROCK_OUTCROP:
			return _build_outcrop()
		PropKind.Kind.BERRY_BUSH:
			return _build_bush()
	return Node3D.new()


func _build_tree() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "Tree"
	_add_box(root, Vector3(0.0, 2.1, 0.0), Vector3(0.7, 4.2, 0.7), COLOUR_TRUNK)
	_add_box(root, Vector3(0.0, 4.9, 0.0), Vector3(3.4, 2.4, 3.4), COLOUR_LEAVES)
	_add_box(root, Vector3(0.0, 6.5, 0.0), Vector3(2.0, 1.4, 2.0), COLOUR_LEAVES)
	# Only the trunk blocks movement; walking under a canopy should be possible.
	_add_collider(root, Vector3(0.0, 2.1, 0.0), Vector3(0.7, 4.2, 0.7))
	return root


func _build_outcrop() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "RockOutcrop"
	_add_box(root, Vector3(0.0, 0.6, 0.0), Vector3(2.6, 1.2, 2.2), COLOUR_ROCK)
	_add_box(root, Vector3(0.5, 1.5, -0.3), Vector3(1.5, 1.4, 1.3), COLOUR_ROCK)
	_add_collider(root, Vector3(0.0, 0.9, 0.0), Vector3(2.6, 1.8, 2.2))
	return root


func _build_bush() -> Node3D:
	# No StaticBody3D: a bush is scenery the player walks through.
	var root := Node3D.new()
	root.name = "BerryBush"
	_add_box(root, Vector3(0.0, 0.5, 0.0), Vector3(1.5, 1.0, 1.5), COLOUR_BERRY_LEAF)
	_add_box(root, Vector3(0.35, 1.0, 0.2), Vector3(0.3, 0.3, 0.3), COLOUR_BERRY)
	_add_box(root, Vector3(-0.3, 0.85, -0.25), Vector3(0.3, 0.3, 0.3), COLOUR_BERRY)
	return root


func _add_box(parent: Node3D, offset: Vector3, size: Vector3,
		colour: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.92
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	parent.add_child(instance)


func _add_collider(parent: Node3D, offset: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = offset
	parent.add_child(collider)
