extends RefCounted
## The player's condition: health, hunger and stamina.
##
## Pure of Node and SceneTree. Advanced by an injected delta rather than by real time, so
## a whole day of starvation can be simulated in a test without waiting for one.
##
## Rates are data, not logic. They live in one dictionary that can be overridden whole or
## in part at construction, which is what lets balance be tuned — and tested — without
## touching any of the code that applies them.

## Every tunable in one place. Overriding any subset at construction replaces only those.
const DEFAULT_RATES := {
	"max_health": 100.0,
	"max_hunger": 100.0,
	"max_stamina": 100.0,

	## Hunger fills in about twelve minutes, a little under one 20-minute day. Long
	## enough that eating is not constant nagging, short enough to matter each day.
	"hunger_per_second": 0.14,

	## Damage once hunger is full. Fifty seconds from starving to dead, which is enough
	## warning to do something about it.
	"starvation_damage_per_second": 2.0,

	## Sprinting empties stamina in roughly eight seconds and refilling takes twelve, so
	## sprinting is a burst rather than a travel mode.
	"stamina_sprint_drain_per_second": 12.0,
	"stamina_regen_per_second": 8.0,

	## Pause before stamina starts coming back, so tapping sprint repeatedly does not
	## dodge the cost.
	"stamina_regen_delay_seconds": 1.0,

	## Health only recovers while well fed, which is what makes food worth gathering
	## beyond simply not starving.
	"health_regen_per_second": 0.45,
	"health_regen_hunger_ceiling": 50.0,
}

var _rates: Dictionary
var _health: float
var _hunger: float
var _stamina: float
var _regen_delay := 0.0


func _init(rates: Dictionary = {}) -> void:
	_rates = DEFAULT_RATES.duplicate()
	for key in rates:
		_rates[key] = rates[key]
	revive()


## Resets to full health, empty hunger and full stamina. Used at spawn and respawn.
func revive() -> void:
	_health = rate("max_health")
	_hunger = 0.0
	_stamina = rate("max_stamina")
	_regen_delay = 0.0


func rate(key: String) -> float:
	return float(_rates.get(key, DEFAULT_RATES.get(key, 0.0)))


func health() -> float:
	return _health


func hunger() -> float:
	return _hunger


func stamina() -> float:
	return _stamina


func health_fraction() -> float:
	return _health / maxf(rate("max_health"), 0.001)


func hunger_fraction() -> float:
	return _hunger / maxf(rate("max_hunger"), 0.001)


func stamina_fraction() -> float:
	return _stamina / maxf(rate("max_stamina"), 0.001)


func is_dead() -> bool:
	return _health <= 0.0


func is_starving() -> bool:
	return _hunger >= rate("max_hunger")


## Sprinting needs some stamina left. Checked rather than assumed, so an exhausted
## player cannot sprint on fumes.
func can_sprint() -> bool:
	return _stamina > 0.0 and not is_dead()


## Advances all three pools. `sprinting` is whether the player is actually sprinting
## this frame, not whether they are asking to.
func tick(delta: float, sprinting: bool) -> void:
	if delta <= 0.0 or is_dead():
		return

	_hunger = minf(_hunger + rate("hunger_per_second") * delta,
			rate("max_hunger"))

	if sprinting:
		_stamina = maxf(
				_stamina - rate("stamina_sprint_drain_per_second") * delta, 0.0)
		_regen_delay = rate("stamina_regen_delay_seconds")
	else:
		# The delay is consumed out of this frame's time and the remainder still
		# regenerates. Spending the whole frame on the delay would mean a long frame
		# recovers nothing at all, so recovery would depend on frame rate.
		var usable := delta
		if _regen_delay > 0.0:
			var consumed := minf(_regen_delay, usable)
			_regen_delay -= consumed
			usable -= consumed
		if usable > 0.0:
			_stamina = minf(
					_stamina + rate("stamina_regen_per_second") * usable,
					rate("max_stamina"))

	if is_starving():
		damage(rate("starvation_damage_per_second") * delta)
	elif _hunger <= rate("health_regen_hunger_ceiling"):
		_health = minf(_health + rate("health_regen_per_second") * delta,
				rate("max_health"))


## Sets all three pools to exact saved values, for a save file to replay. Distinct from
## `revive`, which resets to a fixed full/empty/full rather than arbitrary figures, and
## from `damage`/`heal`/`eat`, which are all relative to whatever the pools already are.
func restore(p_health: float, p_hunger: float, p_stamina: float) -> void:
	_health = clampf(p_health, 0.0, rate("max_health"))
	_hunger = clampf(p_hunger, 0.0, rate("max_hunger"))
	_stamina = clampf(p_stamina, 0.0, rate("max_stamina"))
	_regen_delay = 0.0


func damage(amount: float) -> void:
	if amount <= 0.0:
		return
	_health = maxf(_health - amount, 0.0)


func heal(amount: float) -> void:
	if amount <= 0.0 or is_dead():
		return
	_health = minf(_health + amount, rate("max_health"))


## Eating reduces hunger. Returns how much was actually used, so food is not wasted
## silently when already full.
func eat(nutrition: float) -> float:
	if nutrition <= 0.0:
		return 0.0
	var used := minf(nutrition, _hunger)
	_hunger = maxf(_hunger - nutrition, 0.0)
	return used


## Compact readout for the debug overlay.
func status_line() -> String:
	return "player: health %.0f, hunger %.0f, stamina %.0f%s" % [
		_health, _hunger, _stamina,
		" DEAD" if is_dead() else (" STARVING" if is_starving() else ""),
	]
