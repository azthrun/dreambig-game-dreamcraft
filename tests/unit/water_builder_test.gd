extends "res://tests/test_case.gd"
## Tests the water surfaces.

const WaterBuilder := preload("res://scripts/world/water_builder.gd")
const Heightmap := preload("res://scripts/world/heightmap.gd")
const Biome := preload("res://scripts/world/biome.gd")

const CELLS := 8
const CELL_SIZE := 4.0


func _builder() -> RefCounted:
	return WaterBuilder.new()


func _map_with_river(bed_height: int) -> RefCounted:
	var map: RefCounted = Heightmap.new(CELLS, CELL_SIZE)
	for cz in CELLS:
		for cx in CELLS:
			map.set_height(cx, cz, 20)
			map.set_biome(cx, cz, Biome.Kind.PLAINS)
	# A three-cell river running inland, well above sea level.
	for cz in 3:
		map.set_height(2, cz, bed_height)
		map.set_biome(2, cz, Biome.Kind.RIVER)
	return map


func test_ocean_plane_extends_past_the_island() -> void:
	# Otherwise the sea has a visible edge instead of a horizon.
	var map: RefCounted = Heightmap.new(CELLS, CELL_SIZE)
	var plane: PlaneMesh = _builder().build_ocean_plane(map)
	assert_true(plane.size.x > map.size_m(),
			"ocean should reach beyond the island")
	assert_almost_eq(plane.size.x, plane.size.y, 0.001, "ocean should be square")


func test_river_surface_sits_above_its_own_bed_not_at_sea_level() -> void:
	# The whole reason rivers get their own mesh: an inland bed is tens of metres
	# above the sea, so a sea-level plane would leave it dry.
	var bed := 30
	var mesh: ArrayMesh = _builder().build_river_surface(_map_with_river(bed))
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_true(vertices.size() > 0, "river cells should produce geometry")
	var expected := float(bed) + WaterBuilder.RIVER_DEPTH_M
	for v in vertices:
		assert_almost_eq(v.y, expected, 0.001)


func test_river_surface_covers_exactly_the_river_cells() -> void:
	var mesh: ArrayMesh = _builder().build_river_surface(_map_with_river(30))
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	# Three cells, two triangles each, three vertices per triangle.
	assert_eq(vertices.size(), 3 * 2 * 3)


func test_map_without_rivers_produces_no_river_geometry() -> void:
	var map: RefCounted = Heightmap.new(CELLS, CELL_SIZE)
	for cz in CELLS:
		for cx in CELLS:
			map.set_biome(cx, cz, Biome.Kind.OCEAN)
	var mesh: ArrayMesh = _builder().build_river_surface(map)
	assert_eq(mesh.get_surface_count(), 0,
			"no rivers should mean no surface at all, not an empty one")


func test_water_material_is_translucent_and_double_sided() -> void:
	# Double-sided so the surface is still visible from underneath while swimming.
	var material: StandardMaterial3D = _builder().build_material()
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_true(material.albedo_color.a < 1.0, "water should be see-through")
	assert_eq(material.cull_mode, BaseMaterial3D.CULL_DISABLED)


func test_river_water_is_shallow_enough_to_wade() -> void:
	# Rivers are one cell wide and this shallow on purpose: they should be crossable
	# on foot, so they read as a feature of the landscape rather than as a barrier.
	const Player := preload("res://scripts/player/player.gd")
	assert_true(WaterBuilder.RIVER_DEPTH_M < Player.SWIM_SUBMERGE_HEIGHT,
			"a river should not be deep enough to trigger swimming")
