extends RefCounted
## The island's per-cell world grid: a quantized height and a biome per cell.
##
## Named for the heightmap because that is its load-bearing content, but it carries
## the biome classification on the same grid, since nothing ever needs one without
## the other.
##
## Heights are whole metres by construction — the terraced silhouette SPEC.md
## calls for depends on it, and so does the step-up rule in the player controller.
## Stored as integers so quantization cannot drift.
##
## This object is retained for the lifetime of the world rather than discarded once
## meshes are built. That is deliberate and load-bearing: creature ground queries
## read it directly as an O(1) lookup, which is what lets SPEC.md drop navmesh
## baking entirely.

## Height in metres at or below which a cell is underwater.
const SEA_LEVEL_M := 0

var cells_per_axis: int
var cell_size_m: float

## How many rivers were seeded, and how many of those reached the sea. Recorded by
## the generator so a river that dead-ends inland is detectable rather than merely
## invisible.
var river_sources: int = 0
var rivers_to_sea: int = 0

var _heights: PackedInt32Array
var _biomes: PackedByteArray


func _init(p_cells_per_axis: int, p_cell_size_m: float) -> void:
	cells_per_axis = p_cells_per_axis
	cell_size_m = p_cell_size_m
	var count := p_cells_per_axis * p_cells_per_axis
	_heights = PackedInt32Array()
	_heights.resize(count)
	_biomes = PackedByteArray()
	_biomes.resize(count)


## Total island extent in metres along one axis.
func size_m() -> float:
	return float(cells_per_axis) * cell_size_m


func in_bounds(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < cells_per_axis and cz < cells_per_axis


func set_height(cx: int, cz: int, height_m: int) -> void:
	_heights[cz * cells_per_axis + cx] = height_m


## Height at a cell. Out-of-range coordinates clamp to the nearest edge cell, so
## meshing and creature queries near the border need no special-casing.
func height_at_cell(cx: int, cz: int) -> int:
	var x := clampi(cx, 0, cells_per_axis - 1)
	var z := clampi(cz, 0, cells_per_axis - 1)
	return _heights[z * cells_per_axis + x]


func set_biome(cx: int, cz: int, kind: int) -> void:
	_biomes[cz * cells_per_axis + cx] = kind


## Biome at a cell, clamping out-of-range coordinates to the nearest edge.
func biome_at_cell(cx: int, cz: int) -> int:
	var x := clampi(cx, 0, cells_per_axis - 1)
	var z := clampi(cz, 0, cells_per_axis - 1)
	return _biomes[z * cells_per_axis + x]


func biome_at_world(world_x: float, world_z: float) -> int:
	var cell := world_to_cell(world_x, world_z)
	return biome_at_cell(cell.x, cell.y)


## Cell count per biome, keyed by Biome.Kind.
func biome_counts() -> Dictionary:
	var counts := {}
	for kind in _biomes:
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts


## Raw biome data. Exposed for determinism comparisons in tests.
func biomes() -> PackedByteArray:
	return _biomes


## World position (metres, island centred on the origin) to cell coordinates.
func world_to_cell(world_x: float, world_z: float) -> Vector2i:
	var half := size_m() * 0.5
	return Vector2i(
		floori((world_x + half) / cell_size_m),
		floori((world_z + half) / cell_size_m))


## Ground height in metres at a world position. The O(1) lookup creature
## locomotion depends on.
func height_at_world(world_x: float, world_z: float) -> int:
	var cell := world_to_cell(world_x, world_z)
	return height_at_cell(cell.x, cell.y)


func is_underwater(cx: int, cz: int) -> bool:
	return height_at_cell(cx, cz) <= SEA_LEVEL_M


func min_height() -> int:
	var lowest := _heights[0]
	for h in _heights:
		if h < lowest:
			lowest = h
	return lowest


func max_height() -> int:
	var highest := _heights[0]
	for h in _heights:
		if h > highest:
			highest = h
	return highest


## Fraction of cells above sea level. Used by tests to assert an island actually
## formed rather than the whole map drowning.
func land_fraction() -> float:
	var land := 0
	for h in _heights:
		if h > SEA_LEVEL_M:
			land += 1
	return float(land) / float(_heights.size())


## Raw height data. Exposed for determinism comparisons in tests.
func heights() -> PackedInt32Array:
	return _heights
