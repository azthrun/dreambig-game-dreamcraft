extends Control
## Health, hunger and stamina bars.
##
## Built in code rather than authored as a scene, for the same reason everything else in
## this project is: there are no art assets, so the HUD is coloured rectangles sized to
## the values behind them.
##
## Reads the player's stats each frame and displays them. It owns no state — if the bars
## are wrong, the stats are wrong.

const BAR_WIDTH := 240.0
const BAR_HEIGHT := 16.0
const BAR_GAP := 6.0
const MARGIN := 20.0
const BORDER := 2.0

const COLOUR_BACKING := Color(0.06, 0.07, 0.09, 0.72)
const COLOUR_HEALTH := Color(0.78, 0.22, 0.24)
const COLOUR_HUNGER := Color(0.82, 0.60, 0.20)
const COLOUR_STAMINA := Color(0.35, 0.68, 0.42)

## Hotbar, drawn bottom-centre so it reads as "in hand" rather than as another stat.
const SLOT_SIZE := 62.0
const SLOT_GAP := 6.0
const COLOUR_SLOT := Color(0.06, 0.07, 0.09, 0.72)
const COLOUR_SLOT_SELECTED := Color(0.95, 0.85, 0.45, 0.92)

## Hunger is shown filling up rather than draining down, because it is a threat that
## grows rather than a resource that depletes.
const LABELS := ["health", "food", "stamina"]

## How long a one-off message stays on screen. Long enough to read, short enough that it
## is gone before the next one matters.
const NOTICE_SECONDS := 2.4

## Colour of the temperature readout when the player is losing health to the cold.
const COLOUR_COLD := Color(0.55, 0.78, 1.0)
const COLOUR_WARM := Color(1.0, 1.0, 1.0)

var _player: Node
var _climate: Node
var _fills: Array[ColorRect] = []
var _labels: Array[Label] = []
var _temperature: Label
var _inventory: RefCounted
var _harvester: Node
var _prompt: Label
var _notice: Label
var _notice_left := 0.0
var _slot_backings: Array[ColorRect] = []
var _slot_labels: Array[Label] = []


func bind(player: Node, climate: Node = null) -> void:
	_player = player
	_climate = climate
	if _player != null and _player.has_method(&"inventory"):
		_inventory = _player.inventory()
		_build_hotbar()
	if _player != null and _player.has_method(&"harvester"):
		_harvester = _player.harvester()

	# Things that happen once and have to be said: what was eaten, why a fire refused
	# fuel, that the gun is empty. These were being emitted and displayed nowhere.
	for path in [^"ItemPlacer", ^"Firearm"]:
		var component := _player.get_node_or_null(path) if _player != null else null
		if component == null:
			continue
		for signal_name in [&"message", &"refused"]:
			if component.has_signal(signal_name) \
					and not component.is_connected(signal_name, show_notice):
				component.connect(signal_name, show_notice)


func _ready() -> void:
	# The container spans the viewport so its bottom edge is the screen's bottom; the
	# bars then anchor to that edge. Without this the container has no size and
	# bottom-anchored children land at the top, on top of the debug overlay.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bars()


## Shows a one-off message under the crosshair.
func show_notice(text: String) -> void:
	if _notice == null:
		return
	_notice.text = text
	_notice_left = NOTICE_SECONDS


func notice_text() -> String:
	return _notice.text if _notice != null else ""


func _process(delta: float) -> void:
	if _notice != null and _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice.text = ""

	if _player == null or not _player.has_method(&"stats"):
		return
	var stats: RefCounted = _player.stats()
	if stats == null:
		return

	# Hunger is inverted for display: a full bar means well fed, which is the direction
	# every other bar reads in.
	_set_bar(0, stats.health_fraction(), stats.health())
	_set_bar(1, 1.0 - stats.hunger_fraction(),
			stats.rate("max_hunger") - stats.hunger())
	_set_bar(2, stats.stamina_fraction(), stats.stamina())

	if _temperature != null and _climate != null \
			and _climate.has_method(&"temperature_c"):
		var cold: bool = _climate.is_cold()
		# Says outright that the cold is doing damage, rather than leaving the player to
		# infer it from a health bar that is quietly falling.
		_temperature.text = "%.0f C%s" % [
				_climate.temperature_c(), "  freezing" if cold else ""]
		_temperature.modulate = COLOUR_COLD if cold else COLOUR_WARM

	_refresh_hotbar()

	if _prompt != null and _harvester != null and _harvester.has_method(&"prompt"):
		_prompt.text = _harvester.prompt()


