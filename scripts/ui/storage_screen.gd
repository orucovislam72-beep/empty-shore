class_name StorageScreen
extends CanvasLayer
## Экран хранилища: слева — ячейки ящика или запаса знамени базы, справа — рюкзак и быстрая панель.
## Нажатие на предмет перекладывает всю стопку на другую сторону (крупные зоны, без точного
## перетаскивания). Для знамени ниже — право владения и обслуживание: кто свой, расход в час,
## на сколько хватит запаса, кнопки «Стать своим» / «Выйти из своих» / «Сбросить список».
## Действия идут через SurvivalSession (она проверяет дистанцию и право).
## С этапа 3 тот же экран открывает контейнеры мира (open_container): ящики и бочки с лутом,
## мешок с вещами на месте гибели, туша животного.

signal closed

const SLOT: float = 80.0
const GAP: int = 6
const COLS: int = 6
const MAX_SLOTS: int = 36

var _session: SurvivalSession
var _icons: ItemIcons
var _index: int = -1
var _box_slots: Array[StorageSlot] = []
var _inv_slots: Array[InventorySlot] = []
var _title: Label
var _claim_box: VBoxContainer
var _claim_status: Label
var _claim_upkeep: Label
var _join_btn: Button
var _reset_btn: Button
var _refresh_t: float = 0.0
var _bound_storage: ItemStorage
## Ручка контейнера мира (WorldContainers) или -1 — открыт объект игрока (_index).
var _container: int = -1


func _ready() -> void:
	layer = 41
	visible = false


func bind(session: SurvivalSession, icons: ItemIcons) -> void:
	_session = session
	_icons = icons
	_build()
	session.inventory.changed.connect(_redraw)


func is_open() -> bool:
	return visible


func current_index() -> int:
	return _index


func open(index: int) -> void:
	if _session == null or not _session.deployables.has_storage(index):
		return
	_index = index
	_container = -1
	_bind(_session.deployables.storages[index])
	var banner: bool = _session.claims.is_banner(index)
	_title.text = tr("STORAGE_TITLE_BANNER" if banner else "STORAGE_TITLE_BOX")
	_claim_box.visible = banner
	visible = true
	_refresh_claim()
	_redraw()


## Открыть контейнер мира (лут, мешок, туша) по ручке WorldContainers.
func open_container(handle: int) -> void:
	if _session == null:
		return
	var st: ItemStorage = _session.containers.storage_of(handle)
	if st == null:
		return
	_index = -1
	_container = handle
	_bind(st)
	_title.text = tr(_session.containers.name_key(handle))
	_claim_box.visible = false
	visible = true
	_redraw()


func current_container() -> int:
	return _container


func _bind(st: ItemStorage) -> void:
	if _bound_storage != null and _bound_storage.changed.is_connected(_redraw):
		_bound_storage.changed.disconnect(_redraw)
	_bound_storage = st
	st.changed.connect(_redraw)
	for i: int in _box_slots.size():
		_box_slots[i].bind_storage(st)
		_box_slots[i].visible = i < st.size()


func close() -> void:
	if not visible:
		return
	visible = false
	if _bound_storage != null and _bound_storage.changed.is_connected(_redraw):
		_bound_storage.changed.disconnect(_redraw)
	_bound_storage = null
	_index = -1
	_container = -1
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 1.0
		var reach: bool = _session.can_reach_container(_container) if _container >= 0 else _session.can_reach(_index)
		if not reach:
			close()
			return
		_refresh_claim()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("inventory") or event.is_action_pressed("pause") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.07, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	root.add_child(margin)
	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 28)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(cols)

	var left: VBoxContainer = VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 8)
	var head: HBoxContainer = HBoxContainer.new()
	_title = Label.new()
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.add_theme_font_size_override(&"font_size", 26)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_btn: Button = _button("UI_CLOSE", 150.0)
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	left.add_child(head)
	var grid: GridContainer = GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override(&"h_separation", GAP)
	grid.add_theme_constant_override(&"v_separation", GAP)
	for i: int in MAX_SLOTS:
		var s: StorageSlot = StorageSlot.new()
		s.setup(_icons, i, SLOT)
		s.tapped.connect(_on_box_tapped)
		grid.add_child(s)
		_box_slots.append(s)
	left.add_child(grid)
	var hint: Label = Label.new()
	hint.text = "STORAGE_HINT"
	hint.add_theme_font_size_override(&"font_size", 17)
	hint.add_theme_color_override(&"font_color", Color(0.62, 0.65, 0.67))
	left.add_child(hint)

	_claim_box = VBoxContainer.new()
	_claim_box.add_theme_constant_override(&"separation", 6)
	_claim_status = Label.new()
	_claim_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_claim_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_claim_status.custom_minimum_size = Vector2(COLS * SLOT + (COLS - 1) * GAP, 0.0)
	_claim_status.add_theme_font_size_override(&"font_size", 19)
	_claim_box.add_child(_claim_status)
	_claim_upkeep = Label.new()
	_claim_upkeep.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_claim_upkeep.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_claim_upkeep.custom_minimum_size = _claim_status.custom_minimum_size
	_claim_upkeep.add_theme_font_size_override(&"font_size", 18)
	_claim_upkeep.add_theme_color_override(&"font_color", Color(0.8, 0.8, 0.78))
	_claim_box.add_child(_claim_upkeep)
	var btns: HBoxContainer = HBoxContainer.new()
	btns.add_theme_constant_override(&"separation", 10)
	_join_btn = _button("CLAIM_JOIN", 230.0)
	_join_btn.pressed.connect(_on_join)
	btns.add_child(_join_btn)
	_reset_btn = _button("CLAIM_RESET", 230.0)
	_reset_btn.pressed.connect(_on_reset)
	btns.add_child(_reset_btn)
	_claim_box.add_child(btns)
	left.add_child(_claim_box)
	cols.add_child(left)

	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 8)
	var rt: Label = Label.new()
	rt.text = "STORAGE_YOURS"
	rt.add_theme_font_size_override(&"font_size", 22)
	rt.add_theme_color_override(&"font_color", Color(0.62, 0.65, 0.67))
	rt.custom_minimum_size = Vector2(0.0, 72.0)
	rt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.add_child(rt)
	var g2: GridContainer = GridContainer.new()
	g2.columns = COLS
	g2.add_theme_constant_override(&"h_separation", GAP)
	g2.add_theme_constant_override(&"v_separation", GAP)
	# Рюкзак, затем быстрая панель последней строкой.
	for i: int in range(Inventory.BACKPACK_START, Inventory.EQUIP_START):
		g2.add_child(_inv_slot(i))
	for i: int in Inventory.HOTBAR_SIZE:
		g2.add_child(_inv_slot(i))
	right.add_child(g2)
	cols.add_child(right)


func _inv_slot(i: int) -> InventorySlot:
	var s: InventorySlot = InventorySlot.new()
	s.setup(_session.inventory, _icons, i, SLOT)
	s.drag_enabled = false
	s.tapped.connect(_on_inv_tapped)
	_inv_slots.append(s)
	return s


func _button(key: String, w: float) -> Button:
	var b: Button = Button.new()
	b.text = key
	b.custom_minimum_size = Vector2(w, 72.0)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _redraw() -> void:
	if not visible:
		return
	for s: StorageSlot in _box_slots:
		s.queue_redraw()
	for s2: InventorySlot in _inv_slots:
		s2.queue_redraw()


func _on_box_tapped(slot: int) -> void:
	if _container >= 0:
		var st: ItemStorage = _bound_storage
		var id: String = st.slot_id(slot) if st != null else ""
		if _session.container_take(_container, slot) > 0:
			Settings.haptic(10)
			if not _session.containers.is_valid(_container):
				close()
		elif st != null and not st.is_empty(slot):
			Events.toast_requested.emit(tr("NOTICE_INVENTORY_FULL") % tr(_session.items.name_key(id)))
		return
	if _session.storage_take(_index, slot) > 0:
		Settings.haptic(10)
	elif not _session.deployables.storages[_index].is_empty(slot) and not _session.claims.is_banner(_index):
		Events.toast_requested.emit(tr("NOTICE_INVENTORY_FULL") % tr(_session.items.name_key(_session.deployables.storages[_index].slot_id(slot))))
	_refresh_claim()


func _on_inv_tapped(slot: int) -> void:
	if _session.inventory.is_empty(slot):
		return
	if _container >= 0:
		if _session.container_put(_container, slot) > 0:
			Settings.haptic(10)
		return
	if _session.storage_put(_index, slot) > 0:
		Settings.haptic(10)
	_refresh_claim()


func _on_join() -> void:
	var d: Deployables = _session.deployables
	if d.is_authorized(_index, _session.player_id):
		_session.claim_leave(_index)
	else:
		_session.claim_authorize(_index)
	_refresh_claim()


func _on_reset() -> void:
	_session.claim_reset(_index)
	_refresh_claim()


func _refresh_claim() -> void:
	if not visible or not _claim_box.visible:
		return
	var d: Deployables = _session.deployables
	var me: bool = d.is_authorized(_index, _session.player_id)
	_claim_status.text = "%s %s" % [tr("CLAIM_AUTHORIZED" if me else "CLAIM_NOT_AUTHORIZED"), tr("CLAIM_MEMBERS") % d.auth[_index].size()]
	_join_btn.text = "CLAIM_LEAVE" if me else "CLAIM_JOIN"
	_reset_btn.disabled = not me
	var per: Dictionary = _session.claims.upkeep_per_hour(_index)
	if per.is_empty():
		_claim_upkeep.text = tr("CLAIM_UPKEEP_NONE")
		return
	var parts: PackedStringArray = PackedStringArray()
	for item: String in per:
		parts.append("%s %s" % [tr(_session.items.name_key(item)), _fmt(float(per[item]))])
	var text: String = tr("CLAIM_UPKEEP") % ", ".join(parts)
	var h: float = _session.claims.hours_left(_index)
	if h < 0.05:
		text += "\n" + tr("CLAIM_UNPAID")
	else:
		text += "\n" + tr("CLAIM_HOURS") % _fmt(h)
	_claim_upkeep.text = text


static func _fmt(v: float) -> String:
	return str(int(round(v))) if v >= 10.0 else String.num(v, 1)
