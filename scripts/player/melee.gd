extends Node3D
## Swinging whatever is in hand at whatever is in front of you.
##
## Damage comes from the held item's entry in the item table, so a stone tool hits harder
## than a fist without this file knowing what a stone tool is. Bare hands still work, so
## the game is playable before the first craft.

const ItemKind := preload("res://scripts/items/item_kind.gd")
const CreatureBody := preload("res://scripts/creatures/creature_body.gd")

signal struck(target: Node, damage: float)
signal missed

## Reach and rate. Slow enough that a swing is a commitment, so backing off matters once
## predators exist.
const REACH_M := 3.0
const COOLDOWN_SECONDS := 0.65

## A swing is a sphere in front of the player, not a thin ray.
##
## The player's eye is at 1.65 m and a deer's back is at 1.5 m, so a level ray sails
## straight over it — a club needs more tolerance than a rifle. The sphere is centred a
## little below eye line, where a swing would actually land.
const SWING_RADIUS_M := 0.85
const SWING_DROP_M := 0.45

## Creatures and corpses share a layer, so a swing only ever finds living things.
const TARGET_MASK := CreatureBody.CREATURE_LAYER

var _player: Node
var _camera: Camera3D
var _inventory: RefCounted
var _cooldown := 0.0


func bind(player: Node, camera: Camera3D) -> void:
	_player = player
	_camera = camera
	if _player != null and _player.has_method(&"inventory"):
		_inventory = _player.inventory()


func is_ready() -> bool:
	return _cooldown <= 0.0


func cooldown_remaining() -> float:
	return maxf(_cooldown, 0.0)


## Damage the currently held item would do.
func damage() -> float:
	if _inventory == null:
		return ItemKind.BARE_HAND_DAMAGE
	return ItemKind.melee_damage(_inventory.selected_item())


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta


## Swings. Returns whether the swing happened at all — a swing on cooldown is refused,
## which is different from a swing that missed.
func swing() -> bool:
	if not is_ready():
		return false
	_cooldown = COOLDOWN_SECONDS

	var target := _target()
	if target == null:
		missed.emit()
		return true

	var dealt := damage()
	target.take_damage(dealt)
	struck.emit(target, dealt)
	return true


## The nearest creature within the swing volume, or null.
func _target() -> Node:
	if _camera == null:
		return null

	var forward := -_camera.global_transform.basis.z
	var centre := _camera.global_position + forward * (REACH_M * 0.55) \
			+ Vector3.DOWN * SWING_DROP_M

	var sphere := SphereShape3D.new()
	sphere.radius = SWING_RADIUS_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, centre)
	query.collision_mask = TARGET_MASK
	query.collide_with_areas = false
	if _player is CollisionObject3D:
		query.exclude = [(_player as CollisionObject3D).get_rid()]

	var hits := get_world_3d().direct_space_state.intersect_shape(query, 8)
	var best: Node = null
	var best_distance := INF
	for hit in hits:
		var collider: Object = hit.get("collider")
		# Only living creatures take damage; a corpse is looted, not hit again.
		if collider is not Node or not (collider as Node).has_method(&"take_damage"):
			continue
		var node := collider as Node3D
		var distance: float = node.global_position.distance_to(centre)
		if distance < best_distance:
			best = node
			best_distance = distance
	return best
