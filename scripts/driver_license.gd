extends Control

## The Driver's Name screen, between New Game and the garage: a California license
## to type a name on. Positions come from assets/ui/driver_license.svg, in the
## card's own 930 by 622 pixels, each x and y being the left end of the baseline.

const FONT := preload("res://assets/fonts/SpecialElite-Regular.ttf")
const FONT_SIZE := 30
const INK := Color("#25252a")
const NAME_POSITION := Vector2(354, 200)
## The widest letters, a full line of M, still fit before the edge of the card.
const NAME_MAX_LENGTH := 24

## Up, up, down, down, left, right, left, right, B, A as a name starts the game with more cash.
const CHEAT_NAME := "UUDDLRLRBA"
const CHEAT_MONEY := 10000

## The photo fills the blue area of the card, and rounds off with the card's corner.
const _DriverFigure := preload("res://scripts/driver_figure.gd")
const PORTRAIT_RECT := Rect2(0, 280, 276, 342)
const PORTRAIT_CORNER := 12
## Rendered larger than it shows, for smooth edges.
const PORTRAIT_OVERSAMPLE := 2
## How much of the driver the frame shows, in meters, and how far off the camera stands.
const PORTRAIT_FRAME_HEIGHT := 0.46
const PORTRAIT_CAMERA_DISTANCE := 1.6
## Where the camera looks, against the eyes of the figure.
const PORTRAIT_LOOK_Y := -0.03
## The backdrop the driver stands against, before the photo fades.
const PORTRAIT_BACKDROP := Color("#8fa8c0")
const PORTRAIT_FADE := preload("res://shaders/faded_photo.gdshader")

## The MUST WEAR CORRECTIVE LENSES box. A click types an X in it, a little crooked.
const LENSES_BOX := Rect2(892, 472, 24, 24)
## The box is a small target, so clicks this close to it count.
const LENSES_BOX_MARGIN := 6.0
const LENSES_X_SIZE := 26
const LENSES_X_OFFSET := Vector2(-2.5, 0.5)
const LENSES_X_DEGREES := -7.0

## Laid over everything on the card last, so it all ages together.
const CARD_WEAR := preload("res://assets/ui/card_wear.jpg")
const CARD_AGING := preload("res://shaders/aged_paper.gdshader")

const SIGNATURE_FONT := preload("res://assets/fonts/HomemadeApple-Regular.ttf")
const SIGNATURE_SIZE := 30
const SIGNATURE_INK := Color("#2a2d55")
const SIGNATURE_POSITION := Vector2(366, 552)
## Long names shrink to stop this far short of the right edge of the card.
const SIGNATURE_MARGIN := 10.0

## Inches for height, in the card's feet-inches form, and pounds for weight.
const HEIGHT_RANGE := Vector2i(58, 80)
const WEIGHT_RANGE := Vector2i(100, 300)
const WEIGHT_STEP := 5

## The values that change with a click on the card, by id in CARD_VALUES.
var _choices := {
	"sex": ["M", "F"],
	"hair": ["BRN", "BLK", "BLN", "RED", "GRY", "WHI", "BAL"],
	"eyes": ["BRN", "BLU", "GRN", "HZL", "GRY"],
	"height": _height_choices(),
	"weight": _weight_choices(),
}
## A letter alone is a small target, so a clickable value is at least this wide.
const CHOICE_MIN_WIDTH := 34.0

## The rest are stand-ins until the character creator can set them.
const CARD_VALUES: Array[Dictionary] = [
	{"id": "number", "x": 354, "y": 166, "text": "B2026327"},
	{"id": "address", "x": 354, "y": 234, "text": "1104 SOUTH VICTORY BLVD"},
	{"id": "city", "x": 354, "y": 266, "text": "BURBANK, CAL, 91502"},
	{"id": "sex", "x": 354, "y": 336},
	{"id": "hair", "x": 392, "y": 336},
	{"id": "eyes", "x": 474, "y": 336},
	{"id": "height", "x": 554, "y": 336},
	{"id": "weight", "x": 674, "y": 336},
	{"id": "prev_lic", "x": 794, "y": 336, "text": "72"},
	{"id": "birth", "x": 354, "y": 400, "text": "03-19-55"},
	{"id": "issued", "x": 674, "y": 400, "text": "03-19-72"},
]

@onready var _card: Control = $Card
@onready var _name_edit: LineEdit = $Card/NameEdit
@onready var _continue_button: Button = $Buttons/ContinueButton

var _typed_font := FontVariation.new()
var _signature := Label.new()
## The name as typed. The line shows it in capitals, the signature keeps its case.
var _typed_name := ""
var _portrait_view := SubViewport.new()
var _figure := _DriverFigure.new()
## The one trait not printed on the card: a click on the photo changes it.
var _skin: String = GameState.DRIVER_TRAITS_DEFAULT["skin"]
var _lenses_x := Label.new()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_typed_font.base_font = FONT
	_typed_font.spacing_glyph = 2
	for value in CARD_VALUES:
		_add_value(value)
	_setup_name_edit()
	_setup_signature()
	_setup_lenses_box()
	_setup_portrait()
	_setup_aging()
	_continue_button.disabled = true
	_name_edit.edit()


