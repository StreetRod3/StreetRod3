extends CanvasLayer

## Draws the 3D view as colored characters when GameState.retro_mode is on. Sits under the
## menus and the driving HUD, which are on higher layers and so stay as themselves. The garage
## view is a viewport of its own; cover_view() restyles that container instead of the window.

const _SHADER := preload("res://shaders/retro_mode.gdshader")
## On-screen cell. Half the old 8×16, so a 1280×720 view is 320×90 characters instead of 160×45.
const CELL := Vector2i(4, 8)
## The drawn glyph. Scaled into `CELL` by the shader.
const _GLYPH := Vector2i(8, 16)
## Dark to light. Each glyph is denser than the one before it, so a brighter cell reads brighter.
const _RAMP := " .:-=+*#@"

var _rect: ColorRect
var _atlas: Texture2D
var _screen_mat: ShaderMaterial
var _texture_mat: ShaderMaterial
var _covered: SubViewportContainer


func _ready() -> void:
	assert(_glyphs_rise(_glyph_rows()))
	layer = -1
	_atlas = _build_atlas()
	_screen_mat = _make_material(0.0, Color.WHITE)
	_texture_mat = _make_material(2.0, Color.WHITE)
	_rect = ColorRect.new()
	_rect.name = "Characters"
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	_rect.material = _screen_mat
	add_child(_rect)
	_apply()


## A flat field of characters in `ink`, for the graphics page's preview.
func ink_material(ink: Color) -> ShaderMaterial:
	return _make_material(1.0, ink)


func set_enabled(_on: bool) -> void:
	_apply()


## The garage draws its world into `holder` rather than the window. Restyle that, and keep the
## full-screen pass off so it does not paint over the view.
func cover_view(holder: SubViewportContainer) -> void:
	if _covered == holder:
		_apply()
		return
	_drop_cover()
	_covered = holder
	_covered.tree_exited.connect(_on_cover_gone)
	_apply()


func _drop_cover() -> void:
	if _covered != null and is_instance_valid(_covered):
		if _covered.tree_exited.is_connected(_on_cover_gone):
			_covered.tree_exited.disconnect(_on_cover_gone)
		_covered.material = null
	_covered = null


func _on_cover_gone() -> void:
	_covered = null
	_apply()


func _apply() -> void:
	var on := GameState.retro_mode
	var covering := _covered != null and is_instance_valid(_covered)
	if covering:
		_covered.material = _texture_mat if on else null
		_rect.visible = false
	else:
		_rect.visible = on


func _make_material(mode: float, ink: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("glyph_tex", _atlas)
	mat.set_shader_parameter("cell_px", Vector2(CELL))
	mat.set_shader_parameter("glyph_count", float(_RAMP.length()))
	mat.set_shader_parameter("source_mode", mode)
	mat.set_shader_parameter("flat_ink", ink)
	return mat


func _build_atlas() -> Texture2D:
	var glyphs := _glyph_rows()
	var count := glyphs.size()
	var image := Image.create(_GLYPH.x * count, _GLYPH.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))
	for i: int in count:
		var rows := glyphs[i]
		for y: int in _GLYPH.y:
			var bits := int(rows[y])
			for x: int in _GLYPH.x:
				if bits & (1 << (_GLYPH.x - 1 - x)):
					image.set_pixel(i * _GLYPH.x + x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(image)


## Sixteen rows each, bit 7 the left pixel. Built here because a packed array is not a constant.
func _glyph_rows() -> Array[PackedInt32Array]:
	return [
		PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
		PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x18, 0x18, 0, 0]),
		PackedInt32Array([0, 0, 0, 0x18, 0x18, 0, 0, 0, 0, 0, 0x18, 0x18, 0, 0, 0, 0]),
		PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0x7E, 0x7E, 0, 0, 0, 0, 0, 0, 0]),
		PackedInt32Array([0, 0, 0, 0, 0x7E, 0x7E, 0, 0, 0, 0, 0x7E, 0x7E, 0, 0, 0, 0]),
		PackedInt32Array([0, 0, 0, 0x18, 0x18, 0x18, 0x7E, 0x7E, 0x7E, 0x7E, 0x18, 0x18, 0x18, 0, 0, 0]),
		PackedInt32Array([0, 0, 0xDB, 0x7E, 0x3C, 0x7E, 0x7E, 0x7E, 0x3C, 0x7E, 0xDB, 0, 0, 0, 0, 0]),
		PackedInt32Array([0, 0xE7, 0xE7, 0xFF, 0xE7, 0xE7, 0xFF, 0xE7, 0xE7, 0xFF, 0xE7, 0xE7, 0, 0, 0, 0]),
		PackedInt32Array([0, 0x3C, 0x7E, 0xFF, 0xFF, 0xE7, 0xDB, 0xC3, 0xDB, 0xE7, 0xFF, 0xFF, 0x7E, 0x3C, 0x18, 0]),
	]


func _glyphs_rise(glyphs: Array[PackedInt32Array]) -> bool:
	if glyphs.size() != _RAMP.length():
		return false
	var prev := -1
	for rows: PackedInt32Array in glyphs:
		if rows.size() != _GLYPH.y:
			return false
		var n := 0
		for bits: int in rows:
			var v := bits
			while v > 0:
				n += v & 1
				v >>= 1
		if n <= prev:
			return false
		prev = n
	return true
