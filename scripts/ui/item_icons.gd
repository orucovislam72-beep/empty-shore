class_name ItemIcons
extends RefCounted
## Кэш иконок предметов (SVG из assets/icons/items, пути — в data/items/items.json).
## Загружает каждую иконку один раз при первом обращении.

var _db: ItemDB
var _cache: Dictionary = {}


func _init(db: ItemDB) -> void:
	_db = db


func get_icon(id: String) -> Texture2D:
	if id.is_empty():
		return null
	if _cache.has(id):
		return _cache[id]
	var path: String = _db.icon_path(id)
	var tex: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	else:
		push_error("ItemIcons: нет иконки для %s (%s)" % [id, path])
	_cache[id] = tex
	return tex
