class_name InventoryScreen
extends CanvasLayer
## Экран «Вещи»: экипировка, рюкзак 24, быстрая панель 6, описание выбранного предмета и крафт.
## Перенос предметов: перетаскиванием пальцем или «нажми на предмет — нажми на ячейку».
## Игра не ставится на паузу (выживание идёт дальше). Узлы создаются один раз в bind();
## при изменениях обновляется только текст/отрисовка.

signal closed

const SLOT: float = 88.0
const GAP: int = 6

var _session: SurvivalSession
var _icons: ItemIcons
var _slots: Array[InventorySlot] = []
var _selected: int = -1

var _root: Control
var _detail_name: Label
var _detail_desc: Label
var _use_btn: Button
var _split_btn: Button
var _queue_label: Label
var _cancel_btn: Button
var _rows: Dictionary = {}
var _refresh_t: float = 0.0


func _ready() -> void:
	layer = 40
	visible = false


func bind(session: SurvivalSession, icons: ItemIcons) -> void:
	_session = session
	_icons = icons
	_build()
	session.inventory.changed.connect(_on_inventory_changed)
	session.crafting.queue_changed.connect(_refresh_craft)


func is_open() -> bool:
	return visible


func open() -> void:
	if _session == null:
		return
	visible = true
	_select(-1)
	_on_inventory_changed()


func close() -> void:
	if not visible:
		return
	visible = false
	_select(-1)
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	# Таймер очереди и доступность станций (игрок мог отойти от костра) — дважды в секунду.
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.5
		_refresh_craft()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("inventory") or event.is_action_pressed("pause")):
		close()
		get_viewport().set_input_as_handled()


# --- Построение -------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.07, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_root.add_child(margin)
	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 18)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(cols)

	for i: int in Inventory.TOTAL:
		var s: InventorySlot = InventorySlot.new()
		s.setup(_session.inventory, _icons, i, SLOT)
		s.tapped.connect(_on_slot_tapped)
		s.dropped.connect(_on_slot_dropped)
		_slots.append(s)

	# Экипировка.
	var eq: VBoxContainer = VBoxContainer.new()
	eq.add_theme_constant_override(&"separation", GAP)
	eq.add_child(_title("INV_EQUIPMENT"))
	for k: int in Inventory.EQUIP_SLOTS.size():
		var s: InventorySlot = _slots[Inventory.EQUIP_START + k]
		s.placeholder_key = "INV_EQUIP_%s" % Inventory.EQUIP_SLOTS[k].to_upper()
		eq.add_child(s)
	cols.add_child(eq)

	# Рюкзак и быстрая панель.
	var mid: VBoxContainer = VBoxContainer.new()
	mid.add_theme_constant_override(&"separation", GAP)
	mid.add_child(_title("INV_BACKPACK"))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override(&"h_separation", GAP)
	grid.add_theme_constant_override(&"v_separation", GAP)
	for i: int in range(Inventory.BACKPACK_START, Inventory.EQUIP_START):
		grid.add_child(_slots[i])
	mid.add_child(grid)
	mid.add_child(_title("INV_HOTBAR"))
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override(&"separation", GAP)
	for i: int in Inventory.HOTBAR_SIZE:
		hb.add_child(_slots[i])
	mid.add_child(hb)
	cols.add_child(mid)

	# Описание предмета и крафт.
	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size = Vector2(440.0, 0.0)
	right.add_theme_constant_override(&"separation", 8)
	var top: HBoxContainer = HBoxContainer.new()
	var detail_box: VBoxContainer = VBoxContainer.new()
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override(&"font_size", 26)
	_detail_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	detail_box.add_child(_detail_name)
	_detail_desc = Label.new()
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.74))
	_detail_desc.add_theme_font_size_override(&"font_size", 18)
	_detail_desc.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	detail_box.add_child(_detail_desc)
	top.add_child(detail_box)
	var close_btn: Button = _button("UI_CLOSE", 140.0)
	close_btn.pressed.connect(close)
	top.add_child(close_btn)
	right.add_child(top)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 10)
	_use_btn = _button("INV_EAT", 150.0)
	_use_btn.pressed.connect(_on_use)
	actions.add_child(_use_btn)
	_split_btn = _button("INV_SPLIT", 150.0)
	_split_btn.pressed.connect(_on_split)
	actions.add_child(_split_btn)
	right.add_child(actions)

	right.add_child(_title("CRAFT_TITLE"))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 6)
	for rid: String in _session.crafting.recipe_ids():
		list.add_child(_craft_row(rid))
	scroll.add_child(list)
	right.add_child(scroll)
	var qrow: HBoxContainer = HBoxContainer.new()
	_queue_label = Label.new()
	_queue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_queue_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_queue_label.add_theme_font_size_override(&"font_size", 18)
	qrow.add_child(_queue_label)
	_cancel_btn = _button("CRAFT_CANCEL", 150.0)
	_cancel_btn.pressed.connect(_on_cancel)
	qrow.add_child(_cancel_btn)
	right.add_child(qrow)
	cols.add_child(right)


func _title(key: String) -> Label:
	var l: Label = Label.new()
	l.text = key
	l.add_theme_font_size_override(&"font_size", 20)
	l.add_theme_color_override(&"font_color", Color(0.62, 0.65, 0.67))
	return l


func _button(key: String, w: float) -> Button:
	var b: Button = Button.new()
	b.text = key
	b.custom_minimum_size = Vector2(w, 72.0)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _craft_row(rid: String) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.12, 0.9)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override(&"panel", sb)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var icon: TextureRect = TextureRect.new()
	icon.texture = _icons.get_icon(_session.crafting.result_of(rid))
	icon.custom_minimum_size = Vector2(64.0, 64.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_l: Label = Label.new()
	name_l.text = _session.items.name_key(_session.crafting.result_of(rid))
	name_l.add_theme_font_size_override(&"font_size", 22)
	info.add_child(name_l)
	var need: Label = Label.new()
	need.add_theme_font_size_override(&"font_size", 17)
	need.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	need.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	info.add_child(need)
	row.add_child(info)
	var btn: Button = _button("CRAFT_MAKE", 130.0)
	btn.pressed.connect(_on_craft.bind(rid))
	row.add_child(btn)
	panel.add_child(row)
	_rows[rid] = {"need": need, "button": btn}
	return panel


# --- Обновление -------------------------------------------------------------

func _on_inventory_changed() -> void:
	if not visible:
		return
	for s: InventorySlot in _slots:
		s.queue_redraw()
	if _selected >= 0 and _session.inventory.is_empty(_selected):
		_select(-1)
	else:
		_update_detail()
	_refresh_craft()


func _refresh_craft() -> void:
	if not visible or _session == null:
		return
	var cr: Crafting = _session.crafting
	var inv: Inventory = _session.inventory
	var stations: PackedStringArray = _session.stations_at(_session.player_position)
	for rid: String in _rows:
		var r: Dictionary = _rows[rid]
		var ing: Dictionary = cr.ingredients(rid)
		var parts: PackedStringArray = PackedStringArray()
		for item: String in ing:
			parts.append("%s %d/%d" % [tr(_session.items.name_key(item)), inv.count_of(item), int(ing[item])])
		var st: String = cr.station_of(rid)
		var text: String = " · ".join(parts)
		if not st.is_empty():
			text += "\n" + tr("CRAFT_NEEDS_STATION") % tr("STATION_%s" % st.to_upper())
		var check: Crafting.Check = cr.check(rid, inv, stations)
		var need: Label = r["need"]
		if need.text != text:
			need.text = text
		need.modulate = Color(1, 1, 1) if check == Crafting.Check.OK or check == Crafting.Check.QUEUE_FULL else Color(0.95, 0.6, 0.55)
		(r["button"] as Button).disabled = check != Crafting.Check.OK
	if cr.queue.is_empty():
		_queue_label.text = tr("CRAFT_QUEUE_EMPTY")
		_cancel_btn.disabled = true
	else:
		var head: Dictionary = cr.queue[0]
		var item: String = cr.result_of(String(head["recipe"]))
		_queue_label.text = tr("CRAFT_QUEUE") % [tr(_session.items.name_key(item)), ceilf(float(head["left"])), cr.queue.size() - 1]
		_cancel_btn.disabled = false


func _select(slot: int) -> void:
	_selected = slot
	for s: InventorySlot in _slots:
		s.set_selected(s.slot == slot)
	_update_detail()


func _update_detail() -> void:
	if _selected < 0 or _session.inventory.is_empty(_selected):
		_detail_name.text = tr("INV_HINT_TITLE")
		_detail_desc.text = tr("INV_HINT")
		_use_btn.visible = false
		_split_btn.visible = false
		return
	var id: String = _session.inventory.slot_id(_selected)
	_detail_name.text = tr(_session.items.name_key(id))
	_detail_desc.text = tr(_session.items.desc_key(id))
	_use_btn.visible = _session.items.kind(id) == ItemDB.KIND_FOOD
	_split_btn.visible = _session.inventory.slot_count(_selected) > 1


# --- Действия ---------------------------------------------------------------

func _on_slot_tapped(slot: int) -> void:
	Settings.haptic(10)
	if _selected >= 0 and _selected != slot and not _session.inventory.is_empty(_selected):
		# Второе нажатие — перенос в эту ячейку.
		if _session.inventory.move(_selected, slot):
			_select(-1)
			return
	if _session.inventory.is_empty(slot):
		_select(-1)
	else:
		_select(slot if _selected != slot else -1)


func _on_slot_dropped(from: int, to: int) -> void:
	if _session.inventory.move(from, to):
		Settings.haptic(10)
	_select(-1)


func _on_use() -> void:
	if _selected >= 0:
		_session.eat_slot(_selected)


func _on_split() -> void:
	if _selected >= 0:
		_session.inventory.split(_selected)


func _on_craft(rid: String) -> void:
	var c: Crafting.Check = _session.craft(rid)
	if c != Crafting.Check.OK:
		Events.toast_requested.emit(tr("CRAFT_FAIL_%d" % c))
	else:
		Settings.haptic(15)
	_refresh_craft()


func _on_cancel() -> void:
	var lost: int = _session.crafting.cancel(0, _session.inventory)
	if lost > 0:
		Events.toast_requested.emit(tr("CRAFT_REFUND_LOST") % lost)
