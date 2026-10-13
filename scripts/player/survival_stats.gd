class_name SurvivalStats
extends RefCounted
## Здоровье, голод, жажда. Чистая логика без сцен (data/balance/survival.json).
## Голод и жажда убывают со временем; на нуле отнимают здоровье; при сытости здоровье восстанавливается.

signal died(cause: String)

const DEFAULT_PATH: String = "res://data/balance/survival.json"

var max_health: float = 100.0
var max_hunger: float = 100.0
var max_thirst: float = 100.0
var health: float = 100.0
var hunger: float = 75.0
var thirst: float = 75.0

var _cfg: Dictionary = {}
var _dead: bool = false


func configure(cfg: Dictionary) -> void:
	_cfg = cfg
	max_health = JsonData.get_float(cfg, "max_health", 100.0)
	max_hunger = JsonData.get_float(cfg, "max_hunger", 100.0)
	max_thirst = JsonData.get_float(cfg, "max_thirst", 100.0)
	reset_new_game()


func reset_new_game() -> void:
	health = minf(JsonData.get_float(_cfg, "start_health", max_health), max_health)
	hunger = minf(JsonData.get_float(_cfg, "start_hunger", max_hunger), max_hunger)
	thirst = minf(JsonData.get_float(_cfg, "start_thirst", max_thirst), max_thirst)
	_dead = false


func reset_for_respawn() -> void:
	health = JsonData.get_float(_cfg, "respawn_health", 60.0)
	hunger = JsonData.get_float(_cfg, "respawn_hunger", 50.0)
	thirst = JsonData.get_float(_cfg, "respawn_thirst", 50.0)
	_dead = false


func is_dead() -> bool:
	return _dead


func param(key: String, fallback: float) -> float:
	return JsonData.get_float(_cfg, key, fallback)


func tick(delta: float) -> void:
	if _dead or delta <= 0.0:
		return
	var minutes: float = delta / 60.0
	hunger = maxf(hunger - param("hunger_per_min", 1.5) * minutes, 0.0)
	thirst = maxf(thirst - param("thirst_per_min", 2.2) * minutes, 0.0)
	var dmg: float = 0.0
	var cause: String = ""
	if hunger <= 0.0:
		dmg += param("starve_damage_per_min", 4.0) * minutes
		cause = "hunger"
	if thirst <= 0.0:
		dmg += param("dehydrate_damage_per_min", 5.0) * minutes
		cause = "thirst"
	if dmg > 0.0:
		damage(dmg, cause)
	elif hunger >= param("regen_min_hunger", 40.0) and thirst >= param("regen_min_thirst", 40.0):
		health = minf(health + param("regen_per_min", 2.0) * minutes, max_health)


func damage(amount: float, cause: String) -> void:
	if _dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_dead = true
		died.emit(cause)


## Урон от падения по скорости приземления (м/с). Возвращает нанесённый урон.
func fall_damage_for(speed: float) -> float:
	var safe: float = param("fall_safe_speed", 10.0)
	if speed <= safe:
		return 0.0
	return (speed - safe) * param("fall_damage_per_mps", 9.0)


func eat(food: Dictionary) -> void:
	hunger = minf(hunger + JsonData.get_float(food, "hunger", 0.0), max_hunger)
	thirst = minf(thirst + JsonData.get_float(food, "thirst", 0.0), max_thirst)
	health = minf(health + JsonData.get_float(food, "health", 0.0), max_health)


func drink() -> void:
	thirst = minf(thirst + param("drink_amount", 20.0), max_thirst)


func to_dict() -> Dictionary:
	return {"health": health, "hunger": hunger, "thirst": thirst}


func from_dict(d: Dictionary) -> void:
	health = clampf(JsonData.get_float(d, "health", health), 0.0, max_health)
	hunger = clampf(JsonData.get_float(d, "hunger", hunger), 0.0, max_hunger)
	thirst = clampf(JsonData.get_float(d, "thirst", thirst), 0.0, max_thirst)
	# Сохранение с нулевым здоровьем (вылет в момент гибели) — сразу считаем погибшим.
	_dead = health <= 0.0
