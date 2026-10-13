class_name WorldSaveFile
extends RefCounted
## Файл сохранения мира, формат v3 (этап 3): один файл <слот>.save, запись через .tmp и переименование.
## Строение:
##   "ESSV" (4 байта) | u16 версия формата | u64 время записи (unix) |
##   u32 длина + JSON без раздела chunks (игрок, инвентарь, крафт, право владения — небольшое и читаемое) |
##   записи чанков (ChunkCodec) | MD5 всего предыдущего (16 байт).
## Один файл — мир и игрок не разойдутся при вылете между записями; MD5 ловит обрезанный/битый файл,
## тогда читается целый .tmp. Старые сохранения (JSON-конверт SaveFile, v1–v2) читает SaveGame и мигрирует.

const MAGIC: PackedByteArray = [0x45, 0x53, 0x53, 0x56]
const TMP_SUFFIX: String = ".tmp"
const HEADER_MIN: int = 4 + 2 + 8 + 4 + 4 + 16

var migrator: SaveMigrator


func _init(p_migrator: SaveMigrator = null) -> void:
	migrator = p_migrator if p_migrator != null else SaveMigrator.new(3)


## Байты файла для data (без записи на диск) — для тестов и замеров.
func encode(data: Dictionary) -> PackedByteArray:
	var meta: Dictionary = data.duplicate(false)
	meta.erase("chunks")
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_data(MAGIC)
	buf.put_u16(migrator.current_version)
	buf.put_u64(int(Time.get_unix_time_from_system()))
	var mb: PackedByteArray = JSON.stringify(meta).to_utf8_buffer()
	buf.put_u32(mb.size())
	buf.put_data(mb)
	var chunks: Variant = data.get("chunks", {})
	ChunkCodec.encode_chunks(buf, chunks if typeof(chunks) == TYPE_DICTIONARY else {})
	var body: PackedByteArray = buf.data_array
	body.append_array(_md5(body))
	return body


static func _md5(bytes: PackedByteArray) -> PackedByteArray:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish()


func write(path: String, data: Dictionary) -> Error:
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if mk != OK:
			return mk
	var bytes: PackedByteArray = encode(data)
	var tmp_path: String = path + TMP_SUFFIX
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.flush()
	var write_err: Error = f.get_error()
	f.close()
	if write_err != OK:
		return write_err
	var err: Error = DirAccess.rename_absolute(tmp_path, path)
	if err != OK and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp_path, path)
	return err


## {"ok": bool, "data": Dictionary, "error": String, "migrated": bool}. При ошибке основного файла — целый .tmp.
func read(path: String) -> Dictionary:
	var res: Dictionary = _read_one(path)
	if not res["ok"] and res["error"] != "save_from_future" and FileAccess.file_exists(path + TMP_SUFFIX):
		var tmp_res: Dictionary = _read_one(path + TMP_SUFFIX)
		if tmp_res["ok"]:
			return tmp_res
	return res


func _read_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("not_found")
	return decode(FileAccess.get_file_as_bytes(path))


func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_MIN or bytes.slice(0, 4) != MAGIC:
		return _fail("corrupt")
	var body: PackedByteArray = bytes.slice(0, bytes.size() - 16)
	if _md5(body) != bytes.slice(bytes.size() - 16):
		return _fail("corrupt")
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = body
	buf.seek(4)
	var version: int = buf.get_u16()
	buf.get_u64()
	var mlen: int = buf.get_u32()
	if mlen > buf.get_available_bytes():
		return _fail("corrupt")
	var got: Array = buf.get_data(mlen)
	var json: JSON = JSON.new()
	if int(got[0]) != OK or json.parse((got[1] as PackedByteArray).get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return _fail("corrupt")
	var data: Dictionary = json.data
	var ch: Dictionary = ChunkCodec.decode_chunks(buf)
	if not ch["ok"]:
		return _fail("corrupt")
	data["chunks"] = ch["chunks"]
	var mig: Dictionary = migrator.migrate(data, version)
	if not mig["ok"]:
		return _fail(String(mig["error"]))
	return {"ok": true, "data": mig["data"], "error": "", "migrated": version != migrator.current_version}


static func _fail(err: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": err, "migrated": false}
