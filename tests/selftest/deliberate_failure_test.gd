extends "res://tests/test_case.gd"
## Deliberately failing test, run only via `./run_tests.sh --selftest`.
##
## Proves the runner's non-zero exit path actually works. Without this, a runner
## bug that swallowed failures would look identical to a green suite — CI would
## pass forever and nobody would know.
##
## Excluded from the default suite, so the normal run stays green.


func test_this_passes() -> void:
	assert_true(true, "the selftest suite should contain a passing test too")


func test_this_fails_on_purpose() -> void:
	assert_eq(1, 2, "deliberate failure: proves FAIL is reported")


func test_this_also_fails_on_purpose() -> void:
	fail("deliberate failure: proves multiple failures are collected")
