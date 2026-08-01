extends RefCounted
## Decides where props go, from the world grid and a seed.
##
## Pure: returns a list of placements as plain data. Nothing here builds a mesh or
## touches a Node, so density and biome rules are testable without a scene.
##
## Placement is derived entirely from the seed, so props are reproducible and never
## need saving — only which of them have been harvested does.

const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")
const PropKind := preload("res://scripts/world/props/prop_kind.gd")

## Trees stop at this height. Above it the mountains are bare rock, which is what
## makes a treeline visible from a distance.
const TREELINE_M := 44

## Chance per candidate cell, by prop kind and biome. Zero means the prop never
## appears there. Trees are dense in forest and sparse in plains, which is most of
## what makes the two biomes look different at ground level.
const DENSITY := {
	PropKind.Kind.TREE: {
		Biome.Kind.FOREST: 0.42,
		Biome.Kind.PLAINS: 0.035,
	},
	PropKind.Kind.ROCK_OUTCROP: {
		Biome.Kind.MOUNTAINS: 0.10,
		Biome.Kind.PLAINS: 0.012,
		Biome.Kind.BEACH: 0.010,
	},
	PropKind.Kind.BERRY_BUSH: {
		Biome.Kind.PLAINS: 0.055,
		Biome.Kind.FOREST: 0.030,
	},
	# Cover props. Rarer than harvestables on purpose: shelter should be somewhere you
	# head for, not something you are always standing in.
	PropKind.Kind.OVERHANG: {
		Biome.Kind.MOUNTAINS: 0.070,
	},
	PropKind.Kind.CAVE_MOUTH: {
		Biome.Kind.MOUNTAINS: 0.028,
	},
	PropKind.Kind.THICKET: {
		Biome.Kind.FOREST: 0.030,
	},
	# Supply caches. An order of magnitude rarer than anything else, and spread across
	# every land biome rather than concentrated: the reward for exploring has to be
	# somewhere you were not already going.
	PropKind.Kind.CACHE: {
		Biome.Kind.PLAINS: 0.0022,
		Biome.Kind.FOREST: 0.0026,
		Biome.Kind.MOUNTAINS: 0.0060,
		Biome.Kind.BEACH: 0.0030,
	},
}

## Overhangs and caves need a slope to sit against, so they are only considered on
## cells with a neighbour at least this far below — the same 2 m drop that the player
## cannot step up, which is what makes such a cell a hillside rather than a plateau.
const HILLSIDE_DROP_M := 2

## Cells are considered on a stride rather than every cell, so props cannot form a
## dense lattice at 4 m spacing.
const CELL_STRIDE := 2

## How far a prop may be nudged from its cell centre, as a fraction of cell size.
## Breaks up the underlying grid so placement does not read as a checkerboard.
const JITTER := 0.34


## Returns placements as dictionaries: kind, cell, position, yaw, scale.
func place(map: RefCounted, seed_value: int) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	# Offset from the world seed so props do not correlate with terrain noise.
	rng.seed = seed_value + 22013

	var cs: float = map.cell_size_m
	var half: float = map.size_m() * 0.5

	for cz in range(0, map.cells_per_axis, CELL_STRIDE):
		for cx in range(0, map.cells_per_axis, CELL_STRIDE):
			var biome: int = map.biome_at_cell(cx, cz)
			var height: int = map.height_at_cell(cx, cz)
			if height <= Heightmap.SEA_LEVEL_M:
				continue

			var kind := _roll_kind(biome, height, _is_hillside(map, cx, cz), rng)
			if kind < 0:
				continue

			# Placed exactly on the terrace top, so props neither float nor sink.
			var jitter_x := rng.randf_range(-JITTER, JITTER) * cs
			var jitter_z := rng.randf_range(-JITTER, JITTER) * cs
			var position := Vector3(
					float(cx) * cs - half + cs * 0.5 + jitter_x,
					float(height),
					float(cz) * cs - half + cs * 0.5 + jitter_z)

			placements.append({
				"kind": kind,
				"cell": Vector2i(cx, cz),
				# Stable identity, derived from the cell rather than from placement
				# order, so it survives the list being built differently. A save file
				# records the ids of opened caches, and an id that shifted with an
				# unrelated density change would un-loot every crate on the island.
				"id": cz * map.cells_per_axis + cx,
				"position": position,
				"yaw": rng.randf_range(0.0, TAU),
				"scale": rng.randf_range(0.82, 1.28),
			})

	return placements


## Picks a kind for a cell, or -1 for nothing. Rolls once per kind in a fixed order so
## the result depends only on the seed and not on iteration order elsewhere.
func _roll_kind(biome: int, height: int, hillside: bool,
		rng: RandomNumberGenerator) -> int:
	for kind in PropKind.ALL:
		var by_biome: Dictionary = DENSITY[kind]
		var chance: float = by_biome.get(biome, 0.0)
		if kind == PropKind.Kind.TREE and height > TREELINE_M:
			chance = 0.0
		if not hillside and (kind == PropKind.Kind.OVERHANG
				or kind == PropKind.Kind.CAVE_MOUTH):
			chance = 0.0
		# Rolled even when the chance is zero, so the random sequence — and therefore
		# every later placement — does not shift with the biome layout.
		if rng.randf() < chance:
			return kind
	return -1


## True when some neighbour sits far enough below to count as a slope face.
func _is_hillside(map: RefCounted, cx: int, cz: int) -> bool:
	var here: int = map.height_at_cell(cx, cz)
	for offset in [Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(0, -1), Vector2i(0, 1)]:
		if here - map.height_at_cell(cx + offset.x, cz + offset.y) >= HILLSIDE_DROP_M:
			return true
	return false