func _set_bar(index: int, fraction: float, value: float) -> void:
	if index >= _fills.size():
		return
	var clamped := clampf(fraction, 0.0, 1.0)
	_fills[index].size.x = (BAR_WIDTH - BORDER * 2.0) * clamped
	_labels[index].text = "%s %.0f" % [LABELS[index], value]


func _build_bars() -> void:
	var colours := [COLOUR_HEALTH, COLOUR_HUNGER, COLOUR_STAMINA]
	var count := colours.size()
	for i in count:
		# Measured up from the bottom edge, so the stack sits above the screen bottom in
		# reading order regardless of resolution.
		var rows_below := float(count - i)
		var top := -(MARGIN + rows_below * (BAR_HEIGHT + BAR_GAP))

		var backing := _anchored_rect(
				Vector2(MARGIN, top), Vector2(BAR_WIDTH, BAR_HEIGHT))
		backing.color = COLOUR_BACKING
		add_child(backing)

		var fill := _anchored_rect(
				Vector2(MARGIN + BORDER, top + BORDER),
				Vector2(BAR_WIDTH - BORDER * 2.0, BAR_HEIGHT - BORDER * 2.0))
		fill.color = colours[i]
		add_child(fill)
		_fills.append(fill)

		var label := Label.new()
		label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		label.position = Vector2(MARGIN + BAR_WIDTH + 10.0, top - 4.0)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_labels.append(label)

	# Centred just above the hotbar, where the eye already is.
	_prompt = Label.new()
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.position = Vector2(-140.0, -(MARGIN + SLOT_SIZE + 34.0))
	_prompt.size = Vector2(280.0, 24.0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)

	# Just above the prompt, so a refusal and an offer never overwrite each other.
	_notice = Label.new()
	_notice.anchor_left = 0.5
	_notice.anchor_right = 0.5
	_notice.anchor_top = 1.0
	_notice.anchor_bottom = 1.0
	_notice.position = Vector2(-140.0, -(MARGIN + SLOT_SIZE + 58.0))
	_notice.size = Vector2(280.0, 24.0)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notice)

	_temperature = Label.new()
	_temperature.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_temperature.position = Vector2(
			MARGIN, -(MARGIN + float(count + 1) * (BAR_HEIGHT + BAR_GAP)))
	_temperature.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_temperature)


## Five slots across the bottom centre, the selected one outlined.
func _build_hotbar() -> void:
	const Inventory := preload("res://scripts/items/inventory.gd")
	var count := Inventory.HOTBAR_SLOTS
	var total_width := float(count) * SLOT_SIZE + float(count - 1) * SLOT_GAP

	for i in count:
		var x := -total_width * 0.5 + float(i) * (SLOT_SIZE + SLOT_GAP)

		var backing := ColorRect.new()
		# Anchored bottom-centre so the row stays centred at any resolution.
		backing.anchor_left = 0.5
		backing.anchor_right = 0.5
		backing.anchor_top = 1.0
		backing.anchor_bottom = 1.0
		backing.position = Vector2(x, -(MARGIN + SLOT_SIZE))
		backing.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		backing.color = COLOUR_SLOT
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(backing)
		_slot_backings.append(backing)

		var label := Label.new()
		label.position = Vector2(4.0, 4.0)
		label.size = Vector2(SLOT_SIZE - 8.0, SLOT_SIZE - 8.0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Small enough that a two-word item name and its count all fit inside the slot
		# rather than the count being clipped off the bottom.
		label.add_theme_font_size_override("font_size", 11)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backing.add_child(label)
		_slot_labels.append(label)


func _refresh_hotbar() -> void:
	if _inventory == null:
		return
	const ItemKind := preload("res://scripts/items/item_kind.gd")
	for i in _slot_backings.size():
		var selected: bool = i == _inventory.selected_slot()
		_slot_backings[i].color = COLOUR_SLOT_SELECTED if selected \
				else COLOUR_SLOT
		var item: int = _inventory.item_in_slot(i)
		if item == ItemKind.Kind.NONE:
			_slot_labels[i].text = "%d" % (i + 1)
		else:
			_slot_labels[i].text = "%s\n%d" % [
					ItemKind.name_of(item), _inventory.count_in_slot(i)]
		_slot_labels[i].modulate = Color(0.1, 0.1, 0.12) if selected \
				else Color(0.88, 0.90, 0.93)


## A rect anchored to the container's bottom-left, so `position.y` is measured upwards
## from the bottom of the screen.
func _anchored_rect(at: Vector2, size_px: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	rect.position = at
	rect.size = size_px
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
