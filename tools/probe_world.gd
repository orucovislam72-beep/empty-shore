extends SceneTree
## Отладочный скрипт: доли биомов, место высадки, карта биомов картинкой.
## godot --headless --path . -s res://tools/probe_world.gd -- [--map=user://map.png]
func _initialize() -> void:
	var t0: int = Time.get_ticks_usec()
	var g: WorldGen = WorldGen.load_default()
	var t1: int = Time.get_ticks_usec()
	print("[probe] gen init %.1f ms; landing=%s coast_points=%d" % [(t1 - t0) / 1000.0, g.landing, g.coast_points.size()])
	var sh: Dictionary = g.biome_shares(16.0)
	print("[probe] biome shares (land): ", sh)
	print("[probe] map %.2f km2, land ≈ %.2f km2" % [g.grid.size_m * g.grid.size_m / 1e6, float(sh["land_cells"]) * 256.0 / 1e6])
	var out: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			out = a.substr(6)
	if not out.is_empty():
		_save_map(g, out)
	quit()


func _save_map(g: WorldGen, path: String) -> void:
	var px: int = 320
	var img: Image = Image.create(px, px, false, Image.FORMAT_RGB8)
	var cols: Dictionary = g.cfg.get("colors", {})
	var step: float = g.grid.size_m / float(px)
	for j: int in px:
		for i: int in px:
			var x: float = -g.grid.half + (i + 0.5) * step
			var z: float = -g.grid.half + (j + 0.5) * step
			var h: float = g.height_at(x, z)
			var c: Color
			if h < g.water_level:
				c = Color(0.17, 0.33, 0.42).lerp(Color(0.08, 0.16, 0.24), clampf(-h / 16.0, 0.0, 1.0))
			else:
				var a: Array = cols.get(WorldGen.biome_id(g.biome_after_height(x, z, h)), [1, 0, 1])
				c = Color(float(a[0]), float(a[1]), float(a[2])) * (0.85 + 0.15 * clampf(h / 40.0, 0.0, 1.0))
			img.set_pixel(i, j, c)
	# Чанки — тонкая сетка, точки побережья и высадка.
	for k: int in range(0, px, int(px / g.grid.n)):
		for t: int in px:
			img.set_pixel(k, t, img.get_pixel(k, t).darkened(0.15))
			img.set_pixel(t, k, img.get_pixel(t, k).darkened(0.15))
	for p: Vector3 in g.coast_points:
		var cx: int = int((p.x + g.grid.half) / step)
		var cz: int = int((p.z + g.grid.half) / step)
		img.fill_rect(Rect2i(cx - 2, cz - 2, 5, 5), Color(0.95, 0.85, 0.3))
	var lx: int = int((g.landing.x + g.grid.half) / step)
	var lz: int = int((g.landing.z + g.grid.half) / step)
	img.fill_rect(Rect2i(lx - 4, lz - 4, 9, 9), Color(0.9, 0.2, 0.2))
	print("[probe] map -> %s (%s)" % [path, error_string(img.save_png(path))])
