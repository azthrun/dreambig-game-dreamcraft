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
const ShelterVolume := preload("res://scripts/world/props/shelter_volume.gd")

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
		PropKind.Kind.OVERHANG:
			return _build_overhang()
		PropKind.Kind.CAVE_MOUTH:
			return _build_cave_mouth()
		PropKind.Kind.THICKET:
			return _build_thicket()
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


## A rock slab on a pillar, open on three sides. The cheapest thing that reads as
## cover from above without needing a real cave.
func _build_overhang() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "Overhang"
	_add_box(root, Vector3(-1.7, 1.4, 0.0), Vector3(1.3, 2.8, 2.6), COLOUR_ROCK)
	_add_box(root, Vector3(0.6, 3.1, 0.0), Vector3(5.2, 0.7, 3.4), COLOUR_ROCK)
	_add_collider(root, Vector3(-1.7, 1.4, 0.0), Vector3(1.3, 2.8, 2.6))
	_add_collider(root, Vector3(0.6, 3.1, 0.0), Vector3(5.2, 0.7, 3.4))
	# The sheltered space is under the slab, beside the pillar.
	_add_shelter(root, Vector3(0.8, 1.4, 0.0), Vector3(3.6, 2.6, 3.0))
	return root


## Walls and a roof with one side left open, so the player can actually walk in. Not a
## carved cave: a heightmap cannot contain one, so the interior is a built prop.
func _build_cave_mouth() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "CaveMouth"
	var wall_h := 3.2
	# Back and sides, leaving +Z open as the entrance.
	_add_box(root, Vector3(0.0, wall_h * 0.5, -2.2), Vector3(5.4, wall_h, 0.8),
			COLOUR_ROCK)
	_add_box(root, Vector3(-2.3, wall_h * 0.5, 0.0), Vector3(0.8, wall_h, 4.4),
			COLOUR_ROCK)
	_add_box(root, Vector3(2.3, wall_h * 0.5, 0.0), Vector3(0.8, wall_h, 4.4),
			COLOUR_ROCK)
	_add_box(root, Vector3(0.0, wall_h + 0.4, 0.0), Vector3(5.4, 0.8, 5.2),
			COLOUR_ROCK)
	_add_collider(root, Vector3(0.0, wall_h * 0.5, -2.2), Vector3(5.4, wall_h, 0.8))
	_add_collider(root, Vector3(-2.3, wall_h * 0.5, 0.0), Vector3(0.8, wall_h, 4.4))
	_add_collider(root, Vector3(2.3, wall_h * 0.5, 0.0), Vector3(0.8, wall_h, 4.4))
	_add_collider(root, Vector3(0.0, wall_h + 0.4, 0.0), Vector3(5.4, 0.8, 5.2))
	# Interior clearance is taller than the player's standing height, so the entrance
	# is walkable rather than crouch-only.
	_add_shelter(root, Vector3(0.0, 1.5, 0.0), Vector3(3.6, 3.0, 3.6))
	return root


## A close stand of trees whose canopies merge. Cover from rain without a roof.
func _build_thicket() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "Thicket"
	var trunks := [
		Vector3(-1.5, 0.0, -1.2), Vector3(1.6, 0.0, -0.9),
		Vector3(-1.1, 0.0, 1.5), Vector3(1.3, 0.0, 1.4),
	]
	for base in trunks:
		_add_box(root, base + Vector3(0.0, 2.3, 0.0),
				Vector3(0.6, 4.6, 0.6), COLOUR_TRUNK)
		_add_collider(root, base + Vector3(0.0, 2.3, 0.0),
				Vector3(0.6, 4.6, 0.6))
	_add_box(root, Vector3(0.0, 5.4, 0.0), Vector3(6.4, 2.2, 6.4), COLOUR_LEAVES)
	# Sheltered space is the gap between the trunks, under the merged canopy.
	_add_shelter(root, Vector3(0.0, 1.8, 0.0), Vector3(3.4, 3.4, 3.4))
	return root


func _add_shelter(parent: Node3D, offset: Vector3, size: Vector3) -> void:
	var area := Area3D.new()
	area.name = "Shelter"
	area.set_script(ShelterVolume)
	area.position = offset
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	area.add_child(collider)
	parent.add_child(area)


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
