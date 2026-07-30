extends Control
## The crafting screen, opened and closed with the craft action.
##
## Lists every recipe, always — including ones that cannot be afforded yet, greyed with
## the reason. An unaffordable recipe is a signpost towards what to do next, so hiding it
## would remove the only hint the game gives about hunting.
##
## Number keys craft. Those actions are consumed while the screen is open so they do not
## also change the hotbar selection underneath.

const RecipeBook := preload("res://scripts/items/recipe_book.gd")
const Inventory := preload("res://scripts/items/inventory.gd")

const PANEL_WIDTH := 460.0
const PADDING := 18.0
const LINE_HEIGHT := 26.0
const HEADER_ROWS := 2.0

const COLOUR_PANEL := Color(0.05, 0.06, 0.08, 0.9)
const COLOUR_AVAILABLE := Color(0.62, 0.88, 0.60)
const COLOUR_BLOCKED := Color(0.55, 0.57, 0.60)

var _player: Node
var _inventory: RefCounted
var _panel: ColorRect
var _title: Label
var _lines: Array[Label] = []
var _last_result := ""


func bind(player: Node) -> void:
	_player = player
	if _player != null and _player.has_method(&"inventory"):
		_inventory = _player.inventory()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


func is_open() -> bool:
	return visible


func toggle() -> void:
	visible = not visible
	_last_result = ""
	if _player != null:
		if visible and _player.has_method(&"release_mouse"):
			_player.release_mouse()
		elif not visible and _player.has_method(&"capture_mouse"):
			_player.capture_mouse()
	if visible:
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"craft"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return

	if event.is_action_pressed(&"pause"):
		toggle()
		get_viewport().set_input_as_handled()
		return

	# Number keys craft while the screen is open, and are swallowed so they do not also
	# move the hotbar selection behind it.
	for index in mini(RecipeBook.count(), Inventory.HOTBAR_SLOTS):
		if event.is_action_pressed(StringName("hotbar_%d" % (index + 1))):
			_attempt(index)
			get_viewport().set_input_as_handled()
			return


func _attempt(index: int) -> void:
	if _inventory == null:
		return
	var reason := RecipeBook.blocked_reason(_inventory, index)
	if not reason.is_empty():
		_last_result = reason
	elif RecipeBook.craft(_inventory, index):
		_last_result = "made %s" % RecipeBook.describe(index).split("  <")[0]
	_refresh()


func _process(_delta: float) -> void:
	if visible:
		_refresh()


func _build() -> void:
	var height := PADDING * 2.0 \
			+ (HEADER_ROWS + float(RecipeBook.count()) + 1.0) * LINE_HEIGHT
	_panel = ColorRect.new()
	_panel.color = COLOUR_PANEL
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-PANEL_WIDTH * 0.5, -height * 0.5)
	_panel.size = Vector2(PANEL_WIDTH, height)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_title = Label.new()
	_title.position = Vector2(PADDING, PADDING)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_title)

	for i in RecipeBook.count() + 1:
		var label := Label.new()
		label.position = Vector2(PADDING, PADDING + LINE_HEIGHT * float(i + 2))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(label)
		_lines.append(label)


func _refresh() -> void:
	if _inventory == null or _lines.is_empty():
		return
	_title.text = "crafting  (number keys to make, C to close)"

	for index in RecipeBook.count():
		var label := _lines[index]
		var reason := RecipeBook.blocked_reason(_inventory, index)
		if reason.is_empty():
			label.text = "%d  %s" % [index + 1, RecipeBook.describe(index)]
			label.modulate = COLOUR_AVAILABLE
		else:
			label.text = "%d  %s   (%s)" % [
					index + 1, RecipeBook.describe(index), reason]
			label.modulate = COLOUR_BLOCKED

	_lines[RecipeBook.count()].text = _last_result
	_lines[RecipeBook.count()].modulate = COLOUR_AVAILABLE
