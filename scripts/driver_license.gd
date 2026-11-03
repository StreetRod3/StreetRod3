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

const SIGNATURE_FONT := preload("res://assets/fonts/HomemadeApple-Regular.ttf")
const SIGNATURE_SIZE := 30
const SIGNATURE_INK := Color("#2a2d55")
const SIGNATURE_POSITION := Vector2(366, 552)
## Long names shrink to stop this far short of the right edge of the card.
const SIGNATURE_MARGIN := 10.0

## Values that change with a click on the card, by id in CARD_VALUES. The first is the default.
const CARD_CHOICES := {
	"sex": ["M", "F"],
}
## A letter alone is a small target, so a clickable value is at least this wide.
const CHOICE_MIN_WIDTH := 34.0

## The rest are stand-ins until the character creator can set them.
const CARD_VALUES: Array[Dictionary] = [
	{"id": "number", "x": 354, "y": 166, "text": "B2026327"},
	{"id": "address", "x": 354, "y": 234, "text": "1104 SOUTH VICTORY BLVD"},
	{"id": "city", "x": 354, "y": 266, "text": "BURBANK, CAL, 91502"},
	{"id": "sex", "x": 354, "y": 336, "text": "M"},
	{"id": "hair", "x": 392, "y": 336, "text": "BRN"},
	{"id": "eyes", "x": 474, "y": 336, "text": "BRN"},
	{"id": "height", "x": 554, "y": 336, "text": "5-08"},
	{"id": "weight", "x": 674, "y": 336, "text": "165"},
	{"id": "prev_lic", "x": 794, "y": 336, "text": "72"},
	{"id": "birth", "x": 354, "y": 400, "text": "03-19-55"},
	{"id": "issued", "x": 674, "y": 400, "text": "03-19-72"},
]

@onready var _card: Control = $Card
@onready var _name_edit: LineEdit = $Card/NameEdit
@onready var _continue_button: Button = $Buttons/ContinueButton

var _typed_font := FontVariation.new()
var _signature := Label.new()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_typed_font.base_font = FONT
	_typed_font.spacing_glyph = 2
	for value in CARD_VALUES:
		_add_value(value)
	_setup_name_edit()
	_setup_signature()
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
	label.text = str(value["text"])
	label.add_theme_font_override("font", _typed_font)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", INK)
	label.position = Vector2(value["x"], value["y"] - _ascent())
	_card.add_child(label)
	if CARD_CHOICES.has(label.name):
		label.custom_minimum_size.x = CHOICE_MIN_WIDTH
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.gui_input.connect(_on_choice_input.bind(label))


func _on_choice_input(event: InputEvent, label: Label) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var choices: Array = CARD_CHOICES[label.name]
	label.text = choices[wrapi(choices.find(label.text) + 1, 0, choices.size())]
	label.accept_event()


func _setup_name_edit() -> void:
	var blank := StyleBoxEmpty.new()
	for style in ["normal", "focus", "read_only"]:
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


## People sign in upper and lower case, whatever the typed line says.
func _signed_name(driver_name: String) -> String:
	var signed := ""
	var starts_word := true
	for letter in driver_name.to_lower():
		signed += letter.to_upper() if starts_word else letter
		starts_word = letter in " -'"
	return signed


func _ascent() -> float:
	return _typed_font.get_ascent(FONT_SIZE)


func _driver_name() -> String:
	return _name_edit.text.strip_edges()


func _on_name_changed(new_text: String) -> void:
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
	var driver_name := _driver_name()
	var driver_sex: String = (_card.get_node("sex") as Label).text
	GameState.new_game()
	GameState.driver_name = driver_name
	GameState.driver_sex = driver_sex
	GameState.current_scene_path = GameState.SCENE_GARAGE
	get_tree().change_scene_to_file(GameState.SCENE_GARAGE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_MAIN_MENU)
