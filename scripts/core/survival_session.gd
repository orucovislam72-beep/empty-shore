class_name SurvivalSession
extends RefCounted
## Игровая сессия выживания (этап 1): связывает инвентарь, крафт, показатели, время суток,
## ресурсные узлы и размещённые объекты. Чистая логика без сцен: сцена передаёт сюда
## «намерения» игрока (ударить, съесть, поставить, попить, сделать) и рисует результат.
## С этапа 2 — строительство (BuildingGrid), право владения, обслуживание и износ (BaseClaims),
## двери с кодовыми замками и хранилища. Каждое действие проверяет право игрока player_id.
## С этапа 3 — мир по чанкам (WorldGen), бой (ближний, лук, самопал; снаряды — Projectiles), животные
## (AnimalSim), точки лута, мешок с вещами при гибели и туши (WorldContainers), возрождение у спальника
## или кровати, иначе на побережье; сохранение по чанкам (раздел chunks).
## На этапе 4 этот же класс будет работать на сервере.

## Короткое сообщение игроку: key — ключ перевода (с %s для названия предмета), item_id — предмет или "".
signal notice(key: String, item_id: String)
signal gathered(item_id: String, amount: int)
signal active_slot_changed(slot: int)
signal player_died(cause: String)
signal respawned(position: Vector3)
## Объект (ящик, знамя) опустился на землю после обрушения пола.
signal deployable_moved(index: int)
## Игрока ранили (животное): amount — урон, cause — кто.
signal player_hurt(amount: float, cause: String)
## Удар или снаряд попал в цель (what — Projectiles.Hit).
signal hit_confirmed(what: int)
## Выстрел из оружия weapon_id (для отдачи и звука).
signal fired(weapon_id: String)
## Перезарядка началась (seconds > 0) или закончилась (0).
signal reload_changed(seconds: float)

const GAME_CFG_PATH: String = "res://data/balance/game.json"

enum Primary { NONE, SWING, EAT, PLACE, SHOOT }
enum Interact { NONE, DRINK, REFUEL, OPEN_DOOR, CLOSE_DOOR, UNLOCK, STORAGE, CLAIM, LOOT }
## Результат строительного действия.
enum Build { OK, BAD_PLACE, NO_PRIVILEGE, NO_RESOURCES, NO_TARGET, MAX_LEVEL, FULL_HP, NO_LOCK_ITEM, BAD_CODE, LOCKED }

