extends GutTest
## Таблицы лута, точки лута (наполнение, опустошение, перезарядка), мешок с вещами, туши,
## сохранение по чанкам.

var db: ItemDB
var tables: LootTable
var lcfg: Dictionary


func before_all() -> void:
	db = ItemDB.load_default()
	tables = LootTable.load_default()
	lcfg = JsonData.load_dict(WorldContainers.DEFAULT_PATH)


func _boxes() -> WorldContainers:
	var c: WorldContainers = WorldContainers.new()
	c.configure(lcfg, db, tables)
	c.grid = ChunkGrid.new(1280.0, 64.0)
	return c


func test_tables_reference_known_items() -> void:
	assert_eq(tables.table_ids().size(), 3)
	for t: String in tables.table_ids():
		for it: String in tables.items_of(t):
			assert_true(db.has(it), "%s: предмет %s есть в items.json" % [t, it])
	for ty: Dictionary in lcfg["types"]:
		assert_true(tables.has_table(String(ty["table"])), "у точки %s есть таблица" % ty["id"])


func test_roll_is_deterministic_by_seed() -> void:
	var r1: RandomNumberGenerator = RandomNumberGenerator.new()
	var r2: RandomNumberGenerator = RandomNumberGenerator.new()
	r1.seed = 5
	r2.seed = 5
	var a: ItemStorage = ItemStorage.new(db, 8)
	var b: ItemStorage = ItemStorage.new(db, 8)
	assert_gt(tables.roll("crate_common", r1, a), 0)
	tables.roll("crate_common", r2, b)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_point_fills_on_open_empties_and_respawns() -> void:
	var c: WorldContainers = _boxes()
	var i: int = c.add_point("crate", Vector3(10.0, 1.0, 10.0))
	assert_eq(c.nearest(Vector3(11.0, 1.0, 10.0)), i)
	watch_signals(c)
	var st: ItemStorage = c.storage_of(i)
	assert_false(st.is_all_empty(), "ящик наполнен броском по таблице")
	var inv: Inventory = Inventory.new(db)
	for s: int in st.size():
		st.take_to_inventory(s, inv)
	c.after_take(i)
	assert_false(c.is_point_available(i), "пустой ящик исчез")
	assert_signal_emitted(c, "point_changed")
	assert_eq(c.nearest(Vector3(11.0, 1.0, 10.0)), -1)
	assert_null(c.storage_of(i))
	c.tick(float(lcfg["types"][0]["respawn_s"]) + 1.0)
	assert_true(c.is_point_available(i), "через respawn_s снова на месте")
	assert_false(c.storage_of(i).is_all_empty(), "и снова наполнен")


func test_death_bag_takes_everything_and_disappears_when_empty() -> void:
	var c: WorldContainers = _boxes()
	var inv: Inventory = Inventory.new(db)
	inv.add("wood", 120)
	inv.add("crude_gun", 1)
	var gun: int = -1
	for s: int in Inventory.TOTAL:
		if inv.slot_id(s) == "crude_gun":
			gun = s
	inv.set_slot_ammo(gun, 1)
	inv.add("bow", 1)
	var h: int = c.add_bag(Vector3(1.0, 2.0, 3.0), "local", inv)
	assert_true(WorldContainers.is_dynamic(h))
	for s: int in Inventory.TOTAL:
		assert_true(inv.is_empty(s), "инвентарь пуст")
	var st: ItemStorage = c.storage_of(h)
	assert_eq(st.count_of("wood"), 120)
	assert_eq(st.count_of("crude_gun"), 1)
	assert_eq(st.count_of("gun_ammo"), 1, "патрон из магазина — в мешке")
	assert_eq(c.kind_of(h), WorldContainers.KIND_BAG)
	var inv2: Inventory = Inventory.new(db)
	for s: int in st.size():
		st.take_to_inventory(s, inv2)
	c.after_take(h)
	assert_false(c.is_valid(h), "пустой мешок исчез")
	assert_eq(inv2.count_of("wood"), 120)
	assert_eq(c.add_bag(Vector3.ZERO, "local", Inventory.new(db)), -1, "пустой инвентарь — без мешка")


func test_bag_despawns_after_time() -> void:
	var c: WorldContainers = _boxes()
	var inv: Inventory = Inventory.new(db)
	inv.add("stone", 5)
	var h: int = c.add_bag(Vector3.ZERO, "local", inv)
	c.tick(c.bag_despawn_s - 1.0)
	assert_true(c.is_valid(h))
	c.tick(2.0)
	assert_false(c.is_valid(h), "мешок исчез через despawn_s")


func test_corpse_has_drops() -> void:
	var c: WorldContainers = _boxes()
	var h: int = c.add_corpse("deer", Vector3(5.0, 0.0, 5.0), 0.3, {"meat": 6, "hide": 4})
	assert_eq(c.name_key(h), "LOOT_CORPSE")
	assert_eq(c.storage_of(h).count_of("meat"), 6)
	assert_eq(c.storage_of(h).count_of("hide"), 4)


func test_save_by_chunks_round_trip() -> void:
	var c: WorldContainers = _boxes()
	var i: int = c.add_point("barrel", Vector3(100.0, 1.0, -50.0))
	var j: int = c.add_point("crate", Vector3(-300.0, 4.0, 200.0))
	c.storage_of(i)
	var st: ItemStorage = c.storage_of(j)
	var inv: Inventory = Inventory.new(db)
	for s: int in st.size():
		st.take_to_inventory(s, inv)
	c.after_take(j)
	inv.add("metal", 7)
	var bag: int = c.add_bag(Vector3(3.0, 1.0, 4.0), "local", inv)
	c.add_corpse("wolf", Vector3(30.0, 1.0, 40.0), 1.0, {"meat": 4})
	var out: Dictionary = {}
	c.to_chunks(out)
	var json: Dictionary = JSON.parse_string(JSON.stringify(out))
	var c2: WorldContainers = _boxes()
	c2.add_point("barrel", Vector3(100.0, 1.0, -50.0))
	c2.add_point("crate", Vector3(-300.0, 4.0, 200.0))
	c2.from_chunks(json, true)
	assert_eq(JSON.stringify(c2.storage_of(i).to_dict()), JSON.stringify(c.storage_of(i).to_dict()), "содержимое бочки")
	assert_false(c2.is_point_available(j), "пустой ящик ждёт наполнения")
	assert_eq(c2.dynamic_count(), 2, "мешок и туша")
	var found: bool = false
	for k: int in c2.dynamic_count():
		if c2.d_kind[k] == WorldContainers.KIND_BAG:
			found = true
			assert_eq(c2.d_storage[k].count_of("metal"), 7 + c.storage_of(bag).count_of("metal") - 7)
	assert_true(found)
