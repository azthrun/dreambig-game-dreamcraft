extends Control
## Pause: resume, save, or return to the main menu, opened and closed with the pause
## action. Number keys pick an option, the same convention as every other screen.
##
## Only reacts to the pause action while a game is actually running (`set_active`) and
## while neither the inventory nor crafting screen is already open, so Escape keeps
## meaning "close what's open" first and "pause" second - the same precedence those two
## screens already give each other.
##
## Suspending gameplay is the engine's own tree pause: every simulation node
## (creatures, weather, sky, the player) is `PROCESS_MODE_INHERIT` and stops for free.
## This screen sets itself to `PROCESS_MODE_ALWAYS` so it keeps working while paused.

const PANEL_WIDTH := 420.0
const PADDING := 18.0
const LINE_HEIGHT := 26.0

const COLOUR_PANEL := Color(0.05, 0.06, 0.08, 0.94)
const COLOUR_OPTION := Color(0.88, 0.90, 0.93)
const COLOUR_TITLE := Color(0.95, 0.85, 0.45)

signal resume_requested
signal save_requested
signal main_menu_requested

var _active := false
var _inventory: Control
var _crafting: Control

var _panel: ColorRect
var _title: Label
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


## `inventory` and `crafting` are the sibling screens whose own Escape handling must win
## first when they are open, so this screen never steals the key from them.
func bind(inventory: Control, crafting: Control) -> void:
	_inventory = inventory
	_crafting = crafting


## Whether a running session exists to pause. False while the main menu is showing.
func set_active(active: bool) -> void:
	_active = active
	if not active:
		visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_status.text = ""
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if not visible and not _active:
			return
		if not visible and ((_inventory != null and _inventory.is_open())
				or (_crafting != null and _crafting.is_open())):
			# Those screens consume "pause" themselves to close before this ever runs,
			# by scene order - this check is a second line of defence, not the primary.
			return
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if event.is_action_pressed(&"hotbar_1"):
		resume_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"hotbar_2"):
		save_requested.emit()
		_status.text = "saved"
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"hotbar_3"):
		main_menu_requested.emit()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_panel = ColorRect.new()
	_panel.color = COLOUR_PANEL
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	var height := PADDING * 2.0 + 5.0 * LINE_HEIGHT
	_panel.position = Vector2(-PANEL_WIDTH * 0.5, -height * 0.5)
	_panel.size = Vector2(PANEL_WIDTH, height)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_title = Label.new()
	_title.text = "paused"
	_title.modulate = COLOUR_TITLE
	_title.position = Vector2(PADDING, PADDING)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_title)

	var options := ["1  resume", "2  save", "3  main menu"]
	for i in options.size():
		var label := Label.new()
		label.text = options[i]
		label.modulate = COLOUR_OPTION
		label.position = Vector2(PADDING, PADDING + LINE_HEIGHT * float(i + 2))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(label)

	_status = Label.new()
	_status.modulate = COLOUR_OPTION
	_status.position = Vector2(PADDING, PADDING + LINE_HEIGHT * float(options.size() + 2))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_status)