func _input(event: InputEvent) -> void:
	# Here and not in _unhandled_input because a LineEdit being typed in keeps Escape.
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _add_value(value: Dictionary) -> void:
	var label := Label.new()
	label.name = str(value["id"])
	label.text = str(value.get("text", GameState.DRIVER_TRAITS_DEFAULT.get(value["id"], "")))
	label.add_theme_font_override("font", _typed_font)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", INK)
	label.position = Vector2(value["x"], value["y"] - _ascent())
	_card.add_child(label)
	if _choices.has(label.name):
		label.custom_minimum_size.x = CHOICE_MIN_WIDTH
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.gui_input.connect(_on_choice_input.bind(label))


func _on_choice_input(event: InputEvent, label: Label) -> void:
	var step := _choice_step(event)
	if step == 0:
		return
	var choices: Array = _choices[label.name]
	label.text = choices[wrapi(choices.find(label.text) + step, 0, choices.size())]
	label.reset_size()
	label.accept_event()
	_update_portrait()


func _on_portrait_input(event: InputEvent, frame: Control) -> void:
	var step := _choice_step(event)
	if step == 0:
		return
	var tones: Array[String] = _DriverFigure.SKIN_TONES
	_skin = tones[wrapi(tones.find(_skin) + step, 0, tones.size())]
	frame.accept_event()
	_update_portrait()


func _on_lenses_input(event: InputEvent, area: Control) -> void:
	if _choice_step(event) == 0:
		return
	_lenses_x.visible = not _lenses_x.visible
	area.accept_event()
	_update_portrait()


## 1 for the next choice, -1 for the previous one, 0 for an event that changes nothing.
func _choice_step(event: InputEvent) -> int:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return 0
	match button.button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP:
			return 1
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_DOWN:
			return -1
	return 0


static func _height_choices() -> Array:
	var heights := []
	for inches in range(HEIGHT_RANGE.x, HEIGHT_RANGE.y + 1):
		heights.append("%d-%02d" % [inches / 12, inches % 12])
	return heights


static func _weight_choices() -> Array:
	var weights := []
	for pounds in range(WEIGHT_RANGE.x, WEIGHT_RANGE.y + 1, WEIGHT_STEP):
		weights.append(str(pounds))
	return weights


func _setup_name_edit() -> void:
	var blank := StyleBoxEmpty.new()
	for style: String in ["normal", "focus", "read_only"]:
		_name_edit.add_theme_stylebox_override(style, blank)
	_name_edit.add_theme_font_override("font", _typed_font)
	_name_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	_name_edit.add_theme_color_override("font_color", INK)
	_name_edit.add_theme_color_override("caret_color", INK)
	_name_edit.add_theme_color_override("font_placeholder_color", Color(INK, 0.45))
	_name_edit.max_length = NAME_MAX_LENGTH
	_name_edit.keep_editing_on_text_submit = true
	_name_edit.position = NAME_POSITION - Vector2(0, _ascent())
	_name_edit.size = Vector2(_card.size.x - NAME_POSITION.x, _typed_font.get_height(FONT_SIZE))


func _setup_lenses_box() -> void:
	var area := Control.new()
	area.name = "lenses"
	var target := LENSES_BOX.grow(LENSES_BOX_MARGIN)
	area.position = target.position
	area.size = target.size
	area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	area.gui_input.connect(_on_lenses_input.bind(area))
	_lenses_x.text = "X"
	_lenses_x.add_theme_font_override("font", _typed_font)
	_lenses_x.add_theme_font_size_override("font_size", LENSES_X_SIZE)
	_lenses_x.add_theme_color_override("font_color", INK)
	_lenses_x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lenses_x.reset_size()
	_lenses_x.pivot_offset = _lenses_x.size * 0.5
	_lenses_x.rotation_degrees = LENSES_X_DEGREES
	_lenses_x.position = LENSES_BOX.size * 0.5 + Vector2(LENSES_BOX_MARGIN, LENSES_BOX_MARGIN) - _lenses_x.size * 0.5 + LENSES_X_OFFSET
	_lenses_x.visible = GameState.DRIVER_TRAITS_DEFAULT["glasses"]
	area.add_child(_lenses_x)
	_card.add_child(area)


