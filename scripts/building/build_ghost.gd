class_name BuildGhost
extends MeshInstance3D
## «Призрак» детали в режиме строительства: полупрозрачная модель на месте, которое подсказала
## BuildingGrid.suggest(). Зелёный — можно ставить, красный — нельзя (причина — в подсказке HUD).
## Только присваивания, без выделения памяти при каждом обновлении.

const OK_COLOR: Color = Color(0.45, 0.85, 0.5, 0.38)
const BAD_COLOR: Color = Color(0.95, 0.38, 0.32, 0.38)

var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D
var _type: String = ""


func _ready() -> void:
	_ok_mat = _make_mat(OK_COLOR)
	_bad_mat = _make_mat(BAD_COLOR)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


static func _make_mat(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m


## Показать призрак: модель типа, мировое преобразование и годность места.
func show_at(type: String, model: Mesh, xf: Transform3D, ok: bool) -> void:
	if _type != type:
		_type = type
		mesh = model
	global_transform = xf
	material_override = _ok_mat if ok else _bad_mat
	visible = true


func hide_ghost() -> void:
	visible = false
