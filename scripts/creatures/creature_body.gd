extends CharacterBody3D
## A creature in the world: steers where its brain says, over the terrain it stands on.
##
## Ground height comes from an O(1) heightmap lookup rather than a raycast, and there is
## no navmesh anywhere. That is the whole reason SPEC could delete navmesh baking: the
## generator already owns the heights, so asking "how high is it here" costs an array
## index.
##
## Decisions and obstacle checks run on an interval rather than every frame, and animals
## far from the player do not think at all. With dozens on the island, per-frame cost has
## to stay proportional to what the player can actually see.

const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const CreatureFactory := preload("res://scripts/creatures/creature_factory.gd")
const PreyBrain := preload("res://scripts/creatures/prey_brain.gd")
const PredatorBrain := preload("res://scripts/creatures/predator_brain.gd")
const Corpse := preload("res://scripts/creatures/corpse.gd")

## Steepest step a creature will climb. Matches the player's own limit, so terrain that
## reads as a cliff is a cliff for everything.
const MAX_CLIMB_M := 1.05

## How often a creature re-decides and re-checks for obstacles.
const DECISION_INTERVAL := 0.2

## Beyond this from the player, a creature stops thinking entirely.
const ACTIVE_RADIUS_M := 130.0

## How far past its own detection range a creature looks for other animals, so a brain's
## release margin has something to measure against. Matches the largest margin either
## brain applies.
const NEIGHBOUR_SEARCH_MARGIN := 1.5

## Movement below this in a decision window counts as no progress, which is what tells the
## brain it is wedged.
const PROGRESS_EPSILON_M := 0.25

## How fast a creature turns to face where it is going, in radians per second.
const TURN_RATE := 6.0

## Collision layer for creatures, kept off the world layer so they do not block the
## player's own movement or catch the harvest ray.
const CREATURE_LAYER := 8

signal died(kind: int, at: Vector3)

## How long a struck animal flashes, and what it flashes to.
const HIT_FLASH_SECONDS := 0.18
const HIT_FLASH_COLOUR := Color(1.0, 0.42, 0.38)

var kind := CreatureKind.Kind.DEER

var _health := 0.0
## Where a predator patrols around. Prey wander freely, so this is only read by
## predators, but every body carries it rather than branching on species.
var _anchor := Vector3.ZERO
var _attack_countdown := 0.0
var _flash_countdown := 0.0
var _meshes: Array[MeshInstance3D] = []

var _map: RefCounted
var _player: Node3D
var _brain: RefCounted
var _animator: AnimationPlayer
## Where every other animal is. Null in tests that care only about one animal, which is
## why every use of it is guarded.
var _registry: RefCounted
## The animal this one is hunting, or running from, as of the last decision.
var _neighbour: Node3D

var _decision_countdown := 0.0
var _last_decision_position := Vector3.ZERO
var _made_progress := true
var _active := true
var _current_clip := ""


func configure(p_kind: int, map: RefCounted, player: Node3D,
		seed_value: int, registry: RefCounted = null) -> void:
	kind = p_kind
	_map = map
	_player = player
	_registry = registry
	if _registry != null:
		_registry.add(get_instance_id(), p_kind, global_position, self)
	# Role picks the brain, not species, so a new animal needs no new wiring — even one
	# like the boar that behaves a little differently, since that difference is a flag
	# on the species table rather than a branch here.
	_brain = PredatorBrain.new(seed_value) if CreatureKind.is_predator(p_kind) \
			else PreyBrain.new(seed_value, CreatureKind.retaliates(p_kind))
	_anchor = global_position

	collision_layer = CREATURE_LAYER
	# Collides with nothing: movement is driven from the heightmap, and letting animals
	# push the player around would be worse than letting them overlap.
	collision_mask = 0

	var factory: RefCounted = CreatureFactory.new()
	_animator = factory.build(self, kind)

	var shape := CapsuleShape3D.new()
	var body: Dictionary = CreatureKind.body(kind)
	shape.radius = float(body.get("width", 0.7)) * 0.6
	shape.height = float(body.get("height", 1.4))
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = shape.height * 0.5
	add_child(collider)

	_health = CreatureKind.health(kind)
	_collect_meshes()

	_last_decision_position = global_position
	# Dormant until the first decision proves the player is close enough to care.
	_active = false
	_set_simulated(false)


