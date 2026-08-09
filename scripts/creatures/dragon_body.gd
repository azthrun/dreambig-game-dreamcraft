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


func configure(p_kind: int, map: RefCounted, player: Node3D, seed_value: int,
		registry: RefCounted = null) -> void:
	super.configure(p_kind, map, player, seed_value, registry)
	# The base picks a brain from role; a dragon's role is PREDATOR for every other
	# purpose (registry queries, `is_predator`) but its actual decisions are its own.
	_brain = DragonBrainScript.new(seed_value)


func _move(delta: float) -> void:
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
