class_name ChunkCodec
extends RefCounted
## Двоичная запись чанков мира в сохранении (формат v3, см. docs/ROADMAP.md, этап 3, решение 2).
## Вход и выход — словарь, совместимый с JSON: {"cx,cz": {"r": [...], "l": [...], "c": [...], "p": [...], "d": [...]}}.
## Запись чанка: i16 cx, i16 cz, u8 число разделов, затем разделы «u8 тег, u32 длина, данные»
## (неизвестный тег пропускается по длине — так новые версии смогут добавлять разделы).
##  1 r — узлы: u16 n × (u16 номер в чанке, u16 запас, f32 секунд до восстановления)
##  2 l — точки лута: u16 n × (u16 номер, f32 секунд до наполнения, u16 бросков, хранилище)
##  3 c — мешки и туши: u16 n × (строка вид, f32 x, y, z, поворот, срок, строка владелец, u16 ячеек, хранилище)
##  4 p — детали построек, 5 d — объекты: u16 n × (u32 порядковый номер, u32 длина, var_to_bytes(запись))
## Хранилище: u8 n × (u8 ячейка, строка id, u16 количество, i32 прочность). Строки — put_utf8_string.
## Числа little-endian (StreamPeerBuffer по умолчанию).

const TAG_RESOURCES: int = 1
const TAG_LOOT: int = 2
const TAG_CONTAINERS: int = 3
const TAG_PIECES: int = 4
const TAG_DEPLOYABLES: int = 5
const TAGS: Dictionary = {"r": TAG_RESOURCES, "l": TAG_LOOT, "c": TAG_CONTAINERS, "p": TAG_PIECES, "d": TAG_DEPLOYABLES}


static func encode_chunks(buf: StreamPeerBuffer, chunks: Dictionary) -> void:
	var keys: Array = []
	for k: Variant in chunks:
		var c: Vector2i = ChunkGrid.parse_key(String(k))
		if c.x >= 0 and typeof(chunks[k]) == TYPE_DICTIONARY and not (chunks[k] as Dictionary).is_empty():
			keys.append(k)
	buf.put_u32(keys.size())
	for k: Variant in keys:
		var c2: Vector2i = ChunkGrid.parse_key(String(k))
		buf.put_16(c2.x)
		buf.put_16(c2.y)
		var ch: Dictionary = chunks[k]
		var tags: Array = []
		for t: String in TAGS:
			if typeof(ch.get(t)) == TYPE_ARRAY and not (ch[t] as Array).is_empty():
				tags.append(t)
		buf.put_u8(tags.size())
		for t2: String in tags:
			var sec: StreamPeerBuffer = StreamPeerBuffer.new()
			_encode_section(sec, int(TAGS[t2]), ch[t2])
			buf.put_u8(int(TAGS[t2]))
			buf.put_u32(sec.data_array.size())
			buf.put_data(sec.data_array)


static func _encode_section(b: StreamPeerBuffer, tag: int, list: Array) -> void:
	b.put_u16(list.size())
	for e: Variant in list:
		var a: Array = e
		match tag:
			TAG_RESOURCES:
				b.put_u16(int(a[0]))
				b.put_u16(int(a[1]))
				b.put_float(float(a[2]))
			TAG_LOOT:
				b.put_u16(int(a[0]))
				b.put_float(float(a[1]))
				b.put_u16(int(a[3]) if a.size() > 3 else 0)
				_put_storage(b, a[2] if typeof(a[2]) == TYPE_DICTIONARY else {})
			TAG_CONTAINERS:
				b.put_utf8_string(String(a[0]))
				for f: int in range(1, 6):
					b.put_float(float(a[f]))
				b.put_utf8_string(String(a[6]))
				b.put_u16(int(a[8]) if a.size() > 8 else 34)
				_put_storage(b, a[7] if typeof(a[7]) == TYPE_DICTIONARY else {})
			_:
				var bytes: PackedByteArray = var_to_bytes(a[1])
				b.put_u32(int(a[0]))
				b.put_u32(bytes.size())
				b.put_data(bytes)


static func _put_storage(b: StreamPeerBuffer, d: Dictionary) -> void:
	var slots: Array = d.get("slots", []) if typeof(d.get("slots")) == TYPE_ARRAY else []
	b.put_u8(mini(slots.size(), 255))
	for i: int in mini(slots.size(), 255):
		var s: Array = slots[i]
		b.put_u8(int(s[0]))
		b.put_utf8_string(String(s[1]))
		b.put_u16(int(s[2]))
		b.put_32(int(s[3]))


static func _get_storage(b: StreamPeerBuffer) -> Dictionary:
	var n: int = b.get_u8()
	var slots: Array = []
	for i: int in n:
		var slot: int = b.get_u8()
		var id: String = b.get_utf8_string()
		var cnt: int = b.get_u16()
		var dur: int = b.get_32()
		slots.append([slot, id, cnt, dur])
	return {"slots": slots}


## Читает записи чанков. Возвращает {"ok": bool, "chunks": Dictionary}.
static func decode_chunks(buf: StreamPeerBuffer) -> Dictionary:
	var out: Dictionary = {}
	if buf.get_available_bytes() < 4:
		return {"ok": false, "chunks": out}
	var count: int = buf.get_u32()
	for ci: int in count:
		if buf.get_available_bytes() < 5:
			return {"ok": false, "chunks": out}
		var cx: int = buf.get_16()
		var cz: int = buf.get_16()
		var nsec: int = buf.get_u8()
		var ch: Dictionary = {}
		for si: int in nsec:
			if buf.get_available_bytes() < 5:
				return {"ok": false, "chunks": out}
			var tag: int = buf.get_u8()
			var len: int = buf.get_u32()
			if len > buf.get_available_bytes():
				return {"ok": false, "chunks": out}
			var got: Array = buf.get_data(len)
			if int(got[0]) != OK:
				return {"ok": false, "chunks": out}
			var name: String = ""
			for t: String in TAGS:
				if int(TAGS[t]) == tag:
					name = t
			if name.is_empty():
				continue
			var sec: StreamPeerBuffer = StreamPeerBuffer.new()
			sec.data_array = got[1]
			ch[name] = _decode_section(sec, tag)
		out[ChunkGrid.key(Vector2i(cx, cz))] = ch
	return {"ok": true, "chunks": out}


static func _decode_section(b: StreamPeerBuffer, tag: int) -> Array:
	var list: Array = []
	var n: int = b.get_u16()
	for i: int in n:
		match tag:
			TAG_RESOURCES:
				var local: int = b.get_u16()
				var rem: int = b.get_u16()
				list.append([local, rem, snappedf(b.get_float(), 0.01)])
			TAG_LOOT:
				var l2: int = b.get_u16()
				var resp: float = snappedf(b.get_float(), 0.01)
				var rolls: int = b.get_u16()
				list.append([l2, resp, _get_storage(b), rolls])
			TAG_CONTAINERS:
				var kind: String = b.get_utf8_string()
				var f: Array = []
				for k: int in 5:
					f.append(snappedf(b.get_float(), 0.001))
				var owner: String = b.get_utf8_string()
				var size: int = b.get_u16()
				list.append([kind, f[0], f[1], f[2], f[3], f[4], owner, _get_storage(b), size])
			_:
				var order: int = b.get_u32()
				var len: int = b.get_u32()
				var got: Array = b.get_data(len)
				var v: Variant = bytes_to_var(got[1]) if int(got[0]) == OK else null
				if typeof(v) == TYPE_ARRAY:
					list.append([order, v])
	return list
