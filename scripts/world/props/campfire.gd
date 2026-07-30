extends Node3D
## A placed campfire: burns fuel, gives light and warmth, and goes out.
##
## The other half of the answer to cold. Shelter gets you out of the weather where you
## happen to be standing; a fire is warmth you can put where you choose, at the cost of
## wood you had to gather.
##
## Fuel is advanced by an injected delta so burn-down is testable without waiting three
## minutes for it.

const TemperatureModel := preload("res://scripts/world/temperature_model.gd")
const ProceduralAudio := preload("res://scripts/audio/procedural_audio.gd")

signal went_out

## How far the warmth reaches, and how much it adds at the centre.
##
## Sized against the temperature model: a stormy night on open ground sits near -9 C, so
## 16 C at the fire is enough to make standing beside it survivable while a step away is
## not.
const HEAT_RADIUS_M := 6.0
const HEAT_STRENGTH_C := 16.0

## Seconds of burn a fresh fire starts with, what one wood adds, and the ceiling.
const INITIAL_FUEL_SECONDS := 180.0
const FUEL_PER_WOOD_SECONDS := 90.0
const MAX_FUEL_SECONDS := 600.0

## Steeper than this and a fire cannot be placed: it would sit half-buried in a terrace
## face. Matches the player's own walkable limit.
const MAX_GROUND_SLOPE_DEGREES := 40.0

var _fuel := 0.0
var _burning := false

var _light: OmniLight3D
var _flames: GPUParticles3D
var _audio: AudioStreamPlayer3D
var _flicker := 0.0


## Whether a point is somewhere a fire can go: solid, level enough, and out of the water.
##
## Static and pure so the rule can be asserted without placing anything.
static func is_valid_ground(point: Vector3, normal: Vector3,
		sea_level_y: float) -> bool:
	if point.y <= sea_level_y:
		return false
	var slope := rad_to_deg(normal.angle_to(Vector3.UP))
	return slope <= MAX_GROUND_SLOPE_DEGREES


func _ready() -> void:
	_build()
	light(INITIAL_FUEL_SECONDS)


func is_burning() -> bool:
	return _burning


func fuel_remaining() -> float:
	return _fuel


## Lights the fire with a given amount of fuel.
func light(seconds: float) -> void:
	_fuel = clampf(seconds, 0.0, MAX_FUEL_SECONDS)
	_burning = _fuel > 0.0
	_apply_state()


## Adds fuel to a burning fire, or relights a dead one. Returns whether it was accepted —
## a fire already at capacity refuses, so wood is not wasted on it.
func add_fuel(seconds: float = FUEL_PER_WOOD_SECONDS) -> bool:
	if seconds <= 0.0 or _fuel >= MAX_FUEL_SECONDS:
		return false
	_fuel = minf(_fuel + seconds, MAX_FUEL_SECONDS)
	if not _burning:
		_burning = true
	_apply_state()
	return true


## Warmth contributed at a position. Zero once the fire is out, which is what makes an
## extinguished fire stop helping rather than merely dim.
func heat_at(position: Vector3) -> float:
	if not _burning:
		return 0.0
	return TemperatureModel.heat_from_source(
			_origin().distance_to(position), HEAT_RADIUS_M, HEAT_STRENGTH_C)


## Where the fire is. global_position is only meaningful inside the tree, and warmth is
## worth asking about for a fire that has been built but not yet parented.
func _origin() -> Vector3:
	return global_position if is_inside_tree() else position


func tick(delta: float) -> void:
	if not _burning or delta <= 0.0:
		return
	_fuel = maxf(_fuel - delta, 0.0)
	if _fuel <= 0.0:
		_burning = false
		_apply_state()
		went_out.emit()


func _process(delta: float) -> void:
	tick(delta)
	if _burning and _light != null:
		# A little flicker, so a fire reads as alive rather than as a lamp.
		_flicker += delta * 9.0
		_light.light_energy = 2.6 + sin(_flicker) * 0.35 \
				+ sin(_flicker * 2.7) * 0.18


func _apply_state() -> void:
	if _light != null:
		_light.visible = _burning
	if _flames != null:
		_flames.emitting = _burning
	if _audio != null:
		if _burning and not _audio.playing:
			_audio.play()
		elif not _burning and _audio.playing:
			_audio.stop()


func status_line() -> String:
	if not _burning:
		return "campfire: out"
	return "campfire: burning, %.0fs left" % _fuel


func _build() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.38, 0.36, 0.34)
	stone.roughness = 0.95

	# A ring of stones around a couple of logs, in keeping with the cuboid look.
	for i in 6:
		var angle := TAU * float(i) / 6.0
		_add_box(Vector3(cos(angle) * 0.62, 0.11, sin(angle) * 0.62),
				Vector3(0.28, 0.22, 0.28), stone)

	var log_material := StandardMaterial3D.new()
	log_material.albedo_color = Color(0.29, 0.19, 0.12)
	log_material.roughness = 0.95
	_add_box(Vector3(0.0, 0.12, 0.0), Vector3(0.9, 0.16, 0.18), log_material)
	_add_box(Vector3(0.0, 0.12, 0.0), Vector3(0.18, 0.16, 0.9), log_material)

	_light = OmniLight3D.new()
	_light.name = "FireLight"
	_light.position = Vector3(0.0, 0.7, 0.0)
	_light.light_color = Color(1.0, 0.63, 0.28)
	_light.omni_range = HEAT_RADIUS_M * 2.4
	_light.shadow_enabled = false
	add_child(_light)

	_flames = GPUParticles3D.new()
	_flames.name = "Flames"
	_flames.amount = 40
	_flames.lifetime = 0.85
	_flames.position = Vector3(0.0, 0.2, 0.0)
	_flames.draw_pass_1 = _flame_mesh()
	_flames.process_material = _flame_process()
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Particles are culled against this box rather than where they end up, so it has to
	# cover the whole flame.
	_flames.visibility_aabb = AABB(
			Vector3(-1.0, -0.5, -1.0), Vector3(2.0, 3.0, 2.0))
	add_child(_flames)

	_audio = AudioStreamPlayer3D.new()
	_audio.name = "FireAudio"
	_audio.stream = ProceduralAudio.fire()
	_audio.unit_size = HEAT_RADIUS_M
	_audio.max_distance = HEAT_RADIUS_M * 3.0
	_audio.volume_db = -8.0
	add_child(_audio)


func _add_box(offset: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	add_child(instance)


func _flame_mesh() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.16, 0.16)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.55, 0.16)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.48, 0.12)
	material.emission_energy_multiplier = 2.2
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	return mesh


func _flame_process() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.22
	material.direction = Vector3(0.0, 1.0, 0.0)
	material.spread = 12.0
	material.initial_velocity_min = 0.8
	material.initial_velocity_max = 1.6
	material.gravity = Vector3(0.0, 0.6, 0.0)
	material.scale_min = 0.3
	material.scale_max = 1.0
	# Shrinking as they rise reads as flame rather than as confetti.
	var curve := CurveTexture.new()
	var shape := Curve.new()
	shape.add_point(Vector2(0.0, 1.0))
	shape.add_point(Vector2(1.0, 0.0))
	curve.curve = shape
	material.scale_curve = curve
	return material
