class_name MidiSong
extends RefCounted

## Standard MIDI, played as a square wave. The Street Rod files are the PC speaker
## tunes (one voice, a square lead), and a square wave is that speaker.

const RATE := 22050
const _AMP := 0.3
const _VOICES := 8

const _TEMPO := 1
const _RANGE := 2
const _BEND := 3
const _OFF := 4
const _ON := 5

static var _cache: Dictionary = {}

var _bytes: PackedByteArray = PackedByteArray()
var _at := 0


static func stream(path: String) -> AudioStream:
	if _cache.has(path):
		var cached: Variant = _cache[path]
		if cached is AudioStream:
			return cached
	var song: Object = (load("res://scripts/midi_song.gd") as GDScript).new()
	var wav: AudioStreamWAV = song.call("_render", path)
	if wav != null:
		_cache[path] = wav
	return wav


func _render(path: String) -> AudioStreamWAV:
	_bytes = FileAccess.get_file_as_bytes(path)
	_at = 0
	if _bytes.size() < 14 or _text(0, 4) != "MThd":
		push_warning("Not a MIDI file: %s" % path)
		return null
	_at = 4
	_u32()
	var format := _u16()
	var tracks := _u16()
	var division := _u16()
	if format > 1 or division <= 0 or (division & 0x8000) != 0:
		push_warning("Unsupported MIDI timing: %s" % path)
		return null
	var events: Array[Dictionary] = []
	for _track in tracks:
		if _at + 8 > _bytes.size() or _text(_at, 4) != "MTrk":
			break
		_at += 4
		var length := _u32()
		var stop := mini(_at + length, _bytes.size())
		_track_events(stop, events)
		_at = stop
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := int(a["t"])
		var tb := int(b["t"])
		if ta == tb:
			return int(a["k"]) < int(b["k"])
		return ta < tb
	)
	return _bake(events, division)


func _track_events(stop: int, events: Array[Dictionary]) -> void:
	var tick := 0
	var status := 0
	var rpn_msb: PackedInt32Array = PackedInt32Array()
	var rpn_lsb: PackedInt32Array = PackedInt32Array()
	var data_msb: PackedInt32Array = PackedInt32Array()
	var data_lsb: PackedInt32Array = PackedInt32Array()
	rpn_msb.resize(16)
	rpn_lsb.resize(16)
	data_msb.resize(16)
	data_lsb.resize(16)
	rpn_msb.fill(127)
	rpn_lsb.fill(127)
	while _at < stop:
		tick += _varlen()
		if _at >= stop:
			return
		var lead := _bytes[_at]
		if lead >= 0x80:
			status = lead
			_at += 1
		if status == 0:
			return
		if status == 0xff:
			if _at >= stop:
				return
			var meta := _bytes[_at]
			_at += 1
			var size := _varlen()
			if meta == 0x51 and size == 3 and _at + 3 <= _bytes.size():
				var tempo := (_bytes[_at] << 16) | (_bytes[_at + 1] << 8) | _bytes[_at + 2]
				events.append({"t": tick, "k": _TEMPO, "a": tempo, "b": 0, "c": 0})
			_at += size
			continue
		if status == 0xf0 or status == 0xf7:
			_at += _varlen()
			continue
		var kind := status & 0xf0
		var channel := status & 0x0f
		if kind == 0xc0 or kind == 0xd0:
			_at += 1
			continue
		if _at + 1 >= _bytes.size():
			return
		var d1 := _bytes[_at]
		var d2 := _bytes[_at + 1]
		_at += 2
		if kind == 0x90 and d2 > 0:
			events.append({"t": tick, "k": _ON, "a": d1, "b": d2, "c": channel})
		elif kind == 0x80 or kind == 0x90:
			events.append({"t": tick, "k": _OFF, "a": d1, "b": 0, "c": channel})
		elif kind == 0xe0:
			events.append({"t": tick, "k": _BEND, "a": d1 | (d2 << 7), "b": 0, "c": channel})
		elif kind == 0xb0:
			if d1 == 101:
				rpn_msb[channel] = d2
			elif d1 == 100:
				rpn_lsb[channel] = d2
			elif d1 == 6:
				data_msb[channel] = d2
			elif d1 == 38:
				data_lsb[channel] = d2
			if (d1 == 6 or d1 == 38) and rpn_msb[channel] == 0 and rpn_lsb[channel] == 0:
				events.append({"t": tick, "k": _RANGE, "a": data_msb[channel], "b": data_lsb[channel], "c": channel})


