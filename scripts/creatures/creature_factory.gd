extends RefCounted
## Builds a creature body from boxes, with limbs on pivots and clips to swing them.
##
## Same approach Minecraft uses for its animals and the same one this project uses for
## everything else: there is no 3D art, so a body is eight boxes assembled to known
## proportions. Legs hang from pivot nodes so a rotation swings the whole limb, which is
## all the animation a cuboid animal needs.
##
## Species differ by proportion, colour, coat pattern and gait — all of them entries in
## the species table — so the remaining animals reuse this whole file.

const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")

## Names of the clips every creature has, so the body can switch between them without
## knowing which species it is.
const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_RUN := "run"

## How far the legs swing, in degrees, and how fast each gait plays. Fallbacks: a species
## states its own in the table, so a heavy cat does not walk like a deer.
const WALK_SWING_DEGREES := 22.0
const RUN_SWING_DEGREES := 42.0
const WALK_CYCLE_SECONDS := 0.9
const RUN_CYCLE_SECONDS := 0.42


## Builds the visual body under `parent` and returns the AnimationPlayer driving it.
func build(parent: Node3D, kind: int) -> AnimationPlayer:
	var shape: Dictionary = CreatureKind.body(kind)
	var height := float(shape.get("height", 1.4))
	var length := float(shape.get("length", 1.6))
	var width := float(shape.get("width", 0.7))
	var body_colour: Color = shape.get("body_colour", Color(0.5, 0.4, 0.3))
	var head_colour: Color = shape.get("head_colour", body_colour)
	var leg_colour: Color = shape.get("leg_colour", body_colour.darkened(0.3))

	# Torso sits at two thirds of the height; legs make up the rest.
	var leg_length := height * 0.42
	var torso_y := leg_length + (height - leg_length) * 0.5

	_box(parent, Vector3(0.0, torso_y, 0.0),
			Vector3(width, height - leg_length, length), body_colour)

	# Head and neck, forward along -Z, which is the direction a body faces.
	var head_y := torso_y + (height - leg_length) * 0.42
	_box(parent, Vector3(0.0, head_y, -length * 0.42),
			Vector3(width * 0.55, width * 0.55, length * 0.34), head_colour)

	# The coat pattern breaks up the torso so a tan predator is not mistaken for a tan
	# deer at a glance, which matters when one of them can kill you. Three cats of
	# similar shape need it against each other too.
	var torso_height := height - leg_length
	var marking_colour: Color = shape.get("marking_colour", body_colour.darkened(0.5))
	match int(shape.get("markings", CreatureKind.Marking.NONE)):
		CreatureKind.Marking.SPOTS:
			_spots(parent, torso_y, torso_height, length, width, marking_colour)
		CreatureKind.Marking.STRIPES:
			_stripes(parent, torso_y, torso_height, length, width, marking_colour)

	# The mane is the lion's whole silhouette at range: a maneless tan cat would read as
	# a large leopard that had lost its spots.
	if bool(shape.get("mane", false)):
		var mane_colour: Color = shape.get("mane_colour", body_colour.darkened(0.55))
		_box(parent, Vector3(0.0, head_y - torso_height * 0.06, -length * 0.30),
				Vector3(width * 1.32, torso_height * 1.24, length * 0.2), mane_colour)

	var legs: Array[Node3D] = []
	var offsets := [
		Vector3(width * 0.32, leg_length, -length * 0.32),
		Vector3(-width * 0.32, leg_length, -length * 0.32),
		Vector3(width * 0.32, leg_length, length * 0.32),
		Vector3(-width * 0.32, leg_length, length * 0.32),
	]
	for offset in offsets:
		# A pivot at the hip, with the leg hanging below it, so rotating the pivot
		# swings the whole limb from the top rather than spinning it about its middle.
		var pivot := Node3D.new()
		pivot.position = offset
		parent.add_child(pivot)
		_box(pivot, Vector3(0.0, -leg_length * 0.5, 0.0),
				Vector3(width * 0.24, leg_length, width * 0.24), leg_colour)
		legs.append(pivot)

	return _build_animations(parent, legs, CreatureKind.gait(kind))


