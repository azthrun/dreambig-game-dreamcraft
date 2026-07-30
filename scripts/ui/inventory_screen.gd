extends Control
## The inventory screen, opened and closed with the inventory action.
##
## Lists what is carried, one line per occupied slot. Deliberately plain: this project
## has no UI art, and a readable list beats a grid of missing icons.
##
## Opening releases the mouse so the list can be read without the camera spinning; closing
## recaptures it.

const ItemKind := preload("res://scripts/items/item_kind.gd")

const PANEL_WIDTH := 420.0
const PADDING := 18.0
const LINE_HEIGHT := 22.0

## Two rows of headroom above the list, then one line per slot, then padding. Derived
## rather than fixed: a hard-coded height silently cropped the last slots the moment the
## inventory grew past what fitted.
const HEADER_ROWS := 2.0

const COLOUR_PANEL := Color(0.05, 0.06, 0.08, 0.88)
const COLOUR_SELECTED := Color(0.95, 0.85, 0.45)
const COLOUR_NORMAL := Color(0.88, 0.90, 0.93)
const COLOUR_EMPTY := Color(0.45, 0.47, 0.50)

var _player: Node
var _inventory: RefCounted
var _panel: ColorRect
var _title: Label
var _lines: Array[Label] = []


func bind(player: Node) -> void:
	_player = player
	if _player != null and _player.has_method(&"inventory"):
		_inventory = _player.inventory()
	_rebuild()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


func is_open() -> bool:
	return visible


func toggle() -> void:
	visible = not visible
	# The camera should not keep turning while a screen is being read.
	if _player != null:
		if visible and _player.has_method(&"release_mouse"):
			_player.release_mouse()
		elif not visible and _player.has_method(&"capture_mouse"):
			_player.capture_mouse()
	if visible:
		_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"pause"):
		# Escape closes the screen before it reaches the pause handling, so it is not
		# also releasing the mouse underneath.
		toggle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible:
		_rebuild()


func _build() -> void:
	_panel = ColorRect.new()
	_panel.color = COLOUR_PANEL
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	var height := _panel_height()
	_panel.position = Vector2(-PANEL_WIDTH * 0.5, -height * 0.5)
	_panel.size = Vector2(PANEL_WIDTH, height)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_title = Label.new()
	_title.position = Vector2(PADDING, PADDING)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_title)


## Tall enough for every slot, so the list can never overflow its own panel.
func _panel_height() -> float:
	var slots := float(_inventory.capacity()) if _inventory != null \
			else float(preload("res://scripts/items/inventory.gd").DEFAULT_CAPACITY)
	return PADDING * 2.0 + (HEADER_ROWS + slots) * LINE_HEIGHT


func _rebuild() -> void:
	if _panel == null or _inventory == null:
		return

	_title.text = "inventory  (tab to close)"
	# Capacity is known only once bound, so the panel is resized here rather than at
	# build time.
	var height := _panel_height()
	if absf(_panel.size.y - height) > 0.5:
		_panel.size.y = height
		_panel.position.y = -height * 0.5

	var capacity: int = _inventory.capacity()
	while _lines.size() < capacity:
		var label := Label.new()
		label.position = Vector2(
				PADDING, PADDING + LINE_HEIGHT * float(_lines.size() + 2))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(label)
		_lines.append(label)

	for slot in capacity:
		var label := _lines[slot]
		var item: int = _inventory.item_in_slot(slot)
		var selected: bool = slot == _inventory.selected_slot()
		var marker := ">" if selected else " "
		if item == ItemKind.Kind.NONE:
			label.text = "%s %2d  -" % [marker, slot + 1]
			label.modulate = COLOUR_SELECTED if selected else COLOUR_EMPTY
		else:
			label.text = "%s %2d  %s x%d" % [
					marker, slot + 1, ItemKind.name_of(item),
					_inventory.count_in_slot(slot)]
			label.modulate = COLOUR_SELECTED if selected else COLOUR_NORMAL
