extends GutTest
## Хранилище (ящик, запас знамени): добавление стопками, перекладывание в инвентарь и обратно, сохранение.

var db: ItemDB


func before_each() -> void:
	db = ItemDB.load_default()


func test_add_stacks_and_overflow() -> void:
	var st: ItemStorage = ItemStorage.new(db, 2)
	assert_eq(st.add("wood", 1500), 0, "1000 + 500 в две ячейки")
	assert_eq(st.count_of("wood"), 1500)
	assert_eq(st.add("stone", 10), 10, "места нет — всё вернулось")
	assert_eq(st.add("wood", 600), 100, "дополнилась только неполная стопка")


func test_remove_all_or_nothing() -> void:
	var st: ItemStorage = ItemStorage.new(db, 4)
	st.add("stone", 50)
	assert_false(st.remove("stone", 60))
	assert_eq(st.count_of("stone"), 50, "при нехватке ничего не списано")
	assert_true(st.remove("stone", 20))
	assert_eq(st.count_of("stone"), 30)


func test_put_and_take_with_inventory_keep_durability() -> void:
	var inv: Inventory = Inventory.new(db)
	var st: ItemStorage = ItemStorage.new(db, 6)
	inv.add("stone_axe", 1)
	var axe_slot: int = 0
	inv.wear(axe_slot, 10)
	var dur: int = inv.slot_durability(axe_slot)
	assert_eq(st.put_from_inventory(inv, axe_slot), 1)
	assert_true(inv.is_empty(axe_slot))
	assert_eq(st.slot_durability(0), dur, "прочность сохраняется")
	assert_eq(st.take_to_inventory(0, inv), 1)
	assert_eq(inv.count_of("stone_axe"), 1)
	assert_true(st.is_all_empty())


func test_take_partial_when_inventory_full() -> void:
	var inv: Inventory = Inventory.new(db)
	for i: int in Inventory.EQUIP_START:
		inv.add("stone_axe", 1)
	var st: ItemStorage = ItemStorage.new(db, 2)
	st.add("wood", 10)
	assert_eq(st.take_to_inventory(0, inv), 0, "инвентарь полон")
	assert_eq(st.count_of("wood"), 10)


func test_save_and_load() -> void:
	var st: ItemStorage = ItemStorage.new(db, 5)
	st.add("metal", 30)
	st.add("berries", 3)
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_dict()))
	var st2: ItemStorage = ItemStorage.new(db, 5)
	assert_eq(st2.from_dict(d), 0)
	assert_eq(st2.count_of("metal"), 30)
	assert_eq(st2.count_of("berries"), 3)
	d["slots"].append([99, "wood", 5, -1])
	d["slots"].append([1, "unknown_item", 5, -1])
	assert_eq(st2.from_dict(d), 2, "неверная ячейка и неизвестный предмет пропущены")
