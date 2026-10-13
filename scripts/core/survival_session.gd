class_name SurvivalSession
extends RefCounted
## Игровая сессия выживания (этап 1): связывает инвентарь, крафт, показатели, время суток,
## ресурсные узлы и размещённые объекты. Чистая логика без сцен: сцена передаёт сюда
## «намерения» игрока (ударить, съесть, поставить, попить, сделать) и рисует результат.
## На этапе 4 этот же класс будет работать на сервере.

## Короткое сообщение игроку: key — ключ перевода (с %s для названия предмета), item_id — предмет или "".
signal notice(key: String, item_id: String)
signal gathered(item_id: String, amount: int)
signal active_slot_changed(slot: int)
signal player_died(cause: String)
signal respawned(position: Vector3)

const GAME_CFG_PATH: String = "res://data/balance/game.json"

enum Primary { NONE, SWING, EAT, PLACE }
enum Interact { NONE, DRINK, REFUEL }

var items: ItemDB
var inventory: Inventory
var crafting: Crafting
var stats: SurvivalStats
var clock: DayNightCycle
var resources: ResourceField
var deployables: Deployables
var terrain: TerrainMath
var water_level: float = -4.0

var active_slot: int = 0
var play_time: float = 0.0
var player_position: Vector3 = Vector3.ZERO
var player_yaw: float = 0.0
var player_pitch: float = 0.0
var spawn_point: Vector3 = Vector3.ZERO

var _cfg: Dictionary = {}
var _swing_cd: float = 0.0
var _drink_cd: float = 0.0
var _stations: PackedStringArray = PackedStringArray()


## Создаёт сессию с данными из data/. field — уже сгенерированные ресурсные узлы.
static func create(p_terrain: TerrainMath, field: ResourceField, p_water_level: float) -> SurvivalSession:
	var s: SurvivalSession = SurvivalSession.new()
	var db: ItemDB = ItemDB.load_default()
	s.setup(db, p_terrain, field, p_water_level, {
		"game": JsonData.load_dict(GAME_CFG_PATH),
		"recipes": JsonData.load_dict(Crafting.DEFAULT_PATH),
		"survival": JsonData.load_dict(SurvivalStats.DEFAULT_PATH),
		"day_night": JsonData.load_dict(DayNightCycle.DEFAULT_PATH),
		"deployables": JsonData.load_dict(Deployables.DEFAULT_PATH),
	})
	return s


func setup(db: ItemDB, p_terrain: TerrainMath, field: ResourceField, p_water_level: float, cfgs: Dictionary) -> void:
	items = db
	terrain = p_terrain
	resources = field
	water_level = p_water_level
	_cfg = cfgs.get("game", {})
	inventory = Inventory.new(db)
	crafting = Crafting.new(db)
	crafting.configure(cfgs.get("recipes", {}))
	stats = SurvivalStats.new()
	stats.configure(cfgs.get("survival", {}))
	clock = DayNightCycle.new()
	clock.configure(cfgs.get("day_night", {}))
	deployables = Deployables.new()
	deployables.configure(cfgs.get("deployables", {}))
	var sp: Variant = _cfg.get("spawn", [0.0, 0.0])
	var sx: float = float(sp[0]) if typeof(sp) == TYPE_ARRAY and (sp as Array).size() >= 2 else 0.0
	var sz: float = float(sp[1]) if typeof(sp) == TYPE_ARRAY and (sp as Array).size() >= 2 else 0.0
	spawn_point = Vector3(sx, terrain.height_at(sx, sz), sz)
	player_position = spawn_point
	stats.died.connect(_on_died)
	# Только методы, не лямбды: лямбда с self создала бы цикл ссылок RefCounted (утечка).
	crafting.crafted.connect(_on_crafted)
	crafting.output_blocked.connect(_on_craft_blocked)


func autosave_interval() -> float:
	return JsonData.get_float(_cfg, "autosave_interval_s", 60.0)


func tick(delta: float) -> void:
	play_time += delta
	_swing_cd = maxf(_swing_cd - delta, 0.0)
	_drink_cd = maxf(_drink_cd - delta, 0.0)
	clock.tick(delta)
	resources.tick(delta)
	deployables.tick(delta)
	crafting.tick(delta, inventory)
	stats.tick(delta)


