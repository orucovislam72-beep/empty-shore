class_name SettingsMenu
extends PanelContainer
## Экран настроек (используется в главном меню и в паузе). Собирается из кода по списку полей.
## Изменения применяются сразу (Settings.apply), сохраняются в файл при закрытии.

signal closed

const ROW_HEIGHT: float = 64.0

var _preset_option: OptionButton
var _widgets: Dictionary = {}
var _syncing: bool = false
var _preset_ids: PackedStringArray = PackedStringArray()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 16)
	margin.add_child(outer)

	var header: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "SETTINGS_TITLE"
	title.add_theme_font_size_override(&"font_size", 38)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back: Button = Button.new()
	back.text = "UI_BACK"
	back.custom_minimum_size = Vector2(200.0, ROW_HEIGHT)
	back.pressed.connect(close)
	header.add_child(back)
	outer.add_child(header)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 10)
	scroll.add_child(list)

	_section(list, "SETTINGS_SECTION_GRAPHICS")
	_preset_option = OptionButton.new()
	for p: Variant in Settings.data.preset_names():
		_preset_ids.append(String(p))
		_preset_option.add_item("PRESET_" + String(p).to_upper())
	_preset_ids.append(GameSettings.PRESET_CUSTOM)
	_preset_option.add_item("PRESET_CUSTOM")
	_preset_option.item_selected.connect(_on_preset_selected)
	_row(list, "SETTINGS_PRESET", _preset_option)
	_slider(list, "render_scale", "SETTINGS_RENDER_SCALE", GameSettings.RENDER_SCALE_MIN, GameSettings.RENDER_SCALE_MAX, 0.05, true)
	var fps: OptionButton = OptionButton.new()
	fps.add_item("SETTINGS_FPS_30", 30)
	fps.add_item("SETTINGS_FPS_60", 60)
	fps.item_selected.connect(func(idx: int) -> void: _set_value("fps_limit", fps.get_item_id(idx), false))
	_widgets["fps_limit"] = fps
	_row(list, "SETTINGS_FPS", fps)
	_slider(list, "draw_distance", "SETTINGS_DRAW_DISTANCE", GameSettings.DRAW_DISTANCE_MIN, GameSettings.DRAW_DISTANCE_MAX, 10.0, true)
	_check(list, "shadows", "SETTINGS_SHADOWS", true)
	_slider(list, "grass_density", "SETTINGS_GRASS", 0.0, 1.0, 0.05, true)
	_check(list, "battery_saver", "SETTINGS_BATTERY_SAVER", false)
	_check(list, "auto_quality", "SETTINGS_AUTO_QUALITY", false)

	_section(list, "SETTINGS_SECTION_CONTROLS")
	_slider(list, "look_sensitivity", "SETTINGS_LOOK_SENS", 0.1, 3.0, 0.05, false)
	_slider(list, "aim_sensitivity", "SETTINGS_AIM_SENS", 0.1, 3.0, 0.05, false)
	_check(list, "invert_y", "SETTINGS_INVERT_Y", false)
	var touch: OptionButton = OptionButton.new()
	touch.add_item("SETTINGS_TOUCH_AUTO", GameSettings.TOUCH_AUTO)
	touch.add_item("SETTINGS_TOUCH_ON", GameSettings.TOUCH_ON)
	touch.add_item("SETTINGS_TOUCH_OFF", GameSettings.TOUCH_OFF)
	touch.item_selected.connect(func(idx: int) -> void: _set_value("touch_controls", touch.get_item_id(idx), false))
	_widgets["touch_controls"] = touch
	_row(list, "SETTINGS_TOUCH", touch)
	_check(list, "left_handed", "SETTINGS_LEFT_HANDED", false)
	_slider(list, "hud_scale", "SETTINGS_HUD_SCALE", 0.75, 1.5, 0.05, false)
	_slider(list, "hud_opacity", "SETTINGS_HUD_OPACITY", 0.2, 1.0, 0.05, false)
	_check(list, "vibration", "SETTINGS_VIBRATION", false)

	_section(list, "SETTINGS_SECTION_OTHER")
	_check(list, "show_debug", "SETTINGS_DEBUG", false)

	Events.settings_changed.connect(_sync_from_settings)
	_sync_from_settings()


func close() -> void:
	Settings.save()
	closed.emit()


func _section(list: VBoxContainer, key: String) -> void:
	var l: Label = Label.new()
	l.text = key
	l.add_theme_font_size_override(&"font_size", 30)
	l.add_theme_color_override(&"font_color", Color(0.85, 0.63, 0.25))
	list.add_child(l)


func _row(list: VBoxContainer, key: String, control: Control) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	var l: Label = Label.new()
	l.text = key
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_stretch_ratio = 1.2
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	row.add_child(control)
	list.add_child(row)


func _slider(list: VBoxContainer, field: String, key: String, min_v: float, max_v: float, step: float, graphics: bool) -> void:
	var box: HBoxContainer = HBoxContainer.new()
	var slider: HSlider = HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0.0, 48.0)
	var value_label: Label = Label.new()
	value_label.custom_minimum_size = Vector2(90.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(slider)
	box.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = _format_value(field, v)
		_set_value(field, v, graphics))
	_widgets[field] = slider
	_widgets[field + "__label"] = value_label
	_row(list, key, box)


func _check(list: VBoxContainer, field: String, key: String, graphics: bool) -> void:
	var cb: CheckButton = CheckButton.new()
	cb.toggled.connect(func(on: bool) -> void: _set_value(field, on, graphics))
	_widgets[field] = cb
	_row(list, key, cb)


static func _format_value(field: String, v: float) -> String:
	if field == "draw_distance":
		return TranslationServer.translate("UNIT_METERS") % int(v)
	if field == "render_scale" or field == "grass_density" or field == "hud_opacity" or field == "hud_scale":
		return "%d%%" % int(round(v * 100.0))
	return "%.2f" % v


func _set_value(field: String, v: Variant, graphics: bool) -> void:
	if _syncing:
		return
	Settings.data.set(field, v)
	if graphics:
		Settings.data.mark_custom()
	Settings.apply()


func _on_preset_selected(idx: int) -> void:
	if _syncing:
		return
	var id: String = _preset_ids[idx]
	if id != GameSettings.PRESET_CUSTOM:
		Settings.data.apply_preset(id)
	else:
		Settings.data.mark_custom()
	Settings.apply()


func _sync_from_settings() -> void:
	_syncing = true
	var s: GameSettings = Settings.data
	var idx: int = _preset_ids.find(s.quality_preset)
	_preset_option.select(idx if idx >= 0 else _preset_ids.size() - 1)
	for field: String in _widgets.keys():
		if field.ends_with("__label"):
			continue
		var w: Control = _widgets[field]
		var v: Variant = s.get(field)
		if w is HSlider:
			(w as HSlider).set_value_no_signal(float(v))
			(_widgets[field + "__label"] as Label).text = _format_value(field, float(v))
		elif w is CheckButton:
			(w as CheckButton).set_pressed_no_signal(bool(v))
		elif w is OptionButton:
			var ob: OptionButton = w
			for i: int in ob.item_count:
				if ob.get_item_id(i) == int(v):
					ob.select(i)
	_syncing = false
