extends RefCounted

## Street Rod 2's AdLib driver, the part of it that plays the motor: AdLib Inc.'s
## sample driver (ADLIB.C's SetVoiceTimbre, SetVoicePitch, SetVoiceVolume, NoteOn
## and NoteOff) as the game linked it, turning a voice, a timbre, a bend and a
## volume into writes to the chip. Ported from SRDecomp's sr2/src/game/adlib.c
## (3c57:16c6..2514); only the melodic voices are here, the motor plays on 3 and 4.
## The F-number tables are the game's own, a little sharp, as SR2 builds them.

const _Opl2 := preload("res://scripts/opl2.gd")

const MID_PITCH := 0x2000
const _TABLES := 25

## MSR.SND's "motor" timbre: the low byte of each of its 28 words. Thirteen
## parameters for each operator (KSL MULT FB AR SL EG DR RR TL AM VIB KSR CNT),
## then the two waveforms.
const MOTOR: Array[int] = [
	0, 3, 3, 15, 15, 0, 0, 0, 11, 0, 0, 0, 1,
	0, 1, 122, 6, 0, 1, 0, 6, 0, 0, 0, 1, 1,
	1, 3,
]

enum { _KSL, _MULT, _FB, _AR, _SL, _EG, _DR, _RR, _TL, _AM, _VIB, _KSR, _CNT, _WS }

var chip = _Opl2.new()

var _fnum: Array[PackedInt32Array] = []
var _pitch_step := 25
var _transpose := PackedInt32Array()
var _table := PackedInt32Array()
var _note := PackedInt32Array()
var _key_on := PackedInt32Array()
var _volume := PackedInt32Array()
var _op: Array[PackedInt32Array] = []


func _init() -> void:
	_transpose.resize(9)
	_table.resize(9)
	_note.resize(9)
	_key_on.resize(9)
	_volume.resize(_Opl2.OPERATORS)
	for op in _Opl2.OPERATORS:
		var p := PackedInt32Array()
		p.resize(14)
		_op.append(p)
	_warm_init()


## SoundWarmInit (3c57:24ad): the tables, rhythm mode on, the depths 0, a range of
## 1, channels 0..8 keyed off, waveform select on and every volume 0x7f.
func _warm_init() -> void:
	for t in _TABLES:
		_fnum.append(fnum_table(4 * t, 100))
	chip.write(0xbd, 0x20)
	chip.write(0x08, 0)
	set_pitch_range(1)
	for v in 9:
		chip.write(0xa0 + v, 0)
		chip.write(0xb0 + v, 0)
	for slot in [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13, 16, 17, 18, 19, 20, 21]:
		chip.write(0xe0 + slot, 0)
	chip.write(0x01, 0x20)
	_volume.fill(0x7f)


## 3c57:1e1f: the first F-number of the table bend/den of a semitone up, times 8;
## 1e8e: that table's twelve, each 106/100 of the last, rounded and over 8.
static func fnum_table(bend: int, den: int) -> PackedInt32Array:
	var a := 100 * den
	var v := (a + 6 * bend) * 0xcb78 / (a * 25) * 0x24000 / 0x1b503
	var out := PackedInt32Array()
	out.append(((v + 4) & 0xffff) >> 3)
	for i in 11:
		v = v * 0x6a / 100
		out.append(((v + 4) & 0xffff) >> 3)
	return out


## SetPitchRange (3c57:23aa): 1..12 semitones for a full bend.
func set_pitch_range(range_: int) -> void:
	_pitch_step = clampi(range_, 1, 12) * 25


## The music driver's voice program (3c57:27e4): the volume kept, then the timbre.
func program(voice: int, volume: int, timbre: Array[int]) -> void:
	set_voice_volume(voice, volume)
	set_voice_timbre(voice, timbre)


## SetVoiceTimbre (3c57:22bc) for a melodic voice: both operators loaded and sent.
func set_voice_timbre(voice: int, timbre: Array[int]) -> void:
	var mod_op := _op_of(voice)
	_load_operator(mod_op, timbre.slice(0, 13), timbre[26])
	_load_operator(mod_op + 3, timbre.slice(13, 26), timbre[27])


