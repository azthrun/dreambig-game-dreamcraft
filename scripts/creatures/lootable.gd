extends Node
## Makes a corpse lootable: what it carries, and whether it has been picked clean.
##
## A component rather than a script on the corpse root, matching how harvestable props
## work, so the same hold-to-interact code serves both without knowing which it has found.
##
## Unlike a harvestable, a corpse yields several different items and does not come back.

const ItemKind := preload("res://scripts/items/item_kind.gd")

signal looted

## Item to count, straight from the species drop table.
var contents: Dictionary = {}

var _emptied := false


func configure(drops: Dictionary) -> void:
	contents = drops.duplicate()


func is_empty() -> bool:
	return _emptied or contents.is_empty()


func can_loot() -> bool:
	return not is_empty()


## The single item this corpse offers next, so the shared prompt can name something.
func headline_item() -> int:
	for item in contents:
		return int(item)
	return ItemKind.Kind.NONE


## Moves everything into an inventory, taking only what fits.
##
## Returns what was actually taken. A corpse with anything left is still lootable, so a
## player who arrives full can drop something and come back rather than losing the kill.
func loot(inventory: RefCounted) -> Dictionary:
	var taken := {}
	var remaining := {}
	for item in contents:
		var wanted := int(contents[item])
		var moved: int = inventory.add(item, wanted)
		if moved > 0:
			taken[item] = moved
		if moved < wanted:
			remaining[item] = wanted - moved

	contents = remaining
	if contents.is_empty():
		_emptied = true
		looted.emit()
	return taken


## Total items still on the corpse, for prompts and tests.
func remaining_count() -> int:
	var total := 0
	for item in contents:
		total += int(contents[item])
	return total
