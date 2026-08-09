extends Node
## Makes a prop harvestable: what it yields, and how long before it comes back.
##
## A child component rather than a script on the prop root, because prop roots are
## different types — a tree is a StaticBody3D, a bush is a plain Node3D — and a component
## does not care.
##
## Processing is off while the prop is intact and only switched on while it is regrowing.
## With thousands of props on the island, per-frame cost has to be proportional to the few
## that are depleted rather than to all of them.

const ItemKind := preload("res://scripts/items/item_kind.gd")

signal depleted
signal restored

## What one harvest yields.
var item: int = ItemKind.Kind.NONE
var amount: int = 1

## The placement's cell-derived id — see `prop_placer.gd`. Set directly by `props.gd`
## after building, the same way `prop_kind`/`prop_yield` are recorded as node meta, so a
## save file can key depletion state to a specific prop without re-deriving placement.
var prop_id: int = 0

## How long a depleted prop takes to come back. Long enough that an area can be stripped
## and has to be left alone, short enough that the island is not permanently bare.
var respawn_seconds: float = 150.0

var _depleted := false
var _remaining := 0.0

## Meshes that disappear while depleted — a stripped tree keeps its trunk and loses its
## canopy. Populated by the factory, which is what knows the shape of each prop.
var _harvest_visuals: Array[Node3D] = []


func _ready() -> void:
	# Nothing to do until something is harvested.
	set_process(false)


## `visuals` are the meshes that vanish while depleted.
##
## Takes a plain Array rather than Array[Node3D]: GDScript refuses an untyped literal
## where a typed array is expected, so a bare `[]` at any call site would fail at runtime
## rather than at parse time. Copying element-wise keeps the field typed without making
## every caller remember the cast.
func configure(p_item: int, p_amount: int, p_respawn: float,
		visuals: Array = []) -> void:
	item = p_item
	amount = p_amount
	respawn_seconds = p_respawn
	_harvest_visuals.clear()
	for node in visuals:
		if node is Node3D:
			_harvest_visuals.append(node)


func is_depleted() -> bool:
	return _depleted


func can_harvest() -> bool:
	return not _depleted and item != ItemKind.Kind.NONE and amount > 0


func time_until_respawn() -> float:
	return _remaining


## Takes the prop's yield, returning how much was produced. Returns zero when already
## depleted, so a second harvest of the same bush gives nothing.
func harvest() -> int:
	if not can_harvest():
		return 0
	_depleted = true
	_remaining = respawn_seconds
	_apply_visuals()
	set_process(true)
	depleted.emit()
	return amount


## Advances regrowth. Separate from _process so respawn timing can be tested by injecting
## deltas rather than by waiting.
func tick(delta: float) -> void:
	if not _depleted or delta <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		restore()


## Restores a partway-regrown depleted state, for a save file to replay. Distinct from
## `harvest()`, which always resets the timer to a full `respawn_seconds` — a save has to
## be able to put back an arbitrary remaining time instead.
func restore_depleted(remaining: float) -> void:
	_depleted = true
	_remaining = maxf(remaining, 0.0)
	_apply_visuals()
	set_process(true)


func restore() -> void:
	if not _depleted:
		return
	_depleted = false
	_remaining = 0.0
	_apply_visuals()
	set_process(false)
	restored.emit()


func _process(delta: float) -> void:
	tick(delta)


func _apply_visuals() -> void:
	for node in _harvest_visuals:
		if is_instance_valid(node):
			node.visible = not _depleted