func _bake(events: Array[Dictionary], division: int) -> AudioStreamWAV:
	var total := _length(events, division)
	var data := PackedByteArray()
	data.resize(maxi(total, 1) * 2)
	var bends: PackedInt32Array = PackedInt32Array()
	var ranges: PackedInt32Array = PackedInt32Array()
	bends.resize(16)
	ranges.resize(16)
	bends.fill(8192)
	ranges.fill(2)
	var voices: Array[Dictionary] = []
	var at := 0.0
	var written := 0
	var tick := 0
	var sec_per_tick := 500000.0 / 1000000.0 / float(division)
	for ev: Dictionary in events:
		var next_tick := int(ev["t"])
		if next_tick > tick:
			at += float(next_tick - tick) * float(RATE) * sec_per_tick
			var dest := mini(int(at), data.size() / 2)
			written = _fill(data, written, dest, voices, bends, ranges)
			tick = next_tick
		var channel := int(ev["c"])
		match int(ev["k"]):
			_TEMPO:
				sec_per_tick = float(ev["a"]) / 1000000.0 / float(division)
			_RANGE:
				ranges[channel] = int(ev["a"])
			_BEND:
				bends[channel] = int(ev["a"])
			_OFF:
				_note_off(voices, channel, int(ev["a"]))
			_ON:
				_note_on(voices, channel, int(ev["a"]))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


func _length(events: Array[Dictionary], division: int) -> int:
	var at := 0.0
	var tick := 0
	var sec_per_tick := 500000.0 / 1000000.0 / float(division)
	for ev: Dictionary in events:
		var next_tick := int(ev["t"])
		if next_tick > tick:
			at += float(next_tick - tick) * float(RATE) * sec_per_tick
			tick = next_tick
		if int(ev["k"]) == _TEMPO:
			sec_per_tick = float(ev["a"]) / 1000000.0 / float(division)
	return int(at)


func _fill(data: PackedByteArray, written: int, dest: int, voices: Array[Dictionary], bends: PackedInt32Array, ranges: PackedInt32Array) -> int:
	if dest <= written or voices.is_empty():
		return maxi(dest, written)
	var count := dest - written
	var steps: Array[float] = []
	var phases: Array[float] = []
	for voice: Dictionary in voices:
		var channel := int(voice["c"])
		var semis := float(bends[channel] - 8192) / 8192.0 * float(ranges[channel])
		var freq := 440.0 * pow(2.0, (float(voice["n"]) - 69.0 + semis) / 12.0)
		steps.append(freq / float(RATE))
		phases.append(float(voice["p"]))
	var level := int(_AMP * 32767.0)
	for i in count:
		var mix := 0
		for k in steps.size():
			mix += level if phases[k] < 0.5 else -level
			phases[k] += steps[k]
			if phases[k] >= 1.0:
				phases[k] -= 1.0
		data.encode_s16((written + i) * 2, clampi(mix, -32767, 32767))
	for k in voices.size():
		voices[k]["p"] = phases[k]
	return dest


func _note_on(voices: Array[Dictionary], channel: int, note: int) -> void:
	for voice: Dictionary in voices:
		if int(voice["c"]) == channel and int(voice["n"]) == note:
			voice["p"] = 0.0
			return
	if voices.size() >= _VOICES:
		voices.remove_at(0)
	voices.append({"c": channel, "n": note, "p": 0.0})


func _note_off(voices: Array[Dictionary], channel: int, note: int) -> void:
	for i in voices.size():
		var voice: Dictionary = voices[i]
		if int(voice["c"]) == channel and int(voice["n"]) == note:
			voices.remove_at(i)
			return


func _varlen() -> int:
	var value := 0
	for _i in 4:
		if _at >= _bytes.size():
			return value
		var byte := _bytes[_at]
		_at += 1
		value = (value << 7) | (byte & 0x7f)
		if byte < 0x80:
			return value
	return value


func _u16() -> int:
	if _at + 2 > _bytes.size():
		return 0
	var value := (_bytes[_at] << 8) | _bytes[_at + 1]
	_at += 2
	return value


func _u32() -> int:
	if _at + 4 > _bytes.size():
		return 0
	var value := (_bytes[_at] << 24) | (_bytes[_at + 1] << 16) | (_bytes[_at + 2] << 8) | _bytes[_at + 3]
	_at += 4
	return value


func _text(at: int, size: int) -> String:
	if at < 0 or at + size > _bytes.size():
		return ""
	return _bytes.slice(at, at + size).get_string_from_ascii()
