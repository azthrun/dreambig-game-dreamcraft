extends RefCounted
## Turns heightmap cells into terraced tile meshes.
##
## Each cell contributes a flat top quad at its own height, plus a vertical skirt
## quad on any side where the neighbour sits lower. That is what produces the
## stepped silhouette: the surface is not a smooth heightfield with ramps, it is
## flat plateaus joined by vertical faces.
##
## Vertices are not shared between faces, so every triangle carries its own normal
## and shading is flat with no smoothing across a step edge.
##
## Pure data in, data out: takes a heightmap, returns meshes and collision faces.
## No Node, no SceneTree.

const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

## Cells along one axis of a tile. The island splits into
## (cells_per_axis / TILE_CELLS)^2 tiles, each independently frustum-cullable.
const TILE_CELLS := 64

## Godot treats clockwise-wound triangles as front faces. Quads below are defined
## counter-clockwise as seen from their normal (right-hand rule), then emitted
## reversed to match.
##
## Winding is the one property a headless run cannot check — there is no rendering
## device to cull against. If terrain renders inside-out or invisible, flip this.
const FLIP_WINDING := false

## Per-biome colour, so the terrain reads as geography rather than as a height ramp.
const COLOUR_DEEP := Color(0.09, 0.17, 0.28)
const COLOUR_SHALLOW := Color(0.24, 0.42, 0.52)
const COLOUR_SAND := Color(0.81, 0.75, 0.55)
const COLOUR_PLAINS := Color(0.44, 0.58, 0.29)
const COLOUR_FOREST := Color(0.19, 0.36, 0.20)
const COLOUR_ROCK := Color(0.45, 0.43, 0.41)
const COLOUR_SNOW := Color(0.93, 0.95, 0.97)
const COLOUR_RIVER := Color(0.27, 0.50, 0.62)

## Mountains above this height wear snow. Purely visual; the biome is unchanged.
const SNOW_LINE_M := 70

## Ocean deeper than this uses the darker colour.
const DEEP_WATER_M := -12


func tiles_per_axis(map: RefCounted) -> int:
	return int(ceil(float(map.cells_per_axis) / float(TILE_CELLS)))


