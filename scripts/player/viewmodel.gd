extends Node3D
## What the player sees in their own hands.
##
## There is no player body — the first-person decision removed the character model
## entirely — so the only way to know what is being held is to draw it on the camera.
## Built from boxes in code, like every other object in this game.
##
## Parented under the camera, so it moves with the view for free and the recoil kick
## applied to the camera carries the gun with it.

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

## How long the muzzle flash stays lit. Two frames at sixty, which is what a flash is.
const FLASH_SECONDS := 0.035

const COLOUR_BODY := Color(0.16, 0.16, 0.18)
const COLOUR_GRIP := Color(0.28, 0.20, 0.14)
const COLOUR_FLASH := Color(1.0, 0.86, 0.45)

var _inventory: RefCounted
var _model: Node3D
var _flash: MeshInstance3D
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
	return _model != null and _model.visible


## Rocks the gun back. Called by the firearm rather than watched for, so the feedback
## cannot drift out of step with the shot that caused it.
func kick() -> void:
	_kick = 1.0
	_flash_left = FLASH_SECONDS


func _process(delta: float) -> void:
	_refresh()

	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash != null:
			_flash.visible = _flash_left > 0.0

	if _kick > 0.0:
		_kick = maxf(_kick - delta / KICK_RECOVERY_SECONDS, 0.0)
	_apply_pose()


## Shows the model only while a firearm is held. Anything else is drawn by nothing at
## all — a stone tool viewmodel is not in scope, and an empty frame is honest.
func _refresh() -> void:
	var item: int = _inventory.selected_item() if _inventory != null \
			else ItemKind.Kind.NONE
	var wanted := item if ItemKind.is_firearm(item) else ItemKind.Kind.NONE
	if wanted == _shown:
		return
	_shown = wanted
	if _model != null:
		_model.visible = _shown != ItemKind.Kind.NONE
	if _flash != null and _shown == ItemKind.Kind.NONE:
		_flash.visible = false


func _apply_pose() -> void:
	if _model == null:
		return
	_model.position = REST_POSITION + Vector3(0.0, 0.0, KICK_BACK_M * _kick)
	_model.rotation.x = deg_to_rad(KICK_PITCH_DEGREES) * _kick


func _build() -> void:
	if _model != null:
		return
	_model = Node3D.new()
	_model.name = "Pistol"
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)

	# Slide, barrel and grip. Small and close: it reads as a pistol because of where it
	# sits in the frame, not because of detail no player will ever be close enough to see.
	_box(_model, Vector3(0.0, 0.0, 0.0), Vector3(0.05, 0.09, 0.22), COLOUR_BODY)
	_box(_model, Vector3(0.0, 0.012, -0.16), Vector3(0.032, 0.032, 0.12),
			COLOUR_BODY)
	_box(_model, Vector3(0.0, -0.085, 0.05), Vector3(0.045, 0.11, 0.07),
			COLOUR_GRIP)

	_flash = _box(_model, Vector3(0.0, 0.012, -0.245),
			Vector3(0.075, 0.075, 0.075), COLOUR_FLASH)
	_flash.visible = false
	_model.visible = false


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
