extends "res://scripts/creatures/lootable.gd"
## A supply cache: a lootable that comes back.
##
## Extends the corpse's Lootable rather than reimplementing it, and is named `Lootable`
## in the tree, so the player's existing hold-to-take interaction finds it without
## knowing caches exist — the same trick the cooking rack uses. No new key, no new
## prompt, no second refusal path.
##
## What it adds is the two things a corpse does not have: an identity that survives
## being emptied, and a refill.

const CacheLoot := preload("res://scripts/world/props/cache_loot.gd")

signal refilled

## How long an opened cache stays empty.
##
## Deliberately far longer than a berry bush's 120 s. A crate that refilled on a walk
## around the block would turn ammunition into a renewable resource, which is the one
## thing SPEC says it must not be.
const RESPAWN_SECONDS := 900.0

## Stable across the cache's whole life, including while it is empty. This is what a
## save file records so that reloading cannot re-open a crate that has been looted —
## which is the actual reason the id exists.
var cache_id := 0

var _seed := 0
var _looted := false
var _remaining := 0.0
## How many times this crate has been emptied. Feeds the roll so a refill is not the
## same reward again, while leaving `cache_id` alone — the id is what a save file keys
## on, so it has to outlive the contents.
var _refills := 0
## Meshes hidden while the crate is empty, so a looted cache reads as looted from a
## distance rather than only when it refuses to open.
var _open_visuals: Array[Node3D] = []


func _ready() -> void:
	# Nothing to count down until something is taken. Thousands of props on the island
	# means per-frame cost has to follow the few that are in a temporary state.
	set_process(false)


## Fills the crate from the loot table. `visuals` are hidden while it is empty.
func configure_cache(p_seed: int, p_cache_id: int, visuals: Array = []) -> void:
	_seed = p_seed
	cache_id = p_cache_id
	_open_visuals.clear()
	for node in visuals:
		if node is Node3D:
			_open_visuals.append(node)
	configure(CacheLoot.roll(_seed, cache_id))


## Whether this cache has been opened and not yet refilled.
func is_looted() -> bool:
	return _looted


func time_until_refill() -> float:
	return _remaining


## How many times this crate has been emptied. Read by a save so a reloaded crate's
## *next* refill still advances the roll rather than repeating one already given out.
func refills_count() -> int:
	return _refills


## Restores a cache to its opened state, for a save file to replay. `remaining` is what
## was left on the refill timer; `refills` is how many times it had already been emptied,
## which the next `refill()` roll depends on.
func restore_looted(remaining: float = RESPAWN_SECONDS, refills: int = 0) -> void:
	contents = {}
	_emptied = true
	_looted = true
	_remaining = maxf(remaining, 0.0)
	_refills = maxi(refills, 0)
	_apply_visuals()
	set_process(true)


func loot(inventory: RefCounted) -> Dictionary:
	var taken := super(inventory)
	# Only a crate that was actually emptied starts refilling. A player who arrives
	# full takes what fits and can come back for the rest, exactly as with a corpse.
	if not taken.is_empty() and is_empty() and not _looted:
		_looted = true
		_remaining = RESPAWN_SECONDS
		_apply_visuals()
		set_process(true)
	return taken


## Advances the refill. Separate from `_process` so the interval can be tested by
## injecting deltas rather than by waiting fifteen minutes.
func tick(delta: float) -> void:
	if not _looted or delta <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		refill()


## Fills the crate again, with different contents: the roll is advanced by how many
## times this cache has been emptied, so a known crate is not a known reward.
func refill() -> void:
	if not _looted:
		return
	_looted = false
	_remaining = 0.0
	_emptied = false
	_refills += 1
	configure(CacheLoot.roll(_seed, cache_id + _refills * 977))
	_apply_visuals()
	set_process(false)
	refilled.emit()


func _process(delta: float) -> void:
	tick(delta)


func _apply_visuals() -> void:
	for node in _open_visuals:
		if is_instance_valid(node):
			node.visible = not _looted