## Builds one tile. Returns { mesh: ArrayMesh, faces: PackedVector3Array,
## triangles: int }, where `faces` is the triangle soup for collision — the same
## geometry, so visuals and collision cannot disagree.
func build_tile(map: RefCounted, tile_x: int, tile_z: int) -> Dictionary:
	var cx0 := tile_x * TILE_CELLS
	var cz0 := tile_z * TILE_CELLS
	var cx1: int = mini(cx0 + TILE_CELLS, map.cells_per_axis)
	var cz1: int = mini(cz0 + TILE_CELLS, map.cells_per_axis)

	# Pass 1: count triangles so the arrays are sized once instead of growing.
	var triangles := 0
	for cz in range(cz0, cz1):
		for cx in range(cx0, cx1):
			triangles += 2
			var h: int = map.height_at_cell(cx, cz)
			for offset in [Vector2i(-1, 0), Vector2i(1, 0),
					Vector2i(0, -1), Vector2i(0, 1)]:
				if map.height_at_cell(cx + offset.x, cz + offset.y) < h:
					triangles += 2

	var vertex_count := triangles * 3
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	colours.resize(vertex_count)

	# Pass 2: fill.
	var cursor := 0
	var cs: float = map.cell_size_m
	var half: float = map.size_m() * 0.5

	for cz in range(cz0, cz1):
		var z0 := float(cz) * cs - half
		var z1 := z0 + cs
		for cx in range(cx0, cx1):
			var x0 := float(cx) * cs - half
			var x1 := x0 + cs
			var h: int = map.height_at_cell(cx, cz)
			var y := float(h)
			var colour := colour_for_cell(map.biome_at_cell(cx, cz), h)

			# Top face, counter-clockwise seen from +Y.
			cursor = _add_quad(vertices, normals, colours, cursor,
					Vector3(x0, y, z0), Vector3(x0, y, z1),
					Vector3(x1, y, z1), Vector3(x1, y, z0),
					Vector3.UP, colour)

			# Skirts, only where the neighbour is lower.
			var west: int = map.height_at_cell(cx - 1, cz)
			if west < h:
				var yl := float(west)
				cursor = _add_quad(vertices, normals, colours, cursor,
						Vector3(x0, yl, z0), Vector3(x0, yl, z1),
						Vector3(x0, y, z1), Vector3(x0, y, z0),
						Vector3.LEFT, colour)

			var east: int = map.height_at_cell(cx + 1, cz)
			if east < h:
				var yl := float(east)
				cursor = _add_quad(vertices, normals, colours, cursor,
						Vector3(x1, yl, z1), Vector3(x1, yl, z0),
						Vector3(x1, y, z0), Vector3(x1, y, z1),
						Vector3.RIGHT, colour)

			var north: int = map.height_at_cell(cx, cz - 1)
			if north < h:
				var yl := float(north)
				cursor = _add_quad(vertices, normals, colours, cursor,
						Vector3(x1, yl, z0), Vector3(x0, yl, z0),
						Vector3(x0, y, z0), Vector3(x1, y, z0),
						Vector3.FORWARD, colour)

			var south: int = map.height_at_cell(cx, cz + 1)
			if south < h:
				var yl := float(south)
				cursor = _add_quad(vertices, normals, colours, cursor,
						Vector3(x0, yl, z1), Vector3(x1, yl, z1),
						Vector3(x1, y, z1), Vector3(x0, y, z1),
						Vector3.BACK, colour)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours

	var mesh := ArrayMesh.new()
	if vertex_count > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return {
		"mesh": mesh,
		"faces": vertices,
		"triangles": triangles,
	}


## Material for terrain meshes.
##
## Lives here rather than with the spawning code because this module decides the vertex
## colours, and how they must be interpreted is part of that decision.
func build_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# One material covers the whole island; colour comes from the mesh.
	material.vertex_color_use_as_albedo = true
	# Vertex colours are authored in sRGB, the same space as the biome palette above.
	# Without this, Godot treats them as already-linear and every terrain colour renders
	# far too pale — a 0.45 grey arrives on screen at roughly 0.70. Props never showed
	# the problem because they use albedo_color, which Godot converts; only vertex
	# colours are passed through untouched.
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


## Colour for a cell, from its biome. Height is consulted only where a biome spans a
## visible range: ocean depth, and snow on high peaks.
func colour_for_cell(biome: int, height_m: int) -> Color:
	match biome:
		Biome.Kind.OCEAN:
			return COLOUR_DEEP if height_m <= DEEP_WATER_M else COLOUR_SHALLOW
		Biome.Kind.BEACH:
			return COLOUR_SAND
		Biome.Kind.PLAINS:
			return COLOUR_PLAINS
		Biome.Kind.FOREST:
			return COLOUR_FOREST
		Biome.Kind.MOUNTAINS:
			return COLOUR_SNOW if height_m >= SNOW_LINE_M else COLOUR_ROCK
		Biome.Kind.RIVER:
			return COLOUR_RIVER
	return COLOUR_PLAINS


## Appends a quad as two triangles. (a, b, c, d) must be counter-clockwise as seen
## from `normal`; they are emitted reversed so the front face is clockwise, which is
## Godot's convention. Returns the new cursor.
func _add_quad(vertices: PackedVector3Array, normals: PackedVector3Array,
		colours: PackedColorArray, cursor: int,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		normal: Vector3, colour: Color) -> int:
	var ordered: Array
	if FLIP_WINDING:
		ordered = [a, b, c, a, c, d]
	else:
		ordered = [a, c, b, a, d, c]
	for v in ordered:
		vertices[cursor] = v
		normals[cursor] = normal
		colours[cursor] = colour
		cursor += 1
	return cursor
