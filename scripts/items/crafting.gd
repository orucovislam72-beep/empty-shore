class_name Crafting
extends RefCounted
## Крафт: рецепты из data/recipes/recipes.json и очередь изготовления. Чистая логика без сцен.
## Ингредиенты списываются при постановке в очередь; отмена возвращает их.
## Станция (костёр, верстак) нужна только при постановке в очередь.

signal queue_changed
signal crafted(item_id: String, count: int)
## Готовый предмет не помещается в инвентарь — ждёт в очереди, пока не освободится место.
signal output_blocked(item_id: String)

const DEFAULT_PATH: String = "res://data/recipes/recipes.json"

enum Check { OK, UNKNOWN, MISSING_INGREDIENTS, NEED_STATION, QUEUE_FULL }

var db: ItemDB
var max_queue: int = 8
## Очередь: {"recipe": String, "left": float}
var queue: Array[Dictionary] = []

var _recipes: Dictionary = {}
var _order: PackedStringArray = PackedStringArray()
var _blocked_reported: bool = false


func _init(p_db: ItemDB = null) -> void:
	db = p_db


func configure(data: Dictionary) -> void:
	max_queue = maxi(JsonData.get_int(data, "max_queue", 8), 1)
	_recipes.clear()
	_order.clear()
	var list: Variant = data.get("recipes", [])
	if typeof(list) != TYPE_ARRAY:
		push_error("Crafting: поле recipes должно быть массивом")
		return
	for r: Variant in list:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var rd: Dictionary = r
		var id: String = String(rd.get("id", ""))
		if id.is_empty() or not db.has(String(rd.get("result", ""))):
			push_error("Crafting: рецепт с неизвестным результатом: %s" % id)
			continue
		_recipes[id] = rd
		_order.append(id)


static func load_default(p_db: ItemDB) -> Crafting:
	var c: Crafting = Crafting.new(p_db)
	c.configure(JsonData.load_dict(DEFAULT_PATH))
	return c


func recipe_ids() -> PackedStringArray:
	return _order


func has_recipe(id: String) -> bool:
	return _recipes.has(id)


func recipe(id: String) -> Dictionary:
	return _recipes.get(id, {})


func result_of(id: String) -> String:
	return String(recipe(id).get("result", ""))


func ingredients(id: String) -> Dictionary:
	return recipe(id).get("ingredients", {})


func station_of(id: String) -> String:
	return String(recipe(id).get("station", ""))


func time_of(id: String) -> float:
	return maxf(JsonData.get_float(recipe(id), "time", 1.0), 0.0)


func check(recipe_id: String, inv: Inventory, stations: PackedStringArray) -> Check:
	if not _recipes.has(recipe_id):
		return Check.UNKNOWN
	var st: String = station_of(recipe_id)
	if not st.is_empty() and not stations.has(st):
		return Check.NEED_STATION
	var ing: Dictionary = ingredients(recipe_id)
	for item: String in ing:
		if inv.count_of(item) < int(ing[item]):
			return Check.MISSING_INGREDIENTS
	if queue.size() >= max_queue:
		return Check.QUEUE_FULL
	return Check.OK


## Ставит рецепт в очередь и списывает ингредиенты.
func start(recipe_id: String, inv: Inventory, stations: PackedStringArray) -> Check:
	var c: Check = check(recipe_id, inv, stations)
	if c != Check.OK:
		return c
	var ing: Dictionary = ingredients(recipe_id)
	for item: String in ing:
		inv.remove(item, int(ing[item]))
	queue.append({"recipe": recipe_id, "left": time_of(recipe_id)})
	queue_changed.emit()
	return Check.OK


## Отменяет позицию очереди и возвращает ингредиенты. Возвращает число предметов,
## которые не поместились в инвентарь (они теряются — игрока об этом предупреждает интерфейс).
func cancel(index: int, inv: Inventory) -> int:
	if index < 0 or index >= queue.size():
		return 0
	var rid: String = String(queue[index]["recipe"])
	queue.remove_at(index)
	var lost: int = 0
	var ing: Dictionary = ingredients(rid)
	for item: String in ing:
		lost += inv.add(item, int(ing[item]))
	queue_changed.emit()
	return lost


## Продвигает первую позицию очереди.
func tick(delta: float, inv: Inventory) -> void:
	if queue.is_empty():
		return
	var head: Dictionary = queue[0]
	var left: float = float(head["left"]) - delta
	head["left"] = maxf(left, 0.0)
	if left > 0.0:
		return
	var rid: String = String(head["recipe"])
	var item: String = result_of(rid)
	var n: int = maxi(JsonData.get_int(recipe(rid), "count", 1), 1)
	if inv.free_space_for(item) < n:
		if not _blocked_reported:
			_blocked_reported = true
			output_blocked.emit(item)
		return
	_blocked_reported = false
	inv.add(item, n)
	queue.remove_at(0)
	crafted.emit(item, n)
	queue_changed.emit()


func to_dict() -> Dictionary:
	var q: Array = []
	for e: Dictionary in queue:
		q.append([e["recipe"], e["left"]])
	return {"queue": q}


func from_dict(d: Dictionary) -> void:
	queue.clear()
	var q: Variant = d.get("queue", [])
	if typeof(q) == TYPE_ARRAY:
		for e: Variant in q:
			if typeof(e) == TYPE_ARRAY and (e as Array).size() >= 2 and _recipes.has(String(e[0])):
				queue.append({"recipe": String(e[0]), "left": maxf(float(e[1]), 0.0)})
	queue_changed.emit()
