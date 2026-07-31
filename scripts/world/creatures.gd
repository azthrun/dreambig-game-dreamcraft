extends Node3D
## Spawns the island's animals, weighted by biome.
##
## Placement is derived from the world seed, so a given island is populated the same way
## every time and the population never needs saving — only which animals have been killed
## will, once persistence exists.

const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const CreatureBody := preload("res://scripts/creatures/creature_body.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")

## Total animals on the island.
##
## A cap rather than a density: the island is a fixed size, so a number is easier to reason
## about than a rate, and it puts a hard ceiling on the per-frame cost.
const POPULATION := 60

## Attempts before giving up on placing one. Generous, since most cells are ocean.
const MAX_ATTEMPTS := 8000

var _counts: Dictionary = {}
var _creatures: Array[Node3D] = []


func populate(map: RefCounted, player: Node3D, seed_value: int) -> Dictionary:
	for child in get_children():
		child.queue_free()
	_creatures.clear()
	_counts = {}

	var rng := RandomNumberGenerator.new()
	# Offset so animal placement does not correlate with terrain or prop noise.
	rng.seed = seed_value + 5150

	var attempts := 0
	while _creatures.size() < POPULATION and attempts < MAX_ATTEMPTS:
		attempts += 1
		var cx := rng.randi_range(1, map.cells_per_axis - 2)
		var cz := rng.randi_range(1, map.cells_per_axis - 2)
		if map.height_at_cell(cx, cz) <= Heightmap.SEA_LEVEL_M:
			continue

		var kind := _roll_kind(map.biome_at_cell(cx, cz), rng)
		if kind < 0:
			continue

		_spawn(kind, map, player, _world_position(map, cx, cz),
				rng.randi(), rng.randf_range(0.0, TAU))

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
	for creature in _creatures:
		if is_instance_valid(creature) and creature.is_active():
			active += 1
	var parts := PackedStringArray()
	for kind in CreatureKind.ALL:
		parts.append("%s %d" % [CreatureKind.name_of(kind),
				int(_counts.get(kind, 0))])
	return "creatures: %s (%d thinking)" % [", ".join(parts), active]


## Picks a species for a biome, weighted, or -1 for nothing here.
func _roll_kind(biome: int, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for kind in CreatureKind.ALL:
		total += CreatureKind.biome_weight(kind, biome)
	if total <= 0.0:
		return -1

	var roll := rng.randf() * total
	var accumulated := 0.0
	for kind in CreatureKind.ALL:
		accumulated += CreatureKind.biome_weight(kind, biome)
		if roll <= accumulated:
			return kind
	return -1


func _spawn(kind: int, map: RefCounted, player: Node3D, position: Vector3,
		seed_value: int, yaw: float) -> void:
	var creature: Node3D = CreatureBody.new()
	creature.name = "%s_%d" % [CreatureKind.name_of(kind), _creatures.size()]
	add_child(creature)
	creature.global_position = position
	creature.rotation.y = yaw
	creature.configure(kind, map, player, seed_value)
	_creatures.append(creature)
	_counts[kind] = int(_counts.get(kind, 0)) + 1


func _world_position(map: RefCounted, cx: int, cz: int) -> Vector3:
	var half: float = map.size_m() * 0.5
	var cell_size: float = map.cell_size_m
	return Vector3(
			float(cx) * cell_size - half + cell_size * 0.5,
			float(map.height_at_cell(cx, cz)),
			float(cz) * cell_size - half + cell_size * 0.5)