func _setup_portrait() -> void:
	_portrait_view.size = Vector2i(PORTRAIT_RECT.size) * PORTRAIT_OVERSAMPLE
	_portrait_view.own_world_3d = true
	_portrait_view.msaa_3d = Viewport.MSAA_4X
	_portrait_view.add_child(_figure)
	var camera := Camera3D.new()
	camera.fov = rad_to_deg(2.0 * atan(PORTRAIT_FRAME_HEIGHT * 0.5 / PORTRAIT_CAMERA_DISTANCE))
	camera.position = Vector3(0.0, PORTRAIT_LOOK_Y, PORTRAIT_CAMERA_DISTANCE)
	var world := Environment.new()
	world.background_mode = Environment.BG_COLOR
	world.background_color = PORTRAIT_BACKDROP
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color.WHITE
	world.ambient_light_energy = 0.42
	camera.environment = world
	_portrait_view.add_child(camera)
	var flash := DirectionalLight3D.new()
	flash.rotation_degrees = Vector3(-26.0, 24.0, 0.0)
	flash.light_energy = 0.95
	_portrait_view.add_child(flash)
	add_child(_portrait_view)

	var corner := StyleBoxFlat.new()
	corner.corner_radius_bottom_left = PORTRAIT_CORNER
	var frame := Panel.new()
	frame.name = "Portrait"
	frame.add_theme_stylebox_override("panel", corner)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame.gui_input.connect(_on_portrait_input.bind(frame))
	frame.position = PORTRAIT_RECT.position
	frame.size = PORTRAIT_RECT.size
	var photo := TextureRect.new()
	photo.texture = _portrait_view.get_texture()
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.size = PORTRAIT_RECT.size
	var fade := ShaderMaterial.new()
	fade.shader = PORTRAIT_FADE
	photo.material = fade
	frame.add_child(photo)
	_card.add_child(frame)
	_update_portrait()


func _setup_aging() -> void:
	var aging := ShaderMaterial.new()
	aging.shader = CARD_AGING
	aging.set_shader_parameter("wear_map", CARD_WEAR)
	aging.set_shader_parameter("card_size", _card.size)
	aging.set_shader_parameter("corner_radius", float(PORTRAIT_CORNER))
	var cover := ColorRect.new()
	cover.name = "Aging"
	cover.material = aging
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.size = _card.size
	_card.add_child(cover)


## The photo only needs drawing when the driver changes.
func _update_portrait() -> void:
	_figure.apply(_traits())
	_portrait_view.render_target_update_mode = SubViewport.UPDATE_ONCE


func _traits() -> Dictionary:
	var traits := {}
	for id: String in _choices:
		traits[id] = (_card.get_node(id) as Label).text
	traits["skin"] = _skin
	traits["glasses"] = _lenses_x.visible
	return traits


func _setup_signature() -> void:
	_signature.name = "signature"
	_signature.add_theme_font_override("font", SIGNATURE_FONT)
	_signature.add_theme_color_override("font_color", SIGNATURE_INK)
	_card.add_child(_signature)


func _update_signature() -> void:
	var signed := _signed_name(_driver_name())
	var room := _card.size.x - SIGNATURE_POSITION.x - SIGNATURE_MARGIN
	var width := SIGNATURE_FONT.get_string_size(signed, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGNATURE_SIZE).x
	var font_size := SIGNATURE_SIZE
	if width > room:
		font_size = floori(SIGNATURE_SIZE * room / width)
	_signature.text = signed
	_signature.add_theme_font_size_override("font_size", font_size)
	_signature.position = SIGNATURE_POSITION - Vector2(0, SIGNATURE_FONT.get_ascent(font_size))
	_signature.reset_size()


## People sign in upper and lower case, whatever the typed line says. Capitals typed
## inside a word stay, as in McGee, unless the whole name is capitals, which is caps lock.
func _signed_name(driver_name: String) -> String:
	if driver_name == driver_name.to_upper():
		driver_name = driver_name.to_lower()
	var signed := ""
	var starts_word := true
	for letter in driver_name:
		signed += letter.to_upper() if starts_word else letter
		starts_word = letter in " -'"
	return signed


func _ascent() -> float:
	return _typed_font.get_ascent(FONT_SIZE)


func _driver_name() -> String:
	return _typed_name.strip_edges()


## Works out the typed form of the line after an edit: everything after the caret and the
## part before the edit are unchanged, and what lies between arrived as it was typed.
func _typed_form(new_text: String) -> String:
	var caret := _name_edit.caret_column
	var after_caret := new_text.length() - caret
	var unchanged := 0
	var most := mini(_typed_name.length() - after_caret, caret)
	while unchanged < most and _typed_name[unchanged].to_upper() == new_text[unchanged].to_upper():
		unchanged += 1
	var typed := _typed_name.left(unchanged) + new_text.substr(unchanged, caret - unchanged)
	if after_caret > 0:
		typed += _typed_name.right(after_caret)
	return typed if typed.to_upper() == new_text.to_upper() else new_text


func _on_name_changed(new_text: String) -> void:
	_typed_name = _typed_form(new_text)
	# Licenses are typed in capitals, whatever the shift key says.
	var capitals := new_text.to_upper()
	if capitals != new_text:
		var caret := _name_edit.caret_column
		_name_edit.text = capitals
		_name_edit.caret_column = caret
	_continue_button.disabled = _driver_name().is_empty()
	_update_signature()


func _on_name_submitted(_new_text: String) -> void:
	_on_continue_pressed()


func _on_continue_pressed() -> void:
	if _driver_name().is_empty():
		return
	var driver_name := _signed_name(_driver_name())
	var traits := _traits()
	GameState.new_game()
	GameState.driver_name = driver_name
	GameState.driver_traits = traits
	if driver_name.to_upper() == CHEAT_NAME:
		GameState.money = CHEAT_MONEY
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_MAIN_MENU)
