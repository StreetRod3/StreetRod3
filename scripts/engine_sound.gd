extends AudioStreamPlayer

## The engine as Street Rod 2 plays it on the AdLib: MSR.SND's "motor" timbre held
## on one voice of an emulated OPL2, bent up with the revs and louder with them
## (SRDecomp's engine.c, 1001:27c4). On the tune screen a second motor voice plays
## against the first, as SR2's tune screen does (tune.c, 3c57 7e06): the two bend
## apart with each step off the sweet spot and beat against each other, and agree
## only when the timing is right.

const _Sr2Adlib := preload("res://scripts/sr2_adlib.gd")
const _Opl2 := preload("res://scripts/opl2.gd")
const _Car := preload("res://scripts/player_race_car.gd")

const BUFFER_S := 0.12
## Idle rev on the tune screen. The sweet spot is the top of idle; each step away drops a semitone and a half.
const TUNE_RPM_PEAK := 700.0
const TUNE_SEMITONES_PER_STEP := 1.5
## SR2's rev counter idles at 1500 and redlines at 5700. Ours run from the car's
## idle to its redline, and are laid onto SR2's in a straight line.
const SR2_IDLE := 1500
const SR2_REDLINE := 5700
## The motor's note, and the voices SR2 plays it on.
const _NOTE := 0x18
const _VOICE := 3
const _VOICE2 := 4
## The chip on its own is quiet beside the music; this brings the motor up to where
## the engine has always sat in the mix.
const GAIN := 6.0
## The AdLib card's output capacitor. The motor's waveform is all on one side of
## zero and the card passes only what moves, so a one-pole high-pass at this corner
## takes the offset away as the card does.
const DC_CORNER_HZ := 5.0

var _driver = _Sr2Adlib.new()
var _playback: AudioStreamGeneratorPlayback
var _rpm: float = 600.0
var _blown: bool = false
## On the tune screen, the steps from the sweet spot (signed); off it, not tuning.
var _tuning: bool = false
var _tune_step: int = 0
var _voice_on: bool = false
var _voice2_on: bool = false
var _dc_r: float = 1.0
var _dc_in: float = 0.0
var _dc_out: float = 0.0
var play_on_ready: bool = true


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _Opl2.SAMPLE_RATE
	gen.buffer_length = BUFFER_S
	stream = gen
	volume_db = -6.0 + GameState.exhaust_volume_db()
	bus = "Master"
	_dc_r = exp(-TAU * DC_CORNER_HZ / _Opl2.SAMPLE_RATE)
	if play_on_ready:
		_start_playback()


## Idle speed for this tune step. Highest when `tune` is `sweet`.
static func tune_rpm(tune: int, sweet: int) -> float:
	var gap := float(absi(tune - sweet))
	return TUNE_RPM_PEAK * pow(2.0, -gap * TUNE_SEMITONES_PER_STEP / 12.0)


## Our revs on SR2's rev counter. At or past the redline it reads SR2's redline
## exactly, where SR2's note jumps to the top of its bend.
static func sr2_rpm(rpm: float) -> int:
	if rpm >= _Car.RPM_REDLINE:
		return SR2_REDLINE
	var f := (rpm - _Car.RPM_IDLE) / (_Car.RPM_REDLINE - _Car.RPM_IDLE)
	return clampi(SR2_IDLE + int(f * float(SR2_REDLINE - SR2_IDLE)), SR2_IDLE, SR2_REDLINE - 1)


## 1001:27f5..2807: the motor's bend for SR2's rev counter, 3 rpm - 4500, or the
## top of the bend at exactly the redline; and its volume, (rpm - 1500) / 128 + 0x50.
static func motor_bend(rpm: int) -> int:
	return 0x3fff if rpm == SR2_REDLINE else 3 * rpm - 4500


static func motor_volume(rpm: int) -> int:
	return (rpm - SR2_IDLE) / 128 + 0x50


## The two motor voices for the garage tune screen; they agree when `tune` is `sweet`.
func set_tune(tune: int, sweet: int) -> void:
	_tuning = true
	_tune_step = tune - sweet
	set_state(tune_rpm(tune, sweet), 0.0, false, false)


## SR2's engine note follows the revs alone, so the throttle and the shift change nothing.
func set_state(rpm: float, _throttle: float, blown: bool, _shifting: bool = false) -> void:
	_rpm = rpm
	_blown = blown
	if blown:
		_motor_off()
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


## 3c57:0b2c (and 0bd2 for the second voice): the motor programmed at volume 0x40,
## a range of six semitones, no bend, and the note keyed on again.
func _motor_on(voice: int) -> void:
	_driver.program(voice, 0x40, _Sr2Adlib.MOTOR)
	_driver.set_pitch_range(6)
	_driver.set_voice_pitch(voice, 0)
	_driver.note_off(voice)
	_driver.note_on(voice, _NOTE)


func _motor_off() -> void:
	if _voice_on:
		_driver.set_voice_volume(_VOICE, 0)
		_driver.note_off(_VOICE)
	if _voice2_on:
		_driver.note_off(_VOICE2)
	_voice_on = false
	_voice2_on = false


func _motor_note(voice: int, bend: int, volume: int) -> void:
	_driver.set_voice_pitch(voice, bend)
	_driver.set_voice_volume(voice, volume)


func _fill_buffer() -> void:
	if _playback == null:
		_playback = get_stream_playback()
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	if not _voice_on:
		_motor_on(_VOICE)
		_voice_on = true
	if _tuning:
		if not _voice2_on:
			_motor_on(_VOICE2)
			_voice2_on = true
		var t := _tune_step
		var volume := 0x4a if t == 0 else 0x52
		_motor_note(_VOICE, (((t + 0x10) * 2) & 0xff) << 8, volume)
		_motor_note(_VOICE2, t * 0x300 + 0x2000, volume)
	else:
		var rpm := sr2_rpm(_rpm)
		_motor_note(_VOICE, motor_bend(rpm), motor_volume(rpm))
	var buf: PackedVector2Array = _driver.chip.render(frames, GAIN)
	var r := _dc_r
	var x1 := _dc_in
	var y1 := _dc_out
	for i in frames:
		var x := buf[i].x
		y1 = x - x1 + r * y1
		x1 = x
		buf[i] = Vector2(y1, y1)
	_dc_in = x1
	_dc_out = y1
	_playback.push_buffer(buf)