## SetVoiceVolume (3c57:2128): 0..0x7f on the voice's carrier; more is 0x7f.
func set_voice_volume(voice: int, volume: int) -> void:
	var op := _op_of(voice) + 3
	_volume[op] = 0x7f if (volume & 0xffff) > 0x7f else volume
	_write_ksl_tl(op)


## SetVoicePitch (3c57:20cf): 0..0x3fff, 0x2000 none; the note played again as it was.
func set_voice_pitch(voice: int, bend: int) -> void:
	if (bend & 0xffff) > 0x3fff:
		bend = 0x3fff
	_change_pitch(voice, bend)
	_set_freq(voice, _note[voice], _key_on[voice])


## NoteOn (3c57:2024): the note less 12, keyed on.
func note_on(voice: int, note: int) -> void:
	_set_freq(voice, maxi(note - 12, 0), 1)


## NoteOff (3c57:1fd6).
func note_off(voice: int) -> void:
	_set_freq(voice, _note[voice], 0)


## ChangePitch (3c57:1d40): the bend as a table, a 25th of a semitone apart, and
## whole semitones of transpose.
func _change_pitch(voice: int, bend: int) -> void:
	var q := ((bend - MID_PITCH) * _pitch_step) / MID_PITCH
	var r: int
	if q < 0:
		var a := 0x18 - q
		_transpose[voice] = a / -25
		r = (a - 0x18) % 25
		if r != 0:
			r = 25 - r
	else:
		_transpose[voice] = q / 25
		r = q % 25
	_table[voice] = r


## SetFreq (3c57:1825).
func _set_freq(voice: int, note: int, key_on: int) -> void:
	_key_on[voice] = key_on
	_note[voice] = note
	var n := clampi(note + _transpose[voice], 0, 0x5f)
	var fnum := _fnum[_table[voice]][n % 12]
	chip.write(0xa0 + voice, fnum & 0xff)
	chip.write(0xb0 + voice, ((n / 12) << 2) + (0x20 if key_on != 0 else 0) + ((fnum >> 8) & 3))


## 3c57:1c6c: thirteen parameters and the waveform, and all of it sent (1b6a).
func _load_operator(op: int, params: Array[int], ws: int) -> void:
	var o := _op[op]
	for i in 13:
		o[i] = params[i]
	o[_WS] = ws & 3
	var slot := _slot_of(op)
	_write_ksl_tl(op)
	if op % 6 < 3:
		chip.write(0xc0 + _channel_of(op), (1 if o[_CNT] == 0 else 0) | (o[_FB] << 1))
	chip.write(0x60 + slot, (o[_AR] << 4) | (o[_DR] & 0xf))
	chip.write(0x80 + slot, (o[_SL] << 4) | (o[_RR] & 0xf))
	chip.write(0x20 + slot, (0x80 if o[_AM] else 0) + (0x40 if o[_VIB] else 0) + (0x20 if o[_EG] else 0) + (0x10 if o[_KSR] else 0) + (o[_MULT] & 0xf))
	chip.write(0xe0 + slot, o[_WS])


## 3c57:1ae2: KSL and the total level, scaled by the operator's volume.
func _write_ksl_tl(op: int) -> void:
	var o := _op[op]
	var a := 0x3f - (o[_TL] & 0x3f)
	var p := (a * _volume[op]) & 0xffff
	p = ((p << 1) + 0x7f) & 0xffff
	chip.write(0x40 + _slot_of(op), (o[_KSL] << 6) | (0x3f - p / 0xfe))


static func _op_of(voice: int) -> int:
	return (voice % 3) + 6 * (voice / 3)


static func _slot_of(op: int) -> int:
	return (op / 6) * 8 + op % 6


static func _channel_of(op: int) -> int:
	return (op / 6) * 3 + op % 3
