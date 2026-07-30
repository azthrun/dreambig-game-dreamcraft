extends Node3D
## Finds the harvestable the player is looking at, and takes it if they hold interact.
##
## Holding rather than tapping, so harvesting is a small commitment: releasing early
## cancels and yields nothing. That also means a full inventory can be reported before any
## time is invested, instead of after.

const ItemKind := preload("res://scripts/items/item_kind.gd")

signal prompt_changed(text: String)

## How far the player can reach, and how long a harvest takes.
const REACH_M := 3.6
const HOLD_SECONDS := 0.9

## World layer plus the interaction layer, so the ray finds both solid props and the
## non-solid ones the player can walk through.
const HARVEST_MASK := 1 | 4

## Re-aimed this often rather than every frame. The prop under the crosshair cannot
## change faster than this at walking speed, and it keeps a raycast off the hot path.
const AIM_INTERVAL := 0.08

var _player: Node
var _camera: Camera3D
var _inventory: RefCounted

var _target: Node = null
var _progress := 0.0
var _aim_countdown := 0.0
var _prompt := ""


func bind(player: Node, camera: Camera3D) -> void:
	_player = player
	_camera = camera
	if _player != null and _player.has_method(&"inventory"):
		_inventory = _player.inventory()


## The harvestable currently under the crosshair, or null.
func target() -> Node:
	return _target


## Hold progress, 0..1. Drives the prompt's progress readout.
func progress() -> float:
	return clampf(_progress / HOLD_SECONDS, 0.0, 1.0)


func prompt() -> String:
	return _prompt


func _physics_process(delta: float) -> void:
	_aim_countdown -= delta
	if _aim_countdown <= 0.0:
		_aim_countdown = AIM_INTERVAL
		_acquire_target()

	if _target == null or not _target.can_harvest():
		_reset_progress()
		_set_prompt("")
		return

	if not Input.is_action_pressed(&"interact"):
		# Released early: the harvest is abandoned rather than banked.
		_reset_progress()
		_set_prompt(_ready_prompt())
		return

	# Refuse before any time is spent, rather than after a full hold.
	if not _has_room():
		_reset_progress()
		_set_prompt("inventory full")
		return

	_progress += delta
	if _progress >= HOLD_SECONDS:
		_complete()
	else:
		_set_prompt("%s  %d%%" % [_ready_prompt(), int(progress() * 100.0)])


func _complete() -> void:
	var yielded: int = _target.harvest()
	_reset_progress()
	if yielded <= 0:
		return
	var taken: int = _inventory.add(_target.item, yielded)
	# Report honestly when only part of the yield fitted, rather than quietly losing it.
	if taken < yielded:
		_set_prompt("took %d %s, no room for %d" % [
			taken, ItemKind.name_of(_target.item), yielded - taken])
	else:
		_set_prompt("+%d %s" % [taken, ItemKind.name_of(_target.item)])


func _has_room() -> bool:
	if _inventory == null or _target == null:
		return false
	return _inventory.room_for(_target.item) > 0


func _ready_prompt() -> String:
	return "hold E: %s" % ItemKind.name_of(_target.item)


func _reset_progress() -> void:
	_progress = 0.0


func _set_prompt(text: String) -> void:
	if text == _prompt:
		return
	_prompt = text
	prompt_changed.emit(text)


## Casts from the camera and looks for a Harvestable on whatever was hit.
func _acquire_target() -> void:
	_target = null
	if _camera == null:
		return

	var space := get_world_3d().direct_space_state
	var from := _camera.global_position
	var to := from - _camera.global_transform.basis.z * REACH_M

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = HARVEST_MASK
	# Shelter volumes are Areas; ignoring them stops cover props swallowing the ray.
	query.collide_with_areas = false
	if _player is CollisionObject3D:
		query.exclude = [(_player as CollisionObject3D).get_rid()]

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return

	var collider: Object = hit.get("collider")
	if collider is Node:
		_target = (collider as Node).get_node_or_null(^"Harvestable")
