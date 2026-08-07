extends Node3D
## What the player sees in their own hands.
##
## There is no player body — the first-person decision removed the character model
## entirely — so the only way to know what is being held is to draw it on the camera.
## Built from boxes in code, like every other object in this game.
##
## Parented under the camera, so it moves with the view for free and the recoil kick
## applied to the camera carries the gun with it. One model per firearm, built once and
## swapped by visibility rather than rebuilt on every selection change.

const ItemKind := preload("res://scripts/items/item_kind.gd")

## Where the gun sits in the frame: low and to the right, out of the crosshair.
##
## Far enough out that it reads as held rather than pressed against the lens. At 0.42 m
## from a 75-degree camera the visible frame is only 64 cm tall, so a 22 cm pistol filled
## a third of the screen; the distance and the model both had to come down.
const REST_POSITION := Vector3(0.15, -0.13, -0.62)

## Everything below is modelled at life size and then scaled to fit the frame, so the
## proportions stay honest and only one number decides how big it reads.
const MODEL_SCALE := 0.55

## How far the gun rocks back on a shot, and how quickly it returns.
const KICK_BACK_M := 0.055
const KICK_PITCH_DEGREES := 7.0
const KICK_RECOVERY_SECONDS := 0.16

## The machine gun kicks back less per shot than the pistol — a real shot is felt once
## per shot, and an automatic weapon fires many times a second, so the same 7-degree
## snap on every round would read as a jackhammer rather than as gunfire.
const MG_KICK_PITCH_DEGREES := 3.0

## How long the muzzle flash stays lit. Two frames at sixty, which is what a flash is.
const FLASH_SECONDS := 0.035

const COLOUR_BODY := Color(0.16, 0.16, 0.18)
const COLOUR_GRIP := Color(0.28, 0.20, 0.14)
const COLOUR_FLASH := Color(1.0, 0.86, 0.45)

## The machine gun reads as a different weapon at a glance: longer, boxier, with a
## drum magazine and a barrel shroud rather than a slide — nothing about its silhouette
## should be mistakable for the pistol's.
const COLOUR_MG_BODY := Color(0.22, 0.24, 0.20)
const COLOUR_MG_DRUM := Color(0.13, 0.13, 0.14)
const COLOUR_MG_STOCK := Color(0.30, 0.22, 0.15)

var _inventory: RefCounted
## One entry per firearm kind: {root, flash}.
var _models: Dictionary = {}
var _shown := ItemKind.Kind.NONE

var _kick := 0.0
var _flash_left := 0.0


func bind(player: Node) -> void:
	if player != null and player.has_method(&"inventory"):
		_inventory = player.inventory()
	_build()
	_refresh()


## The item currently drawn, or NONE when the hands are empty. Read by tests, which
## cannot see the screen.
func shown_item() -> int:
	return _shown


func is_visible_model() -> bool:
	var entry: Dictionary = _models.get(_shown, {})
	var root: Node3D = entry.get("root")
	return root != null and root.visible


## Rocks the gun back. Called by the firearm rather than watched for, so the feedback
## cannot drift out of step with the shot that caused it.
func kick() -> void:
	_kick = 1.0
	_flash_left = FLASH_SECONDS


func _process(delta: float) -> void:
	_refresh()

	var flash: MeshInstance3D = _models.get(_shown, {}).get("flash")
	if _flash_left > 0.0:
		_flash_left -= delta
		if flash != null:
			flash.visible = _flash_left > 0.0

	if _kick > 0.0:
		_kick = maxf(_kick - delta / KICK_RECOVERY_SECONDS, 0.0)
	_apply_pose()


