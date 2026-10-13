extends Control
## Главное меню: «Играть», «Настройки», «Выход». Пишет в лог время до показа меню.

const GAME_SCENE: String = "res://scenes/main/game.tscn"

var _menu_box: VBoxContainer
var _settings: SettingsMenu


func _ready() -> void:
	print("[boot] main menu ready: %d ms since engine start" % Time.get_ticks_msec())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override(&"separation", 18)
	center.add_child(_menu_box)

	var title: Label = Label.new()
	title.text = "GAME_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 64)
	_menu_box.add_child(title)
	var subtitle: Label = Label.new()
	subtitle.text = "MENU_SUBTITLE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override(&"font_color", Color(0.62, 0.65, 0.67))
	_menu_box.add_child(subtitle)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 24.0)
	_menu_box.add_child(spacer)

	var play: Button = _menu_button("MENU_PLAY")
	play.pressed.connect(_on_play)
	_menu_button("MENU_SETTINGS").pressed.connect(_open_settings)
	if OS.get_name() != "iOS":
		_menu_button("MENU_QUIT").pressed.connect(func() -> void: get_tree().quit())
	play.grab_focus.call_deferred()

	var version: Label = Label.new()
	version.text = TranslationServer.translate("MENU_VERSION") % String(ProjectSettings.get_setting("application/config/version", "0"))
	version.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	version.add_theme_color_override(&"font_color", Color(0.45, 0.48, 0.5))
	version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version.position = Vector2(24.0, -48.0)
	add_child(version)

	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	add_child(_settings)


func _menu_button(key: String) -> Button:
	var b: Button = Button.new()
	b.text = key
	b.custom_minimum_size = Vector2(420.0, 80.0)
	_menu_box.add_child(b)
	return b


func _on_play() -> void:
	Settings.haptic(20)
	get_tree().change_scene_to_file(GAME_SCENE)


func _open_settings() -> void:
	_settings.visible = true
	_menu_box.visible = false


func _close_settings() -> void:
	_settings.visible = false
	_menu_box.visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _settings != null and _settings.visible:
			_settings.close()
		else:
			get_tree().quit()
