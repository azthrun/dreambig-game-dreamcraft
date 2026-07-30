extends RefCounted
## Base class for headless tests.
##
## Subclass with `extends "res://tests/test_case.gd"` and name methods `test_*`.
## The runner discovers them, calls `before_each` / `after_each` around each one,
## and treats any recorded failure as a failing test.
##
## Assertions record failures rather than halting, so one bad assertion does not
## hide the rest of the test. They are deliberately plain: no matcher DSL, no
## reflection on internals. Tests assert on observable behaviour only.
##
## Deliberately not registered with `class_name`: global class names resolve
## through Godot's script class cache, which is not guaranteed to be current when
## a fresh file is run headlessly. Extending by path always resolves.

var _failures: Array[String] = []
var _assertion_count: int = 0
var _current_test: String = ""


## Overridable lifecycle hooks. Default to no-ops.
func before_each() -> void:
	pass


func after_each() -> void:
	pass


## Failure messages recorded so far, across every test on this instance.
func failures() -> Array[String]:
	return _failures


## Total assertions evaluated, passing or failing. Used to catch a suite that
## runs but asserts nothing.
func assertion_count() -> int:
	return _assertion_count


## Called by the runner before invoking each test method.
func begin_test(name: String) -> void:
	_current_test = name


# --- assertions ---------------------------------------------------------------

func assert_true(value: bool, msg: String = "") -> void:
	_assertion_count += 1
	if not value:
		_record(msg, "expected true, got false")


func assert_false(value: bool, msg: String = "") -> void:
	_assertion_count += 1
	if value:
		_record(msg, "expected false, got true")


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	_assertion_count += 1
	if actual != expected:
		_record(msg, "expected %s, got %s" % [_show(expected), _show(actual)])


func assert_ne(actual: Variant, other: Variant, msg: String = "") -> void:
	_assertion_count += 1
	if actual == other:
		_record(msg, "expected any value other than %s" % _show(other))


## Approximate float comparison. Use for anything derived from noise, physics or
## trigonometry, where exact equality is meaningless.
func assert_almost_eq(actual: float, expected: float, epsilon: float = 0.000001,
		msg: String = "") -> void:
	_assertion_count += 1
	if absf(actual - expected) > epsilon:
		_record(msg, "expected %f +/- %f, got %f" % [expected, epsilon, actual])


## Inclusive numeric range check.
func assert_in_range(value: float, minimum: float, maximum: float,
		msg: String = "") -> void:
	_assertion_count += 1
	if value < minimum or value > maximum:
		_record(msg, "expected value within [%f, %f], got %f"
				% [minimum, maximum, value])


## Membership. Works for Array and packed arrays (elements), Dictionary (keys),
## and String (substring).
func assert_has(collection: Variant, item: Variant, msg: String = "") -> void:
	_assertion_count += 1
	if not _contains(collection, item):
		_record(msg, "expected %s to contain %s"
				% [_show(collection), _show(item)])


func assert_not_has(collection: Variant, item: Variant, msg: String = "") -> void:
	_assertion_count += 1
	if _contains(collection, item):
		_record(msg, "expected %s not to contain %s"
				% [_show(collection), _show(item)])


## Unconditional failure, for unreachable branches.
func fail(msg: String) -> void:
	_assertion_count += 1
	_record(msg, "explicit failure")


# --- internals ----------------------------------------------------------------

func _contains(collection: Variant, item: Variant) -> bool:
	return item in collection


func _record(msg: String, detail: String) -> void:
	var text := detail if msg.is_empty() else "%s (%s)" % [msg, detail]
	_failures.append("%s: %s" % [_current_test, text])


func _show(value: Variant) -> String:
	if value is String:
		return '"%s"' % value
	return str(value)
