extends RefCounted

## Sounds of the jack, the wheels, and the tire machine, built in code like the other shop
## sounds. Each is made the first time it is asked for and kept.

const RATE := 22050

static var _made: Dictionary = {}


## The sound called `sound_name`: "wrench", "jack_pump", "jack_release", "thud", "motor",
## "bead_pop", "air", or "blowout". The motor loops.
static func stream(sound_name: String) -> AudioStreamWAV:
	if not _made.has(sound_name):
		_made[sound_name] = _build(sound_name)
	return _made[sound_name]


static func _build(sound_name: String) -> AudioStreamWAV:
	match sound_name:
		"wrench":
			return _wav(_wrench())
		"jack_pump":
			return _wav(_jack_pump())
		"jack_release":
			return _wav(_jack_release())
		"thud":
			return _wav(_thud())
		"motor":
			return _wav(_motor(), true)
		"bead_pop":
			return _wav(_bead_pop())
		"air":
			return _wav(_air())
		"blowout":
			return _wav(_blowout())
	push_warning("No shop sound called %s" % sound_name)
	return _wav(PackedFloat32Array([0.0]))


static func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


static func _blank(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	return out


## An air wrench: a fast rattle of hammer blows, rising as the nut breaks loose.
static func _wrench() -> PackedFloat32Array:
	var out := _blank(0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var blows := 15
	for b in blows:
		var start := int(float(b) / float(blows) * 0.46 * RATE)
		var level := lerpf(0.45, 0.8, float(b) / float(blows))
		for k in int(0.022 * RATE):
			var i := start + k
			if i >= out.size():
				break
			var t := float(k) / RATE
			var env := exp(-t * 260.0)
			out[i] += (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 1150.0 * t) * 0.35 + sin(TAU * 240.0 * t) * 0.3) * env * level
	return out


## A floor jack being pumped: a low stroke and a creak of the handle, over and over.
static func _jack_pump() -> PackedFloat32Array:
	var out := _blank(1.5)
	var strokes := 5
	for s in strokes:
		var start := int(float(s) / float(strokes) * 1.4 * RATE)
		for k in int(0.2 * RATE):
			var i := start + k
			if i >= out.size():
				break
			var t := float(k) / RATE
			var body := sin(TAU * 95.0 * t) * exp(-t * 24.0) * 0.75
			var creak := sin(TAU * (720.0 + 500.0 * t) * t) * exp(-t * 30.0) * 0.14
			out[i] += body + creak
	return out


## The jack's valve opening: a long breath of oil and air, and the car settling.
static func _jack_release() -> PackedFloat32Array:
	var out := _blank(1.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var low := 0.0
	for i in out.size():
		var t := float(i) / RATE
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.25)
		out[i] = low * minf(t * 12.0, 1.0) * exp(-t * 1.1) * 0.5
		if t > 1.2:
			var u := t - 1.2
			out[i] += sin(TAU * 62.0 * u) * exp(-u * 16.0) * 0.8
	return out


## A wheel and tire landing on the floor, with a small bounce.
static func _thud() -> PackedFloat32Array:
	var out := _blank(0.42)
	for bounce in 2:
		var start := int((0.0 if bounce == 0 else 0.2) * RATE)
		var level := 0.85 if bounce == 0 else 0.3
		for k in out.size() - start:
			var t := float(k) / RATE
			out[start + k] += (sin(TAU * 78.0 * t) + sin(TAU * 131.0 * t) * 0.35) * exp(-t * 20.0) * level * 0.8
	return out


## The tire machine's gear motor: a mains hum and a gear whine, a whole number of cycles
## in the one second so that it loops without a click.
static func _motor() -> PackedFloat32Array:
	var out := _blank(1.0)
	for i in out.size():
		var t := float(i) / float(out.size())
		var hum := sin(TAU * 100.0 * t) * 0.34 + sin(TAU * 200.0 * t) * 0.16
		var whine := sin(TAU * 430.0 * t) * 0.08 + sin(TAU * 860.0 * t) * 0.03
		var chug := 1.0 + sin(TAU * 7.0 * t) * 0.12
		out[i] = (hum + whine) * chug
	return out


## A tire's bead letting go of the rim.
static func _bead_pop() -> PackedFloat32Array:
	var out := _blank(0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in out.size():
		var t := float(i) / RATE
		out[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.35 + sin(TAU * 170.0 * t) * exp(-t * 34.0) * 0.6
	return out


## Air going into a tire, ending in the bead seating with a snap.
static func _air() -> PackedFloat32Array:
	var out := _blank(0.75)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var last := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		# The difference of neighbors leaves the hiss and takes out the rumble.
		var hiss := noise - last
		last = noise
		out[i] = hiss * minf(t * 10.0, 1.0) * clampf((0.6 - t) * 12.0, 0.0, 1.0) * 0.2
		if t > 0.58:
			var u := t - 0.58
			out[i] += sin(TAU * 210.0 * u) * exp(-u * 40.0) * 0.6
	return out


## A tire blowing out: the bang, the thump of the air leaving, and the shreds flapping.
static func _blowout() -> PackedFloat32Array:
	var out := _blank(1.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in out.size():
		var t := float(i) / RATE
		var bang := rng.randf_range(-1.0, 1.0) * exp(-t * 55.0)
		var thump := sin(TAU * 58.0 * t) * exp(-t * 9.0) * 0.8
		var whoosh := rng.randf_range(-1.0, 1.0) * exp(-t * 5.0) * 0.14
		out[i] = (bang + thump + whoosh) * 0.5
	for flap in 8:
		var start := int((0.3 + 0.12 * float(flap)) * RATE)
		var level := lerpf(0.55, 0.2, float(flap) / 8.0)
		for k in int(0.05 * RATE):
			var i := start + k
			if i >= out.size():
				break
			var t := float(k) / RATE
			out[i] += (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 150.0 * t)) * exp(-t * 90.0) * level
	return out
