extends Node3D
## Uses whatever the player is holding: eats food, places a campfire, feeds a burning one.
##
## Bound to the primary action, so "use what is in my hand" is one verb rather than a
## different key per item type.

const ItemKind := preload("res://scripts/items/item_kind.gd")
const Campfire := preload("res://scripts/world/props/campfire.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")

signal message(text: String)

## How far ahead a campfire can be placed, and how far to look for one to refuel.
const PLACE_REACH_M := 4.0
const REFUEL_REACH_M := 3.0

## Layers the placement ray tests against: world plus interaction props.
const PLACE_MASK := 1 | 4

var _player: Node
var _camera: Camera3D
var _inventory: RefCounted
var _world_root: Node
var _climate: Node

var _fires: Array[Node3D] = []


func bind(player: Node, camera: Camera3D, world_root: Node,
		climate: Node) -> void:
	_player = player
	_camera = camera
	_world_root = world_root
	_climate = climate
	if _player != null and _player.has_method(&"inventory"):
		_inventory = _player.inventory()


func placed_fires() -> Array[Node3D]:
	return _fires


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"fire"):
		return
	if _inventory == null:
		return
	# One primary action: use what is in hand, and swing it if it is not something that
	# gets used. Eating, placing and attacking never compete for the same click.
	if use_held_item():
		return
	var melee := get_parent().get_node_or_null(^"Melee")
	if melee != null and melee.has_method(&"swing"):
		melee.swing()


## Acts on the held item. Returns whether anything happened, so callers and tests do not
## have to infer success from side effects.
func use_held_item() -> bool:
	var item: int = _inventory.selected_item()

	if item == ItemKind.Kind.WOOD and _feed_nearby_fire():
		return true

	if ItemKind.is_food(item):
		if _player.eat_selected():
			message.emit("ate %s" % ItemKind.name_of(item))
			return true
		message.emit("not hungry")
		return false

	if item == ItemKind.Kind.CAMPFIRE:
		return _place_campfire()

	return false


## Adds a log to a fire the player is standing near, rather than placing a second one.
func _feed_nearby_fire() -> bool:
	var nearest := _nearest_fire(REFUEL_REACH_M)
	if nearest == null:
		return false
	if not nearest.add_fuel():
		message.emit("fire is already well fed")
		return false
	_inventory.remove_from_slot(_inventory.selected_slot(), 1)
	message.emit("added wood to the fire")
	return true


func _nearest_fire(within_m: float) -> Node3D:
	var best: Node3D = null
	var best_distance := within_m
	for fire in _fires:
		if not is_instance_valid(fire):
			continue
		var distance: float = fire.global_position.distance_to(
				_player.global_position)
		if distance <= best_distance:
			best = fire
			best_distance = distance
	return best


func _place_campfire() -> bool:
	var spot := _find_ground()
	if spot.is_empty():
		message.emit("no ground there")
		return false

	if not Campfire.is_valid_ground(spot["position"], spot["normal"],
			float(Heightmap.SEA_LEVEL_M)):
		message.emit("cannot build a fire there")
		return false

	if _inventory.remove_from_slot(_inventory.selected_slot(), 1) <= 0:
		return false

	var fire: Node3D = Campfire.new()
	fire.name = "Campfire"
	var parent: Node = _world_root if _world_root != null else get_tree().current_scene
	parent.add_child(fire)
	fire.global_position = spot["position"]
	_fires.append(fire)

	# Registered as a heat source so the temperature model can find it without the
	# climate node knowing what a campfire is.
	if _climate != null and _climate.has_method(&"add_heat_source"):
		_climate.add_heat_source(fire, Campfire.HEAT_RADIUS_M,
				Campfire.HEAT_STRENGTH_C)

	message.emit("campfire lit")
	return true


## Casts forward and slightly down to find where a fire would sit.
func _find_ground() -> Dictionary:
	if _camera == null:
		return {}
	var space := get_world_3d().direct_space_state
	var from := _camera.global_position
	var forward := -_camera.global_transform.basis.z
	# Biased downward so looking roughly ahead still finds the ground at the player's
	# feet rather than the horizon.
	var to := from + (forward + Vector3.DOWN * 0.9).normalized() * PLACE_REACH_M

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = PLACE_MASK
	query.collide_with_areas = false
	if _player is CollisionObject3D:
		query.exclude = [(_player as CollisionObject3D).get_rid()]

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	return {"position": hit["position"], "normal": hit["normal"]}