## Shows the model matching whatever is selected, and hides every other one. Anything
## that is not a firearm draws nothing at all — a stone tool viewmodel is not in scope,
## and an empty frame is honest.
func _refresh() -> void:
	var item: int = _inventory.selected_item() if _inventory != null \
			else ItemKind.Kind.NONE
	var wanted := item if ItemKind.is_firearm(item) else ItemKind.Kind.NONE
	if wanted == _shown:
		return

	var previous: Dictionary = _models.get(_shown, {})
	if previous.has("flash"):
		(previous["flash"] as MeshInstance3D).visible = false

	_shown = wanted
	for kind in _models:
		(_models[kind]["root"] as Node3D).visible = kind == _shown


func _apply_pose() -> void:
	var root: Node3D = _models.get(_shown, {}).get("root")
	if root == null:
		return
	var pitch := MG_KICK_PITCH_DEGREES if _shown == ItemKind.Kind.MACHINE_GUN \
			else KICK_PITCH_DEGREES
	root.position = REST_POSITION + Vector3(0.0, 0.0, KICK_BACK_M * _kick)
	root.rotation.x = deg_to_rad(pitch) * _kick


func _build() -> void:
	if not _models.is_empty():
		return
	_models[ItemKind.Kind.PISTOL] = _build_pistol()
	_models[ItemKind.Kind.MACHINE_GUN] = _build_machine_gun()


## Slide, barrel and grip. Small and close: it reads as a pistol because of where it
## sits in the frame, not because of detail no player will ever be close enough to see.
func _build_pistol() -> Dictionary:
	var root := Node3D.new()
	root.name = "Pistol"
	root.scale = Vector3.ONE * MODEL_SCALE
	root.visible = false
	add_child(root)

	_box(root, Vector3(0.0, 0.0, 0.0), Vector3(0.05, 0.09, 0.22), COLOUR_BODY)
	_box(root, Vector3(0.0, 0.012, -0.16), Vector3(0.032, 0.032, 0.12), COLOUR_BODY)
	_box(root, Vector3(0.0, -0.085, 0.05), Vector3(0.045, 0.11, 0.07), COLOUR_GRIP)

	var flash := _box(root, Vector3(0.0, 0.012, -0.245),
			Vector3(0.075, 0.075, 0.075), COLOUR_FLASH)
	flash.visible = false
	return {"root": root, "flash": flash}


## Longer, boxier, and sat further into the frame than the pistol: a drum magazine
## under the receiver and a shoulder stock behind it, neither of which the pistol has.
## The silhouette alone has to say "machine gun" before the player reads a label.
func _build_machine_gun() -> Dictionary:
	var root := Node3D.new()
	root.name = "MachineGun"
	root.scale = Vector3.ONE * MODEL_SCALE
	root.visible = false
	add_child(root)

	_box(root, Vector3(0.0, 0.0, 0.0), Vector3(0.06, 0.10, 0.40), COLOUR_MG_BODY)
	# Barrel shroud, forward of the receiver.
	_box(root, Vector3(0.0, 0.01, -0.30), Vector3(0.045, 0.045, 0.22), COLOUR_MG_BODY)
	# Drum magazine, hanging below — the one shape the pistol has nothing like.
	_box(root, Vector3(0.0, -0.10, -0.02), Vector3(0.11, 0.11, 0.07), COLOUR_MG_DRUM)
	# Stock, braced back towards the shoulder.
	_box(root, Vector3(0.0, -0.01, 0.24), Vector3(0.04, 0.06, 0.18), COLOUR_MG_STOCK)
	_box(root, Vector3(0.0, -0.09, 0.06), Vector3(0.045, 0.13, 0.06), COLOUR_MG_STOCK)

	var flash := _box(root, Vector3(0.0, 0.01, -0.41),
			Vector3(0.09, 0.09, 0.09), COLOUR_FLASH)
	flash.visible = false
	return {"root": root, "flash": flash}


func _box(parent: Node3D, offset: Vector3, size: Vector3,
		colour: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.6
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Drawn regardless of what is in front of it: at 40 cm from the camera the gun would
	# otherwise clip through anything the player stood close to.
	material.no_depth_test = true
	material.disable_receive_shadows = true
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	# Excluded from shadow casting: a gun held at the camera would throw a shadow
	# across the whole scene.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
