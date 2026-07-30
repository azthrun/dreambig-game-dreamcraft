extends RefCounted
## What the player is carrying, and which slot is in hand.
##
## Pure of Node and SceneTree. A fixed array of slots rather than a bag of counts,
## because capacity is meant to bite: a slot is the unit of space, and a full inventory
## has to refuse things.
##
## Adding always reports how many items were actually taken. Nothing may vanish silently
## — a harvest that cannot fit should leave the resource in the world, and it can only
## know that if it is told.

const ItemKind := preload("res://scripts/items/item_kind.gd")

signal changed
signal selection_changed(slot: int)

## Slots in total, and how many of them the hotbar shows. The hotbar is the first row of
## the same inventory rather than a separate container, so putting something on the
## hotbar is just putting it in an early slot.
const DEFAULT_CAPACITY := 20
const HOTBAR_SLOTS := 5

var _capacity: int
var _items: PackedInt32Array
var _counts: PackedInt32Array
var _selected := 0


func _init(capacity: int = DEFAULT_CAPACITY) -> void:
	_capacity = maxi(capacity, 1)
	_items = PackedInt32Array()
	_counts = PackedInt32Array()
	_items.resize(_capacity)
	_counts.resize(_capacity)
	clear()


func clear() -> void:
	for i in _capacity:
		_items[i] = ItemKind.Kind.NONE
		_counts[i] = 0
	_selected = 0
	changed.emit()


func capacity() -> int:
	return _capacity


func item_in_slot(slot: int) -> int:
	if slot < 0 or slot >= _capacity:
		return ItemKind.Kind.NONE
	return _items[slot]


func count_in_slot(slot: int) -> int:
	if slot < 0 or slot >= _capacity:
		return 0
	return _counts[slot]


func is_slot_empty(slot: int) -> bool:
	return item_in_slot(slot) == ItemKind.Kind.NONE


## True when no slot is free and no existing stack has room for anything more.
func is_full() -> bool:
	for i in _capacity:
		if _items[i] == ItemKind.Kind.NONE:
			return false
		if _counts[i] < ItemKind.stack_limit(_items[i]):
			return false
	return true


func total_of(item: int) -> int:
	var total := 0
	for i in _capacity:
		if _items[i] == item:
			total += _counts[i]
	return total


func has(item: int, count: int = 1) -> bool:
	return total_of(item) >= count


## How many more of an item would fit right now, across partial stacks and empty slots.
func room_for(item: int) -> int:
	if item == ItemKind.Kind.NONE:
		return 0
	var limit := ItemKind.stack_limit(item)
	var room := 0
	for i in _capacity:
		if _items[i] == item:
			room += limit - _counts[i]
		elif _items[i] == ItemKind.Kind.NONE:
			room += limit
	return room


## Adds items, returning how many were actually taken.
##
## Partial success is normal and must be handled by the caller: adding 10 wood to an
## inventory with room for 3 takes 3 and reports 3.
func add(item: int, count: int = 1) -> int:
	if item == ItemKind.Kind.NONE or count <= 0:
		return 0

	var limit := ItemKind.stack_limit(item)
	var remaining := count

	# Top up existing stacks before opening a new slot, so the same item never occupies
	# two half-full slots while the inventory reports itself full.
	for i in _capacity:
		if remaining <= 0:
			break
		if _items[i] != item:
			continue
		var space := limit - _counts[i]
		if space <= 0:
			continue
		var moved := mini(space, remaining)
		_counts[i] += moved
		remaining -= moved

	for i in _capacity:
		if remaining <= 0:
			break
		if _items[i] != ItemKind.Kind.NONE:
			continue
		var moved := mini(limit, remaining)
		_items[i] = item
		_counts[i] = moved
		remaining -= moved

	var added := count - remaining
	if added > 0:
		changed.emit()
	return added


## Removes items, returning how many were actually removed.
func remove(item: int, count: int = 1) -> int:
	if item == ItemKind.Kind.NONE or count <= 0:
		return 0

	var remaining := count
	for i in _capacity:
		if remaining <= 0:
			break
		if _items[i] != item:
			continue
		var taken := mini(_counts[i], remaining)
		_counts[i] -= taken
		remaining -= taken
		if _counts[i] <= 0:
			_items[i] = ItemKind.Kind.NONE
			_counts[i] = 0

	var removed := count - remaining
	if removed > 0:
		changed.emit()
	return removed


## Removes from one specific slot. Used by the hotbar, where which stack is consumed
## matters to the player.
func remove_from_slot(slot: int, count: int = 1) -> int:
	if slot < 0 or slot >= _capacity or count <= 0:
		return 0
	var taken := mini(_counts[slot], count)
	if taken <= 0:
		return 0
	_counts[slot] -= taken
	if _counts[slot] <= 0:
		_items[slot] = ItemKind.Kind.NONE
		_counts[slot] = 0
	changed.emit()
	return taken


# --- hotbar -------------------------------------------------------------------

func selected_slot() -> int:
	return _selected


## The item currently in hand, or NONE. Other systems ask this rather than reaching into
## slots themselves.
func selected_item() -> int:
	return item_in_slot(_selected)


func select(slot: int) -> void:
	if slot < 0 or slot >= HOTBAR_SLOTS or slot == _selected:
		return
	_selected = slot
	selection_changed.emit(_selected)


## Moves the selection by `step`, wrapping around the hotbar. Wrapping matters because
## the scroll wheel has no ends.
func cycle_selection(step: int) -> void:
	if step == 0:
		return
	var next := posmod(_selected + step, HOTBAR_SLOTS)
	if next != _selected:
		_selected = next
		selection_changed.emit(_selected)


## Compact contents summary, for the debug overlay.
func status_line() -> String:
	var parts := PackedStringArray()
	for item in ItemKind.ALL:
		var total := total_of(item)
		if total > 0:
			parts.append("%s %d" % [ItemKind.name_of(item), total])
	var held := ItemKind.name_of(selected_item())
	return "carrying: %s | holding: %s" % [
		"nothing" if parts.is_empty() else ", ".join(parts), held]
