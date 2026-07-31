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

## World layer, the interaction layer, and the creature layer: props to harvest and
## corpses to loot are the same verb, so they are the same ray.
const HARVEST_MASK := 1 | 4 | 8

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

	if _target == null or not _can_take():
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
	if _is_corpse():
		_loot_corpse()
		return

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


## A corpse hands over several different items at once, so what was taken is summarised
## rather than named singly.
func _loot_corpse() -> void:
	var before: int = _target.remaining_count()
	var taken: Dictionary = _target.loot(_inventory)
	_reset_progress()

	if taken.is_empty():
		_set_prompt("no room")
		return

	var parts := PackedStringArray()
	for item in taken:
		parts.append("%d %s" % [int(taken[item]), ItemKind.name_of(item)])
	var left: int = _target.remaining_count()
	if left > 0:
		_set_prompt("+%s, %d left" % [", ".join(parts), left])
	else:
		_set_prompt("+%s" % ", ".join(parts))


func _is_corpse() -> bool:
	return _target != null and _target.has_method(&"loot")


## Both kinds of target answer "is there anything here to take".
func _can_take() -> bool:
	if _target == null:
		return false
	if _is_corpse():
		return _target.can_loot()
	return _target.can_harvest()


func _has_room() -> bool:
	if _inventory == null or _target == null:
		return false
	return _inventory.room_for(_target_item()) > 0


## What this target offers next, whichever kind it is.
func _target_item() -> int:
	if _is_corpse():
		return _target.headline_item()
	return _target.item


func _ready_prompt() -> String:
	var verb := "loot" if _is_corpse() else "harvest"
	return "hold E to %s: %s" % [verb, ItemKind.name_of(_target_item())]


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
	if collider is not Node:
		return
	# Props carry a Harvestable, corpses carry a Lootable. Either satisfies the same
	# hold-to-take interaction, so neither needs its own key or its own code path.
	_target = (collider as Node).get_node_or_null(^"Harvestable")
	if _target == null:
		_target = (collider as Node).get_node_or_null(^"Lootable")