func set_player_pose(pos: Vector3, yaw: float, pitch: float) -> void:
	player_position = pos
	player_yaw = yaw
	player_pitch = pitch


# --- Активный предмет -------------------------------------------------------

func select_slot(slot: int) -> void:
	var s: int = clampi(slot, 0, Inventory.HOTBAR_SIZE - 1)
	if s == active_slot:
		return
	active_slot = s
	active_slot_changed.emit(active_slot)


func active_item() -> String:
	return inventory.slot_id(active_slot) if not inventory.is_empty(active_slot) else ""


## Что делает основная кнопка с активным предметом.
func primary_kind() -> Primary:
	match items.kind(active_item()):
		ItemDB.KIND_FOOD:
			return Primary.EAT
		ItemDB.KIND_DEPLOYABLE:
			return Primary.PLACE
		_:
			return Primary.SWING


func can_swing() -> bool:
	return _swing_cd <= 0.0 and not stats.is_dead()


## Основное действие. origin/dir — луч взгляда, feet — позиция ног, yaw — поворот игрока.
func primary(origin: Vector3, dir: Vector3, feet: Vector3, yaw: float) -> Primary:
	if not can_swing():
		return Primary.NONE
	match primary_kind():
		Primary.EAT:
			_swing_cd = 0.4
			return Primary.EAT if eat_slot(active_slot) else Primary.NONE
		Primary.PLACE:
			_swing_cd = 0.4
			return Primary.PLACE if place_active(feet, yaw) else Primary.NONE
		_:
			_swing_cd = items.swing_time(active_item())
			gather(resources.find_target(origin, dir))
			return Primary.SWING


## Удар по узлу активным предметом. Возвращает добытое количество.
func gather(target: int) -> int:
	if target < 0:
		return 0
	var tool: String = active_item()
	var item: String = resources.item_of(target)
	var mult: float = items.gather_multiplier(tool, item)
	if mult <= 0.0:
		notice.emit("NOTICE_NEED_PICKAXE" if item == "metal_ore" else "NOTICE_WRONG_TOOL", item)
		return 0
	var amount: int = resources.hit(target, mult)
	if amount <= 0:
		return 0
	var left: int = inventory.add(item, amount)
	if left > 0:
		notice.emit("NOTICE_INVENTORY_FULL", item)
	if amount - left > 0:
		gathered.emit(item, amount - left)
	if items.is_tool(tool) and inventory.wear(active_slot):
		notice.emit("NOTICE_TOOL_BROKE", tool)
	return amount - left


func eat_slot(slot: int) -> bool:
	var id: String = inventory.slot_id(slot)
	if inventory.is_empty(slot) or items.kind(id) != ItemDB.KIND_FOOD:
		return false
	stats.eat(items.food(id))
	inventory.remove_at(slot, 1)
	notice.emit("NOTICE_ATE", id)
	return true


## Точка установки объекта перед игроком, на земле.
func placement_point(feet: Vector3, yaw: float) -> Vector3:
	var fwd: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var p: Vector3 = feet + fwd * deployables.place_distance
	p.y = terrain.height_at(p.x, p.z)
	return p


func place_active(feet: Vector3, yaw: float) -> bool:
	var id: String = active_item()
	var kind: String = items.deploy_type(id)
	if kind.is_empty():
		return false
	var p: Vector3 = placement_point(feet, yaw)
	if p.y < water_level:
		notice.emit("NOTICE_CANT_PLACE_WATER", id)
		return false
	if deployables.place(kind, p, yaw) < 0:
		notice.emit("NOTICE_CANT_PLACE", id)
		return false
	inventory.remove_at(active_slot, 1)
	return true


# --- Взаимодействие (кнопка «Взять» по контексту) ---------------------------

func interact_kind(feet: Vector3, yaw: float) -> Interact:
	var near: int = deployables.nearest(feet)
	if near >= 0 and deployables.is_fueled(deployables.kinds[near]):
		return Interact.REFUEL
	if is_water_near(feet, yaw):
		return Interact.DRINK
	return Interact.NONE


func is_water_near(feet: Vector3, yaw: float) -> bool:
	if feet.y > water_level + 1.6:
		return false
	if terrain.height_at(feet.x, feet.z) < water_level:
		return true
	var fwd: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var p: Vector3 = feet + fwd * 1.5
	return terrain.height_at(p.x, p.z) < water_level


