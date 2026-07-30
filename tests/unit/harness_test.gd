extends "res://tests/test_case.gd"
## Tests the assertion helpers themselves.
##
## Worth having: every other test in the project trusts these helpers, so a helper
## that silently never fails would make the whole suite meaningless while still
## reporting green. Each test drives a separate probe instance and asserts on what
## the probe recorded.

const TEST_CASE := preload("res://tests/test_case.gd")


func _probe() -> RefCounted:
	var probe: RefCounted = TEST_CASE.new()
	probe.begin_test("probe")
	return probe


func test_passing_assertions_record_no_failures() -> void:
	var probe := _probe()
	probe.assert_true(true)
	probe.assert_false(false)
	probe.assert_eq(3, 3)
	probe.assert_ne(3, 4)
	probe.assert_almost_eq(1.0, 1.0000001, 0.001)
	probe.assert_in_range(5.0, 0.0, 10.0)
	probe.assert_has([1, 2, 3], 2)
	probe.assert_not_has([1, 2, 3], 9)
	assert_eq(probe.failures().size(), 0, "no assertion above should fail")
	assert_eq(probe.assertion_count(), 8, "every assertion should be counted")


func test_assert_eq_detects_inequality() -> void:
	var probe := _probe()
	probe.assert_eq(3, 4)
	assert_eq(probe.failures().size(), 1)


func test_assert_true_detects_false() -> void:
	var probe := _probe()
	probe.assert_true(false)
	assert_eq(probe.failures().size(), 1)


func test_assert_almost_eq_respects_epsilon() -> void:
	var probe := _probe()
	probe.assert_almost_eq(1.0, 1.5, 0.1)
	assert_eq(probe.failures().size(), 1, "0.5 apart exceeds epsilon 0.1")
	probe.assert_almost_eq(1.0, 1.05, 0.1)
	assert_eq(probe.failures().size(), 1, "0.05 apart is within epsilon 0.1")


func test_assert_in_range_is_inclusive() -> void:
	var probe := _probe()
	probe.assert_in_range(0.0, 0.0, 10.0)
	probe.assert_in_range(10.0, 0.0, 10.0)
	assert_eq(probe.failures().size(), 0, "bounds themselves are in range")
	probe.assert_in_range(10.1, 0.0, 10.0)
	assert_eq(probe.failures().size(), 1, "above the upper bound must fail")


func test_assert_has_covers_collection_kinds() -> void:
	var probe := _probe()
	probe.assert_has({"seed": 1}, "seed")
	probe.assert_has("mountains", "moun")
	probe.assert_has(PackedStringArray(["plains", "ocean"]), "ocean")
	assert_eq(probe.failures().size(), 0,
			"dictionary keys, substrings and packed arrays should all work")


func test_failure_message_names_the_test_and_the_reason() -> void:
	var probe := _probe()
	probe.assert_eq(1, 2, "heights should match")
	assert_eq(probe.failures().size(), 1)
	var message: String = probe.failures()[0]
	assert_has(message, "probe", "message should name the test")
	assert_has(message, "heights should match", "message should carry the note")
	assert_has(message, "expected 2, got 1", "message should show both values")


func test_explicit_fail_records_a_failure() -> void:
	var probe := _probe()
	probe.fail("unreachable branch")
	assert_eq(probe.failures().size(), 1)
