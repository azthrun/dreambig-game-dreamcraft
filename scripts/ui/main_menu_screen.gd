extends Control
## The front door: new game, continue, quit.
##
## Shown at boot and again whenever the pause menu returns to it. Selection is number
## keys, the same convention crafting uses, since this project has no clickable art and
## the mouse is normally captured for looking around anyway.
##
## Continue availability is a one-line pure check (`continue_available`), kept callable
## without a scene so the "no save means no continue" rule has a headless test.

const SaveManager := preload("res://scripts/persistence/save_manager.gd")

const PANEL_WIDTH := 420.0
const PADDING := 18.0
const LINE_HEIGHT := 26.0

const COLOUR_PANEL := Color(0.05, 0.06, 0.08, 0.94)
const COLOUR_OPTION := Color(0.88, 0.90, 0.93)
const COLOUR_DISABLED := Color(0.45, 0.47, 0.50)
const COLOUR_TITLE := Color(0.95, 0.85, 0.45)

signal new_game_requested
signal continue_requested
signal quit_requested

## True once the overwrite prompt is showing in place of the main list.
var _confirming_overwrite := false
var _continue_enabled := false

var _panel: ColorRect
var _title: Label
var _lines: Array[Label] = []


## Pure: whether a save exists at `path`. Kept as a static function, independent of any
## Control instance or scene tree, so "Continue is disabled when no save exists" is a
## headless test rather than a screenshot.
static func continue_available(path: String = SaveManager.SAVE_PATH) -> bool:
	return SaveManager.save_exists(path)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func is_open() -> bool:
	return visible


## Shown at boot and whenever a session returns here. Re-reads save-exists each time,
## since a save may have appeared or vanished since the screen was last shown.
func open() -> void:
	_confirming_overwrite = false
	_continue_enabled = continue_available()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if _confirming_overwrite:
		if event.is_action_pressed(&"hotbar_1"):
			_confirming_overwrite = false
			new_game_requested.emit()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"hotbar_2"):
			_confirming_overwrite = false
			_refresh()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"hotbar_1"):
		if _continue_enabled and SaveManager.save_exists():
			# An existing save is about to be discarded rather than resumed from -
			# that is exactly the destructive step the acceptance criteria wants a
			# prompt in front of.
			_confirming_overwrite = true
			_refresh()
		else:
			new_game_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"hotbar_2") and _continue_enabled:
		continue_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"hotbar_3"):
		quit_requested.emit()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_panel = ColorRect.new()
	_panel.color = COLOUR_PANEL
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	var height := PADDING * 2.0 + 4.0 * LINE_HEIGHT
	_panel.position = Vector2(-PANEL_WIDTH * 0.5, -height * 0.5)
	_panel.size = Vector2(PANEL_WIDTH, height)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_title = Label.new()
	_title.position = Vector2(PADDING, PADDING)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_title)

	for i in 3:
		var label := Label.new()
		label.position = Vector2(PADDING, PADDING + LINE_HEIGHT * float(i + 2))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(label)
		_lines.append(label)


func _refresh() -> void:
	if _panel == null:
		return

	if _confirming_overwrite:
		_title.text = "DREAMCRAFT"
		_title.modulate = COLOUR_TITLE
		_lines[0].text = "overwrite your existing save?"
		_lines[0].modulate = COLOUR_OPTION
		_lines[1].text = "1  yes, start a new game"
		_lines[1].modulate = COLOUR_OPTION
		_lines[2].text = "2  no, go back"
		_lines[2].modulate = COLOUR_OPTION
		return

	_title.text = "DREAMCRAFT"
	_title.modulate = COLOUR_TITLE
	_lines[0].text = "1  new game"
	_lines[0].modulate = COLOUR_OPTION
	_lines[1].text = "2  continue" if _continue_enabled else "2  continue  (no save)"
	_lines[1].modulate = COLOUR_OPTION if _continue_enabled else COLOUR_DISABLED
	_lines[2].text = "3  quit"
	_lines[2].modulate = COLOUR_OPTION
