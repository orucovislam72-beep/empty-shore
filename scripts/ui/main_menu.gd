extends Control
## Главное меню: «Продолжить» (если есть сохранение), «Новая игра», «Настройки», «Выход».
## Пишет в лог время до показа меню.

const GAME_SCENE: String = "res://scenes/main/game.tscn"

var _menu_box: VBoxContainer
var _confirm_box: VBoxContainer
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

	var has_save: bool = SaveGame.has_slot(SaveGame.MAIN_SLOT)
	var first: Button
	if has_save:
		first = _menu_button("MENU_CONTINUE")
		first.pressed.connect(_on_continue)
		_menu_button("MENU_NEW_GAME").pressed.connect(_ask_new_game)
	else:
		first = _menu_button("MENU_NEW_GAME")
		first.pressed.connect(_start_new_game)
	_menu_button("MENU_SETTINGS").pressed.connect(_open_settings)
	if OS.get_name() != "iOS":
		_menu_button("MENU_QUIT").pressed.connect(func() -> void: get_tree().quit())
	first.grab_focus.call_deferred()

	# Подтверждение новой игры поверх существующего сохранения.
	_confirm_box = VBoxContainer.new()
	_confirm_box.add_theme_constant_override(&"separation", 18)
	_confirm_box.visible = false
	center.add_child(_confirm_box)
	var q: Label = Label.new()
	q.text = "MENU_NEW_GAME_CONFIRM"
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(560.0, 0.0)
	_confirm_box.add_child(q)
	var yes: Button = Button.new()
	yes.text = "MENU_NEW_GAME_YES"
	yes.custom_minimum_size = Vector2(420.0, 80.0)
	yes.pressed.connect(_start_new_game)
	_confirm_box.add_child(yes)
	var no: Button = Button.new()
	no.text = "UI_BACK"
	no.custom_minimum_size = Vector2(420.0, 80.0)
	no.pressed.connect(_cancel_new_game)
	_confirm_box.add_child(no)

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


func _on_continue() -> void:
	Settings.haptic(20)
	SaveGame.continue_requested = true
	get_tree().change_scene_to_file(GAME_SCENE)


func _ask_new_game() -> void:
	_menu_box.visible = false
	_confirm_box.visible = true


func _cancel_new_game() -> void:
	_confirm_box.visible = false
	_menu_box.visible = true


func _start_new_game() -> void:
	Settings.haptic(20)
	SaveGame.delete_slot(SaveGame.MAIN_SLOT)
	SaveGame.continue_requested = false
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
		elif _confirm_box != null and _confirm_box.visible:
			_cancel_new_game()
		else:
			get_tree().quit()
