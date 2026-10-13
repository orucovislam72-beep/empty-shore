extends GutTest
## Крафт: проверки, списание, станции, очередь, отмена, блокировка выхода, сохранение.

var db: ItemDB
var inv: Inventory
var cr: Crafting
var none: PackedStringArray = PackedStringArray()


func before_each() -> void:
	db = ItemDB.new()
	db.configure({"items": {
		"wood": {"kind": "resource", "stack": 1000},
		"stone": {"kind": "resource", "stack": 1000},
		"ore": {"kind": "resource", "stack": 100},
		"metal": {"kind": "resource", "stack": 100},
		"axe": {"kind": "tool", "stack": 1, "tool": {"durability": 10}},
	}})
	inv = Inventory.new(db)
	cr = Crafting.new(db)
	cr.configure({"max_queue": 2, "recipes": [
		{"id": "axe", "result": "axe", "count": 1, "time": 2.0, "station": "", "ingredients": {"wood": 30, "stone": 15}},
		{"id": "metal", "result": "metal", "count": 1, "time": 1.0, "station": "campfire", "ingredients": {"ore": 2}},
	]})


func test_missing_ingredients() -> void:
	inv.add("wood", 29)
	inv.add("stone", 15)
	assert_eq(cr.check("axe", inv, none), Crafting.Check.MISSING_INGREDIENTS)
	assert_eq(cr.check("nope", inv, none), Crafting.Check.UNKNOWN)


func test_craft_consumes_and_delivers_after_time() -> void:
	inv.add("wood", 40)
	inv.add("stone", 20)
	watch_signals(cr)
	assert_eq(cr.start("axe", inv, none), Crafting.Check.OK)
	assert_eq(inv.count_of("wood"), 10, "ингредиенты списаны сразу")
	assert_eq(inv.count_of("stone"), 5)
	cr.tick(1.0, inv)
	assert_eq(inv.count_of("axe"), 0, "ещё не готово")
	cr.tick(1.1, inv)
	assert_eq(inv.count_of("axe"), 1)
	assert_signal_emitted_with_parameters(cr, "crafted", ["axe", 1])
	assert_true(cr.queue.is_empty())


func test_station_required() -> void:
	inv.add("ore", 4)
	assert_eq(cr.check("metal", inv, none), Crafting.Check.NEED_STATION)
	assert_eq(cr.start("metal", inv, PackedStringArray(["campfire"])), Crafting.Check.OK)


func test_queue_limit_and_cancel_refunds() -> void:
	inv.add("wood", 100)
	inv.add("stone", 100)
	cr.start("axe", inv, none)
	cr.start("axe", inv, none)
	assert_eq(cr.check("axe", inv, none), Crafting.Check.QUEUE_FULL)
	assert_eq(cr.cancel(1, inv), 0)
	assert_eq(inv.count_of("wood"), 70)
	assert_eq(cr.queue.size(), 1)


func test_blocked_output_waits_for_space() -> void:
	inv.add("wood", 30)
	inv.add("stone", 15)
	cr.start("axe", inv, none)
	# Забиваем все 30 слотов, чтобы топору некуда было лечь.
	inv.add("stone", 1000 * 30)
	watch_signals(cr)
	cr.tick(5.0, inv)
	assert_signal_emitted(cr, "output_blocked")
	assert_eq(cr.queue.size(), 1, "результат ждёт места")
	inv.remove("stone", 1000)
	cr.tick(0.1, inv)
	assert_eq(inv.count_of("axe"), 1)


func test_queue_roundtrip() -> void:
	inv.add("wood", 30)
	inv.add("stone", 15)
	cr.start("axe", inv, none)
	cr.tick(0.5, inv)
	var d: Dictionary = JSON.parse_string(JSON.stringify(cr.to_dict()))
	var cr2: Crafting = Crafting.new(db)
	cr2.configure({"recipes": [{"id": "axe", "result": "axe", "time": 2.0, "ingredients": {}}]})
	cr2.from_dict(d)
	assert_eq(cr2.queue.size(), 1)
	assert_almost_eq(float(cr2.queue[0]["left"]), 1.5, 0.01)


func test_default_recipes_reference_known_items() -> void:
	var real_db: ItemDB = ItemDB.load_default()
	var c: Crafting = Crafting.load_default(real_db)
	assert_gt(c.recipe_ids().size(), 3)
	for rid: String in c.recipe_ids():
		assert_true(real_db.has(c.result_of(rid)), rid)
		for ing: String in c.ingredients(rid):
			assert_true(real_db.has(ing), "%s: ингредиент %s" % [rid, ing])
	assert_true(c.has_recipe("stone_axe"))
	assert_true(c.has_recipe("campfire"))
	assert_eq(c.station_of("stone_axe"), "", "топор делается в руках")
	assert_eq(c.station_of("campfire"), "", "костёр делается в руках")
