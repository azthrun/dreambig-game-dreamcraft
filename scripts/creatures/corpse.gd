extends Node3D
## What a killed animal leaves behind.
##
## A slumped version of the same cuboid body, so a kill is recognisable as the animal it
## was rather than as a generic loot bag. Carries a Lootable holding the species drops.

const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const Lootable := preload("res://scripts/creatures/lootable.gd")

## Layer corpses sit on, matching creatures, so the same interaction ray finds both.
const CORPSE_LAYER := 8

## How long a picked-clean corpse lingers before disappearing.
const CLEARED_LIFETIME := 6.0

var kind := CreatureKind.Kind.DEER
var _cleared_countdown := -1.0


func configure(p_kind: int) -> void:
	kind = p_kind

	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = CORPSE_LAYER
	body.collision_mask = 0
	add_child(body)

	var shape: Dictionary = CreatureKind.body(kind)
	var length := float(shape.get("length", 1.6))
	var width := float(shape.get("width", 0.7))

	# Lying on its side: the torso flat to the ground rather than standing.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(length, width * 0.7, width)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(shape.get("body_colour",
			Color(0.5, 0.4, 0.3))).darkened(0.25)
	material.roughness = 0.95
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position.y = width * 0.35
	instance.material_override = material
	body.add_child(instance)

	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Reaches above eye height on purpose. The player's eye is at 1.65 m, so a box that
	# stopped at the corpse's actual height would be missed by a level look and the kill
	# would be unlootable without aiming at the ground.
	box.size = Vector3(maxf(length, 1.4), 2.4, maxf(width, 1.2))
	collider.shape = box
	collider.position.y = 1.2
	body.add_child(collider)

	var loot := Lootable.new()
	loot.name = "Lootable"
	loot.configure(CreatureKind.drops(kind))
	loot.looted.connect(_on_looted)
	body.add_child(loot)


func _on_looted() -> void:
	# Linger briefly so the player sees it emptied rather than vanish under the crosshair.
	_cleared_countdown = CLEARED_LIFETIME
	set_process(true)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if _cleared_countdown < 0.0:
		return
	_cleared_countdown -= delta
	if _cleared_countdown <= 0.0:
		queue_free()
