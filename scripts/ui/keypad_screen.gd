class_name KeypadScreen
extends CanvasLayer
## Кодовый замок: экран с крупными цифрами 0–9 (кнопки 96 × 80, больше 48 dp), «Стереть» и «Готово».
## Режимы: задать код (новый замок), ввести код (чужая или запертая дверь), сменить код.
## Проверку кода делает SurvivalSession; экран только собирает 4 цифры и отдаёт их сигналом.

signal code_entered(mode: int, door_id: int, code: String)
signal closed

enum Mode { SET, ENTER, CHANGE }

const CODE_LEN: int = 4

var mode: Mode = Mode.ENTER
var door_id: int = -1
var _code: String = ""
var _title: Label
var _display: Label
var _ok: Button


func _ready() -> void:
	layer = 42
	visible = false
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.07, 0.88)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	center.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", 26)
	box.add_child(_title)
	_display = Label.new()
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_display.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_display.add_theme_font_size_override(&"font_size", 48)
	_display.add_theme_color_override(&"font_color", Color(0.85, 0.63, 0.25))
	box.add_child(_display)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	for d: String in ["1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		grid.add_child(_digit(d))
	var clear: Button = _key("KEYPAD_CLEAR")
	clear.pressed.connect(_on_clear)
	grid.add_child(clear)
	grid.add_child(_digit("0"))
	_ok = _key("KEYPAD_OK")
	_ok.pressed.connect(_on_ok)
	grid.add_child(_ok)
	box.add_child(grid)
	var close_btn: Button = _key("UI_CLOSE")
	close_btn.custom_minimum_size = Vector2(316.0, 72.0)
	close_btn.pressed.connect(close)
	box.add_child(close_btn)


func _key(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96.0, 80.0)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _digit(d: String) -> Button:
	var b: Button = _key(d)
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.add_theme_font_size_override(&"font_size", 34)
	b.pressed.connect(press_digit.bind(d))
	return b


func is_open() -> bool:
	return visible


func open(p_mode: Mode, p_door: int) -> void:
	mode = p_mode
	door_id = p_door
	_code = ""
	match mode:
		Mode.SET:
			_title.text = "KEYPAD_SET"
		Mode.CHANGE:
			_title.text = "KEYPAD_CHANGE"
		_:
			_title.text = "KEYPAD_ENTER"
	visible = true
	_update()


func close() -> void:
	if not visible:
		return
	visible = false
	_code = ""
	closed.emit()


func press_digit(d: String) -> void:
	if _code.length() >= CODE_LEN:
		return
	_code += d
	Settings.haptic(8)
	_update()


func _on_clear() -> void:
	_code = ""
	_update()


func _on_ok() -> void:
	if _code.length() != CODE_LEN:
		return
	var c: String = _code
	_code = ""
	_update()
	code_entered.emit(mode, door_id, c)


## Код набран, но не подошёл — стереть и ждать новую попытку.
func reject() -> void:
	_code = ""
	_update()


func _update() -> void:
	var shown: String = ""
	for i: int in CODE_LEN:
		if i < _code.length():
			shown += (_code[i] if mode != Mode.ENTER else "•") + " "
		else:
			shown += "_ "
	_display.text = shown.strip_edges()
	_ok.disabled = _code.length() != CODE_LEN


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed and not event.is_echo():
		var k: Key = (event as InputEventKey).keycode
		if k >= KEY_0 and k <= KEY_9:
			press_digit(str(int(k - KEY_0)))
			get_viewport().set_input_as_handled()
		elif k == KEY_ENTER or k == KEY_KP_ENTER:
			_on_ok()
			get_viewport().set_input_as_handled()
		elif k == KEY_BACKSPACE:
			_on_clear()
			get_viewport().set_input_as_handled()
