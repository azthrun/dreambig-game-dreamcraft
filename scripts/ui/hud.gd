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

## Hunger is shown filling up rather than draining down, because it is a threat that
## grows rather than a resource that depletes.
const LABELS := ["health", "food", "stamina"]

## Colour of the temperature readout when the player is losing health to the cold.
const COLOUR_COLD := Color(0.55, 0.78, 1.0)
const COLOUR_WARM := Color(1.0, 1.0, 1.0)

var _player: Node
var _climate: Node
var _fills: Array[ColorRect] = []
var _labels: Array[Label] = []
var _temperature: Label


func bind(player: Node, climate: Node = null) -> void:
	_player = player
	_climate = climate


func _ready() -> void:
	# The container spans the viewport so its bottom edge is the screen's bottom; the
	# bars then anchor to that edge. Without this the container has no size and
	# bottom-anchored children land at the top, on top of the debug overlay.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bars()


func _process(_delta: float) -> void:
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

	_temperature = Label.new()
	_temperature.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_temperature.position = Vector2(
			MARGIN, -(MARGIN + float(count + 1) * (BAR_HEIGHT + BAR_GAP)))
	_temperature.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_temperature)


## A rect anchored to the container's bottom-left, so `position.y` is measured upwards
## from the bottom of the screen.
func _anchored_rect(at: Vector2, size_px: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	rect.position = at
	rect.size = size_px
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
