extends Node3D
## Spawns the island's props from the placer's output.
##
## Presentation only. What each prop is worth, and where it may appear, are decided in
## the pure placer and kind modules; this just builds what it is told to.

const PropPlacer := preload("res://scripts/world/props/prop_placer.gd")
const PropFactory := preload("res://scripts/world/props/prop_factory.gd")
const PropKind := preload("res://scripts/world/props/prop_kind.gd")
const SupplyCache := preload("res://scripts/world/props/supply_cache.gd")
const Config := preload("res://scripts/config.gd")



var _counts: Dictionary = {}
var _caches: Array[Node] = []
var _harvestables: Array[Node] = []


## Builds every prop for a world grid. Returns per-kind counts.
func populate(map: RefCounted, seed_value: int) -> Dictionary:
	for child in get_children():
		child.queue_free()
	_counts = {}
	_caches.clear()
	_harvestables.clear()

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
		if PropKind.is_container(kind):
			_add_cache(prop, seed_value, int(placement.get("id", 0)))

		var harvestable := prop.get_node_or_null(^"Harvestable")
		if harvestable != null:
			# Same cell-derived id a cache gets — see `prop_placer.gd` — so depletion
			# state can be saved and restored per-prop the same way looted state is.
			harvestable.prop_id = int(placement.get("id", 0))
			harvestable.depleted.connect(_on_prop_depleted)
			harvestable.restored.connect(_on_prop_restored)
			_harvestables.append(harvestable)
		_apply_culling(prop)
		_counts[kind] = int(_counts.get(kind, 0)) + 1

	return _counts


## Fills a crate and names the component `Lootable`, which is what the player's existing
## hold-to-take interaction looks for. A cache needs no new key and no new prompt for the
## same reason the cooking rack needed none.
func _add_cache(prop: Node3D, seed_value: int, cache_id: int) -> void:
	var cache: Node = SupplyCache.new()
	cache.name = "Lootable"
	prop.add_child(cache)
	cache.configure_cache(seed_value, cache_id,
			prop.get_meta(&"cache_visuals", []))
	_caches.append(cache)


## Every cache on the island. Saving records which of these have been opened, since
## re-opening a looted crate is the one way ammunition could be farmed.
func caches() -> Array[Node]:
	return _caches


## Every harvestable on the island. Saving records which of these are depleted and how
## long until they regrow, keyed by `prop_id`.
func harvestables() -> Array[Node]:
	return _harvestables


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
