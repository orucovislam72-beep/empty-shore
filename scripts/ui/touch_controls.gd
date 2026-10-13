class_name TouchControls
extends Control
## Сенсорное управление: левый стик, правая половина — обзор свайпом, кнопки действий.
## Один маршрутизатор мультитача: каждое касание закрепляется за кнопкой, стиком или обзором
## до отпускания пальца. Раскладка пересчитывается при смене размера, настроек и режима для левшей.

const BUTTONS: Array[Dictionary] = [
	{"id": "attack", "action": &"attack", "label": "HUD_ATTACK", "r": 72.0, "pos": Vector2(0.0, 0.0)},
	{"id": "aim", "action": &"aim", "label": "HUD_AIM", "r": 46.0, "pos": Vector2(-10.0, -168.0)},
	{"id": "jump", "action": &"jump", "label": "HUD_JUMP", "r": 50.0, "pos": Vector2(-178.0, 30.0)},
	{"id": "crouch", "action": &"crouch", "label": "HUD_CROUCH", "r": 44.0, "pos": Vector2(-310.0, 44.0), "toggle": true},
	{"id": "reload", "action": &"reload", "label": "HUD_RELOAD", "r": 42.0, "pos": Vector2(-150.0, -128.0)},
	{"id": "interact", "action": &"interact", "label": "HUD_INTERACT", "r": 50.0, "pos": Vector2(-290.0, -110.0), "context": true},
	{"id": "inventory", "action": &"inventory", "label": "HUD_INVENTORY", "r": 40.0, "top": Vector2(-150.0, 0.0)},
	{"id": "build", "action": &"build", "label": "HUD_BUILD", "r": 40.0, "top": Vector2(-250.0, 0.0)},
]

var _stick: TouchStick
var _buttons: Array[TouchButton] = []
var _look_finger: int = -1
var _owner_by_finger: Dictionary = {}
var _safe_margin: Vector2 = Vector2(24.0, 24.0)
var _stick_zone: Rect2 = Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick = TouchStick.new()
	_stick.name = "Stick"
	add_child(_stick)
	for spec: Dictionary in BUTTONS:
		var b: TouchButton = TouchButton.new()
		b.name = String(spec["id"]).capitalize()
		b.setup(spec["action"], spec["label"], spec.get("toggle", false))
		if spec.get("context", false):
			b.visible = false
		add_child(b)
		_buttons.append(b)
	resized.connect(_layout)
	Events.settings_changed.connect(_layout)
	Events.interact_target_changed.connect(_on_interact_target)
	_layout()


func _on_interact_target(label: String) -> void:
	for b: TouchButton in _buttons:
		if b.action == &"interact":
			b.visible = not label.is_empty()


func _canvas_scale() -> float:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var win: Vector2i = DisplayServer.window_get_size()
	if vis.y <= 0.0 or win.y <= 0:
		return 1.0
	return float(win.y) / vis.y


func _compute_safe_margin(scale_px: float) -> Vector2:
	var win: Vector2i = DisplayServer.window_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var base: float = 24.0
	if win.x <= 0 or safe.size.x <= 0:
		return Vector2(base, base)
	var left: float = float(safe.position.x)
	var right: float = float(win.x - safe.end.x)
	var top: float = float(safe.position.y)
	var bottom: float = float(win.y - safe.end.y)
	var mx: float = maxf(maxf(left, right), 0.0) / scale_px
	var my: float = maxf(maxf(top, bottom), 0.0) / scale_px
	return Vector2(base + mx, base + my)


func _layout() -> void:
	if _stick == null:
		return
	var s: GameSettings = Settings.data
	modulate.a = s.hud_opacity
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	var cs: float = _canvas_scale()
	_safe_margin = _compute_safe_margin(cs)
	var min_r: float = UiMetrics.min_touch_units(DisplayServer.screen_get_dpi(), cs) * 0.5
	var k: float = s.hud_scale
	var mirror: bool = s.left_handed
	var mx: float = _safe_margin.x
	var my: float = _safe_margin.y

	_stick.radius = maxf(110.0 * k, min_r * 2.0)
	_stick.position = Vector2.ZERO
	_stick.size = size
	var stick_c: Vector2 = Vector2(mx + _stick.radius + 30.0 * k, h - my - _stick.radius - 20.0 * k)
	_stick_zone = Rect2(0.0, h * 0.25, w * 0.45, h * 0.75)
	if mirror:
		stick_c.x = w - stick_c.x
		_stick_zone.position.x = w - _stick_zone.size.x
	_stick.set_idle_center(stick_c)

	var anchor: Vector2 = Vector2(w - mx - 100.0 * k, h - my - 100.0 * k)
	var top_anchor: Vector2 = Vector2(w - mx - 140.0 * k, my + 50.0 * k)
	for i: int in _buttons.size():
		var spec: Dictionary = BUTTONS[i]
		var b: TouchButton = _buttons[i]
		var r: float = maxf(float(spec["r"]) * k, min_r)
		b.set_radius(r)
		var c: Vector2
		if spec.has("pos"):
			c = anchor + (spec["pos"] as Vector2) * k
		else:
			c = top_anchor + (spec["top"] as Vector2) * k
		if mirror:
			c.x = w - c.x
		b.position = c - Vector2(r, r)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_on_touch_down(t.index, t.position)
		else:
			_on_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		_on_drag(d.index, d.position, d.relative)


## Позиции касаний приходят в координатах окна; переводим в координаты холста.
func _to_canvas(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p


func _on_touch_down(index: int, window_pos: Vector2) -> void:
	var p: Vector2 = _to_canvas(window_pos)
	for i: int in range(_buttons.size() - 1, -1, -1):
		var b: TouchButton = _buttons[i]
		if b.hit(p):
			_owner_by_finger[index] = b
			b.finger_down(index)
			get_viewport().set_input_as_handled()
			return
	if not _stick.is_active() and _stick_zone.has_point(p):
		_owner_by_finger[index] = _stick
		_stick.finger_down(index, p)
		get_viewport().set_input_as_handled()
		return
	var look_side_right: bool = not Settings.data.left_handed
	var on_look_side: bool = (p.x >= size.x * 0.5) if look_side_right else (p.x < size.x * 0.5)
	if _look_finger == -1 and on_look_side:
		_look_finger = index
		_owner_by_finger[index] = self
		get_viewport().set_input_as_handled()


func _on_drag(index: int, window_pos: Vector2, relative: Vector2) -> void:
	var owner_node: Variant = _owner_by_finger.get(index)
	if owner_node == null:
		return
	if owner_node == _stick:
		_stick.finger_move(index, _to_canvas(window_pos))
	elif owner_node == self and index == _look_finger:
		Events.look_input.emit(relative)
	get_viewport().set_input_as_handled()


func _on_touch_up(index: int) -> void:
	var owner_node: Variant = _owner_by_finger.get(index)
	if owner_node == null:
		return
	_owner_by_finger.erase(index)
	if owner_node == _stick:
		_stick.finger_up(index)
	elif owner_node == self:
		_look_finger = -1
	elif owner_node is TouchButton:
		(owner_node as TouchButton).finger_up(index)
	get_viewport().set_input_as_handled()


## Отпустить всё (пауза, сворачивание приложения), чтобы действия не «залипали».
func release_all() -> void:
	_owner_by_finger.clear()
	_look_finger = -1
	_stick.release_all()
	for b: TouchButton in _buttons:
		b.release_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if _stick != null:
			release_all()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and _stick != null:
		release_all()