## Leaving the tree for any reason drops the registration, so a query can never hand back
## a freed body. Death removes it too, but an animal can also be freed outright — the
## island is repopulated that way.
func _exit_tree() -> void:
	if _registry != null:
		_registry.remove(get_instance_id())


func brain() -> RefCounted:
	return _brain


func health() -> float:
	return _health


func health_fraction() -> float:
	return _health / maxf(CreatureKind.health(kind), 0.001)


func is_dead() -> bool:
	return _health <= 0.0


## Wounds the creature. Being hit also panics it, so a struck animal runs whether or not
## it had noticed its attacker.
##
## `from` is where the blow came from, so a deer mauled by a leopard runs from the leopard
## rather than from the player who is not there. Left out, it means the player.
func take_damage(amount: float, from: Vector3 = Vector3.INF) -> void:
	if amount <= 0.0 or is_dead():
		return
	_health = maxf(_health - amount, 0.0)
	_flash_countdown = HIT_FLASH_SECONDS
	_apply_flash(true)

	var struck_by_player := from == Vector3.INF
	if struck_by_player and _player != null:
		from = _player.global_position

	if _brain != null and from != Vector3.INF:
		# Woken and running, even from behind and even if dormant a moment ago.
		_active = true
		_set_simulated(true)
		_brain.tick(DECISION_INTERVAL, {
			"position": global_position,
			"threat_position": from if struck_by_player else Vector3.ZERO,
			"threat_present": struck_by_player,
			"threat_crouching": false,
			"predator_position": from,
			"predator_present": not struck_by_player,
			"quarry_position": from,
			"quarry_present": not struck_by_player,
			## Struck animals always notice, whatever the range.
			"detection_m": 100000.0,
			"made_progress": true,
			## A retaliating species turns and fights the instant it is hit, rather
			## than only when it happens to be cornered. Distinct from
			## `threat_present`, which a predator's strike also sets to false — a boar
			## mauled by a leopard should run from the leopard, not turn on the player
			## who is not there.
			"struck": struck_by_player,
		})

	if is_dead():
		_die()


func _die() -> void:
	if _registry != null:
		_registry.remove(get_instance_id())
	died.emit(kind, global_position)
	var corpse: Node3D = Corpse.new()
	# Parented to the creature's parent, so the corpse outlives the animal.
	get_parent().add_child(corpse)
	corpse.global_position = global_position
	corpse.rotation.y = rotation.y
	corpse.configure(kind)
	queue_free()


func _collect_meshes() -> void:
	_meshes.clear()
	for child in get_children():
		if child is MeshInstance3D:
			_meshes.append(child)
		elif child is Node3D:
			for leg in (child as Node3D).get_children():
				if leg is MeshInstance3D:
					_meshes.append(leg)


func _apply_flash(on: bool) -> void:
	for mesh in _meshes:
		if is_instance_valid(mesh):
			# MeshInstance3D has no tint of its own, so the flash goes through the
			# material's emission. Each box gets its own material from the factory, so
			# this cannot leak between creatures.
			var material := mesh.material_override
			if material is StandardMaterial3D:
				(material as StandardMaterial3D).emission_enabled = on
				(material as StandardMaterial3D).emission = HIT_FLASH_COLOUR
				(material as StandardMaterial3D).emission_energy_multiplier = \
						1.4 if on else 0.0


func is_active() -> bool:
	return _active


func state_name() -> String:
	return _brain.state_name() if _brain != null else "idle"


