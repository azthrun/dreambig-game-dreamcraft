extends Node3D
## Spawns the island's props from the placer's output.
##
## Presentation only. What each prop is worth, and where it may appear, are decided in
## the pure placer and kind modules; this just builds what it is told to.

const PropPlacer := preload("res://scripts/world/props/prop_placer.gd")
const PropFactory := preload("res://scripts/world/props/prop_factory.gd")
const PropKind := preload("res://scripts/world/props/prop_kind.gd")
const Config := preload("res://scripts/config.gd")



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
		var harvestable := prop.get_node_or_null(^"Harvestable")
		if harvestable != null:
			harvestable.depleted.connect(_on_prop_depleted)
			harvestable.restored.connect(_on_prop_restored)
		_apply_culling(prop)
		_counts[kind] = int(_counts.get(kind, 0)) + 1

	return _counts


func counts() -> Dictionary:
	return _counts


## How many props are currently stripped and regrowing. Cheap because harvestables
## announce their own state rather than being polled.
var _depleted_count := 0


func depleted_count() -> int:
	return _depleted_count


func status_line() -> String:
	return "props: %d regrowing" % _depleted_count


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


func _on_prop_depleted() -> void:
	_depleted_count += 1


func _on_prop_restored() -> void:
	_depleted_count = maxi(_depleted_count - 1, 0)


func _apply_culling(prop: Node3D) -> void:
	for child in prop.get_children():
		if child is GeometryInstance3D:
			# Props stop drawing well before terrain does: the island must read to the
			# horizon, but thousands of trees need not.
			(child as GeometryInstance3D).visibility_range_end = \
					Config.prop_cull_distance_m()
