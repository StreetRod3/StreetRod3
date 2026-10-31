extends AudioStreamPlayer

## Looping fuel-pump chug. Silent until play() is called.

const _MIX_RATE := 22050.0
const _PUMP_HZ := 6.5

var _playback: AudioStreamGeneratorPlayback
var _phase: float = 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _MIX_RATE
	gen.buffer_length = 0.1
	stream = gen
	volume_db = -9.0
	bus = "Master"


func _process(_delta: float) -> void:
	if not playing:
		return
	if _playback == null:
		_playback = get_stream_playback()
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	for _i in frames:
		_phase += _PUMP_HZ / _MIX_RATE
		if _phase >= 1.0:
			_phase -= floorf(_phase)
		var click := 0.0
		if _phase < 0.045:
			click = sin(_phase / 0.045 * PI)
		var gurgle := 0.0
		if _phase > 0.07 and _phase < 0.42:
			var t := (_phase - 0.07) / 0.35
			gurgle = sin(t * PI) * sin(_phase * TAU * 14.0)
		var noise := (randf() * 2.0 - 1.0) * gurgle * 0.4
		var sample := (click * 0.5 + gurgle * 0.28 + noise) * 0.42
		_playback.push_frame(Vector2(sample, sample))
