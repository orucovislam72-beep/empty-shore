class_name BuildPanel
extends CanvasLayer
## Панель режима строительства (сверху по центру, под кнопками «Вещи»/«Стройка»):
## выбор детали и материала крупными кнопками, действия с деталью под прицелом
## (улучшить, починить, разобрать, замок) и строка подсказки (стоимость, причина отказа).
## «Поставить» и «Повернуть» — крупные круглые кнопки справа (основная кнопка и бывшая «Перезар.»).
## Панель логики не содержит: выбор и нажатия уходят сигналами в game.gd.

signal piece_selected(type: String)
signal material_selected(mat: int)
## action: "upgrade" | "repair" | "demolish" | "lock"
signal action_pressed(action: String)

const BTN_H: float = 64.0
const PIECE_W: float = 100.0
const ACTION_W: float = 104.0

var panel: PanelContainer
var _piece_btns: Dictionary = {}
var _mat_btns: Array[Button] = []
var _action_btns: Dictionary = {}
var _info: Label


func _ready() -> void:
	layer = 12
	visible = false


func setup(defs: BuildingDefs) -> void:
	panel = PanelContainer.new()
	panel.name = "Panel"
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.09, 0.72)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override(&"panel", sb)
	add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	panel.add_child(box)
	var row1: HBoxContainer = HBoxContainer.new()
	row1.add_theme_constant_override(&"separation", 6)
	for type: String in defs.piece_order:
		var b: Button = _button(defs.name_key(type), PIECE_W)
		b.toggle_mode = true
		b.pressed.connect(_on_piece.bind(type))
		row1.add_child(b)
		_piece_btns[type] = b
	box.add_child(row1)
	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override(&"separation", 6)
	for m: int in defs.material_order.size():
		var mb: Button = _button(defs.material_name(m), PIECE_W)
		mb.toggle_mode = true
		mb.pressed.connect(_on_material.bind(m))
		row2.add_child(mb)
		_mat_btns.append(mb)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(10.0, 0.0)
	row2.add_child(gap)
	for a: String in ["upgrade", "repair", "demolish", "lock"]:
		var ab: Button = _button("BUILD_%s" % a.to_upper(), ACTION_W)
		ab.pressed.connect(func() -> void: action_pressed.emit(a))
		row2.add_child(ab)
		_action_btns[a] = ab
	box.add_child(row2)
	_info = Label.new()
	_info.name = "Info"
	_info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override(&"font_size", 18)
	_info.add_theme_color_override(&"font_color", Color(0.88, 0.88, 0.86))
	box.add_child(_info)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _button(key: String, w: float) -> Button:
	var b: Button = Button.new()
	b.text = key
	b.custom_minimum_size = Vector2(w, BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	return b


func _layout() -> void:
	if panel == null:
		return
	var vp: Vector2 = panel.get_viewport_rect().size
	panel.reset_size()
	panel.position = Vector2(roundf((vp.x - panel.size.x) * 0.5), 124.0)


func _on_piece(type: String) -> void:
	Settings.haptic(10)
	piece_selected.emit(type)


func _on_material(m: int) -> void:
	Settings.haptic(10)
	material_selected.emit(m)


## Отметить выбранные деталь и материал; недоступные материалы детали — выключены.
func show_selection(type: String, mat: int, defs: BuildingDefs) -> void:
	for t: String in _piece_btns:
		(_piece_btns[t] as Button).set_pressed_no_signal(t == type)
	for m: int in _mat_btns.size():
		_mat_btns[m].set_pressed_no_signal(m == mat)
		_mat_btns[m].disabled = not defs.allows(type, m)


## Какие действия с целью доступны (кнопки остаются на месте, чтобы палец не промахивался).
func set_actions(upgrade: bool, repair: bool, demolish: bool, lock_label: String) -> void:
	(_action_btns["upgrade"] as Button).disabled = not upgrade
	(_action_btns["repair"] as Button).disabled = not repair
	(_action_btns["demolish"] as Button).disabled = not demolish
	var lb: Button = _action_btns["lock"]
	lb.disabled = lock_label.is_empty()
	lb.text = lock_label if not lock_label.is_empty() else "BUILD_LOCK"


func set_info(text: String) -> void:
	if _info.text != text:
		_info.text = text


func open() -> void:
	visible = true
	_layout()


func close() -> void:
	visible = false