## Scattered spots, on the flanks and over the back.
##
## The back matters as much as the flanks: the first shot of a leopard at eleven metres —
## inside its charge range — showed a plain tan animal, because the only view of it was
## from above and behind and every spot was on a side face.
func _spots(parent: Node3D, torso_y: float, torso_height: float, length: float,
		width: float, colour: Color) -> void:
	var rng := RandomNumberGenerator.new()
	# Fixed seed: every leopard wears the same coat, which is cheaper than storing one
	# per animal and no player will ever compare two.
	rng.seed = 4242
	for _i in 9:
		var along := rng.randf_range(-0.38, 0.38) * length
		var around := rng.randf_range(-0.3, 0.3) * torso_height
		_box(parent, Vector3(width * 0.51, torso_y + around, along),
				Vector3(0.02, 0.22, 0.28), colour)
		_box(parent, Vector3(-width * 0.51, torso_y + around, along),
				Vector3(0.02, 0.22, 0.28), colour)
	for _i in 7:
		var along := rng.randf_range(-0.36, 0.36) * length
		var across := rng.randf_range(-0.3, 0.3) * width
		_box(parent, Vector3(across, torso_y + torso_height * 0.51, along),
				Vector3(0.2, 0.02, 0.26), colour)


## Bands wrapping the torso, evenly spaced along it.
##
## Regular rather than scattered, and over the back as well as the flanks: that is what
## separates a tiger from a leopard when both are small in the frame, and the back is
## what the player sees from above on a slope.
func _stripes(parent: Node3D, torso_y: float, torso_height: float, length: float,
		width: float, colour: Color) -> void:
	var count := 6
	var thickness := length * 0.055
	for index in count:
		var t := (float(index) + 0.5) / float(count)
		var along := lerpf(-0.4, 0.4, t) * length
		_box(parent, Vector3(width * 0.51, torso_y, along),
				Vector3(0.02, torso_height * 0.82, thickness), colour)
		_box(parent, Vector3(-width * 0.51, torso_y, along),
				Vector3(0.02, torso_height * 0.82, thickness), colour)
		_box(parent, Vector3(0.0, torso_y + torso_height * 0.51, along),
				Vector3(width * 0.86, 0.02, thickness), colour)


func _build_animations(parent: Node3D, legs: Array[Node3D],
		gait: Dictionary) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	parent.add_child(player)

	var library := AnimationLibrary.new()
	library.add_animation(CLIP_IDLE, _clip(parent, legs, 0.0, 1.0))
	library.add_animation(CLIP_WALK, _clip(parent, legs,
			float(gait.get("walk_swing", WALK_SWING_DEGREES)),
			float(gait.get("walk_cycle", WALK_CYCLE_SECONDS))))
	library.add_animation(CLIP_RUN, _clip(parent, legs,
			float(gait.get("run_swing", RUN_SWING_DEGREES)),
			float(gait.get("run_cycle", RUN_CYCLE_SECONDS))))
	player.add_animation_library("", library)
	return player


## One gait. Diagonal legs swing together, which is what makes a four-legged walk read as
## a walk rather than as a hopping table.
func _clip(parent: Node3D, legs: Array[Node3D], swing_degrees: float,
		seconds: float) -> Animation:
	var clip := Animation.new()
	clip.length = seconds
	clip.loop_mode = Animation.LOOP_LINEAR

	for index in legs.size():
		var track := clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(track, "%s:rotation:x" % parent.get_path_to(legs[index]))
		clip.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)

		# Front-left with back-right, front-right with back-left.
		var phase := 1.0 if index == 0 or index == 3 else -1.0
		var swing := deg_to_rad(swing_degrees) * phase
		clip.track_insert_key(track, 0.0, swing)
		clip.track_insert_key(track, seconds * 0.5, -swing)
		clip.track_insert_key(track, seconds, swing)
	return clip


func _box(parent: Node3D, offset: Vector3, size: Vector3, colour: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.95
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	parent.add_child(instance)
