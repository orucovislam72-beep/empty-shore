class_name DeathScreen
extends CanvasLayer
## Экран гибели: причина и кнопка «Возродиться». Мешок с вещами и спальник — этап 3.

signal respawn_requested

var _cause: Label


func _ready() -> void:
	layer = 45
	visible = false
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.09, 0.04, 0.04, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 18)
	center.add_child(box)
	var title: Label = Label.new()
	title.text = "DEATH_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 56)
	box.add_child(title)
	_cause = Label.new()
	_cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cause.add_theme_color_override(&"font_color", Color(0.75, 0.72, 0.7))
	box.add_child(_cause)
	var note: Label = Label.new()
	note.text = "DEATH_ITEMS_LOST"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override(&"font_color", Color(0.6, 0.58, 0.56))
	note.add_theme_font_size_override(&"font_size", 18)
	box.add_child(note)
	var btn: Button = Button.new()
	btn.text = "DEATH_RESPAWN"
	btn.custom_minimum_size = Vector2(420.0, 80.0)
	btn.pressed.connect(_on_respawn)
	box.add_child(btn)


## cause: hunger | thirst | fall | другое.
func show_death(cause: String) -> void:
	match cause:
		"hunger":
			_cause.text = "DEATH_CAUSE_HUNGER"
		"thirst":
			_cause.text = "DEATH_CAUSE_THIRST"
		"fall":
			_cause.text = "DEATH_CAUSE_FALL"
		_:
			_cause.text = "DEATH_CAUSE_OTHER"
	visible = true


func _on_respawn() -> void:
	visible = false
	respawn_requested.emit()
