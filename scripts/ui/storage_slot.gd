class_name StorageSlot
extends Control
## Ячейка хранилища (ящик, запас знамени): иконка, количество, полоска прочности.
## Нажатие — сигнал tapped (экран хранилища перекладывает стопку). Рисует так же, как InventorySlot.

signal tapped(slot: int)

const BG: Color = Color(0.11, 0.12, 0.13, 0.92)
const BG_EMPTY: Color = Color(0.11, 0.12, 0.13, 0.6)
const BORDER: Color = Color(0.32, 0.34, 0.36)
const DUR_COLOR: Color = Color(0.55, 0.75, 0.45)

var slot: int = 0
var _st: ItemStorage
var _icons: ItemIcons
var _pressed: bool = false


func setup(icons: ItemIcons, p_slot: int, side: float) -> void:
	_icons = icons
	slot = p_slot
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func bind_storage(st: ItemStorage) -> void:
	_st = st
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			_pressed = true
		elif _pressed:
			_pressed = false
			tapped.emit(slot)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_pressed = false


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	var empty: bool = _st == null or slot >= _st.size() or _st.is_empty(slot)
	draw_rect(r, BG_EMPTY if empty else BG)
	draw_rect(r, BORDER, false, 1.5)
	if empty:
		return
	var id: String = _st.slot_id(slot)
	var tex: Texture2D = _icons.get_icon(id)
	if tex != null:
		var pad: float = size.x * 0.12
		draw_texture_rect(tex, Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0), false)
	var font: Font = get_theme_font(&"font", &"Label")
	var n: int = _st.slot_count(slot)
	if n > 1:
		var fs: int = int(clampf(size.y * 0.24, 16.0, 26.0))
		var s: String = str(n)
		var ts: Vector2 = font.get_string_size(s, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs)
		var p: Vector2 = Vector2(size.x - ts.x - 6.0, size.y - 8.0)
		draw_string(font, p + Vector2(1.5, 1.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.0, 0.0, 0.0, 0.8))
		draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.95, 0.93))
	var maxd: int = _st.db.max_durability(id)
	var d: int = _st.slot_durability(slot)
	if maxd > 0 and d >= 0:
		var w: float = (size.x - 12.0) * clampf(float(d) / float(maxd), 0.0, 1.0)
		draw_rect(Rect2(6.0, size.y - 9.0, size.x - 12.0, 4.0), Color(0.0, 0.0, 0.0, 0.5))
		draw_rect(Rect2(6.0, size.y - 9.0, w, 4.0), DUR_COLOR if d * 4 > maxd else Color(0.85, 0.35, 0.3))
