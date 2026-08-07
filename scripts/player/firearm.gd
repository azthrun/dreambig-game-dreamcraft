extends Node3D
## Firing whatever gun is in hand: spending a round, hitting something at range, kicking.
##
## Mirrors Melee deliberately. Both are bound the same way, both are asked the same two
## questions by the primary action, and neither knows what weapon it is holding — damage,
## reach, cadence, recoil and which ammunition is spent all come from the item table. The
## machine gun is therefore an entry in that table rather than a second copy of this file.
##
## What makes it different from melee is that it can fail for a reason the player has to
## be told about. An empty gun that clicked silently would be indistinguishable from a
## broken one.

const ItemKind := preload("res://scripts/items/item_kind.gd")
const CreatureBody := preload("res://scripts/creatures/creature_body.gd")
const ProceduralAudio := preload("res://scripts/audio/procedural_audio.gd")

signal fired(item: int, hit: Node)
signal refused(reason: String)

## Creatures and corpses share a layer; the world blocks the shot. Both are in the mask
## so a round stops at the tree in front of the deer rather than passing through it.
const TARGET_MASK := 1 | CreatureBody.CREATURE_LAYER

## How much of the kick recovers on its own, and how fast.
##
## Not all of it: a shot that returned exactly to where it was aimed would make recoil a
## visual effect rather than a cost. The rest is the player's to pull back down.
const RECOIL_RECOVERY := 0.65
const RECOIL_RECOVERY_SECONDS := 0.28

var _player: Node
var _camera: Camera3D
var _inventory: RefCounted

var _cooldown := 0.0
var _recoil_left := 0.0
var _recoil_rate := 0.0

var _shot_audio: AudioStreamPlayer
var _viewmodel: Node

## Built once and replayed, not resynthesised per shot.
##
## `ProceduralAudio.gunshot()` walks a buffer sample by sample with an RNG and two
## `exp()` calls each — cheap once, called from every `fire()` before this. At the
## pistol's 0.45s interval that never showed up; at the machine gun's 0.08s it is called
## roughly twelve times a second, and profiling the machine gun's own perf run (isolating
## it from an unrelated bad reading — see docs/performance.md) found this the only real
## per-shot cost. Every other procedural sound in this project (rain, fire, thunder) is
## already generated once at construction for exactly this reason; this file was the one
## that generated its buffer inside the hot path.
var _gunshot_audio: AudioStreamWAV
var _dry_click_audio: AudioStreamWAV


func _ready() -> void:
	_shot_audio = get_node_or_null(^"Shot") as AudioStreamPlayer
	_gunshot_audio = ProceduralAudio.gunshot()
	_dry_click_audio = ProceduralAudio.dry_click()


func bind(player: Node, camera: Camera3D) -> void:
	_player = player
	_camera = camera
	if _player != null and _player.has_method(&"inventory"):
		_inventory = _player.inventory()
	if _camera != null:
		_viewmodel = _camera.get_node_or_null(^"Viewmodel")


## The gun in hand, or NONE. "Equipped" is "selected in the hotbar" — there is no second
## notion of being wielded, so putting a pistol away is the same gesture as putting a
## stone tool away.
func held_firearm() -> int:
	if _inventory == null:
		return ItemKind.Kind.NONE
	var item: int = _inventory.selected_item()
	return item if ItemKind.is_firearm(item) else ItemKind.Kind.NONE


func is_holding_firearm() -> bool:
	return held_firearm() != ItemKind.Kind.NONE


## Whether the gun in hand fires continuously while the key is held, rather than once
## per click. The primary action asks this before deciding whether its own single press
## should fire the gun at all — see `item_placer.gd`.
func is_automatic_firearm() -> bool:
	return ItemKind.is_automatic(held_firearm())


func is_ready() -> bool:
	return _cooldown <= 0.0


## Rounds left for the gun in hand. Counted in the inventory rather than in a magazine:
## there is no reload, so what the player is carrying is what they can fire.
func rounds_remaining() -> int:
	var gun := held_firearm()
	if gun == ItemKind.Kind.NONE or _inventory == null:
		return 0
	return _inventory.total_of(ItemKind.ammo_for(gun))


