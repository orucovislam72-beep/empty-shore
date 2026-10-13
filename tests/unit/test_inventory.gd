extends GutTest
## Инвентарь: добавление, стопки, перенос, деление, прочность, экипировка, сохранение.

var db: ItemDB
var inv: Inventory


func before_each() -> void:
	db = ItemDB.new()
	db.configure({
		"hand": {"swing_time": 0.8, "gather": {"wood": 0.5}},
		"items": {
			"wood": {"kind": "resource", "stack": 100},
			"berries": {"kind": "food", "stack": 20},
			"axe": {"kind": "tool", "stack": 1, "tool": {"durability": 3, "gather": {"wood": 2.0}}},
			"hat": {"kind": "resource", "stack": 1, "equip": "head"},
		},
	})
	inv = Inventory.new(db)


func test_layout_constants() -> void:
	assert_eq(Inventory.HOTBAR_SIZE, 6)
	assert_eq(Inventory.BACKPACK_SIZE, 24)
	assert_eq(Inventory.TOTAL, 34)


func test_resources_go_to_backpack_and_stack() -> void:
	assert_eq(inv.add("wood", 250), 0)
	assert_eq(inv.count_of("wood"), 250)
	assert_eq(inv.slot_count(Inventory.BACKPACK_START), 100)
	assert_eq(inv.slot_count(Inventory.BACKPACK_START + 2), 50)
	assert_true(inv.is_empty(0), "ресурсы не занимают быструю панель, пока есть место в рюкзаке")
	inv.add("wood", 30)
	assert_eq(inv.slot_count(Inventory.BACKPACK_START + 2), 80, "докладывается в неполную стопку")


func test_tools_go_to_hotbar_with_durability() -> void:
	inv.add("axe", 2)
	assert_eq(inv.slot_id(0), "axe")
	assert_eq(inv.slot_id(1), "axe")
	assert_eq(inv.slot_durability(0), 3)


func test_overflow_returns_leftover() -> void:
	var left: int = inv.add("wood", 100 * 31)
	assert_eq(left, 100, "30 слотов по 100, остаток 100")
	assert_eq(inv.free_space_for("wood"), 0)
	assert_eq(inv.add("unknown", 5), 5, "неизвестный предмет не добавляется")


func test_remove_all_or_nothing() -> void:
	inv.add("wood", 150)
	assert_false(inv.remove("wood", 151))
	assert_eq(inv.count_of("wood"), 150)
	assert_true(inv.remove("wood", 120))
	assert_eq(inv.count_of("wood"), 30)


func test_move_merge_swap_and_partial() -> void:
	var a: int = Inventory.BACKPACK_START
	inv.add("wood", 150)
	assert_false(inv.move(a + 1, a), "в полную стопку не объединить")
	inv.clear_all()
	inv.add("wood", 60)
	inv.move(a, 0, 20)
	assert_eq(inv.slot_count(0), 20)
	assert_eq(inv.slot_count(a), 40)
	assert_true(inv.move(0, a))
	assert_eq(inv.slot_count(a), 60)
	assert_true(inv.is_empty(0))
	inv.add("axe", 1)
	assert_true(inv.move(0, a), "перестановка целых стопок")
	assert_eq(inv.slot_id(a), "axe")
	assert_eq(inv.slot_id(0), "wood")


func test_split() -> void:
	inv.add("berries", 9)
	assert_eq(inv.slot_id(0), "berries")
	assert_true(inv.split(0))
	assert_eq(inv.slot_count(0), 5)
	assert_eq(inv.count_of("berries"), 9)
	assert_false(inv.split(Inventory.BACKPACK_START + 5), "пустой слот не делится")


func test_equipment_accepts_only_matching() -> void:
	inv.add("wood", 1)
	inv.add("hat", 1)
	var head: int = Inventory.EQUIP_START
	var wood_slot: int = Inventory.BACKPACK_START
	assert_false(inv.move(wood_slot, head), "дерево не надеть на голову")
	var hat_slot: int = -1
	for i: int in Inventory.EQUIP_START:
		if inv.slot_id(i) == "hat":
			hat_slot = i
	assert_true(inv.move(hat_slot, head))
	assert_eq(inv.slot_id(head), "hat")
	assert_false(inv.move(wood_slot, head), "перестановка тоже проверяет слот")
	assert_eq(inv.count_of("hat"), 0, "экипировка не считается в count_of")


func test_wear_breaks_tool() -> void:
	inv.add("axe", 1)
	assert_false(inv.wear(0))
	assert_false(inv.wear(0))
	assert_true(inv.wear(0), "третий удар ломает")
	assert_true(inv.is_empty(0))


func test_changed_signal() -> void:
	watch_signals(inv)
	inv.add("wood", 5)
	assert_signal_emitted(inv, "changed")


func test_roundtrip_dict_and_skips_unknown() -> void:
	inv.add("wood", 42)
	inv.add("axe", 1)
	inv.wear(0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(inv.to_dict()))
	(d["slots"] as Array).append([3, "ghost_item", 1, -1])
	var inv2: Inventory = Inventory.new(db)
	assert_eq(inv2.from_dict(d), 1, "одна неизвестная запись пропущена")
	assert_eq(inv2.count_of("wood"), 42)
	assert_eq(inv2.slot_durability(0), 2)
