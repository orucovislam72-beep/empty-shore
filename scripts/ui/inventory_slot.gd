class_name InventorySlot
extends Control
## Ячейка инвентаря: иконка, количество, полоска прочности, выделение.
## Нажатие — сигнал tapped (выбор / перенос «нажми-нажми»); перетаскивание пальцем
## через встроенный drag-and-drop Godot (_get_drag_data / _can_drop_data / _drop_data;
## касания приходят как эмулированная мышь — input_devices/pointing/emulate_mouse_from_touch).

signal tapped(slot: int)
signal dropped(from_slot: int, to_slot: int)

const BG: Color = Color(0.11, 0.12, 0.13, 0.92)
const BG_EMPTY: Color = Color(0.11, 0.12, 0.13, 0.6)
const BORDER: Color = Color(0.32, 0.34, 0.36)
const ACCENT: Color = Color(0.85, 0.63, 0.25)
const DUR_COLOR: Color = Color(0.55, 0.75, 0.45)

var slot: int = 0
var drag_enabled: bool = true
var selected: bool = false
## Подпись пустой ячейки экипировки (ключ перевода) или "".
var placeholder_key: String = ""

var _inv: Inventory
var _icons: ItemIcons
var _pressed: bool = false


func setup(inv: Inventory, icons: ItemIcons, p_slot: int, side: float) -> void:
	_inv = inv
	_icons = icons
	slot = p_slot
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func set_selected(v: bool) -> void:
	if selected != v:
		selected = v
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
	if what == NOTIFICATION_DRAG_BEGIN:
		_pressed = false
	elif what == NOTIFICATION_MOUSE_EXIT:
		_pressed = false


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not drag_enabled or _inv == null or _inv.is_empty(slot):
		return null
	var preview: TextureRect = TextureRect.new()
	preview.texture = _icons.get_icon(_inv.slot_id(slot))
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = size
	preview.position = -size * 0.5
	preview.modulate.a = 0.85
	var holder: Control = Control.new()
	holder.add_child(preview)
	set_drag_preview(holder)
	return {"inv_slot": slot}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not drag_enabled or typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("inv_slot"):
		return false
	var from: int = int(data["inv_slot"])
	return from != slot and _inv.accepts(slot, _inv.slot_id(from))


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	dropped.emit(int(data["inv_slot"]), slot)


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	var empty: bool = _inv == null or _inv.is_empty(slot)
	draw_rect(r, BG_EMPTY if empty else BG)
	draw_rect(r, ACCENT if selected else BORDER, false, 3.0 if selected else 1.5)
	var font: Font = get_theme_font(&"font", &"Label")
	if empty:
		if not placeholder_key.is_empty():
			var fs0: int = 16
			var t: String = tr(placeholder_key)
			var ts0: Vector2 = font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, fs0)
			draw_string(font, Vector2((size.x - ts0.x) * 0.5, size.y * 0.5 + fs0 * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs0, Color(0.45, 0.47, 0.5))
		return
	var id: String = _inv.slot_id(slot)
	var tex: Texture2D = _icons.get_icon(id)
	if tex != null:
		var pad: float = size.x * 0.12
		draw_texture_rect(tex, Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0), false)
	var n: int = _inv.slot_count(slot)
	if n > 1:
		var fs: int = int(clampf(size.y * 0.24, 16.0, 26.0))
		var s: String = str(n)
		var ts: Vector2 = font.get_string_size(s, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs)
		var p: Vector2 = Vector2(size.x - ts.x - 6.0, size.y - 8.0)
		draw_string(font, p + Vector2(1.5, 1.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.0, 0.0, 0.0, 0.8))
		draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.95, 0.93))
	var maxd: int = _inv.db.max_durability(id)
	var d: int = _inv.slot_durability(slot)
	if maxd > 0 and d >= 0:
		var w: float = (size.x - 12.0) * clampf(float(d) / float(maxd), 0.0, 1.0)
		draw_rect(Rect2(6.0, size.y - 9.0, size.x - 12.0, 4.0), Color(0.0, 0.0, 0.0, 0.5))
		draw_rect(Rect2(6.0, size.y - 9.0, w, 4.0), DUR_COLOR if d * 4 > maxd else Color(0.85, 0.35, 0.3))