## Fires. Returns whether a round left the barrel — false covers both "not holding a gun"
## and "holding an empty one", which the caller distinguishes through `refused`.
func fire() -> bool:
	var gun := held_firearm()
	if gun == ItemKind.Kind.NONE:
		return false
	if not is_ready():
		return false

	var ammo := ItemKind.ammo_for(gun)
	if _inventory.remove(ammo, 1) < 1:
		# Told, not merely denied. An empty gun has to be distinguishable from a gun
		# that is not working, and from a click the player did not register — so there
		# is a sound as well as a message.
		_cooldown = ItemKind.fire_interval(gun)
		_play(_dry_click_audio)
		refused.emit("out of %s" % ItemKind.name_of(ammo))
		return false

	_cooldown = ItemKind.fire_interval(gun)

	# The round leaves before the barrel rises. Kicking first sent the shot along the
	# recoiled path — 2.4 degrees is over a metre high at thirty metres, so a deer that
	# was squarely in the crosshair was missed every time.
	var hit := _shoot(gun)

	_kick(ItemKind.recoil_degrees(gun))
	_play(_gunshot_audio)
	if _viewmodel != null and _viewmodel.has_method(&"kick"):
		# Told rather than watched for, so the muzzle flash cannot drift out of step
		# with the shot that caused it.
		_viewmodel.kick()

	fired.emit(gun, hit)
	return true


## Audio only plays once the gun is actually in the world. A firearm can be constructed
## and fired before it is parented — tests do exactly that — and playback on a node
## outside the tree errors.
func _play(stream: AudioStream) -> void:
	if _shot_audio == null or not _shot_audio.is_inside_tree():
		return
	_shot_audio.stream = stream
	_shot_audio.play()


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	_recover(delta)

	# Automatic weapons are polled directly here, the same way the harvester polls its
	# own hold-to-interact key, rather than routed through the primary action's single
	# press event — holding the trigger down has to keep firing without a second click
	# for every round. `fire()` still gates on its own cooldown, so this costs nothing
	# beyond one check per physics frame while a firearm that wants it is in hand.
	if is_automatic_firearm() and Input.is_action_pressed(&"fire"):
		fire()


## Traces the shot and applies damage. Returns what was hit, or null.
func _shoot(gun: int) -> Node:
	if _camera == null:
		return null
	var from := _camera.global_position
	var to := from - _camera.global_transform.basis.z * ItemKind.ranged_reach_m(gun)

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = TARGET_MASK
	query.collide_with_areas = false
	if _player is CollisionObject3D:
		query.exclude = [(_player as CollisionObject3D).get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var collider: Object = hit.get("collider")
	# Terrain and trees stop the round without taking damage; a corpse has no health to
	# take either. Only living things answer take_damage.
	if collider is not Node or not (collider as Node).has_method(&"take_damage"):
		return null

	var target := collider as Node
	target.take_damage(ItemKind.ranged_damage(gun))
	return target


## Kicks the aim up, and schedules the part of it that comes back.
##
## Additive rather than a reset: a single pistol shot is normally well clear of the
## previous one's recovery window, but the machine gun fires faster than
## RECOIL_RECOVERY_SECONDS, and resetting the pool on every round was discarding
## whatever recovery credit the previous round had not yet paid out — recoil could not
## climb during a sustained burst, which is the entire acceptance criterion. Adding to
## the pool and recomputing the rate from its new total is what makes recoil build up
## while the trigger stays down and drain over one recovery window once it is released.
func _kick(degrees: float) -> void:
	if degrees <= 0.0 or _player == null:
		return
	var kick := deg_to_rad(degrees)
	if _player.has_method(&"apply_recoil"):
		_player.apply_recoil(kick)
	_recoil_left += kick * RECOIL_RECOVERY
	_recoil_rate = _recoil_left / RECOIL_RECOVERY_SECONDS


func _recover(delta: float) -> void:
	if _recoil_left <= 0.0 or _player == null:
		return
	var step := minf(_recoil_rate * delta, _recoil_left)
	_recoil_left -= step
	if _player.has_method(&"apply_recoil"):
		_player.apply_recoil(-step)