func interact(feet: Vector3, yaw: float) -> Interact:
	match interact_kind(feet, yaw):
		Interact.REFUEL:
			var i: int = deployables.nearest(feet)
			var want: int = mini(deployables.wood_wanted(i), inventory.count_of("wood"))
			if deployables.wood_wanted(i) <= 0:
				notice.emit("NOTICE_FIRE_FULL", "")
				return Interact.NONE
			if want <= 0:
				notice.emit("NOTICE_NEED_ITEM", "wood")
				return Interact.NONE
			inventory.remove("wood", want)
			deployables.add_fuel(i, want)
			return Interact.REFUEL
		Interact.DRINK:
			if _drink_cd > 0.0:
				return Interact.NONE
			_drink_cd = stats.param("drink_cooldown_s", 0.8)
			stats.drink()
			return Interact.DRINK
	return Interact.NONE


# --- Крафт ------------------------------------------------------------------

func stations_at(pos: Vector3) -> PackedStringArray:
	deployables.stations_near(pos, _stations)
	return _stations


func craft(recipe_id: String) -> Crafting.Check:
	return crafting.start(recipe_id, inventory, stations_at(player_position))


# --- Смерть -----------------------------------------------------------------

func _on_crafted(item_id: String, _count: int) -> void:
	notice.emit("NOTICE_CRAFTED", item_id)


func _on_craft_blocked(item_id: String) -> void:
	notice.emit("NOTICE_CRAFT_BLOCKED", item_id)


func _on_died(cause: String) -> void:
	player_died.emit(cause)


func respawn() -> void:
	if not JsonData.get_bool(_cfg, "respawn_keeps_inventory", false):
		inventory.clear_all()
		crafting.from_dict({})
	stats.reset_for_respawn()
	player_position = spawn_point
	respawned.emit(spawn_point)


# --- Сохранение -------------------------------------------------------------

func to_dict() -> Dictionary:
	var p: Vector3 = player_position
	return {
		"world": {"seed": terrain.seed_value, "hours": snappedf(clock.total_hours(), 0.001), "play_time": snappedf(play_time, 0.1)},
		"player": {
			"pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
			"yaw": snappedf(player_yaw, 0.001),
			"pitch": snappedf(player_pitch, 0.001),
			"active_slot": active_slot,
			"stats": stats.to_dict(),
		},
		"inventory": inventory.to_dict(),
		"crafting": crafting.to_dict(),
		"resources": resources.to_dict(),
		"deployables": deployables.to_dict(),
	}


## Загружает состояние. Возвращает список предупреждений (пустой — всё загружено).
func from_dict(d: Dictionary) -> PackedStringArray:
	var warnings: PackedStringArray = PackedStringArray()
	var world: Dictionary = d.get("world", {})
	if JsonData.get_int(world, "seed", terrain.seed_value) != terrain.seed_value:
		warnings.append("seed_mismatch")
	clock.set_total_hours(JsonData.get_float(world, "hours", clock.total_hours()))
	play_time = JsonData.get_float(world, "play_time", 0.0)
	var pl: Dictionary = d.get("player", {})
	var pos: Variant = pl.get("pos", [])
	if typeof(pos) == TYPE_ARRAY and (pos as Array).size() >= 3:
		player_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		# Не даём появиться под землёй, если рельеф изменился.
		player_position.y = maxf(player_position.y, terrain.height_at(player_position.x, player_position.z))
	player_yaw = JsonData.get_float(pl, "yaw", 0.0)
	player_pitch = JsonData.get_float(pl, "pitch", 0.0)
	active_slot = clampi(JsonData.get_int(pl, "active_slot", 0), 0, Inventory.HOTBAR_SIZE - 1)
	stats.from_dict(pl.get("stats", {}))
	var skipped: int = inventory.from_dict(d.get("inventory", {}))
	if skipped > 0:
		warnings.append("inventory_skipped_%d" % skipped)
	crafting.from_dict(d.get("crafting", {}))
	if not resources.from_dict(d.get("resources", {})):
		warnings.append("resources_reset")
	deployables.from_dict(d.get("deployables", {}))
	active_slot_changed.emit(active_slot)
	return warnings
