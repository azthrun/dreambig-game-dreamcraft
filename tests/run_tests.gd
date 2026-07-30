extends Node
## Headless test runner — the primary test seam for this project.
##
## Discovers `*_test.gd` under the scanned directories, runs every `test_*` method,
## prints a per-test result, and exits non-zero if anything failed.
##
## Run via ./run_tests.sh, or directly:
##   godot --headless --path . res://tests/run_tests.tscn
##   godot --headless --path . res://tests/run_tests.tscn -- --selftest
##
## `--selftest` scans tests/selftest/ instead, which contains a deliberately
## failing test. It exists to prove the non-zero exit path still works, and is
## excluded from the normal suite so the default run stays green.

const TEST_CASE := preload("res://tests/test_case.gd")

const SUFFIX := "_test.gd"
const DEFAULT_DIRS: Array[String] = [
	"res://tests/unit",
	"res://tests/integration",
]
const SELFTEST_DIRS: Array[String] = ["res://tests/selftest"]

const EXIT_OK := 0
const EXIT_FAILED := 1
const EXIT_NO_TESTS := 2


func _ready() -> void:
	var selftest := OS.get_cmdline_user_args().has("--selftest")
	var dirs := SELFTEST_DIRS if selftest else DEFAULT_DIRS

	var scripts: Array[String] = []
	for dir in dirs:
		_collect(dir, scripts)
	scripts.sort()

	if selftest:
		print("running SELFTEST suite (expected to fail)")
	print("scanning: %s" % ", ".join(dirs))

	if scripts.is_empty():
		printerr("no test scripts found (looked for *%s)" % SUFFIX)
		get_tree().quit(EXIT_NO_TESTS)
		return

	var totals := {"tests": 0, "failed": 0, "assertions": 0, "scripts": 0}
	var failure_log: Array[String] = []

	for path in scripts:
		# Must be awaited: _run_script suspends whenever a test yields on a physics
		# frame, and without awaiting here the runner would race ahead and quit
		# before those tests ever resumed — reporting zero tests and still passing.
		await _run_script(path, totals, failure_log)

	print("")
	print("%d scripts, %d tests, %d assertions, %d failed"
			% [totals["scripts"], totals["tests"], totals["assertions"],
			totals["failed"]])

	if not failure_log.is_empty():
		print("")
		print("failures:")
		for line in failure_log:
			print("  %s" % line)

	# A suite that runs but asserts nothing is a broken suite, not a passing one.
	if totals["assertions"] == 0:
		printerr("suite ran %d tests but evaluated no assertions"
				% totals["tests"])
		get_tree().quit(EXIT_NO_TESTS)
		return

	get_tree().quit(EXIT_FAILED if totals["failed"] > 0 else EXIT_OK)


## Recursively gather test script paths. `out` is an Array so it accumulates by
## reference across recursion.
func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect(dir_path.path_join(entry), out)
		elif entry.ends_with(SUFFIX):
			out.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


func _run_script(path: String, totals: Dictionary,
		failure_log: Array[String]) -> void:
	var script: GDScript = load(path)
	if script == null:
		printerr("  could not load %s" % path)
		totals["failed"] += 1
		failure_log.append("%s: failed to load" % path)
		return

	# A script with a parse error still loads as an object, but uncompiled. Report
	# that as a compile failure rather than as a wrong base class, which would send
	# someone looking in entirely the wrong place.
	if not script.can_instantiate():
		printerr("  %s failed to compile, skipping" % path)
		totals["failed"] += 1
		failure_log.append("%s: failed to compile (see parse errors above)" % path)
		return

	if not _extends_test_case(script):
		printerr("  %s does not extend test_case.gd, skipping" % path)
		totals["failed"] += 1
		failure_log.append("%s: does not extend test_case.gd" % path)
		return

	print("")
	print("%s" % path.get_file())
	totals["scripts"] += 1

	var methods := _test_methods(script)
	if methods.is_empty():
		printerr("  no test_* methods in %s" % path)
		totals["failed"] += 1
		failure_log.append("%s: no test_* methods" % path)
		return

	for method in methods:
		# A fresh instance per test, so tests cannot leak state into each other.
		var case: RefCounted = script.new()
		case.set_test_root(self)
		case.begin_test(method)
		# Awaited so integration tests can yield on physics frames. A test that
		# never awaits simply resumes immediately.
		await case.before_each()
		await case.call(method)
		await case.after_each()

		var failures: Array = case.failures()
		totals["tests"] += 1
		totals["assertions"] += case.assertion_count()

		# A test that evaluated no assertions did not pass, it failed to run. GDScript
		# runtime errors cannot be caught, so a test that errors partway through simply
		# stops — and without this it would report green having asserted nothing.
		if failures.is_empty() and case.assertion_count() == 0:
			totals["failed"] += 1
			print("  FAIL  %s" % method)
			print("        asserted nothing (did it error? see output above)")
			failure_log.append("%s -> %s: asserted nothing"
					% [path.get_file(), method])
			continue

		if failures.is_empty():
			print("  PASS  %s" % method)
		else:
			totals["failed"] += 1
			print("  FAIL  %s" % method)
			for f in failures:
				print("        %s" % f)
				failure_log.append("%s -> %s" % [path.get_file(), f])


func _extends_test_case(script: GDScript) -> bool:
	var base := script.get_base_script()
	while base != null:
		if base == TEST_CASE:
			return true
		base = base.get_base_script()
	return false


## Test methods, sorted so run order is deterministic.
func _test_methods(script: GDScript) -> Array[String]:
	var names: Array[String] = []
	for method in script.get_script_method_list():
		var name: String = method["name"]
		if name.begins_with("test_") and not names.has(name):
			names.append(name)
	names.sort()
	return names
