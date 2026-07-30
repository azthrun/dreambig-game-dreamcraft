extends RefCounted
## The weather state machine: which condition is in effect, and what may follow it.
##
## Pure of Node and SceneTree, but deliberately stateful — it owns its own random
## number generator so that a seed plus a sequence of time steps always produces the
## same weather. That reproducibility is what lets a save file store a seed, and what
## makes every test here deterministic.
##
## Conditions form a graph rather than a shuffle. Weather should arrive gradually: a
## clear sky clouds over, thickens, then rains, and only then breaks into a storm.
## Jumping from clear straight to thunderstorm would read as a glitch, so it is not a
## legal edge at all.

enum State {
	CLEAR,
	CLOUDY,
	OVERCAST,
	RAIN,
	THUNDERSTORM,
	FOG,
}

const ALL: Array[int] = [
	State.CLEAR,
	State.CLOUDY,
	State.OVERCAST,
	State.RAIN,
	State.THUNDERSTORM,
	State.FOG,
]

## Legal successors and their relative weights.
##
## Weights are relative, not probabilities — they are normalised at selection. Values
## favour staying near fair weather, so storms are an event rather than the norm.
const TRANSITIONS := {
	State.CLEAR: {
		State.CLOUDY: 7.0,
		State.FOG: 2.0,
	},
	State.CLOUDY: {
		State.CLEAR: 6.0,
		State.OVERCAST: 5.0,
		State.FOG: 2.0,
	},
	State.OVERCAST: {
		State.CLOUDY: 6.0,
		State.RAIN: 5.0,
	},
	State.RAIN: {
		State.OVERCAST: 7.0,
		State.THUNDERSTORM: 3.0,
	},
	State.THUNDERSTORM: {
		State.RAIN: 1.0,
	},
	State.FOG: {
		State.CLEAR: 5.0,
		State.CLOUDY: 4.0,
	},
}

## How long each condition lasts, in seconds: minimum and maximum.
##
## Storms are short and fog is long, so the worst weather passes and the dullest does
## not need constant re-rolling.
const DURATIONS := {
	State.CLEAR: Vector2(90.0, 240.0),
	State.CLOUDY: Vector2(60.0, 180.0),
	State.OVERCAST: Vector2(60.0, 150.0),
	State.RAIN: Vector2(50.0, 130.0),
	State.THUNDERSTORM: Vector2(30.0, 75.0),
	State.FOG: Vector2(80.0, 200.0),
}

var _state: int = State.CLEAR
var _remaining := 0.0
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0, starting_state: int = State.CLEAR) -> void:
	# Offset from the world seed so weather does not correlate with terrain noise.
	_rng.seed = seed_value + 61441
	_state = starting_state
	_remaining = _roll_duration(starting_state)


func current() -> int:
	return _state


## Seconds until the condition changes.
func time_until_change() -> float:
	return _remaining


## Advances the clock. Returns true if the condition changed.
##
## Loops rather than clamping, so a single large step — a debug time-scale jump, or a
## long frame — passes through every condition it should have rather than skipping to
## one and losing the rest.
func advance(delta: float) -> bool:
	if delta <= 0.0:
		return false
	var changed := false
	var left := delta
	while left >= _remaining:
		left -= _remaining
		_state = _pick_next(_state)
		_remaining = _roll_duration(_state)
		changed = true
	_remaining -= left
	return changed


## Forces a condition, for debugging and for restoring a save.
func set_state(state: int) -> void:
	_state = state
	_remaining = _roll_duration(state)


static func name_of(state: int) -> String:
	match state:
		State.CLEAR:
			return "clear"
		State.CLOUDY:
			return "cloudy"
		State.OVERCAST:
			return "overcast"
		State.RAIN:
			return "rain"
		State.THUNDERSTORM:
			return "thunderstorm"
		State.FOG:
			return "fog"
	return "unknown"


## Conditions that may directly follow this one.
static func legal_successors(state: int) -> Array:
	return TRANSITIONS.get(state, {}).keys()


static func is_legal(from: int, to: int) -> bool:
	return TRANSITIONS.get(from, {}).has(to)


## True for conditions that put water in the air. Read by anything that cares about
## being rained on rather than about the specific condition.
static func is_precipitating(state: int) -> bool:
	return state == State.RAIN or state == State.THUNDERSTORM


func _roll_duration(state: int) -> float:
	var range_s: Vector2 = DURATIONS.get(state, Vector2(60.0, 120.0))
	return _rng.randf_range(range_s.x, range_s.y)


## Weighted pick among the legal successors. Never returns the current state, so every
## transition is a visible change rather than a silent re-roll.
func _pick_next(from: int) -> int:
	var options: Dictionary = TRANSITIONS.get(from, {})
	if options.is_empty():
		return from

	var total := 0.0
	for weight in options.values():
		total += float(weight)

	var roll := _rng.randf() * total
	var accumulated := 0.0
	for state in options:
		accumulated += float(options[state])
		if roll <= accumulated:
			return state
	# Floating point can leave the roll a hair past the total.
	return options.keys().back()
