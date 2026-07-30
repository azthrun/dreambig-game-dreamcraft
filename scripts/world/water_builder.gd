extends RefCounted
## Builds the water surfaces: one ocean plane, plus a quad per river cell.
##
## Two meshes rather than one, because rivers are not at sea level. They are carved
## downhill from high ground, so an inland river bed sits tens of metres above the
## sea; a single sea-level plane would leave every river dry. The ocean is therefore a
## single cheap plane and river cells each get a quad at their own bed height.
##
## Neither surface carries collision. That is what stops the player walking on water —
## there is nothing solid to stand on, so they fall through into the swim state.
##
## Pure data in, data out: no Node, no SceneTree.

const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

## How far above the river bed the water surface sits, in metres. Enough to read as
## water rather than as wet ground, without flooding the banks.
const RIVER_DEPTH_M := 0.6

## The ocean plane extends past the island so there is open water to the horizon
## rather than a visible edge.
const OCEAN_OVERHANG := 3.0

const COLOUR_WATER := Color(0.14, 0.38, 0.52, 0.72)


## Flat plane at sea level, sized to run past the island in every direction.
func build_ocean_plane(map: RefCounted) -> PlaneMesh:
	var plane := PlaneMesh.new()
	var extent: float = map.size_m() * OCEAN_OVERHANG
	plane.size = Vector2(extent, extent)
	return plane


## Surface for every river cell, each quad at its own bed height. Returns an empty
## mesh when the map has no rivers.
func build_river_surface(map: RefCounted) -> ArrayMesh:
	var cells: Array[Vector2i] = []
	for cz in map.cells_per_axis:
		for cx in map.cells_per_axis:
			if map.biome_at_cell(cx, cz) == Biome.Kind.RIVER:
				cells.append(Vector2i(cx, cz))

	var mesh := ArrayMesh.new()
	if cells.is_empty():
		return mesh

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(cells.size() * 6)
	normals.resize(cells.size() * 6)

	var cs: float = map.cell_size_m
	var half: float = map.size_m() * 0.5
	var cursor := 0

	for cell in cells:
		var x0 := float(cell.x) * cs - half
		var z0 := float(cell.y) * cs - half
		var x1 := x0 + cs
		var z1 := z0 + cs
		var y := float(map.height_at_cell(cell.x, cell.y)) + RIVER_DEPTH_M

		# Counter-clockwise seen from +Y, emitted reversed so the front face is
		# clockwise — the same convention the terrain mesher uses.
		var a := Vector3(x0, y, z0)
		var b := Vector3(x0, y, z1)
		var c := Vector3(x1, y, z1)
		var d := Vector3(x1, y, z0)
		for v in [a, c, b, a, d, c]:
			vertices[cursor] = v
			normals[cursor] = Vector3.UP
			cursor += 1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Translucent water material, drawn from both sides so the surface is still visible
## from underneath while swimming.
func build_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOUR_WATER
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.12
	material.metallic = 0.25
	# Water should not cast shadows onto the seabed.
	return material
