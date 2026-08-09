extends Node
## The single authority for the current weather condition.
##
## Everything that reacts to weather — sky tint, fog, precipitation, and later the
## temperature model — reads this rather than deciding for itself, so there is exactly
## one answer to "what is the weather" at any moment.
##
## Owns a pure WeatherModel and does nothing but advance it and report.

const WeatherModel := preload("res://scripts/world/weather_model.gd")

signal weather_changed(state: int)

## Seed for the condition sequence. Set from the world seed so a given world always
## gets the same weather.
@export var weather_seed: int = 20260729

@export var paused: bool = false

## Multiplier applied while the debug time-scale action is held, matching the sky so
## the two stay in step when fast-forwarding.
@export var debug_time_scale: float = 60.0

var _model: RefCounted


func _ready() -> void:
	_model = WeatherModel.new(weather_seed)


func _process(delta: float) -> void:
	if paused or _model == null:
		return
	var scale := debug_time_scale if Input.is_action_pressed(&"debug_time_scale") \
			else 1.0
	if _model.advance(delta * scale):
		weather_changed.emit(_model.current())


func current() -> int:
	return _model.current() if _model != null else WeatherModel.State.CLEAR


func current_name() -> String:
	return WeatherModel.name_of(current())


func time_until_change() -> float:
	return _model.time_until_change() if _model != null else 0.0


func is_precipitating() -> bool:
	return WeatherModel.is_precipitating(current())


## Forces a condition. Used by the debug overlay and the screenshot probe.
func set_state(state: int) -> void:
	if _model == null:
		return
	_model.set_state(state)
	weather_changed.emit(state)


## Restores an exact condition and countdown from a save, without re-rolling the
## duration the way `set_state` does.
func restore(state: int, remaining: float) -> void:
	if _model == null:
		return
	_model.restore(state, remaining)
	weather_changed.emit(state)


func status_line() -> String:
	return "weather: %s, next in %.0fs" % [current_name(), time_until_change()]