var items: ItemDB
var inventory: Inventory
var crafting: Crafting
var stats: SurvivalStats
var clock: DayNightCycle
var resources: ResourceField
var deployables: Deployables
var terrain: TerrainMath
var water_level: float = -4.0
var building: BuildingGrid
var claims: BaseClaims
var animals: AnimalSim
var projectiles: Projectiles
var containers: WorldContainers
## Мир этапа 3 (null — маленькая тестовая карта TerrainMath).
var world: WorldGen
## Сетка чанков для сохранения (у маленькой карты — один чанк).
var chunk_grid: ChunkGrid = ChunkGrid.single(256.0)
## Точки возрождения на побережье.
var coast_points: PackedVector3Array = PackedVector3Array()
## Игрок целится (прицел): меньше разброс у лука и самопала.
var aiming: bool = false
## Мешок последней гибели (ручка WorldContainers) или -1.
var last_bag: int = -1
## Идентификатор игрока (офлайн — один локальный игрок; на этапе 4 — у каждого свой).
var player_id: String = "local"

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
var _eye: Vector3 = Vector3.ZERO
var _look: Vector3 = Vector3.FORWARD
var _interact_target: int = -1
var _reload_left: float = 0.0
var _reload_slot: int = -1
var _respawn_cd: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Создаёт сессию с данными из data/. field — уже сгенерированные ресурсные узлы; p_containers — точки
## лута мира (null — без точек). Если p_terrain — WorldGen, игрок появляется на месте высадки.
static func create(p_terrain: TerrainMath, field: ResourceField, p_water_level: float, p_containers: WorldContainers = null) -> SurvivalSession:
	var s: SurvivalSession = SurvivalSession.new()
	var db: ItemDB = ItemDB.load_default()
	s.setup(db, p_terrain, field, p_water_level, {
		"animals": JsonData.load_dict(AnimalSim.DEFAULT_PATH),
		"loot_points": JsonData.load_dict(WorldContainers.DEFAULT_PATH),
		"loot_tables": JsonData.load_dict(LootTable.DEFAULT_PATH),
		"containers": p_containers,
		"game": JsonData.load_dict(GAME_CFG_PATH),
		"recipes": JsonData.load_dict(Crafting.DEFAULT_PATH),
		"survival": JsonData.load_dict(SurvivalStats.DEFAULT_PATH),
		"day_night": JsonData.load_dict(DayNightCycle.DEFAULT_PATH),
		"deployables": JsonData.load_dict(Deployables.DEFAULT_PATH),
		"building": JsonData.load_dict(BuildingDefs.DEFAULT_PATH),
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
	deployables.db = db
	deployables.configure(cfgs.get("deployables", {}))
	var bdefs: BuildingDefs = BuildingDefs.new()
	bdefs.configure(cfgs.get("building", {}))
	building = BuildingGrid.new(bdefs, terrain, water_level)
	building.resources = resources
	building.deployables = deployables
	claims = BaseClaims.new(building, deployables)
	world = terrain as WorldGen
	_rng.seed = terrain.seed_value * 977 + 5
	var sp: Variant = _cfg.get("spawn", [0.0, 0.0])
	var sx: float = float(sp[0]) if typeof(sp) == TYPE_ARRAY and (sp as Array).size() >= 2 else 0.0
	var sz: float = float(sp[1]) if typeof(sp) == TYPE_ARRAY and (sp as Array).size() >= 2 else 0.0
	spawn_point = Vector3(sx, terrain.height_at(sx, sz), sz)
	var half: float = resources.grid.half
	if world != null:
		spawn_point = world.landing
		coast_points = world.coast_points
		chunk_grid = world.grid
		half = world.grid.half
	else:
		chunk_grid = resources.grid
	if coast_points.is_empty():
		coast_points.append(spawn_point)
	player_position = spawn_point
	# Животные, снаряды, контейнеры (этап 3).
	animals = AnimalSim.new()
	animals.configure(cfgs.get("animals", {}), terrain, water_level, half)
	animals.building = building
	animals.rng.seed = terrain.seed_value * 31 + 3
	projectiles = Projectiles.new()
	projectiles.terrain = terrain
	projectiles.animals = animals
	projectiles.resources = resources
	projectiles.building = building
	var given: Variant = cfgs.get("containers")
	if given is WorldContainers:
		containers = given
	else:
		containers = WorldContainers.new()
		containers.configure(cfgs.get("loot_points", {}), db, LootTable.new())
		containers.grid = chunk_grid
	if containers.db == null:
		containers.db = db
	if containers.tables == null or containers.tables.table_ids().is_empty():
		var lt: LootTable = LootTable.new()
		lt.configure(cfgs.get("loot_tables", {}))
		containers.tables = lt
	animals.attacked.connect(_on_animal_attack)
	animals.died.connect(_on_animal_died)
	projectiles.impact.connect(_on_projectile_impact)
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
	animals.tick(delta, player_position, not stats.is_dead())
	if world != null:
		animals.populate(delta, player_position, world.biome_at)
	projectiles.tick(delta)
	containers.tick(delta)
	_tick_reload(delta)
	for k: Variant in _respawn_cd.keys():
		_respawn_cd[k] = float(_respawn_cd[k]) - delta
		if float(_respawn_cd[k]) <= 0.0:
			_respawn_cd.erase(k)
	var removed: PackedInt32Array = claims.tick(delta)
	if not removed.is_empty():
		_settle_deployables()


func set_player_pose(pos: Vector3, yaw: float, pitch: float) -> void:
	player_position = pos
	player_yaw = yaw
	player_pitch = pitch


## Луч взгляда (глаза и направление) — для дверей и деталей под прицелом.
func set_look_ray(eye: Vector3, dir: Vector3) -> void:
	_eye = eye
	_look = dir


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
			return Primary.SHOOT if items.is_ranged(active_item()) else Primary.SWING


func can_swing() -> bool:
	return _swing_cd <= 0.0 and _reload_left <= 0.0 and not stats.is_dead()


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
		Primary.SHOOT:
			_swing_cd = items.swing_time(active_item())
			return Primary.SHOOT if fire(origin, dir) else Primary.NONE
		_:
			_swing_cd = items.swing_time(active_item())
			melee(origin, dir)
			return Primary.SWING


## Удар активным предметом: по животному на луче (если оно ближе ресурсного узла) или добыча.
func melee(origin: Vector3, dir: Vector3) -> void:
	var tool: String = active_item()
	var a: int = animals.find_hit(origin, dir, items.melee_range(tool))
	var at: float = animals.last_hit_t
	var node: int = resources.find_target(origin, dir)
	if a >= 0 and (node < 0 or at <= (resources.hit_center(node) - origin).dot(dir)):
		animals.damage(a, items.melee_damage(tool), player_position)
		hit_confirmed.emit(Projectiles.Hit.ANIMAL)
		if (items.is_tool(tool) or items.is_weapon(tool)) and inventory.wear(active_slot):
			notice.emit("NOTICE_TOOL_BROKE", tool)
		return
	gather(node)


## Выстрел из лука или самопала по лучу взгляда. Возвращает true, если снаряд выпущен.
func fire(origin: Vector3, dir: Vector3) -> bool:
	var w: String = active_item()
	var wt: String = items.weapon_type(w)
	var ammo: String = items.ammo_of(w)
	if wt == ItemDB.WEAPON_GUN:
		var loaded: int = inventory.slot_ammo(active_slot)
		if loaded <= 0:
			if not reload():
				notice.emit("NOTICE_NO_AMMO", ammo)
			return false
		inventory.set_slot_ammo(active_slot, loaded - 1)
	elif wt == ItemDB.WEAPON_BOW:
		if not inventory.remove(ammo, 1):
			notice.emit("NOTICE_NO_AMMO", ammo)
			return false
	else:
		return false
	var wd: Dictionary = items.weapon(w)
	var spread: float = deg_to_rad(JsonData.get_float(wd, "aim_spread_deg" if aiming else "spread_deg", 2.0))
	var d: Vector3 = _spread_dir(dir, spread)
	projectiles.fire(origin + dir * 0.4, d * JsonData.get_float(wd, "speed_mps", 40.0), items.ammo_damage(ammo), JsonData.get_float(wd, "gravity", 9.8), ammo)
	fired.emit(w)
	if inventory.wear(active_slot):
		notice.emit("NOTICE_TOOL_BROKE", w)
	return true


func _spread_dir(dir: Vector3, ang: float) -> Vector3:
	if ang <= 0.0:
		return dir
	var side: Vector3 = dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up: Vector3 = side.cross(dir).normalized()
	var r: float = tan(ang * sqrt(_rng.randf()))
	var a: float = _rng.randf() * TAU
	return (dir + side * r * cos(a) + up * r * sin(a)).normalized()


## Перезарядка огнестрела в активной ячейке (патроны из инвентаря). false — нечего или не нужно.
func reload() -> bool:
	var w: String = active_item()
	if items.weapon_type(w) != ItemDB.WEAPON_GUN or _reload_left > 0.0 or stats.is_dead():
		return false
	if inventory.slot_ammo(active_slot) >= items.magazine_size(w):
		return false
	if inventory.count_of(items.ammo_of(w)) <= 0:
		notice.emit("NOTICE_NO_AMMO", items.ammo_of(w))
		return false
	_reload_left = maxf(JsonData.get_float(items.weapon(w), "reload_s", 2.0), 0.05)
	_reload_slot = active_slot
	reload_changed.emit(_reload_left)
	return true


func is_reloading() -> bool:
	return _reload_left > 0.0


func _tick_reload(delta: float) -> void:
	if _reload_left <= 0.0:
		return
	var w: String = inventory.slot_id(_reload_slot)
	if active_slot != _reload_slot or items.weapon_type(w) != ItemDB.WEAPON_GUN or stats.is_dead():
		_reload_left = 0.0
		reload_changed.emit(0.0)
		return
	_reload_left -= delta
	if _reload_left > 0.0:
		return
	_reload_left = 0.0
	var have: int = inventory.slot_ammo(_reload_slot)
	var n: int = mini(items.magazine_size(w) - have, inventory.count_of(items.ammo_of(w)))
	if n > 0 and inventory.remove(items.ammo_of(w), n):
		inventory.set_slot_ammo(_reload_slot, have + n)
	reload_changed.emit(0.0)


## Патроны активного оружия: x — в магазине (-1 — без магазина), y — в инвентаре; (-1, -1) — не стрелковое.
func ammo_status() -> Vector2i:
	var w: String = active_item()
	if not items.is_ranged(w):
		return Vector2i(-1, -1)
	var spare: int = inventory.count_of(items.ammo_of(w))
	if items.weapon_type(w) == ItemDB.WEAPON_GUN:
		return Vector2i(inventory.slot_ammo(active_slot), spare)
	return Vector2i(-1, spare)


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
	p.y = building.surface_height(p.x, p.z, feet.y + 0.6)
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
	if not claims.can_build(player_id, p):
		notice.emit("NOTICE_NO_PRIVILEGE", "")
		return false
	if deployables.claim_radius(kind) > 0.0 and not claims.can_place_banner(p):
		notice.emit("NOTICE_BANNER_OVERLAP", "")
		return false
	if building.blocks_box(AABB(Vector3(p.x - 0.5, p.y + 0.05, p.z - 0.5), Vector3(1.0, 1.0, 1.0))):
		notice.emit("NOTICE_CANT_PLACE", id)
		return false
	if deployables.place(kind, p, yaw, player_id) < 0:
		notice.emit("NOTICE_CANT_PLACE", id)
		return false
	inventory.remove_at(active_slot, 1)
	return true


# --- Взаимодействие (кнопка «Взять» по контексту) ---------------------------

func interact_kind(feet: Vector3, yaw: float) -> Interact:
	_interact_target = -1
	var door: int = building.find_target(_eye, _look, building.defs.target_reach)
	if door >= 0 and building.is_door(door):
		_interact_target = door
		if building.is_open(door):
			return Interact.CLOSE_DOOR
		return Interact.OPEN_DOOR if building.can_use_door(door, player_id) else Interact.UNLOCK
	var near: int = deployables.nearest(feet)
	if near >= 0:
		_interact_target = near
		if deployables.is_fueled(deployables.kinds[near]):
			return Interact.REFUEL
		if claims.is_banner(near):
			return Interact.CLAIM
		if deployables.has_storage(near):
			return Interact.STORAGE
	var box: int = containers.nearest(feet)
	if box >= 0:
		_interact_target = box
		return Interact.LOOT
	_interact_target = -1
	if is_water_near(feet, yaw):
		return Interact.DRINK
	return Interact.NONE


## Цель последнего interact_kind()/interact(): id двери или индекс объекта.
func interact_target() -> int:
	return _interact_target


func is_water_near(feet: Vector3, yaw: float) -> bool:
	if feet.y > water_level + 1.6:
		return false
	if terrain.height_at(feet.x, feet.z) < water_level:
		return true
	var fwd: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var p: Vector3 = feet + fwd * 1.5
	return terrain.height_at(p.x, p.z) < water_level


## Контекстное действие. Для UNLOCK, STORAGE и CLAIM сцена открывает экран (цель — interact_target()).
func interact(feet: Vector3, yaw: float) -> Interact:
	var kind: Interact = interact_kind(feet, yaw)
	match kind:
		Interact.REFUEL:
			var i: int = _interact_target
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
		Interact.OPEN_DOOR, Interact.CLOSE_DOOR:
			if _door_blocked_by_player(_interact_target, feet):
				notice.emit("NOTICE_DOOR_BLOCKED", "")
				return Interact.NONE
			building.toggle_door(_interact_target, player_id)
			return kind
	return kind


## Не закрываем дверь на игрока, стоящего в проёме.
func _door_blocked_by_player(id: int, feet: Vector3) -> bool:
	if not building.is_open(id):
		return false
	var body: AABB = AABB(Vector3(feet.x - 0.35, feet.y + 0.05, feet.z - 0.35), Vector3(0.7, 1.7, 0.7))
	return body.intersects(building.piece_aabb(id))


# --- Крафт ------------------------------------------------------------------

func stations_at(pos: Vector3) -> PackedStringArray:
	deployables.stations_near(pos, _stations)
	return _stations


func craft(recipe_id: String) -> Crafting.Check:
	return crafting.start(recipe_id, inventory, stations_at(player_position))


# --- Строительство ---------------------------------------------------------

## Подсказка места для детали по текущему взгляду (призрак). out переиспользуется.
func build_suggest(type: String, mat: int, rot: int, out: BuildingGrid.Placement) -> void:
	building.suggest(type, mat, _eye, _look, rot, player_position, out)


## Полная проверка постановки: место, право владения, ресурсы.
func build_check(p: BuildingGrid.Placement) -> Build:
	if not p.is_valid():
		return Build.BAD_PLACE
	var center: Vector3 = building.aabb_of(p.type, p.key, p.depth).get_center()
	if not claims.can_build(player_id, center):
		return Build.NO_PRIVILEGE
	if not has_items(building.defs.cost(p.type, p.material)):
		return Build.NO_RESOURCES
	return Build.OK


## Поставить деталь (намерение игрока). Сессия заново проверяет место — клиенту не верим.
func build_place(p: BuildingGrid.Placement) -> Build:
	p.reason = building.check(p.type, p.material, p.key, _eye, player_position)
	var r: Build = build_check(p)
	if r != Build.OK:
		return r
	take_items(building.defs.cost(p.type, p.material))
	building.add_piece(p.type, p.material, p.key, p.rot, player_id, p.depth if p.type == "foundation" else -1.0)
	return Build.OK


func has_items(cost: Dictionary) -> bool:
	for item: String in cost:
		if inventory.count_of(item) < int(cost[item]):
			return false
	return true


func take_items(cost: Dictionary) -> void:
	for item: String in cost:
		inventory.remove(item, int(cost[item]))


## Деталь под прицелом (для улучшения, ремонта, разбора) или -1.
func build_target() -> int:
	return building.find_target(_eye, _look, building.defs.target_reach)


func _piece_center(id: int) -> Vector3:
	return building.piece_aabb(id).get_center()


func upgrade_cost(id: int) -> Dictionary:
	var next: int = building.defs.next_material(building.p_type[id], building.p_mat[id])
	return building.defs.cost(building.p_type[id], next) if next >= 0 else {}


func build_upgrade(id: int) -> Build:
	if not building.is_alive(id):
		return Build.NO_TARGET
	if not claims.can_build(player_id, _piece_center(id)):
		return Build.NO_PRIVILEGE
	var next: int = building.defs.next_material(building.p_type[id], building.p_mat[id])
	if next < 0:
		return Build.MAX_LEVEL
	var cost: Dictionary = building.defs.cost(building.p_type[id], next)
	if not has_items(cost):
		return Build.NO_RESOURCES
	take_items(cost)
	building.set_material(id, next)
	return Build.OK


## Ремонт: доля стоимости пропорционально недостающей прочности (repair_cost_fraction за полный ремонт).
func repair_cost(id: int) -> Dictionary:
	var out: Dictionary = {}
	var missing: float = 1.0 - building.p_hp[id] / building.max_hp(id)
	if missing <= 0.001:
		return out
	var cost: Dictionary = building.defs.cost(building.p_type[id], building.p_mat[id])
	for item: String in cost:
		out[item] = maxi(int(ceil(float(cost[item]) * building.defs.repair_fraction * missing)), 1)
	return out


func build_repair(id: int) -> Build:
	if not building.is_alive(id):
		return Build.NO_TARGET
	if not claims.can_build(player_id, _piece_center(id)):
		return Build.NO_PRIVILEGE
	var cost: Dictionary = repair_cost(id)
	if cost.is_empty():
		return Build.FULL_HP
	if not has_items(cost):
		return Build.NO_RESOURCES
	take_items(cost)
	building.set_hp(id, building.max_hp(id))
	return Build.OK


## Разобрать деталь: возвращается часть стоимости (demolish_refund) с учётом прочности; держащееся на ней
## обрушивается без возврата.
func build_demolish(id: int) -> Build:
	if not building.is_alive(id):
		return Build.NO_TARGET
	if not claims.can_build(player_id, _piece_center(id)):
		return Build.NO_PRIVILEGE
	var cost: Dictionary = building.defs.cost(building.p_type[id], building.p_mat[id])
	var k: float = building.defs.demolish_refund * building.p_hp[id] / building.max_hp(id)
	var had_lock: bool = building.has_lock(id)
	building.remove_piece(id)
	for item: String in cost:
		var n: int = int(floor(float(cost[item]) * k))
		if n > 0:
			_give(item, n)
	if had_lock:
		_give("code_lock", 1)
	_settle_deployables()
	return Build.OK


## Положить в инвентарь, а что не поместилось — сообщить (выброс на землю — в docs/IDEAS.md).
func _give(item: String, n: int) -> void:
	if inventory.add(item, n) > 0:
		notice.emit("NOTICE_INVENTORY_FULL", item)


## Объекты, под которыми обрушился пол, опускаются на ближайшую поверхность ниже.
func _settle_deployables() -> void:
	for i: int in deployables.size():
		var p: Vector3 = deployables.positions[i]
		var y: float = building.surface_height(p.x, p.z, p.y + 0.05)
		if y < p.y - 0.05:
			deployables.drop_to(i, y)
			deployable_moved.emit(i)


# --- Двери и замки ----------------------------------------------------------

## Поставить кодовый замок на дверь (нужен предмет «Кодовый замок» и право строить у двери).
func lock_attach(id: int, code: String) -> Build:
	if not building.is_door(id) or building.has_lock(id):
		return Build.NO_TARGET
	if not claims.can_build(player_id, _piece_center(id)) and building.p_owner[id] != player_id:
		return Build.NO_PRIVILEGE
	if not BuildingGrid.is_valid_code(code):
		return Build.BAD_CODE
	if inventory.count_of("code_lock") <= 0:
		return Build.NO_LOCK_ITEM
	inventory.remove("code_lock", 1)
	building.attach_lock(id, player_id, code)
	return Build.OK


## Ввести код замка. Верный — игрок запоминается замком, дверь открывается.
func lock_enter(id: int, code: String) -> Build:
	if not building.has_lock(id):
		return Build.NO_TARGET
	if not building.enter_code(id, player_id, code):
		return Build.BAD_CODE
	if not building.is_open(id):
		building.toggle_door(id, player_id)
	return Build.OK


func lock_change(id: int, code: String) -> Build:
	if not building.has_lock(id):
		return Build.NO_TARGET
	if not building.can_use_door(id, player_id):
		return Build.LOCKED
	return Build.OK if building.change_code(id, player_id, code) else Build.BAD_CODE


# --- Хранилища и знамя ------------------------------------------------------

## Достаёт ли игрок до объекта (хранилища или знамени).
func can_reach(index: int) -> bool:
	return index >= 0 and index < deployables.size() and deployables.positions[index].distance_to(player_position) <= deployables.interact_radius + 0.5


func storage_put(index: int, inv_slot: int) -> int:
	if not can_reach(index) or not deployables.has_storage(index):
		return 0
	return deployables.storages[index].put_from_inventory(inventory, inv_slot)


func storage_take(index: int, slot: int) -> int:
	if not can_reach(index) or not deployables.has_storage(index):
		return 0
	# Запас обслуживания знамени берут только «свои».
	if claims.is_banner(index) and not deployables.is_authorized(index, player_id):
		notice.emit("NOTICE_NO_PRIVILEGE", "")
		return 0
	return deployables.storages[index].take_to_inventory(slot, inventory)


## Получить право у знамени (как в жанре: кто добрался до знамени — тот и свой).
func claim_authorize(index: int) -> bool:
	if not claims.is_banner(index) or not can_reach(index):
		return false
	deployables.authorize(index, player_id)
	return true


func claim_leave(index: int) -> bool:
	if not claims.is_banner(index) or not can_reach(index):
		return false
	deployables.deauthorize(index, player_id)
	return true


## Сбросить список права (оставив себя) — только «свой».
func claim_reset(index: int) -> bool:
	if not claims.is_banner(index) or not can_reach(index) or not deployables.is_authorized(index, player_id):
		return false
	deployables.clear_auth(index)
	deployables.authorize(index, player_id)
	return true


# --- Контейнеры мира (лут, мешки, туши) -------------------------------------

func can_reach_container(handle: int) -> bool:
	return containers.is_valid(handle) and containers.position_of(handle).distance_to(player_position) <= containers.interact_radius + 0.5


func container_take(handle: int, slot: int) -> int:
	if not can_reach_container(handle):
		return 0
	var st: ItemStorage = containers.storage_of(handle)
	var n: int = st.take_to_inventory(slot, inventory)
	if n > 0:
		containers.after_take(handle)
	return n


func container_put(handle: int, inv_slot: int) -> int:
	if not can_reach_container(handle):
		return 0
	return containers.storage_of(handle).put_from_inventory(inventory, inv_slot)


# --- Бой и животные ---------------------------------------------------------

func _on_animal_attack(_animal: int, dmg: float, kind: String) -> void:
	if stats.is_dead():
		return
	player_hurt.emit(dmg, kind)
	stats.damage(dmg, kind)


func _on_animal_died(kind: String, pos: Vector3, yaw: float) -> void:
	var def: Dictionary = animals.defs[animals.kind_ids.find(kind)] if animals.kind_ids.has(kind) else {}
	containers.add_corpse(kind, pos, yaw, def.get("drops", {}))
	notice.emit("NOTICE_ANIMAL_KILLED", "")


func _on_projectile_impact(what: int, _target: int, _pos: Vector3, _ammo: String) -> void:
	if what == Projectiles.Hit.ANIMAL:
		hit_confirmed.emit(what)


# --- Смерть -----------------------------------------------------------------

func _on_crafted(item_id: String, _count: int) -> void:
	notice.emit("NOTICE_CRAFTED", item_id)


func _on_craft_blocked(item_id: String) -> void:
	notice.emit("NOTICE_CRAFT_BLOCKED", item_id)


## Гибель: всё из инвентаря (и очереди крафта — ингредиенты) ложится в мешок на месте гибели.
func _on_died(cause: String) -> void:
	_reload_left = 0.0
	last_bag = -1
	if not JsonData.get_bool(_cfg, "respawn_keeps_inventory", false):
		while not crafting.queue.is_empty():
			crafting.cancel(crafting.queue.size() - 1, inventory)
		var p: Vector3 = player_position
		p.y = maxf(p.y, terrain.height_at(p.x, p.z))
		last_bag = containers.add_bag(p, player_id, inventory)
		inventory.clear_all()
	player_died.emit(cause)


## Свои спальники и кровати: [{index, kind, name (ключ перевода), cooldown, distance}].
func respawn_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in deployables.size():
		var def: Dictionary = deployables.type_def(deployables.kinds[i])
		if not def.has("respawn_cooldown_s") or deployables.owners[i] != player_id:
			continue
		out.append({"index": i, "kind": deployables.kinds[i], "name": String(def.get("name", "")), "cooldown": float(_respawn_cd.get(i, 0.0)),
			"distance": deployables.positions[i].distance_to(player_position)})
	return out


func can_respawn_at(index: int) -> bool:
	if index < 0 or index >= deployables.size() or deployables.owners[index] != player_id:
		return false
	return deployables.type_def(deployables.kinds[index]).has("respawn_cooldown_s") and float(_respawn_cd.get(index, 0.0)) <= 0.0


## Точка на побережье для возрождения без спальника (случайная из coast_points).
func coast_respawn_point() -> Vector3:
	return coast_points[_rng.randi() % coast_points.size()]


## Возрождение: у спальника/кровати point (если можно), иначе на побережье.
func respawn(point: int = -1) -> void:
	var pos: Vector3
	if can_respawn_at(point):
		var b: Vector3 = deployables.positions[point]
		var side: Vector3 = Vector3(cos(deployables.yaws[point]), 0.0, -sin(deployables.yaws[point])) * 1.2
		pos = b + side
		pos.y = building.surface_height(pos.x, pos.z, b.y + 0.6)
		_respawn_cd[point] = JsonData.get_float(deployables.type_def(deployables.kinds[point]), "respawn_cooldown_s", 120.0)
	else:
		pos = coast_respawn_point()
	if not JsonData.get_bool(_cfg, "respawn_keeps_inventory", false):
		inventory.clear_all()
		crafting.from_dict({})
	stats.reset_for_respawn()
	animals.clear()
	projectiles.clear()
	player_position = pos
	respawned.emit(pos)


# --- Сохранение -------------------------------------------------------------

## Раздел chunks: {"cx,cz": {"r": узлы, "l": точки лута, "c": мешки и туши, "p": детали построек, "d": объекты}}
## (формат записи на диск — SaveGame / WorldSaveFile: двоичные записи чанков).
func to_dict() -> Dictionary:
	var p: Vector3 = player_position
	var chunks: Dictionary = {}
	resources.to_chunks(chunks)
	containers.to_chunks(chunks)
	_pieces_to_chunks(chunks)
	_deployables_to_chunks(chunks)
	var cds: Dictionary = {}
	for k: Variant in _respawn_cd:
		cds[str(k)] = snappedf(float(_respawn_cd[k]), 0.1)
	return {
		"world": {"seed": terrain.seed_value, "generator": WorldGen.GENERATOR_VERSION if world != null else 0,
			"resources_hash": resources.layout_hash, "loot_hash": containers.layout_hash,
			"hours": snappedf(clock.total_hours(), 0.001), "play_time": snappedf(play_time, 0.1)},
		"player": {
			"pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
			"yaw": snappedf(player_yaw, 0.001),
			"pitch": snappedf(player_pitch, 0.001),
			"active_slot": active_slot,
			"stats": stats.to_dict(),
			"respawn_cd": cds,
		},
		"inventory": inventory.to_dict(),
		"crafting": crafting.to_dict(),
		"claims": claims.to_dict(),
		"chunks": chunks,
	}


static func _chunk_of(out: Dictionary, k: String) -> Dictionary:
	if not out.has(k):
		out[k] = {}
	return out[k]


## Детали построек — в чанки по центру клетки; [порядковый номер, запись BuildingGrid].
func _pieces_to_chunks(out: Dictionary) -> void:
	var list: Array = building.to_dict()["pieces"]
	var g: float = building.defs.grid
	for i: int in list.size():
		var e: Array = list[i]
		var ch: Dictionary = _chunk_of(out, chunk_grid.key_of((float(e[2]) + 0.5) * g, (float(e[3]) + 0.5) * g))
		if not ch.has("p"):
			ch["p"] = []
		(ch["p"] as Array).append([i, e])


func _deployables_to_chunks(out: Dictionary) -> void:
	var list: Array = deployables.to_dict()["objects"]
	for i: int in list.size():
		var e: Array = list[i]
		var ch: Dictionary = _chunk_of(out, chunk_grid.key_of(float(e[1]), float(e[3])))
		if not ch.has("d"):
			ch["d"] = []
		(ch["d"] as Array).append([i, e])


## Собирает записи tag из всех чанков в исходном порядке.
static func _gather_ordered(chunks: Dictionary, tag: String) -> Array:
	var all: Array = []
	for k: Variant in chunks:
		if typeof(chunks[k]) != TYPE_DICTIONARY:
			continue
		var list: Variant = (chunks[k] as Dictionary).get(tag, [])
		if typeof(list) != TYPE_ARRAY:
			continue
		for e: Variant in list:
			if typeof(e) == TYPE_ARRAY and (e as Array).size() >= 2 and typeof(e[1]) == TYPE_ARRAY:
				all.append(e)
	all.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	for e2: Array in all:
		out.append(e2[1])
	return out


## Загружает состояние. Возвращает список предупреждений (пустой — всё загружено).
func from_dict(d: Dictionary) -> PackedStringArray:
	var warnings: PackedStringArray = PackedStringArray()
	var wd: Dictionary = d.get("world", {})
	if JsonData.get_int(wd, "seed", terrain.seed_value) != terrain.seed_value:
		warnings.append("seed_mismatch")
	clock.set_total_hours(JsonData.get_float(wd, "hours", clock.total_hours()))
	play_time = JsonData.get_float(wd, "play_time", 0.0)
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
	_respawn_cd.clear()
	var cds: Variant = pl.get("respawn_cd", {})
	if typeof(cds) == TYPE_DICTIONARY:
		for k: Variant in cds:
			_respawn_cd[int(String(k))] = float(cds[k])
	var bskip: int = 0
	if d.has("chunks") and typeof(d["chunks"]) == TYPE_DICTIONARY:
		var chunks: Dictionary = d["chunks"]
		var hash_ok: bool = JsonData.get_int(wd, "resources_hash", 0) == resources.layout_hash
		if not resources.from_chunks(chunks, hash_ok):
			warnings.append("resources_reset")
		containers.from_chunks(chunks, JsonData.get_int(wd, "loot_hash", 0) == containers.layout_hash)
		deployables.from_dict({"objects": _gather_ordered(chunks, "d")})
		bskip = building.from_dict({"pieces": _gather_ordered(chunks, "p")})
	else:
		# Словарь старого формата (v2) без миграции.
		if not resources.from_dict(d.get("resources", {})):
			warnings.append("resources_reset")
		deployables.from_dict(d.get("deployables", {}))
		bskip = building.from_dict(d.get("building", {}))
	if bskip > 0:
		warnings.append("building_skipped_%d" % bskip)
	claims.from_dict(d.get("claims", {}))
	active_slot_changed.emit(active_slot)
	return warnings
