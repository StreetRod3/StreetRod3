extends AudioStreamPlayer

const MIX_RATE := 22050.0
const BUFFER_S := 0.12
## Idle rev on the tune screen. The sweet spot is the top of idle; each step away drops a semitone and a half.
const TUNE_RPM_PEAK := 700.0
const TUNE_SEMITONES_PER_STEP := 1.5
const TUNE_THROTTLE := 0.0
## On the tune screen the idle plays this loud, and off the sweet spot a second firing
## beat runs this much faster per step, so the two drift against each other and the
## idle lopes, and each firing misses this often per step: as Street Rod 2 sounds two
## notes that only agree when the timing is right.
const TUNE_AMP := 0.24
const TUNE_BEAT_PER_STEP := 0.025
const TUNE_MISS_PER_STEP := 0.05

var _playback: AudioStreamGeneratorPlayback
var _phase: float = 0.0
var _rumble_phase: float = 0.0
var _rpm: float = 600.0
var _throttle: float = 0.0
var _blown: bool = false
var _shifting: bool = false
var _amp: float = 0.0
## Steps off the sweet spot on the tune screen, or -1 elsewhere.
var _tune_off: int = -1
var _phase2: float = 0.0
var _missing: bool = false
var play_on_ready: bool = true


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_S
	stream = gen
	volume_db = -6.0 + GameState.exhaust_volume_db()
	bus = "Master"
	if play_on_ready:
		_start_playback()


## Idle speed for this tune step. Highest when `tune` is `sweet`.
static func tune_rpm(tune: int, sweet: int) -> float:
	var gap := float(absi(tune - sweet))
	return TUNE_RPM_PEAK * pow(2.0, -gap * TUNE_SEMITONES_PER_STEP / 12.0)


## Idle lope for the garage tune screen. Pitch is highest when `tune` is `sweet`.
func set_tune(tune: int, sweet: int) -> void:
	set_state(tune_rpm(tune, sweet), TUNE_THROTTLE, false, false)
	_tune_off = absi(tune - sweet)


func set_state(rpm: float, throttle: float, blown: bool, shifting: bool = false) -> void:
	_rpm = rpm
	_throttle = clampf(throttle, 0.0, 1.0)
	_blown = blown
	_shifting = shifting
	if blown:
		_amp = 0.0
		if playing:
			stop()
		return
	_start_playback()


func _start_playback() -> void:
	if playing:
		if _playback == null:
			_playback = get_stream_playback()
		return
	play()
	_playback = get_stream_playback()


func _process(_delta: float) -> void:
	if _blown or not playing:
		return
	_fill_buffer()


func _fill_buffer() -> void:
	if _playback == null:
		_playback = get_stream_playback()
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return

	var target_amp := 0.07 + 0.20 * _throttle
	if _tune_off >= 0:
		target_amp = TUNE_AMP
	if _shifting:
		target_amp *= 0.35
	_amp = lerpf(_amp, target_amp, 0.08)

	# V8 4-stroke: four exhaust pulses per revolution.
	# Floor stays under idle so the tune screen can lope below 500 rpm.
	var fire_hz := maxf(_rpm, 200.0) / 15.0
	var rumble_hz := fire_hz * 0.5
	var roughness := clampf((_rpm - 600.0) / 5900.0, 0.0, 1.0)
	var off := maxi(_tune_off, 0)
	var beat_hz := fire_hz * (1.0 + TUNE_BEAT_PER_STEP * float(off))

	for _i in frames:
		_phase += fire_hz / MIX_RATE
		if _phase >= 1.0:
			_phase -= floorf(_phase)
			_missing = off > 0 and randf() < TUNE_MISS_PER_STEP * float(off)
		_rumble_phase += rumble_hz / MIX_RATE
		if _rumble_phase >= 1.0:
			_rumble_phase -= floorf(_rumble_phase)

		var pulse := 1.0 - _phase
		pulse *= pulse
		if off > 0:
			_phase2 += beat_hz / MIX_RATE
			if _phase2 >= 1.0:
				_phase2 -= floorf(_phase2)
			var pulse2 := 1.0 - _phase2
			pulse = (pulse + pulse2 * pulse2) * 0.5
			if _missing:
				pulse *= 0.15
		var h2 := sin(_phase * TAU * 2.0) * 0.22
		var h3 := sin(_phase * TAU * 3.0) * 0.10
		var rumble := sin(_rumble_phase * TAU) * 0.16
		var noise := (randf() * 2.0 - 1.0) * (0.06 + 0.14 * _throttle * roughness)
		var sample := (pulse * 0.62 + h2 + h3 + rumble + noise) * _amp
		_playback.push_frame(Vector2(sample, sample))
