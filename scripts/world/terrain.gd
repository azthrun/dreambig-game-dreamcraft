extends Node3D
## Generates the island once and spawns it as static tiles.
##
## Presentation only: it owns no game state. The heightmap it holds is the
## authoritative data, produced by the generator and read by everything else.
##
## Generation happens once at startup rather than streaming, which is what the
## finite-island decision buys — no chunk residency, no LOD, no async load hitches.

const IslandGenerator := preload("res://scripts/world/island_generator.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const TerrainMesher := preload("res://scripts/world/terrain_mesher.gd")
const Biome := preload("res://scripts/world/biome.gd")
const WaterBuilder := preload("res://scripts/world/water_builder.gd")

## Any integer produces a complete, playable island. Fixed by default so a run is
## reproducible; a random seed per playthrough is a later concern.
@export var world_seed: int = 20260729

@export var generate_on_ready: bool = true

var _map: RefCounted
var _stats: Dictionary = {}


func _ready() -> void:
	if generate_on_ready:
		generate()


## The authoritative heightmap. Creature locomotion and shelter checks read this.
func heightmap() -> RefCounted:
	return _map


## Generation and meshing statistics from the last run.
func stats() -> Dictionary:
	return _stats


func generate() -> void:
	for child in get_children():
		child.queue_free()

	var gen_start := Time.get_ticks_usec()
	var generator: RefCounted = IslandGenerator.new()
	_map = generator.generate(world_seed)
	var gen_us := Time.get_ticks_usec() - gen_start

	var mesher: RefCounted = TerrainMesher.new()
	var material: Material = mesher.build_material()
	var per_axis: int = mesher.tiles_per_axis(_map)

	var mesh_start := Time.get_ticks_usec()
	var triangles := 0
	for tz in per_axis:
		for tx in per_axis:
			var built: Dictionary = mesher.build_tile(_map, tx, tz)
			triangles += int(built["triangles"])
			_spawn_tile(tx, tz, built, material)
	var mesh_us := Time.get_ticks_usec() - mesh_start

	_spawn_water()

	_stats = {
		"seed": world_seed,
		"cells_per_axis": _map.cells_per_axis,
		"cell_size_m": _map.cell_size_m,
		"size_m": _map.size_m(),
		"tiles": per_axis * per_axis,
		"triangles": triangles,
		"min_height_m": _map.min_height(),
		"max_height_m": _map.max_height(),
		"land_fraction": _map.land_fraction(),
		"generate_ms": gen_us / 1000.0,
		"mesh_ms": mesh_us / 1000.0,
		"river_sources": _map.river_sources,
		"rivers_to_sea": _map.rivers_to_sea,
		"biomes": _map.biome_counts(),
	}

	for line in stat_lines():
		print(line)


## Human-readable summary, shared by stdout and the on-screen overlay.
func stat_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if _stats.is_empty():
		lines.append("terrain: not generated")
		return lines
	lines.append("island: %.0fm across, %d cells @ %.0fm, %d tiles"
			% [_stats["size_m"], _stats["cells_per_axis"],
			_stats["cell_size_m"], _stats["tiles"]])
	lines.append("height: %dm to %dm, land %.1f%%"
			% [_stats["min_height_m"], _stats["max_height_m"],
			_stats["land_fraction"] * 100.0])
	lines.append("triangles: %d" % _stats["triangles"])
	lines.append("rivers: %d of %d reached the sea"
			% [_stats["rivers_to_sea"], _stats["river_sources"]])
	var counts: Dictionary = _stats["biomes"]
	var total := 0
	for kind in counts:
		total += int(counts[kind])
	var parts := PackedStringArray()
	for kind in Biome.ALL:
		var count := int(counts.get(kind, 0))
		parts.append("%s %.1f%%" % [Biome.name_of(kind), 100.0 * count / total])
	lines.append("biomes: %s" % ", ".join(parts))
	lines.append("generate: %.0fms, mesh: %.0fms"
			% [_stats["generate_ms"], _stats["mesh_ms"]])
	return lines


## Water surfaces get no collision at all, which is what makes the player fall
## through into the swim state instead of standing on the sea.
func _spawn_water() -> void:
	var builder: RefCounted = WaterBuilder.new()
	var material: Material = builder.build_material()

	var water := Node3D.new()
	water.name = "Water"
	add_child(water)

	var ocean := MeshInstance3D.new()
	ocean.name = "Ocean"
	ocean.mesh = builder.build_ocean_plane(_map)
	ocean.material_override = material
	ocean.position.y = float(Heightmap.SEA_LEVEL_M)
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.add_child(ocean)

	var rivers := MeshInstance3D.new()
	rivers.name = "Rivers"
	rivers.mesh = builder.build_river_surface(_map)
	rivers.material_override = material
	rivers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.add_child(rivers)


func _spawn_tile(tile_x: int, tile_z: int, built: Dictionary,
		material: Material) -> void:
	var faces: PackedVector3Array = built["faces"]
	if faces.is_empty():
		return

	var body := StaticBody3D.new()
	body.name = "Tile_%d_%d" % [tile_x, tile_z]
	add_child(body)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = built["mesh"]
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	# Collision is built from the very same triangles that are drawn, so the
	# surface the player walks on cannot disagree with the surface they see.
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	body.add_child(collider)
