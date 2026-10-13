class_name TouchButton
extends Control
## Круглая сенсорная кнопка. Нажатие отправляет действие InputMap через Input.parse_input_event,
## поэтому для игры нет разницы между кнопкой на экране, клавиатурой и геймпадом.
## Касания распределяет TouchControls (мультитач), сама кнопка мышь не ловит.

const COLOR_IDLE: Color = Color(0.09, 0.1, 0.11, 0.55)
const COLOR_RING: Color = Color(0.85, 0.87, 0.88, 0.7)
const COLOR_ACCENT: Color = Color(0.85, 0.63, 0.25, 0.9)

var action: StringName = &""
var label_key: String = ""
var toggle: bool = false
var radius: float = 40.0
var pressed: bool = false
var _finger: int = -1


func setup(p_action: StringName, p_label_key: String, p_toggle: bool = false) -> void:
	action = p_action
	label_key = p_label_key
	toggle = p_toggle
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_label(key: String) -> void:
	if label_key != key:
		label_key = key
		queue_redraw()


func set_radius(r: float) -> void:
	radius = r
	size = Vector2(r * 2.0, r * 2.0)
	queue_redraw()


func center() -> Vector2:
	return global_position + size * 0.5


## Попадание с запасом: зона нажатия чуть больше рисунка (не требуем точного попадания).
func hit(point: Vector2) -> bool:
	return visible and point.distance_to(center()) <= radius * 1.15


func finger_down(index: int) -> void:
	_finger = index
	if toggle:
		_set_pressed(not pressed)
	else:
		_set_pressed(true)
	Settings.haptic(15)


func finger_up(index: int) -> void:
	if index != _finger:
		return
	_finger = -1
	if not toggle:
		_set_pressed(false)


func release_all() -> void:
	_finger = -1
	_set_pressed(false)


func _set_pressed(value: bool) -> void:
	if pressed == value:
		return
	pressed = value
	if action != &"":
		var ev: InputEventAction = InputEventAction.new()
		ev.action = action
		ev.pressed = value
		ev.strength = 1.0 if value else 0.0
		Input.parse_input_event(ev)
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	draw_circle(c, radius, COLOR_ACCENT if pressed else COLOR_IDLE, true, -1.0, true)
	draw_arc(c, radius, 0.0, TAU, 48, COLOR_RING, 2.0, true)
	if label_key.is_empty():
		return
	var font: Font = get_theme_font(&"font", &"Label")
	var fs: int = int(clampf(radius * 0.36, 14.0, 30.0))
	var text: String = tr(label_key)
	var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.95, 0.93))
