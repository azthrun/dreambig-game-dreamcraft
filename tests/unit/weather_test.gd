extends "res://tests/test_case.gd"
## Tests the weather state machine: legality, determinism, weighting, and reachability.

const Weather := preload("res://scripts/world/weather_model.gd")

const SEED := 20260729

## Long enough to walk the whole graph many times over.
const LONG_RUN_STEPS := 4000
const STEP_SECONDS := 30.0


func _model(seed_value: int = SEED, start: int = Weather.State.CLEAR) -> RefCounted:
	return Weather.new(seed_value, start)


## Runs the machine and returns every condition it passed through, in order.
func _sequence(model: RefCounted, steps: int) -> Array[int]:
	var seen: Array[int] = [model.current()]
	for _i in steps:
		if model.advance(STEP_SECONDS):
			seen.append(model.current())
	return seen


func test_starts_in_the_requested_condition() -> void:
	assert_eq(_model(SEED, Weather.State.FOG).current(), Weather.State.FOG)
	assert_eq(_model(SEED, Weather.State.CLEAR).current(), Weather.State.CLEAR)


func test_all_six_conditions_are_reachable() -> void:
	var seen := {}
	for state in _sequence(_model(), LONG_RUN_STEPS):
		seen[state] = true
	for state in Weather.ALL:
		assert_true(seen.has(state),
				"%s never occurred in a long run" % Weather.name_of(state))


func test_every_transition_taken_is_a_legal_one() -> void:
	# The graph is the whole point: weather should arrive gradually rather than
	# teleporting between unrelated conditions.
	var sequence := _sequence(_model(), LONG_RUN_STEPS)
	var illegal := 0
	for i in range(1, sequence.size()):
		if not Weather.is_legal(sequence[i - 1], sequence[i]):
			illegal += 1
	assert_true(sequence.size() > 100, "expected plenty of transitions to check")
	assert_eq(illegal, 0, "every transition must follow a declared edge")


func test_clear_never_becomes_a_thunderstorm_directly() -> void:
	# The specific jump that would read as a glitch: a cloudless sky erupting.
	assert_false(Weather.is_legal(Weather.State.CLEAR, Weather.State.THUNDERSTORM))
	var sequence := _sequence(_model(), LONG_RUN_STEPS)
	var jumps := 0
	for i in range(1, sequence.size()):
		if sequence[i - 1] == Weather.State.CLEAR \
				and sequence[i] == Weather.State.THUNDERSTORM:
			jumps += 1
	assert_eq(jumps, 0)


func test_a_condition_never_transitions_to_itself() -> void:
	# A transition that changes nothing would look like a stalled machine.
	var sequence := _sequence(_model(), LONG_RUN_STEPS)
	var repeats := 0
	for i in range(1, sequence.size()):
		if sequence[i] == sequence[i - 1]:
			repeats += 1
	assert_eq(repeats, 0)
	for state in Weather.ALL:
		assert_false(Weather.is_legal(state, state),
				"%s should not list itself as a successor" % Weather.name_of(state))


func test_same_seed_and_steps_produce_identical_weather() -> void:
	var a := _sequence(_model(SEED), 500)
	var b := _sequence(_model(SEED), 500)
	assert_eq(a, b)


func test_different_seeds_produce_different_weather() -> void:
	assert_ne(_sequence(_model(SEED), 500), _sequence(_model(SEED + 1), 500))


func test_transitions_are_weighted_not_uniform() -> void:
	# From overcast, clearing up is weighted above raining. With uniform selection the
	# two would be equally likely, so this is what proves weights are applied at all.
	var to_cloudy := 0
	var to_rain := 0
	for i in 4000:
		var model := _model(SEED + i, Weather.State.OVERCAST)
		# Exactly one transition. Advancing further would walk several hops and sample
		# where the machine ended up rather than what overcast chose first.
		model.advance(model.time_until_change() + 0.001)
		match model.current():
			Weather.State.CLOUDY:
				to_cloudy += 1
			Weather.State.RAIN:
				to_rain += 1
	assert_true(to_cloudy + to_rain > 3000, "overcast should lead somewhere")
	assert_true(to_cloudy > to_rain,
			"clearing (weight 6) should beat raining (weight 5): %d vs %d"
					% [to_cloudy, to_rain])


func test_countdown_runs_down_and_resets_on_change() -> void:
	var model := _model()
	var before: float = model.time_until_change()
	assert_true(before > 0.0)
	model.advance(1.0)
	assert_almost_eq(model.time_until_change(), before - 1.0, 0.001)
	# Advance well past the end; the countdown must be reset, not left negative.
	model.advance(10000.0)
	assert_true(model.time_until_change() > 0.0,
			"a new condition should carry a fresh duration")


func test_durations_stay_within_their_configured_range() -> void:
	for state in Weather.ALL:
		var model := _model(SEED, state)
		var bounds: Vector2 = Weather.DURATIONS[state]
		assert_in_range(model.time_until_change(), bounds.x, bounds.y,
				"%s duration out of range" % Weather.name_of(state))


func test_a_single_large_step_passes_through_conditions_rather_than_skipping() -> void:
	# A debug time-scale jump or a long frame must not swallow whole conditions and
	# leave the machine somewhere unreachable from where it started.
	var stepwise := _model(SEED)
	for _i in 200:
		stepwise.advance(10.0)
	var one_jump := _model(SEED)
	one_jump.advance(2000.0)
	assert_eq(one_jump.current(), stepwise.current(),
			"one large step should land where many small ones do")


func test_advancing_by_nothing_changes_nothing() -> void:
	var model := _model()
	var before: float = model.time_until_change()
	assert_false(model.advance(0.0))
	assert_false(model.advance(-5.0))
	assert_almost_eq(model.time_until_change(), before, 0.001)


func test_precipitation_covers_rain_and_storms_only() -> void:
	assert_true(Weather.is_precipitating(Weather.State.RAIN))
	assert_true(Weather.is_precipitating(Weather.State.THUNDERSTORM))
	for state in [Weather.State.CLEAR, Weather.State.CLOUDY,
			Weather.State.OVERCAST, Weather.State.FOG]:
		assert_false(Weather.is_precipitating(state),
				"%s is not precipitation" % Weather.name_of(state))


func test_every_condition_is_named_and_has_somewhere_to_go() -> void:
	for state in Weather.ALL:
		assert_ne(Weather.name_of(state), "unknown")
		assert_true(Weather.legal_successors(state).size() > 0,
				"%s is a dead end" % Weather.name_of(state))


func test_forcing_a_condition_takes_effect_immediately() -> void:
	var model := _model()
	model.set_state(Weather.State.THUNDERSTORM)
	assert_eq(model.current(), Weather.State.THUNDERSTORM)
	assert_true(model.time_until_change() > 0.0)
