extends Node3D
## Spawns the island's animals, weighted by biome.
##
## Placement is derived from the world seed, so a given island is populated the same way
## every time and the population never needs saving — only which animals have been killed
## will, once persistence exists.

const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const CreatureBody := preload("res://scripts/creatures/creature_body.gd")
const DragonBody := preload("res://scripts/creatures/dragon_body.gd")
const Population := preload("res://scripts/creatures/population.gd")
const CreatureRegistry := preload("res://scripts/creatures/creature_registry.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const DragonNest := preload("res://scripts/world/dragon_nest.gd")

## Total animals on the island.
##
## A cap rather than a density: the island is a fixed size, so a number is easier to reason
## about than a rate, and it puts a hard ceiling on the per-frame cost. Per-species caps
## live in the species table beside the rest of what makes a species itself.
##
## Set to the sum of every species' own cap (40 + 20 + 9 + 7 + 4), so a full population of
## everything fits without any one species crowding another out of the places that are
## left — the same reasoning that set deer's own cap below the old total. Raised from 60
## when the boar was added; re-measure rather than assume the extra animals are free.
const POPULATION := 80

## Attempts before giving up on placing one. Generous, since most cells are ocean.
const MAX_ATTEMPTS := 8000

var _counts: Dictionary = {}
var _creatures: Array[Node3D] = []
## Shared by every animal, so a predator can find a deer and a deer can find the
## predator without either walking the scene tree.
var _registry: RefCounted = CreatureRegistry.new()


func registry() -> RefCounted:
	return _registry


func populate(map: RefCounted, player: Node3D, seed_value: int) -> Dictionary:
	for child in get_children():
		child.queue_free()
	_creatures.clear()
	_counts = {}
	_registry = CreatureRegistry.new()

	var rng := RandomNumberGenerator.new()
	# Offset so animal placement does not correlate with terrain or prop noise.
	rng.seed = seed_value + 5150
	# Weighting and both kinds of cap live in the pure class, which is where they are
	# tested; this loop only picks cells and builds bodies.
	var population: RefCounted = Population.new(seed_value + 5151, POPULATION)

	var attempts := 0
	while not population.is_full() and attempts < MAX_ATTEMPTS:
		attempts += 1
		var cx := rng.randi_range(1, map.cells_per_axis - 2)
		var cz := rng.randi_range(1, map.cells_per_axis - 2)
		if map.height_at_cell(cx, cz) <= Heightmap.SEA_LEVEL_M:
			continue

		var kind: int = population.roll(map.biome_at_cell(cx, cz))
		if kind < 0:
			continue

		_spawn(kind, map, player, _world_position(map, cx, cz),
				rng.randi(), rng.randf_range(0.0, TAU))
		population.record(kind)

	_counts = population.counts()

	# Outside the general roll on purpose — see `creature_kind.gd`. Nest sites are
	# deliberate, not density, so they are placed and counted separately.
	var nests := DragonNest.sites(
			map, seed_value, CreatureKind.max_population(CreatureKind.Kind.DRAGON))
	for nest_position in nests:
		_spawn_dragon(nest_position, map, player, rng.randi())
	_counts[CreatureKind.Kind.DRAGON] = nests.size()

	return _counts


func counts() -> Dictionary:
	return _counts


func creatures() -> Array[Node3D]:
	return _creatures


## One-off summary for the boot report, so what actually spawned is visible in a
## headless run rather than only in the live overlay.
func stat_lines() -> PackedStringArray:
	var parts := PackedStringArray()
	var total := 0
	for kind in CreatureKind.ALL:
		var count := int(_counts.get(kind, 0))
		total += count
		parts.append("%s %d" % [CreatureKind.name_of(kind), count])
	var lines := PackedStringArray()
	lines.append("creatures: %d total (%s)" % [total, ", ".join(parts)])
	return lines


func status_line() -> String:
	var active := 0
	var hunting := 0
	for creature in _creatures:
		if not is_instance_valid(creature) or not creature.is_active():
			continue
		active += 1
		# Predators hunting animals rather than the player. Reported because it is
		# otherwise invisible: it happens wherever the deer are, not wherever the
		# player is looking.
		var brain: RefCounted = creature.brain()
		if brain != null and brain.has_method(&"is_hunting_quarry") \
				and brain.is_hunting_quarry():
			hunting += 1
	var parts := PackedStringArray()
	for kind in CreatureKind.ALL:
		parts.append("%s %d" % [CreatureKind.name_of(kind),
				int(_counts.get(kind, 0))])
	return "creatures: %s (%d thinking, %d hunting)" % [", ".join(parts), active,
			hunting]


func _spawn(kind: int, map: RefCounted, player: Node3D, position: Vector3,
		seed_value: int, yaw: float) -> void:
	var creature: Node3D = CreatureBody.new()
	creature.name = "%s_%d" % [CreatureKind.name_of(kind), _creatures.size()]
	add_child(creature)
	creature.global_position = position
	creature.rotation.y = yaw
	creature.configure(kind, map, player, seed_value, _registry)
	_creatures.append(creature)


## A dragon at a chosen nest site, on the ground — it climbs to its patrol altitude
## itself once it wakes, the same as any other creature waking from dormancy.
func _spawn_dragon(position: Vector3, map: RefCounted, player: Node3D,
		seed_value: int) -> void:
	var dragon: Node3D = DragonBody.new()
	dragon.name = "dragon_%d" % _creatures.size()
	add_child(dragon)
	dragon.global_position = position
	dragon.configure(CreatureKind.Kind.DRAGON, map, player, seed_value, _registry)
	_creatures.append(dragon)


func _world_position(map: RefCounted, cx: int, cz: int) -> Vector3:
	var half: float = map.size_m() * 0.5
	var cell_size: float = map.cell_size_m
	return Vector3(
			float(cx) * cell_size - half + cell_size * 0.5,
			float(map.height_at_cell(cx, cz)),
			float(cz) * cell_size - half + cell_size * 0.5)
