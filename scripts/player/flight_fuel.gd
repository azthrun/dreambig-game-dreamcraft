extends RefCounted
## The flying suit's fuel tank: how much it holds, how fast flying spends it.
##
## Pure of Node and SceneTree, like SurvivalStats — advanced by an injected delta so a
## whole flight can be simulated in a test without waiting for it.
##
## Starts empty. The suit itself is found in a cache; fuel is a separate, rarer find (see
## `cache_loot.gd`), so finding the suit does not also hand over the ability to use it.

## Enough for a short flight, not island-wide travel — the acceptance criterion the whole
## gadget rests on. At CAPACITY and DRAIN_PER_SECOND below, a full tank lasts 20 seconds.
const CAPACITY := 120.0

const DRAIN_PER_SECOND := 6.0

## How much tank one found `FUEL` item tops up. A third of a full tank, so a single find
## is worth a real flight without instantly maxing the suit out.
const FUEL_PER_ITEM := 30.0

var _capacity: float
var _fuel: float


func _init(capacity: float = CAPACITY) -> void:
	_capacity = maxf(capacity, 0.001)
	_fuel = 0.0


func fuel() -> float:
	return _fuel


func capacity() -> float:
	return _capacity


func fraction() -> float:
	return _fuel / _capacity


func is_empty() -> bool:
	return _fuel <= 0.0


func is_full() -> bool:
	return _fuel >= _capacity


func can_fly() -> bool:
	return not is_empty()


## Sets the tank to an exact value, for a save file to replay — `add` and `drain` are
## both relative, which is right for gameplay but not for restoring a precise figure.
func set_fuel(value: float) -> void:
	_fuel = clampf(value, 0.0, _capacity)


## Adds fuel, capped at capacity. Returns how much was actually added, the same
## partial-success shape as `Inventory.add`.
func add(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var added := minf(amount, _capacity - _fuel)
	_fuel += added
	return added


## Spends fuel for `delta` seconds of flight. Never goes negative — exhaustion is read
## through `is_empty()`, not by a caller checking for a negative tank.
func drain(delta: float) -> void:
	if delta <= 0.0:
		return
	_fuel = maxf(_fuel - DRAIN_PER_SECOND * delta, 0.0)


## Compact readout for the debug overlay.
func status_line() -> String:
	return "fuel: %.0f / %.0f" % [_fuel, _capacity]
