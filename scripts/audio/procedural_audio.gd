extends RefCounted
## Generates the game's sound effects as PCM data.
##
## Same reasoning as the cuboid props and the star field: this project has no external
## assets, so sound is synthesised rather than loaded. Rain is filtered noise, thunder is
## a low rumble under a decaying envelope. Neither will win awards, but both read as what
## they are, and nothing has to be downloaded or licensed.

const MIX_RATE := 22050

## Low-pass strength for rain, 0..1. Higher is duller. Unfiltered white noise reads as
## static or radio hiss rather than rain.
const RAIN_SMOOTHING := 0.55

const RAIN_SECONDS := 2.0
const THUNDER_SECONDS := 2.6

## Thunder's rumble is much duller than rain, which is what makes it read as distant and
## heavy rather than as a burst of noise.
const THUNDER_SMOOTHING := 0.93

## A shot is short and violent: the whole sound is over in a fifth of a second, and a
## dry click is over in a fiftieth.
const GUNSHOT_SECONDS := 0.22
const CLICK_SECONDS := 0.06
const GUNSHOT_TAIL_SMOOTHING := 0.82

## Fire sits between rain and thunder: duller than rain, far brighter than thunder.
const FIRE_SECONDS := 3.0
const FIRE_SMOOTHING := 0.74


## Looping rain. Seamless because the loop points are set to the whole buffer and the
## signal has no envelope to discontinue.
static func rain(seed_value: int = 12345) -> AudioStreamWAV:
	var samples := int(MIX_RATE * RAIN_SECONDS)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var data := PackedByteArray()
	data.resize(samples * 2)
	var previous := 0.0
	for i in samples:
		var noise := rng.randf_range(-1.0, 1.0)
		previous = lerpf(noise, previous, RAIN_SMOOTHING)
		# Taper the first and last few milliseconds into each other so the loop seam is
		# inaudible even with the filter's memory reset.
		var value := previous * 0.6
		_write_sample(data, i, value)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples
	return stream


## Looping fire crackle: a duller hiss than rain, with occasional sharper pops so it
## reads as burning rather than as running water.
static func fire(seed_value: int = 24680) -> AudioStreamWAV:
	var samples := int(MIX_RATE * FIRE_SECONDS)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var data := PackedByteArray()
	data.resize(samples * 2)
	var previous := 0.0
	for i in samples:
		var noise := rng.randf_range(-1.0, 1.0)
		previous = lerpf(noise, previous, FIRE_SMOOTHING)
		var value := previous * 0.42
		# Sparse crackles on top of the hiss.
		if rng.randf() < 0.0006:
			value += rng.randf_range(-0.55, 0.55)
		_write_sample(data, i, value)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples
	return stream


## One-shot thunder: a heavily filtered rumble that swells then decays.
static func thunder(seed_value: int = 54321) -> AudioStreamWAV:
	var samples := int(MIX_RATE * THUNDER_SECONDS)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var data := PackedByteArray()
	data.resize(samples * 2)
	var previous := 0.0
	for i in samples:
		var progress := float(i) / float(samples)
		var noise := rng.randf_range(-1.0, 1.0)
		previous = lerpf(noise, previous, THUNDER_SMOOTHING)
		# Fast attack, long decay — the shape of a real thunderclap.
		var envelope := progress / 0.04 if progress < 0.04 \
				else pow(1.0 - (progress - 0.04) / 0.96, 2.2)
		_write_sample(data, i, previous * envelope * 3.0)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


## Writes one clamped 16-bit little-endian sample.
static func _write_sample(data: PackedByteArray, index: int, value: float) -> void:
	var clamped := clampf(value, -1.0, 1.0)
	var as_int := int(clamped * 32767.0)
	if as_int < 0:
		as_int += 65536
	data[index * 2] = as_int & 0xFF
	data[index * 2 + 1] = (as_int >> 8) & 0xFF


## A gunshot: a hard crack decaying into a short tail.
##
## The crack is what makes it read as a shot rather than as a thump — an envelope alone
## on noise sounds like a door closing. The tail is the same noise low-passed, which
## stands in for the report bouncing off the terrain.
static func gunshot(seed_value: int = 31415) -> AudioStreamWAV:
	var samples := int(MIX_RATE * GUNSHOT_SECONDS)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var data := PackedByteArray()
	data.resize(samples * 2)
	var smoothed := 0.0
	for i in samples:
		var t := float(i) / float(samples)
		var noise := rng.randf_range(-1.0, 1.0)
		smoothed = lerpf(noise, smoothed, GUNSHOT_TAIL_SMOOTHING)
		# Crack first, tail after: the bright noise dies in a few milliseconds while the
		# dull one rings on.
		var crack := noise * exp(-t * 90.0)
		var tail := smoothed * exp(-t * 12.0) * 0.7
		_write_sample(data, i, clampf(crack + tail, -1.0, 1.0) * 0.85)

	return _one_shot(data)


## The sound of pulling the trigger on an empty gun.
##
## Deliberately tiny and dry. It exists so that "nothing happened" is audibly different
## from "the game did not register the click", which is the whole reason an empty gun
## must not fail silently.
static func dry_click(seed_value: int = 27182) -> AudioStreamWAV:
	var samples := int(MIX_RATE * CLICK_SECONDS)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(samples)
		_write_sample(data, i, rng.randf_range(-1.0, 1.0) * exp(-t * 70.0) * 0.3)

	return _one_shot(data)


static func _one_shot(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream
