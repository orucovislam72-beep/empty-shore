class_name PauseMenu
extends CanvasLayer
## Меню паузы: продолжить, настройки, выход в главное меню. Ставит дерево сцены на паузу.

signal resumed
signal quit_to_menu_requested

var _panel: Control
var _box: VBoxContainer
var _settings: SettingsMenu


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_panel = ColorRect.new()
	(_panel as ColorRect).color = Color(0.05, 0.06, 0.07, 0.8)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override(&"separation", 18)
	center.add_child(_box)
	var title: Label = Label.new()
	title.text = "PAUSE_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 48)
	_box.add_child(title)
	_button("PAUSE_RESUME").pressed.connect(close)
	_button("MENU_SETTINGS").pressed.connect(_open_settings)
	_button("PAUSE_TO_MENU").pressed.connect(func() -> void: quit_to_menu_requested.emit())
	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	add_child(_settings)


func _button(key: String) -> Button:
	var b: Button = Button.new()
	b.text = key
	b.custom_minimum_size = Vector2(420.0, 80.0)
	_box.add_child(b)
	return b


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_close_settings()
	get_tree().paused = true


func close() -> void:
	if _settings.visible:
		_settings.close()
	visible = false
	get_tree().paused = false
	resumed.emit()


## Кнопка «Назад» на Android: сначала закрывает настройки, потом паузу.
func back() -> void:
	if _settings.visible:
		_settings.close()
	else:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		back()
		get_viewport().set_input_as_handled()


func _open_settings() -> void:
	_settings.visible = true
	_panel.visible = false


func _close_settings() -> void:
	_settings.visible = false
	_panel.visible = true
