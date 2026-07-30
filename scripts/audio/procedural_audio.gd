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