func _physics_process(delta: float) -> void:
	if _brain == null or _map == null:
		return

	if _flash_countdown > 0.0:
		_flash_countdown -= delta
		if _flash_countdown <= 0.0:
			_apply_flash(false)

	_decision_countdown -= delta
	if _decision_countdown <= 0.0:
		_decision_countdown = DECISION_INTERVAL
		_decide()

	if not _active:
		return

	_update_attack(delta)
	_move(delta)


## Strikes whatever the brain is hunting while it says it is in range, on this species'
## own cadence.
##
## The cooldown lives here rather than in the brain, so a slower or faster animal is a
## number in the species table rather than a second brain. The brain names its target but
## never touches health: one is a decision, the other is a consequence.
func _update_attack(delta: float) -> void:
	if _attack_countdown > 0.0:
		_attack_countdown -= delta

	if not _brain.has_method(&"is_attacking") or not _brain.is_attacking():
		return
	if _attack_countdown > 0.0:
		return

	if _brain.has_method(&"is_hunting_quarry") and _brain.is_hunting_quarry():
		_strike_neighbour()
		return

	if _player == null or not is_instance_valid(_player):
		return
	_attack_countdown = CreatureKind.attack_interval(kind)
	if _player.has_method(&"stats"):
		var stats: RefCounted = _player.stats()
		if stats != null and not stats.is_dead():
			stats.damage(CreatureKind.attack_damage(kind))


## A strike on another animal. The kill is reported back to the brain, which is the only
## thing the brain cannot work out for itself.
func _strike_neighbour() -> void:
	if not is_instance_valid(_neighbour) or _neighbour.is_dead():
		return
	_attack_countdown = CreatureKind.attack_interval(kind)
	_neighbour.take_damage(CreatureKind.attack_damage(kind), global_position)
	if _neighbour.is_dead() and _brain.has_method(&"note_kill"):
		_brain.note_kill()
		_neighbour = null


## Re-decides. Only reached on the decision interval, so everything here is off the
## per-frame path.
func _decide() -> void:
	var to_player := INF
	if _player != null and is_instance_valid(_player):
		to_player = global_position.distance_to(_player.global_position)

	var was_active := _active
	_active = to_player <= ACTIVE_RADIUS_M
	if _active != was_active:
		_set_simulated(_active)
	if not _active:
		return

	# Only ever from here: the neighbour scan is on the decision path, five times a
	# second and only while awake, rather than on the per-frame path where sixty animals
	# looking each other up would be sixty times the work for the same answer.
	if _registry != null:
		_registry.move(get_instance_id(), global_position)
		_neighbour = _find_neighbour()

	# Progress is measured between decisions rather than between frames: a creature
	# pressed against a rock still jitters frame to frame, but covers no ground.
	var travelled := global_position.distance_to(_last_decision_position)
	_made_progress = travelled >= PROGRESS_EPSILON_M
	_last_decision_position = global_position

	var crouching := false
	if _player != null and _player.has_method(&"is_crouching"):
		crouching = _player.is_crouching()

	var sprinting := false
	if _player != null and _player.has_method(&"is_sprinting"):
		sprinting = _player.is_sprinting()

	var neighbour_at := Vector3.ZERO
	var neighbour_present := is_instance_valid(_neighbour)
	if neighbour_present:
		neighbour_at = _neighbour.global_position

	# Both brains are handed the neighbour under the name their own role cares about,
	# and each ignores the other. A predator hunts prey; prey runs from predators.
	_brain.tick(DECISION_INTERVAL, {
		"position": global_position,
		"anchor": _anchor,
		"threat_position": _player.global_position if _player != null \
				else Vector3.ZERO,
		"threat_present": _player != null and is_instance_valid(_player),
		"threat_crouching": crouching,
		"threat_sprinting": sprinting,
		"quarry_position": neighbour_at,
		"quarry_present": neighbour_present,
		"predator_position": neighbour_at,
		"predator_present": neighbour_present,
		"detection_m": CreatureKind.detection_m(kind),
		"health_fraction": health_fraction(),
		"made_progress": _made_progress,
	})


