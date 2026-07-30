extends Node3D
## Spawns the island's props from the placer's output.
##
## Presentation only. What each prop is worth, and where it may appear, are decided in
## the pure placer and kind modules; this just builds what it is told to.

const PropPlacer := preload("res://scripts/world/props/prop_placer.gd")
const PropFactory := preload("res://scripts/world/props/prop_factory.gd")
const PropKind := preload("res://scripts/world/props/prop_kind.gd")

## Props are hidden past this distance, per the performance budget. Terrain stays
## visible much further out, so the horizon still reads as an island.
const CULL_DISTANCE_M := 150.0

var _counts: Dictionary = {}


## Builds every prop for a world grid. Returns per-kind counts.
func populate(map: RefCounted, seed_value: int) -> Dictionary:
	for child in get_children():
		child.queue_free()
	_counts = {}

	var placer: RefCounted = PropPlacer.new()
	var factory: RefCounted = PropFactory.new()
	var placements: Array = placer.place(map, seed_value)

	for placement in placements:
		var kind: int = placement["kind"]
		var prop: Node3D = factory.build(kind)
		add_child(prop)
		prop.position = placement["position"]
		prop.rotation.y = placement["yaw"]
		prop.scale = Vector3.ONE * float(placement["scale"])
		# Recorded on the node so a harvest interaction can read what this prop gives
		# up without re-deriving it.
		prop.set_meta(&"prop_kind", kind)
		prop.set_meta(&"prop_yield", PropKind.yield_of(kind))
		_apply_culling(prop)
		_counts[kind] = int(_counts.get(kind, 0)) + 1

	return _counts


func counts() -> Dictionary:
	return _counts


func stat_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var parts := PackedStringArray()
	var total := 0
	for kind in PropKind.ALL:
		var count := int(_counts.get(kind, 0))
		total += count
		parts.append("%s %d" % [PropKind.name_of(kind), count])
	lines.append("props: %d total (%s)" % [total, ", ".join(parts)])
	return lines


func _apply_culling(prop: Node3D) -> void:
	for child in prop.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).visibility_range_end = CULL_DISTANCE_M
