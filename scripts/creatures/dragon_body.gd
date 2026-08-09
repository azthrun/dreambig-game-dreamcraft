extends "res://scripts/creatures/creature_body.gd"
## The dragon in the world: the same decision loop, health, attack and corpse plumbing
## every creature already has, with flight substituted for ground steering.
##
## This is "extends Predator with flight" the way this codebase actually extends things —
## by overriding the one method that differs, `_move`, rather than forking the whole
## body. Dormancy, damage, death and looting are all inherited unchanged: a dragon far
## from the player stops thinking exactly like a deer does, and a bullet or a swing kills
## it exactly the same way.

const DragonBrainScript := preload("res://scripts/creatures/dragon_brain.gd")

## Never flies lower than this above the terrain beneath it, so a dive does not end by
## flying into the mountain it just passed over. Landing is a deliberate, brain-driven
## descent to the ground — see `_move` — not this clamp relaxing.
const MIN_CLEARANCE_M := 4.0

## Colour of the fire-breath cone, and of the thin warning beam during the telegraph.
const FLAME_COLOUR := Color(1.0, 0.5, 0.12, 0.85)
const TELEGRAPH_COLOUR := Color(1.0, 0.75, 0.35, 0.5)

## How wide the telegraph's warning beam reads relative to the full cone at that same
## range — a hint of what is coming, not the cone itself. The telegraph also does not
## reach the cone's full range, so it never reads as though it were already breathing.
const TELEGRAPH_LENGTH_SCALE := 0.4

var _flame: MeshInstance3D


func configure(p_kind: int, map: RefCounted, player: Node3D, seed_value: int,
		registry: RefCounted = null) -> void:
	super.configure(p_kind, map, player, seed_value, registry)
	# The base picks a brain from role; a dragon's role is PREDATOR for every other
	# purpose (registry queries, `is_predator`) but its actual decisions are its own.
	_brain = DragonBrainScript.new(seed_value)
	_flame = _build_flame()


func _move(delta: float) -> void:
	_update_flame()

	if _brain.has_method(&"is_landed") and _brain.is_landed():
		# Settled onto whatever is beneath it, the same instant "settle" every ground
		# creature already uses — a cuboid animal touching down does not need an
		# animated descent to read as landing.
		if _map != null:
			global_position.y = float(
					_map.height_at_world(global_position.x, global_position.z))
		_play(CreatureFactory.CLIP_IDLE)
		return

	var direction: Vector3 = _brain.desired_direction()
	if direction.length_squared() < 0.0001:
		_play(CreatureFactory.CLIP_IDLE)
		return

	var running: bool = _brain.is_running() if _brain.has_method(&"is_running") \
			else false
	var speed := CreatureKind.run_speed(kind) if running else CreatureKind.walk_speed(kind)
	_play(CreatureFactory.CLIP_RUN if running else CreatureFactory.CLIP_WALK)

	global_position += direction * speed * delta

	if _map != null:
		var floor_y := float(
				_map.height_at_world(global_position.x, global_position.z))
		global_position.y = maxf(global_position.y, floor_y + MIN_CLEARANCE_M)

	_face(direction, delta)


## The cone deals continuous damage over the duration of contact, not a lump per attack
## interval the way every other creature's strike does — this is what makes fire breath
## a damage-over-time hazard rather than a single hit, and overriding this one method is
## what keeps that difference from leaking into the shared decision loop.
func _update_attack(delta: float) -> void:
	if not _brain.has_method(&"is_breathing") or not _brain.is_breathing():
		return
	if not _brain.has_method(&"is_hitting_player") or not _brain.is_hitting_player():
		return
	if _player == null or not is_instance_valid(_player) \
			or not _player.has_method(&"stats"):
		return
	var stats: RefCounted = _player.stats()
	if stats != null and not stats.is_dead():
		stats.damage(DragonBrainScript.BREATH_DAMAGE_PER_SECOND * delta)


## Shows the fire-breath cone while it is live, and a thinner warning beam during the
## telegraph that precedes it — the visible half of "avoided by moving out of it": a cone
## nothing on screen hinted at could not be dodged, only survived by luck.
func _update_flame() -> void:
	if _flame == null:
		return

	var breathing: bool = _brain.has_method(&"is_breathing") and _brain.is_breathing()
	var telegraphing: bool = _brain.has_method(&"is_telegraphing") \
			and _brain.is_telegraphing()
	if not breathing and not telegraphing:
		_flame.visible = false
		return

	var origin: Vector3
	var direction: Vector3
	var length: float
	if breathing:
		origin = _brain.breath_origin()
		direction = _brain.breath_direction()
		length = DragonBrainScript.BREATH_RANGE_M
		(_flame.material_override as StandardMaterial3D).albedo_color = FLAME_COLOUR
	else:
		origin = global_position
		direction = _brain.aim_direction()
		length = DragonBrainScript.BREATH_RANGE_M * TELEGRAPH_LENGTH_SCALE
		(_flame.material_override as StandardMaterial3D).albedo_color = TELEGRAPH_COLOUR

	if direction.length_squared() < 0.0001:
		_flame.visible = false
		return
	direction = direction.normalized()

	var half_width := length * tan(deg_to_rad(DragonBrainScript.BREATH_HALF_ANGLE_DEGREES))
	(_flame.mesh as BoxMesh).size = Vector3(half_width * 1.4, half_width * 1.4, length)
	_flame.global_position = origin + direction * (length * 0.5)
	_flame.visible = true
	if absf(direction.dot(Vector3.UP)) < 0.999:
		_flame.look_at(_flame.global_position + direction, Vector3.UP)


func _build_flame() -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.albedo_color = FLAME_COLOUR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.5, 0.1)
	material.emission_energy_multiplier = 1.6
	material.disable_receive_shadows = true

	var instance := MeshInstance3D.new()
	instance.name = "Flame"
	instance.mesh = mesh
	instance.material_override = material
	instance.visible = false
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance
