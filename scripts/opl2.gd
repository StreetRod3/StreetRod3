extends RefCounted

## The AdLib card's chip, a Yamaha YM3812 (OPL2), written to through its registers
## and run at its own sample rate. Ported from Aaron Giles's ymfm, the emulator the
## Street Rod 2 port plays its AdLib through, so the same writes make the same
## samples. Only the nine melodic channels are here: no rhythm-mode percussion, no
## LFO (tremolo and vibrato), no timers. Street Rod 2's motor timbre uses none of
## them.
##
## ymfm is under the BSD 3-Clause License:
##
## Copyright (c) 2021, Aaron Giles
## All rights reserved.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions are met:
##
## 1. Redistributions of source code must retain the above copyright notice, this
##    list of conditions and the following disclaimer.
##
## 2. Redistributions in binary form must reproduce the above copyright notice,
##    this list of conditions and the following disclaimer in the documentation
##    and/or other materials provided with the distribution.
##
## 3. Neither the name of the copyright holder nor the names of its
##    contributors may be used to endorse or promote products derived from
##    this software without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
## AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
## IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
## DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
## FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
## DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
## SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
## CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
## OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
## OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## The AdLib's 14.31818 MHz crystal over 4 is the chip's clock, and the chip makes
## one sample every 72 clocks.
const SAMPLE_RATE := 3579545.0 / 72.0

const CHANNELS := 9
const OPERATORS := 18

const _EG_ATTACK := 1
const _EG_DECAY := 2
const _EG_SUSTAIN := 3
const _EG_RELEASE := 4
const _EG_QUIET := 0x380

## |sin| over a quarter wave as 4.8 logarithmic attenuation, from the OPN die.
const _SIN_TABLE: Array[int] = [
	0x859, 0x6c3, 0x607, 0x58b, 0x52e, 0x4e4, 0x4a6, 0x471, 0x443, 0x41a, 0x3f5, 0x3d3, 0x3b5, 0x398, 0x37e, 0x365,
	0x34e, 0x339, 0x324, 0x311, 0x2ff, 0x2ed, 0x2dc, 0x2cd, 0x2bd, 0x2af, 0x2a0, 0x293, 0x286, 0x279, 0x26d, 0x261,
	0x256, 0x24b, 0x240, 0x236, 0x22c, 0x222, 0x218, 0x20f, 0x206, 0x1fd, 0x1f5, 0x1ec, 0x1e4, 0x1dc, 0x1d4, 0x1cd,
	0x1c5, 0x1be, 0x1b7, 0x1b0, 0x1a9, 0x1a2, 0x19b, 0x195, 0x18f, 0x188, 0x182, 0x17c, 0x177, 0x171, 0x16b, 0x166,
	0x160, 0x15b, 0x155, 0x150, 0x14b, 0x146, 0x141, 0x13c, 0x137, 0x133, 0x12e, 0x129, 0x125, 0x121, 0x11c, 0x118,
	0x114, 0x10f, 0x10b, 0x107, 0x103, 0x0ff, 0x0fb, 0x0f8, 0x0f4, 0x0f0, 0x0ec, 0x0e9, 0x0e5, 0x0e2, 0x0de, 0x0db,
	0x0d7, 0x0d4, 0x0d1, 0x0cd, 0x0ca, 0x0c7, 0x0c4, 0x0c1, 0x0be, 0x0bb, 0x0b8, 0x0b5, 0x0b2, 0x0af, 0x0ac, 0x0a9,
	0x0a7, 0x0a4, 0x0a1, 0x09f, 0x09c, 0x099, 0x097, 0x094, 0x092, 0x08f, 0x08d, 0x08a, 0x088, 0x086, 0x083, 0x081,
	0x07f, 0x07d, 0x07a, 0x078, 0x076, 0x074, 0x072, 0x070, 0x06e, 0x06c, 0x06a, 0x068, 0x066, 0x064, 0x062, 0x060,
	0x05e, 0x05c, 0x05b, 0x059, 0x057, 0x055, 0x053, 0x052, 0x050, 0x04e, 0x04d, 0x04b, 0x04a, 0x048, 0x046, 0x045,
	0x043, 0x042, 0x040, 0x03f, 0x03e, 0x03c, 0x03b, 0x039, 0x038, 0x037, 0x035, 0x034, 0x033, 0x031, 0x030, 0x02f,
	0x02e, 0x02d, 0x02b, 0x02a, 0x029, 0x028, 0x027, 0x026, 0x025, 0x024, 0x023, 0x022, 0x021, 0x020, 0x01f, 0x01e,
	0x01d, 0x01c, 0x01b, 0x01a, 0x019, 0x018, 0x017, 0x017, 0x016, 0x015, 0x014, 0x014, 0x013, 0x012, 0x011, 0x011,
	0x010, 0x00f, 0x00f, 0x00e, 0x00d, 0x00d, 0x00c, 0x00c, 0x00b, 0x00a, 0x00a, 0x009, 0x009, 0x008, 0x008, 0x007,
	0x007, 0x007, 0x006, 0x006, 0x005, 0x005, 0x005, 0x004, 0x004, 0x004, 0x003, 0x003, 0x003, 0x002, 0x002, 0x002,
	0x002, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000,
]

## 10-bit mantissas of 2^-x, also from the die, reversed; the implied 0x400 bit and
## the shift by 2 are added when the table is built.
const _POWER_MANTISSA: Array[int] = [
	0x3fa, 0x3f5, 0x3ef, 0x3ea, 0x3e4, 0x3df, 0x3da, 0x3d4, 0x3cf, 0x3c9, 0x3c4, 0x3bf, 0x3b9, 0x3b4, 0x3ae, 0x3a9,
	0x3a4, 0x39f, 0x399, 0x394, 0x38f, 0x38a, 0x384, 0x37f, 0x37a, 0x375, 0x370, 0x36a, 0x365, 0x360, 0x35b, 0x356,
	0x351, 0x34c, 0x347, 0x342, 0x33d, 0x338, 0x333, 0x32e, 0x329, 0x324, 0x31f, 0x31a, 0x315, 0x310, 0x30b, 0x306,
	0x302, 0x2fd, 0x2f8, 0x2f3, 0x2ee, 0x2e9, 0x2e5, 0x2e0, 0x2db, 0x2d6, 0x2d2, 0x2cd, 0x2c8, 0x2c4, 0x2bf, 0x2ba,
	0x2b5, 0x2b1, 0x2ac, 0x2a8, 0x2a3, 0x29e, 0x29a, 0x295, 0x291, 0x28c, 0x288, 0x283, 0x27f, 0x27a, 0x276, 0x271,
	0x26d, 0x268, 0x264, 0x25f, 0x25b, 0x257, 0x252, 0x24e, 0x249, 0x245, 0x241, 0x23c, 0x238, 0x234, 0x230, 0x22b,
	0x227, 0x223, 0x21e, 0x21a, 0x216, 0x212, 0x20e, 0x209, 0x205, 0x201, 0x1fd, 0x1f9, 0x1f5, 0x1f0, 0x1ec, 0x1e8,
	0x1e4, 0x1e0, 0x1dc, 0x1d8, 0x1d4, 0x1d0, 0x1cc, 0x1c8, 0x1c4, 0x1c0, 0x1bc, 0x1b8, 0x1b4, 0x1b0, 0x1ac, 0x1a8,
	0x1a4, 0x1a0, 0x19c, 0x199, 0x195, 0x191, 0x18d, 0x189, 0x185, 0x181, 0x17e, 0x17a, 0x176, 0x172, 0x16f, 0x16b,
	0x167, 0x163, 0x160, 0x15c, 0x158, 0x154, 0x151, 0x14d, 0x149, 0x146, 0x142, 0x13e, 0x13b, 0x137, 0x134, 0x130,
	0x12c, 0x129, 0x125, 0x122, 0x11e, 0x11b, 0x117, 0x114, 0x110, 0x10c, 0x109, 0x106, 0x102, 0x0ff, 0x0fb, 0x0f8,
	0x0f4, 0x0f1, 0x0ed, 0x0ea, 0x0e7, 0x0e3, 0x0e0, 0x0dc, 0x0d9, 0x0d6, 0x0d2, 0x0cf, 0x0cc, 0x0c8, 0x0c5, 0x0c2,
	0x0be, 0x0bb, 0x0b8, 0x0b5, 0x0b1, 0x0ae, 0x0ab, 0x0a8, 0x0a4, 0x0a1, 0x09e, 0x09b, 0x098, 0x094, 0x091, 0x08e,
	0x08b, 0x088, 0x085, 0x082, 0x07e, 0x07b, 0x078, 0x075, 0x072, 0x06f, 0x06c, 0x069, 0x066, 0x063, 0x060, 0x05d,
	0x05a, 0x057, 0x054, 0x051, 0x04e, 0x04b, 0x048, 0x045, 0x042, 0x03f, 0x03c, 0x039, 0x036, 0x033, 0x030, 0x02d,
	0x02a, 0x028, 0x025, 0x022, 0x01f, 0x01c, 0x019, 0x016, 0x014, 0x011, 0x00e, 0x00b, 0x008, 0x006, 0x003, 0x000,
]

## Eight 4-bit attenuation steps for each 6-bit envelope rate.
const _INCREMENT_TABLE: Array[int] = [
	0x00000000, 0x00000000, 0x10101010, 0x10101010,
	0x10101010, 0x10101010, 0x11101110, 0x11101110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x11111111, 0x21112111, 0x21212121, 0x22212221,
	0x22222222, 0x42224222, 0x42424242, 0x44424442,
	0x44444444, 0x84448444, 0x84848484, 0x88848884,
	0x88888888, 0x88888888, 0x88888888, 0x88888888,
]

## Key scale attenuation for the top four F-number bits at block 7.
const _KSL_TABLE: Array[int] = [0, 24, 32, 37, 40, 43, 45, 47, 48, 50, 51, 52, 53, 54, 55, 56]

## The four OPL2 waveforms, 1024 entries each, sign in bit 15.
static var _waves: Array[PackedInt32Array] = []
static var _power := PackedInt32Array()

var _regs := PackedByteArray()

# Each operator's derived values, refreshed when its channel's registers change.
var _step := PackedInt32Array()
var _level := PackedInt32Array()
var _sustain := PackedInt32Array()
var _rate := PackedInt32Array()  # 5 per operator, by envelope state
var _wave := PackedInt32Array()

# Each operator's running state.
var _phase := PackedInt32Array()
var _atten := PackedInt32Array()
var _state := PackedInt32Array()
var _key_state := PackedInt32Array()

# Each channel's: the operator-1 output fed back, and the registers' choices.
var _fb0 := PackedInt32Array()
var _fb1 := PackedInt32Array()
var _fb_in := PackedInt32Array()
var _feedback := PackedInt32Array()
var _additive := PackedInt32Array()
var _dirty := PackedByteArray()
var _active := PackedInt32Array()
var _env_counter := 0
var _any_dirty := true


func _init() -> void:
	_build_tables()
	_regs.resize(256)
	_step.resize(OPERATORS)
	_level.resize(OPERATORS)
	_sustain.resize(OPERATORS)
	_wave.resize(OPERATORS)
	_phase.resize(OPERATORS)
	_atten.resize(OPERATORS)
	_state.resize(OPERATORS)
	_key_state.resize(OPERATORS)
	_rate.resize(OPERATORS * 5)
	_fb0.resize(CHANNELS)
	_fb1.resize(CHANNELS)
	_fb_in.resize(CHANNELS)
	_feedback.resize(CHANNELS)
	_additive.resize(CHANNELS)
	_dirty.resize(CHANNELS)
	for op in OPERATORS:
		_atten[op] = 0x3ff
		_state[op] = _EG_RELEASE
	_dirty.fill(1)


static func _build_tables() -> void:
	if not _waves.is_empty():
		return
	for m in _POWER_MANTISSA:
		_power.append((m | 0x400) << 2)
	var sine := PackedInt32Array()
	sine.resize(1024)
	for i in 1024:
		var j := i
		if j & 0x100:
			j = ~j
		sine[i] = _SIN_TABLE[j & 0xff] | (((i >> 9) & 1) << 15)
	var zero := sine[0]
	var half := PackedInt32Array()
	var absolute := PackedInt32Array()
	var quarter := PackedInt32Array()
	half.resize(1024)
	absolute.resize(1024)
	quarter.resize(1024)
	for i in 1024:
		half[i] = zero if i & 0x200 else sine[i]
		absolute[i] = sine[i] & 0x7fff
		quarter[i] = zero if i & 0x100 else sine[i] & 0x7fff
	_waves = [sine, half, absolute, quarter]


## One write: the register number to port 0x388 and the value to 0x389.
func write(reg: int, value: int) -> void:
	reg &= 0xff
	_regs[reg] = value & 0xff
	var ch := -1
	if reg >= 0xa0 and reg <= 0xc8:
		ch = reg & 0x0f
	elif reg >= 0x20 and reg < 0xa0 or reg >= 0xe0:
		ch = _slot_channel(reg & 0x1f)
	elif reg == 0x01 or reg == 0x08:
		_dirty.fill(1)
		_any_dirty = true
		return
	if ch >= 0 and ch < CHANNELS:
		_dirty[ch] = 1
		_any_dirty = true


## Samples from the chip at SAMPLE_RATE, as -1..1, after the YM3014 DAC.
func render(frames: int, gain: float = 1.0) -> PackedVector2Array:
	if _any_dirty:
		_prepare()
	var mix := PackedInt32Array()
	mix.resize(frames)
	for ch in _active:
		var made := _render_channel(ch, frames)
		for f in frames:
			mix[f] += made[f]
	_env_counter = (_env_counter + 4 * frames) & 0xffffffff
	_refresh_active()
	var out := PackedVector2Array()
	out.resize(frames)
	var scale := gain / 32768.0
	for f in frames:
		var v := float(_roundtrip_fp(mix[f])) * scale
		out[f] = Vector2(v, v)
	return out


## One channel's samples, everything it needs held in locals (GDScript reads those
## far faster than members), and its state put back after.
func _render_channel(ch: int, frames: int) -> PackedInt32Array:
	var made := PackedInt32Array()
	made.resize(frames)
	var m := _op_of(ch, 0)
	var c := m + 3
	var m_phase := _phase[m]
	var c_phase := _phase[c]
	var m_step := _step[m]
	var c_step := _step[c]
	var m_att := _atten[m]
	var c_att := _atten[c]
	var m_state := _state[m]
	var c_state := _state[c]
	var m_sustain := _sustain[m]
	var c_sustain := _sustain[c]
	var m_level := _level[m]
	var c_level := _level[c]
	var m_wave: PackedInt32Array = _waves[_wave[m]]
	var c_wave: PackedInt32Array = _waves[_wave[c]]
	var rates := _rate
	var power := _power
	var fb := _feedback[ch]
	var additive := _additive[ch]
	var fb0 := _fb0[ch]
	var fb1 := _fb1[ch]
	var fb_in := _fb_in[ch]
	var env_counter := _env_counter
	for f in frames:
		env_counter = (env_counter + 4) & 0xffffffff
		var env := env_counter >> 2
		fb0 = fb1
		fb1 = fb_in
		# The envelopes: attack to decay at full volume, decay to sustain at the level.
		if m_state == _EG_ATTACK and m_att == 0:
			m_state = _EG_DECAY
		if m_state == _EG_DECAY and m_att >= m_sustain:
			m_state = _EG_SUSTAIN
		var rate := rates[m * 5 + m_state]
		var shift := rate >> 2
		var counter := (env << shift) & 0xffffffff
		if (counter & 0x7ff) == 0:
			m_att = _envelope_step(rate, shift, counter, m_state == _EG_ATTACK, m_att)
		if c_state == _EG_ATTACK and c_att == 0:
			c_state = _EG_DECAY
		if c_state == _EG_DECAY and c_att >= c_sustain:
			c_state = _EG_SUSTAIN
		rate = rates[c * 5 + c_state]
		shift = rate >> 2
		counter = (env << shift) & 0xffffffff
		if (counter & 0x7ff) == 0:
			c_att = _envelope_step(rate, shift, counter, c_state == _EG_ATTACK, c_att)
		m_phase = (m_phase + m_step) & 0xfffff
		c_phase = (c_phase + c_step) & 0xfffff
		# Operator 1, with its own last two outputs fed back.
		var v1 := 0
		if m_att <= _EG_QUIET:
			var opmod := 0
			if fb != 0:
				opmod = (fb0 + fb1) >> (10 - fb)
			var s1 := m_wave[((m_phase >> 10) + opmod) & 0x3ff]
			var x1 := (s1 & 0x7fff) + (mini(m_att + m_level, 0x3ff) << 2)
			v1 = power[x1 & 0xff] >> (x1 >> 8)
			if s1 & 0x8000:
				v1 = -v1
		fb_in = v1
		# Operator 2. The OPL2 modulates it with operator 1's previous sample.
		var v2 := 0
		if c_att <= _EG_QUIET:
			var p := c_phase >> 10
			if additive == 0:
				p += fb1 >> 1
			var s2 := c_wave[p & 0x3ff]
			var x2 := (s2 & 0x7fff) + (mini(c_att + c_level, 0x3ff) << 2)
			v2 = power[x2 & 0xff] >> (x2 >> 8)
			if s2 & 0x8000:
				v2 = -v2
		if additive == 0:
			made[f] = v2 >> 1
		else:
			made[f] = clampi((fb1 >> 1) + (v2 >> 1), -32768, 32767)
	_phase[m] = m_phase
	_phase[c] = c_phase
	_atten[m] = m_att
	_atten[c] = c_att
	_state[m] = m_state
	_state[c] = c_state
	_fb0[ch] = fb0
	_fb1[ch] = fb1
	_fb_in[ch] = fb_in
	return made


static func _envelope_step(rate: int, shift: int, counter: int, attack: bool, att: int) -> int:
	var bits := (counter >> (11 if shift <= 11 else shift)) & 7
	var inc := (_INCREMENT_TABLE[rate] >> (4 * bits)) & 0xf
	if attack:
		# Attack is the one that falls, by a fraction of what is left.
		if rate < 62:
			att += ((-att - 1) * inc) >> 4
		return att
	return mini(att + inc, 0x3ff)


## The YM3014's 10.3 floating point: what the DAC keeps of a 16-bit sample.
static func _roundtrip_fp(value: int) -> int:
	if value < -32768:
		return -32768
	if value > 32767:
		return 32767
	var scan := value ^ (value >> 31)
	var e := 0
	if scan >= 16384:
		e = 6
	elif scan >= 8192:
		e = 5
	elif scan >= 4096:
		e = 4
	elif scan >= 2048:
		e = 3
	elif scan >= 1024:
		e = 2
	elif scan >= 512:
		e = 1
	return value & ~((1 << e) - 1)


## A channel's operators are at slots ch % 3 + 8 * (ch / 3) and three above.
static func _op_of(ch: int, second: int) -> int:
	return (ch % 3) + 6 * (ch / 3) + 3 * second


static func _slot_channel(slot: int) -> int:
	var within := slot & 7
	if within >= 6 or slot >= 0x16:
		return -1
	return (slot >> 3) * 3 + within % 3


static func _slot_of(op: int) -> int:
	return (op / 6) * 8 + op % 6


func _prepare() -> void:
	_any_dirty = false
	var wse := (_regs[0x01] & 0x20) != 0
	var note_sel := (_regs[0x08] >> 6) & 1
	for ch in CHANNELS:
		if _dirty[ch] == 0:
			continue
		_dirty[ch] = 0
		var fnum := _regs[0xa0 + ch] | ((_regs[0xb0 + ch] & 3) << 8)
		var block := (_regs[0xb0 + ch] >> 2) & 7
		var key := (_regs[0xb0 + ch] >> 5) & 1
		_feedback[ch] = (_regs[0xc0 + ch] >> 1) & 7
		_additive[ch] = _regs[0xc0 + ch] & 1
		var keycode := (block << 1) | ((fnum >> (9 - note_sel)) & 1)
		for second in 2:
			var op := _op_of(ch, second)
			var slot := _slot_of(op)
			var r20 := _regs[0x20 + slot]
			var r40 := _regs[0x40 + slot]
			var r60 := _regs[0x60 + slot]
			var r80 := _regs[0x80 + slot]
			_wave[op] = (_regs[0xe0 + slot] & 3) if wse else 0
			var mult := r20 & 0xf
			var multiple := ((mult & 0xe) | ((0xc2aa >> mult) & 1)) * 2
			if multiple == 0:
				multiple = 1
			_step[op] = ((((fnum << 2) << block) >> 2) * multiple) >> 1
			var level := (r40 & 0x3f) << 3
			var ksl_bits := (r40 >> 6) & 3
			var ksl := ((ksl_bits >> 1) & 1) | ((ksl_bits & 1) << 1)
			if ksl != 0:
				level += maxi(0, _KSL_TABLE[(fnum >> 6) & 0xf] - 8 * (block ^ 7)) << ksl
			_level[op] = level
			var sl := (r80 >> 4) & 0xf
			sl |= (sl + 1) & 0x10
			_sustain[op] = sl << 5
			var ksrval := keycode >> (2 * (((r20 >> 4) & 1) ^ 1))
			var rr := _effective_rate((r80 & 0xf) * 4, ksrval)
			_rate[op * 5 + _EG_ATTACK] = _effective_rate(((r60 >> 4) & 0xf) * 4, ksrval)
			_rate[op * 5 + _EG_DECAY] = _effective_rate((r60 & 0xf) * 4, ksrval)
			_rate[op * 5 + _EG_SUSTAIN] = 0 if r20 & 0x20 else rr
			_rate[op * 5 + _EG_RELEASE] = rr
			if key != _key_state[op]:
				_key_state[op] = key
				if key != 0:
					if _state[op] != _EG_ATTACK:
						_state[op] = _EG_ATTACK
						_phase[op] = 0
						if _rate[op * 5 + _EG_ATTACK] >= 62:
							_atten[op] = 0
				elif _state[op] < _EG_RELEASE:
					_state[op] = _EG_RELEASE
	_refresh_active()


## Channels still sounding: keyed on, or not yet at full attenuation after the release.
func _refresh_active() -> void:
	_active.clear()
	for ch in CHANNELS:
		for second in 2:
			var op := _op_of(ch, second)
			if _state[op] != _EG_RELEASE or _atten[op] < 0x3ff:
				_active.append(ch)
				break


static func _effective_rate(raw: int, ksr: int) -> int:
	return 0 if raw == 0 else mini(raw + ksr, 63)
