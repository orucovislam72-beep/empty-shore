class_name StatBars
extends Control
## Полоски здоровья, сытости и воды с иконками. Перерисовываются только при изменении значений
## (HUD передаёт значения 4 раза в секунду).

const BAR_W: float = 170.0
const BAR_H: float = 16.0
const ROW_H: float = 30.0
const ICON: float = 24.0
const COLORS: Array[Color] = [Color(0.77, 0.31, 0.35), Color(0.85, 0.63, 0.25), Color(0.35, 0.6, 0.77)]
const ICON_PATHS: Array[String] = ["res://assets/icons/hud/health.svg", "res://assets/icons/hud/hunger.svg", "res://assets/icons/hud/thirst.svg"]

var _values: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0])
var _icons: Array[Texture2D] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(ICON + 8.0 + BAR_W, ROW_H * 3.0)
	size = custom_minimum_size
	for p: String in ICON_PATHS:
		_icons.append(load(p) as Texture2D)


## Значения 0..1: здоровье, сытость, вода.
func set_values(health: float, hunger: float, thirst: float) -> void:
	var changed: bool = absf(_values[0] - health) > 0.002 or absf(_values[1] - hunger) > 0.002 or absf(_values[2] - thirst) > 0.002
	if not changed:
		return
	_values[0] = health
	_values[1] = hunger
	_values[2] = thirst
	queue_redraw()


func _draw() -> void:
	for i: int in 3:
		var y: float = float(i) * ROW_H
		if i < _icons.size() and _icons[i] != null:
			draw_texture_rect(_icons[i], Rect2(0.0, y + (ROW_H - ICON) * 0.5, ICON, ICON), false)
		var x: float = ICON + 8.0
		var by: float = y + (ROW_H - BAR_H) * 0.5
		draw_rect(Rect2(x, by, BAR_W, BAR_H), Color(0.06, 0.07, 0.08, 0.75))
		var v: float = clampf(_values[i], 0.0, 1.0)
		var c: Color = COLORS[i]
		if v < 0.2:
			c = c.lerp(Color(0.95, 0.3, 0.25), 0.5)
		draw_rect(Rect2(x + 2.0, by + 2.0, (BAR_W - 4.0) * v, BAR_H - 4.0), c)
