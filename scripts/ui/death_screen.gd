class_name DeathScreen
extends CanvasLayer
## Экран гибели: причина, где остались вещи, выбор точки возрождения — свои спальники и кровати
## (если не на перезарядке) и «На побережье». Крупные кнопки (≥ 80 px по высоте).

## point — индекс спальника/кровати (объекта) или -1 — побережье.
signal respawn_requested(point: int)

const MAX_POINTS: int = 4
const CAUSES: Dictionary = {
	"hunger": "DEATH_CAUSE_HUNGER", "thirst": "DEATH_CAUSE_THIRST", "fall": "DEATH_CAUSE_FALL",
	"wolf": "DEATH_CAUSE_WOLF", "bear": "DEATH_CAUSE_BEAR", "deer": "DEATH_CAUSE_DEER",
}

var _cause: Label
var _note: Label
var _point_buttons: Array[Button] = []
var _point_index: PackedInt32Array = PackedInt32Array()


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
	box.add_theme_constant_override(&"separation", 14)
	center.add_child(box)
	var title: Label = Label.new()
	title.text = "DEATH_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 52)
	box.add_child(title)
	_cause = Label.new()
	_cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cause.add_theme_color_override(&"font_color", Color(0.75, 0.72, 0.7))
	box.add_child(_cause)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_color_override(&"font_color", Color(0.6, 0.58, 0.56))
	_note.add_theme_font_size_override(&"font_size", 18)
	box.add_child(_note)
	var choose: Label = Label.new()
	choose.text = "DEATH_CHOOSE"
	choose.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(choose)
	_point_index.resize(MAX_POINTS)
	for i: int in MAX_POINTS:
		var b: Button = Button.new()
		b.custom_minimum_size = Vector2(460.0, 72.0)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.focus_mode = Control.FOCUS_NONE
		b.visible = false
		b.pressed.connect(_on_point.bind(i))
		box.add_child(b)
		_point_buttons.append(b)
	var coast: Button = Button.new()
	coast.name = "Coast"
	coast.text = "DEATH_RESPAWN_COAST"
	coast.custom_minimum_size = Vector2(460.0, 80.0)
	coast.focus_mode = Control.FOCUS_NONE
	coast.pressed.connect(_on_coast)
	box.add_child(coast)


## cause: hunger | thirst | fall | wolf | bear | deer | другое. points — из SurvivalSession.respawn_points()
## (у каждой точки ключ name — ключ перевода названия).
func show_death(cause: String, had_items: bool, points: Array[Dictionary] = []) -> void:
	_cause.text = CAUSES.get(cause, "DEATH_CAUSE_OTHER")
	_note.text = "DEATH_ITEMS_IN_BAG" if had_items else "DEATH_NO_ITEMS"
	refresh_points(points)
	visible = true


## Обновить кнопки спальников (перезарядка идёт и пока открыт экран).
func refresh_points(points: Array[Dictionary]) -> void:
	for i: int in MAX_POINTS:
		var b: Button = _point_buttons[i]
		if i >= points.size():
			b.visible = false
			continue
		var p: Dictionary = points[i]
		var name_key: String = String(p.get("name", ""))
		var cd: float = float(p.get("cooldown", 0.0))
		_point_index[i] = int(p.get("index", -1))
		b.visible = true
		b.disabled = cd > 0.0
		if cd > 0.0:
			b.text = tr("DEATH_RESPAWN_WAIT") % [tr(name_key), int(ceil(cd))]
		else:
			b.text = tr("DEATH_RESPAWN_AT") % [tr(name_key), int(round(float(p.get("distance", 0.0))))]


func _on_point(i: int) -> void:
	visible = false
	respawn_requested.emit(_point_index[i])


func _on_coast() -> void:
	visible = false
	respawn_requested.emit(-1)
