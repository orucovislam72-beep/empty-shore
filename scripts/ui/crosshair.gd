class_name Crosshair
extends Control
## Простой прицел: точка с кольцом.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(24.0, 24.0)
	size = custom_minimum_size


func _draw() -> void:
	var c: Vector2 = size * 0.5
	draw_circle(c, 2.5, Color(0.95, 0.95, 0.93, 0.9), true, -1.0, true)
	draw_arc(c, 9.0, 0.0, TAU, 32, Color(0.95, 0.95, 0.93, 0.5), 1.5, true)
