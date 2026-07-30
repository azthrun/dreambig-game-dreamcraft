extends "res://tests/test_case.gd"
## Tests terraced meshing against hand-built heightmaps.
##
## Hand-built rather than generated: a 4x4 map with known heights makes the exact
## triangle count predictable, which is the only way to prove skirts appear exactly
## where a neighbour is lower and nowhere else.

const TerrainMesher := preload("res://scripts/world/terrain_mesher.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

const CELLS := 4
const CELL_SIZE := 4.0


func _flat_map(height_m: int) -> RefCounted:
	var map: RefCounted = Heightmap.new(CELLS, CELL_SIZE)
	for cz in CELLS:
		for cx in CELLS:
			map.set_height(cx, cz, height_m)
	return map


func _mesher() -> RefCounted:
	return TerrainMesher.new()


func test_flat_terrain_produces_only_top_faces() -> void:
	# No height differences means no skirts: two triangles per cell, nothing more.
	var built: Dictionary = _mesher().build_tile(_flat_map(5), 0, 0)
	assert_eq(built["triangles"], CELLS * CELLS * 2)


func test_a_raised_cell_adds_exactly_four_skirts() -> void:
	var map := _flat_map(0)
	map.set_height(1, 1, 3)
	var built: Dictionary = _mesher().build_tile(map, 0, 0)
	# Base 32, plus 4 vertical quads (2 triangles each) around the raised cell.
	assert_eq(built["triangles"], CELLS * CELLS * 2 + 8)


func test_a_lowered_cell_adds_skirts_to_its_neighbours() -> void:
	# A pit is skirted by the four cells around it, not by the pit itself.
	var map := _flat_map(0)
	map.set_height(1, 1, -3)
	var built: Dictionary = _mesher().build_tile(map, 0, 0)
	assert_eq(built["triangles"], CELLS * CELLS * 2 + 8)


func test_vertex_count_matches_triangle_count() -> void:
	var built: Dictionary = _mesher().build_tile(_flat_map(2), 0, 0)
	var mesh: ArrayMesh = built["mesh"]
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(vertices.size(), int(built["triangles"]) * 3)


func test_collision_faces_are_the_drawn_geometry() -> void:
	# Same triangle soup for both, so the surface walked on cannot drift from the
	# surface seen.
	var built: Dictionary = _mesher().build_tile(_flat_map(2), 0, 0)
	var mesh: ArrayMesh = built["mesh"]
	var drawn: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var faces: PackedVector3Array = built["faces"]
	assert_eq(faces.size(), drawn.size())
	assert_eq(faces, drawn)
	assert_eq(faces.size() % 3, 0, "collision faces must be whole triangles")


## Tolerance for normals read back out of an ArrayMesh.
##
## Godot compresses normals in mesh surfaces, so a normal written as exactly
## (0, 1, 0) reads back as roughly (0, 1, -0.000015). Comparisons must therefore be
## angular, not exact — is_equal_approx is too strict for a mesh round-trip.
const NORMAL_TOLERANCE := 0.999


func test_flat_terrain_normals_all_point_up() -> void:
	var built: Dictionary = _mesher().build_tile(_flat_map(7), 0, 0)
	var normals: PackedVector3Array = built["mesh"].surface_get_arrays(0)[
			Mesh.ARRAY_NORMAL]
	var wrong := 0
	for n in normals:
		if n.normalized().dot(Vector3.UP) < NORMAL_TOLERANCE:
			wrong += 1
	assert_eq(wrong, 0, "flat terrain should have only upward normals")


func test_winding_is_reversed_against_the_shading_normal() -> void:
	# Godot treats clockwise-wound triangles as front faces, so the right-hand-rule
	# normal derived from vertex order is the opposite of the shading normal. Pinning
	# that relationship catches an accidental winding flip, which would otherwise
	# only show up as invisible terrain on screen.
	var built: Dictionary = _mesher().build_tile(_flat_map(1), 0, 0)
	var arrays: Array = built["mesh"].surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	var checked := 0
	var mismatched := 0
	for tri in range(0, vertices.size(), 3):
		var geometric := (vertices[tri + 1] - vertices[tri]).cross(
				vertices[tri + 2] - vertices[tri]).normalized()
		if geometric.length() < 0.5:
			continue  # degenerate, skip
		checked += 1
		if geometric.dot(-normals[tri].normalized()) < NORMAL_TOLERANCE:
			mismatched += 1
	assert_true(checked > 0, "should have inspected some triangles")
	assert_eq(mismatched, 0,
			"winding must stay opposite the shading normal (FLIP_WINDING)")


func test_tile_geometry_stays_inside_its_own_footprint() -> void:
	# Tiles must not overlap, or frustum culling would draw neighbours twice.
	var map := _flat_map(0)
	map.set_height(2, 2, 6)
	var built: Dictionary = _mesher().build_tile(map, 0, 0)
	var half: float = map.size_m() * 0.5
	var vertices: PackedVector3Array = built["faces"]
	var outside := 0
	for v in vertices:
		if v.x < -half - 0.001 or v.x > half + 0.001:
			outside += 1
		elif v.z < -half - 0.001 or v.z > half + 0.001:
			outside += 1
	assert_eq(outside, 0, "no vertex may fall outside the island footprint")


func test_tiles_cover_the_whole_heightmap() -> void:
	var map := _flat_map(0)
	var per_axis: int = _mesher().tiles_per_axis(map)
	assert_true(per_axis >= 1)
	assert_true(per_axis * TerrainMesher.TILE_CELLS >= map.cells_per_axis,
			"tile grid must cover every cell")


func test_each_biome_gets_its_own_colour() -> void:
	var mesher := _mesher()
	var seen := {}
	for kind in Biome.ALL:
		var colour: Color = mesher.colour_for_cell(kind, 10)
		assert_false(seen.has(colour),
				"%s shares a colour with another biome" % Biome.name_of(kind))
		seen[colour] = true


func test_colour_reflects_depth_and_snow_within_a_biome() -> void:
	var mesher := _mesher()
	assert_eq(mesher.colour_for_cell(Biome.Kind.OCEAN, -20),
			TerrainMesher.COLOUR_DEEP)
	assert_eq(mesher.colour_for_cell(Biome.Kind.OCEAN, -2),
			TerrainMesher.COLOUR_SHALLOW)
	assert_eq(mesher.colour_for_cell(Biome.Kind.MOUNTAINS, 55),
			TerrainMesher.COLOUR_ROCK)
	assert_eq(mesher.colour_for_cell(Biome.Kind.MOUNTAINS, 90),
			TerrainMesher.COLOUR_SNOW)
