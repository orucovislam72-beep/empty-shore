class_name BuildingDefs
extends RefCounted
## Описание деталей построек и материалов из data/balance/building.json (стоимость, прочность,
## износ, обслуживание, размеры сетки). Только чтение данных, без состояния мира.

const DEFAULT_PATH: String = "res://data/balance/building.json"

const SLOT_CELL: String = "cell"
const SLOT_EDGE: String = "edge"
const SLOT_DOOR: String = "door"
const SLOT_STAIRS: String = "stairs"

var grid: float = 3.0
var wall_h: float = 3.0
var step: float = 0.25
var wall_t: float = 0.2
var floor_t: float = 0.2
var doorway_w: float = 1.2
var doorway_h: float = 2.2
var roof_rise: float = 1.5
var found_min_above: float = 0.15
var found_max_above: float = 2.5
var found_max_buried: float = 0.3
var found_below: float = 0.4
var aim_cell: float = 4.0
var aim_edge: float = 2.0
var build_range: float = 8.0
var target_reach: float = 4.5
var tick_s: float = 10.0
var repair_fraction: float = 0.5
var demolish_refund: float = 0.5
## Высота этажа в шагах сетки высот (3 м / 0,25 м = 12).
var level_steps: int = 12

var material_order: PackedStringArray = PackedStringArray(["wood", "stone", "metal"])
var piece_order: PackedStringArray = PackedStringArray()
var _pieces: Dictionary = {}
var _materials: Dictionary = {}


static func load_default() -> BuildingDefs:
	var d: BuildingDefs = BuildingDefs.new()
	d.configure(JsonData.load_dict(DEFAULT_PATH))
	return d


func configure(cfg: Dictionary) -> void:
	grid = JsonData.get_float(cfg, "grid_m", 3.0)
	wall_h = JsonData.get_float(cfg, "wall_h_m", 3.0)
	step = maxf(JsonData.get_float(cfg, "height_step_m", 0.25), 0.05)
	wall_t = JsonData.get_float(cfg, "wall_thickness_m", 0.2)
	floor_t = JsonData.get_float(cfg, "floor_thickness_m", 0.2)
	doorway_w = JsonData.get_float(cfg, "doorway_w_m", 1.2)
	doorway_h = JsonData.get_float(cfg, "doorway_h_m", 2.2)
	roof_rise = JsonData.get_float(cfg, "roof_rise_m", 1.5)
	var f: Dictionary = cfg.get("foundation", {})
	found_min_above = JsonData.get_float(f, "min_above_ground_m", 0.15)
	found_max_above = JsonData.get_float(f, "max_above_ground_m", 2.5)
	found_max_buried = JsonData.get_float(f, "max_buried_m", 0.3)
	found_below = JsonData.get_float(f, "below_ground_m", 0.4)
	aim_cell = JsonData.get_float(cfg, "aim_cell_m", 4.0)
	aim_edge = JsonData.get_float(cfg, "aim_edge_m", 2.0)
	build_range = JsonData.get_float(cfg, "build_range_m", 8.0)
	target_reach = JsonData.get_float(cfg, "target_reach_m", 4.5)
	tick_s = maxf(JsonData.get_float(cfg, "tick_s", 10.0), 0.1)
	repair_fraction = JsonData.get_float(cfg, "repair_cost_fraction", 0.5)
	demolish_refund = JsonData.get_float(cfg, "demolish_refund", 0.5)
	level_steps = maxi(int(round(wall_h / step)), 1)
	_pieces = cfg.get("pieces", {})
	_materials = cfg.get("materials", {})
	var mo: Variant = cfg.get("material_order", [])
	if typeof(mo) == TYPE_ARRAY and not (mo as Array).is_empty():
		material_order = PackedStringArray(mo)
	var po: Variant = cfg.get("piece_order", [])
	piece_order = PackedStringArray(po) if typeof(po) == TYPE_ARRAY else PackedStringArray()
	if piece_order.is_empty():
		piece_order = PackedStringArray(_pieces.keys())


func has_piece(type: String) -> bool:
	return _pieces.has(type)


func piece_def(type: String) -> Dictionary:
	return _pieces.get(type, {})


func slot_of(type: String) -> String:
	return String(piece_def(type).get("slot", ""))


func name_key(type: String) -> String:
	return String(piece_def(type).get("name", ""))


func material_name(mat: int) -> String:
	if mat < 0 or mat >= material_order.size():
		return ""
	return String((_materials.get(material_order[mat], {}) as Dictionary).get("name", ""))


func material_index(mat_id: String) -> int:
	return material_order.find(mat_id)


## Разрешён ли материал mat (индекс в material_order) для детали.
func allows(type: String, mat: int) -> bool:
	if mat < 0 or mat >= material_order.size():
		return false
	return (piece_def(type).get("materials", {}) as Dictionary).has(material_order[mat])


## Следующий разрешённый материал выше mat или -1.
func next_material(type: String, mat: int) -> int:
	for m: int in range(mat + 1, material_order.size()):
		if allows(type, m):
			return m
	return -1


## Первый разрешённый материал не ниже mat (для выбора в панели) или -1.
func first_allowed_from(type: String, mat: int) -> int:
	for m: int in range(maxi(mat, 0), material_order.size()):
		if allows(type, m):
			return m
	for m: int in range(0, material_order.size()):
		if allows(type, m):
			return m
	return -1


func _mat_def(type: String, mat: int) -> Dictionary:
	if not allows(type, mat):
		return {}
	return (piece_def(type)["materials"] as Dictionary)[material_order[mat]]


## Стоимость {предмет: количество}.
func cost(type: String, mat: int) -> Dictionary:
	return _mat_def(type, mat).get("cost", {})


func max_hp(type: String, mat: int) -> float:
	return JsonData.get_float(_mat_def(type, mat), "hp", 100.0)


func decay_full_s(mat: int) -> float:
	if mat < 0 or mat >= material_order.size():
		return 3600.0
	return maxf(JsonData.get_float(_materials.get(material_order[mat], {}), "decay_full_s", 3600.0), 1.0)


func upkeep_fraction(mat: int) -> float:
	if mat < 0 or mat >= material_order.size():
		return 0.0
	return JsonData.get_float(_materials.get(material_order[mat], {}), "upkeep_fraction_per_hour", 0.05)


func height_of(hy: int) -> float:
	return float(hy) * step
