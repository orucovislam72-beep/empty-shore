class_name Hotbar
extends HBoxContainer
## Быстрая панель на HUD: 6 ячеек, нажатие выбирает активный предмет.
## Перетаскивание здесь выключено (оно в экране «Вещи»), чтобы не мешать игре.

signal slot_selected(slot: int)

var _slots: Array[InventorySlot] = []


func setup(inv: Inventory, icons: ItemIcons, side: float) -> void:
	add_theme_constant_override(&"separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i: int in Inventory.HOTBAR_SIZE:
		var s: InventorySlot = InventorySlot.new()
		s.setup(inv, icons, i, side)
		s.drag_enabled = false
		s.tapped.connect(_on_tapped)
		add_child(s)
		_slots.append(s)
	inv.changed.connect(_redraw)


func set_slot_side(side: float) -> void:
	for s: InventorySlot in _slots:
		s.custom_minimum_size = Vector2(side, side)
	reset_size()


func set_active(slot: int) -> void:
	for s: InventorySlot in _slots:
		s.set_selected(s.slot == slot)


func _on_tapped(slot: int) -> void:
	Settings.haptic(10)
	slot_selected.emit(slot)


func _redraw() -> void:
	for s: InventorySlot in _slots:
		s.queue_redraw()
