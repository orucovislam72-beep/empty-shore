class_name TouchStick
extends Control
## Плавающий виртуальный стик (в Godot 4.7 появился встроенный класс VirtualJoystick — имя занято;
## свой стик оставлен ради общего маршрутизатора мультитача и автобега, см. docs/IDEAS.md). Вектор отдаётся в действия move_* через Input.action_press
## с силой нажатия, так что персонаж читает его так же, как клавиатуру и геймпад.
## Двойной толчок вперёд — автобег (Events.autorun_toggle_requested).

const COLOR_BASE: Color = Color(0.09, 0.1, 0.11, 0.45)
const COLOR_RING: Color = Color(0.85, 0.87, 0.88, 0.6)
const COLOR_KNOB: Color = Color(0.85, 0.87, 0.88, 0.85)

var radius: float = 110.0
var idle_center: Vector2 = Vector2.ZERO
var dead_zone: float = 0.15
var value: Vector2 = Vector2.ZERO

var _finger: int = -1
var _center: Vector2 = Vector2.ZERO
var _knob: Vector2 = Vector2.ZERO
var _double_tap: DoubleTapDetector = DoubleTapDetector.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_active() -> bool:
	return _finger != -1


func set_idle_center(p: Vector2) -> void:
	idle_center = p
	if _finger == -1:
		_center = p
	queue_redraw()


func finger_down(index: int, pos: Vector2) -> void:
	_finger = index
	_center = pos
	_knob = Vector2.ZERO
	_update_value()


func finger_move(index: int, pos: Vector2) -> void:
	if index != _finger:
		return
	var offset: Vector2 = pos - _center
	# Если палец ушёл далеко — подтягиваем центр за пальцем, чтобы не терять управление.
	if offset.length() > radius * 1.4:
		_center = pos - offset.normalized() * radius * 1.4
		offset = pos - _center
	_knob = StickMath.clamp_knob(offset, radius)
	value = StickMath.to_vector(offset, radius, dead_zone)
	_update_value()


func finger_up(index: int) -> void:
	if index != _finger:
		return
	release_all()


func release_all() -> void:
	_finger = -1
	_knob = Vector2.ZERO
	_center = idle_center
	value = Vector2.ZERO
	_update_value()


func _update_value() -> void:
	_apply_axis(&"move_left", &"move_right", value.x)
	_apply_axis(&"move_forward", &"move_back", value.y)
	if _double_tap.update(maxf(-value.y, 0.0), Time.get_ticks_msec() / 1000.0):
		Events.autorun_toggle_requested.emit()
		Settings.haptic(25)
	queue_redraw()


static func _apply_axis(negative: StringName, positive: StringName, v: float) -> void:
	if v < 0.0:
		Input.action_press(negative, -v)
		Input.action_release(positive)
	elif v > 0.0:
		Input.action_press(positive, v)
		Input.action_release(negative)
	else:
		Input.action_release(negative)
		Input.action_release(positive)


func _draw() -> void:
	var c: Vector2 = _center - global_position
	draw_circle(c, radius, COLOR_BASE, true, -1.0, true)
	draw_arc(c, radius, 0.0, TAU, 64, COLOR_RING, 2.0, true)
	draw_circle(c + _knob, radius * 0.42, COLOR_KNOB, true, -1.0, true)