## The nearest animal of the opposite role, within the range this species can sense.
##
## Searched a little beyond detection, because the brains apply their own release margin
## and an animal that vanished from the search the instant it left detection range would
## make that margin meaningless.
func _find_neighbour() -> Node3D:
	var detection := CreatureKind.detection_m(kind)
	var wanted := CreatureKind.Role.PREDATOR
	if CreatureKind.is_predator(kind):
		wanted = CreatureKind.Role.PREY
		# Predators track animals further than they notice a person, and the search has
		# to reach as far as the brain is willing to look or the extra range is fiction.
		detection = PredatorBrain.quarry_range(detection)
	var found: Dictionary = _registry.nearest_of_role(global_position, wanted,
			detection * NEIGHBOUR_SEARCH_MARGIN, get_instance_id())
	if found.is_empty():
		return null
	var body: Variant = found.get("ref")
	return body if body is Node3D and is_instance_valid(body) else null


## Switches a creature between simulated and dormant.
##
## An AnimationPlayer costs CPU every frame whatever it is playing, so sixty of them
## ticking idle clips across the island is pure waste — stopping them outright is worth
## far more than switching the clip. Meshes are hidden at the same distance, since a
## creature too far away to think is also too far away to make out.
func _set_simulated(simulated: bool) -> void:
	if _animator != null:
		if simulated:
			_current_clip = ""
			_play(CreatureFactory.CLIP_IDLE)
		else:
			_animator.stop()
			_current_clip = ""
	for child in get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = simulated
		elif child is Node3D:
			# Leg pivots hold the leg meshes.
			for leg in (child as Node3D).get_children():
				if leg is MeshInstance3D:
					(leg as MeshInstance3D).visible = simulated


func _move(delta: float) -> void:
	var direction: Vector3 = _brain.desired_direction()
	if direction.length_squared() < 0.0001:
		_play(CreatureFactory.CLIP_IDLE)
		_settle()
		return

	# Prey run when they flee; predators run when they charge or break off. Both answer
	# the same two questions, so the body does not branch on species.
	var running: bool = _brain.is_running() if _brain.has_method(&"is_running") \
			else _brain.is_fleeing()
	var scale: float = _brain.speed_scale() if _brain.has_method(&"speed_scale") \
			else 1.0
	var speed := (CreatureKind.run_speed(kind) if running \
			else CreatureKind.walk_speed(kind)) * scale
	_play(CreatureFactory.CLIP_RUN if running else CreatureFactory.CLIP_WALK)

	var step := direction * speed * delta
	var target := global_position + step

	# Refuse anything the creature could not climb. Terrain is quantized, so this is a
	# comparison of two integers rather than a slope calculation.
	var here: int = _map.height_at_world(global_position.x, global_position.z)
	var there: int = _map.height_at_world(target.x, target.z)
	if absi(there - here) > int(ceil(MAX_CLIMB_M)):
		return

	# Off the island entirely, or into the sea.
	if there <= 0:
		return

	global_position.x = target.x
	global_position.z = target.z
	_settle()
	_face(direction, delta)


## Plants the creature on the terrain. The O(1) lookup that replaces navmesh and raycasts
## both.
func _settle() -> void:
	global_position.y = float(
			_map.height_at_world(global_position.x, global_position.z))


func _face(direction: Vector3, delta: float) -> void:
	var wanted := atan2(direction.x, direction.z)
	rotation.y = rotate_toward(rotation.y, wanted, TURN_RATE * delta)


func _play(clip: String) -> void:
	if _animator == null or clip == _current_clip:
		return
	_current_clip = clip
	if _animator.has_animation(clip):
		_animator.play(clip)
