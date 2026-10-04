class_name ProceduralTex
extends RefCounted
## 程序纹理 v2：更真实的材质图案 + user:// 磁盘缓存（首次生成，之后秒加载）。
## 灰度图案 + albedo_color 调色，配合三平面世界映射与高度视差。

static var _cache := {}
const CACHE_DIR := "user://tex_cache"


static func _img(size: int) -> Image:
	return Image.create(size, size, false, Image.FORMAT_RGB8)


## 值噪声：cells 网格随机值 + 双线性插值
static func _value_noise(img: Image, rng: RandomNumberGenerator, cells: int, amp: float) -> void:
	var s := img.get_width()
	var grid: Array = []
	for y in cells + 1:
		var row: Array = []
		for x in cells + 1:
			row.append(rng.randf_range(-amp, amp))
		grid.append(row)
	var cw := float(s) / cells
	for py in s:
		var gy := py / cw
		var y0 := int(gy)
		var fy := gy - y0
		fy = fy * fy * (3.0 - 2.0 * fy)
		var r0: Array = grid[y0]
		var r1: Array = grid[y0 + 1]
		for px in s:
			var gx := px / cw
			var x0 := int(gx)
			var fx := gx - x0
			fx = fx * fx * (3.0 - 2.0 * fx)
			var v: float = lerpf(lerpf(r0[x0], r0[x0 + 1], fx), lerpf(r1[x0], r1[x0 + 1], fx), fx)
			var c := img.get_pixel(px, py)
			c = Color(clampf(c.r + v, 0, 1), clampf(c.g + v, 0, 1), clampf(c.b + v, 0, 1))
			img.set_pixel(px, py, c)


static func _speckle(img: Image, rng: RandomNumberGenerator, amount: float, cell := 1) -> void:
	var s := img.get_width()
	var y := 0
	while y < s:
		var x := 0
		while x < s:
			var v := rng.randf_range(-amount, amount)
			var c := img.get_pixel(x, y)
			c = Color(clampf(c.r + v, 0, 1), clampf(c.g + v, 0, 1), clampf(c.b + v, 0, 1))
			for dy in cell:
				for dx in cell:
					if x + dx < s and y + dy < s:
						img.set_pixel(x + dx, y + dy, c)
			x += cell
		y += cell


static func _blotches(img: Image, rng: RandomNumberGenerator, color: Color, count: int, rmin: float, rmax: float) -> void:
	var s := img.get_width()
	for i in count:
		var cx := rng.randf_range(0, s)
		var cy := rng.randf_range(0, s)
		var r := rng.randf_range(rmin, rmax)
		var y := int(cy - r)
		while y <= cy + r:
			var x := int(cx - r)
			while x <= cx + r:
				var dx := x - cx
				var dy := y - cy
				if dx * dx + dy * dy <= r * r:
					img.set_pixel((x + s) % s, (y + s) % s, color)
				x += 1
			y += 1


static func _cracks(img: Image, rng: RandomNumberGenerator, count: int, dark := 0.62) -> void:
	var s := img.get_width()
	for i in count:
		var x := rng.randf_range(0, s)
		var y := rng.randf_range(0, s)
		var ang := rng.randf_range(0, TAU)
		for step in rng.randi_range(40, 120):
			ang += rng.randf_range(-0.35, 0.35)
			x = wrapf(x + cos(ang) * 2.0, 0, s)
			y = wrapf(y + sin(ang) * 2.0, 0, s)
			var c := img.get_pixel(int(x) % s, int(y) % s)
			var v := c.r * dark
			img.set_pixel(int(x) % s, int(y) % s, Color(v, v, v))
			if rng.randf() < 0.35:
				var xx := (int(x) % s) + rng.randi_range(-2, 2)
				var yy := (int(y) % s) + rng.randi_range(-2, 2)
				var c2 := img.get_pixel((xx + s) % s, (yy + s) % s)
				var v2 := c2.r * (dark + 0.15)
				img.set_pixel((xx + s) % s, (yy + s) % s, Color(v2, v2, v2))


# ---------------- 各纹理 ----------------

## 柏油：多层噪声 + 骨料 + 裂纹 + 补丁
static func asphalt(seed_v: int) -> ImageTexture:
	var key := "asphalt_%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var cached := _load_cache(key)
	if cached != null:
		return cached
	var img := _img(256)
	img.fill(Color(0.5, 0.5, 0.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	_value_noise(img, rng, 4, 0.05)
	_value_noise(img, rng, 16, 0.045)
	_speckle(img, rng, 0.13)
	_blotches(img, rng, Color(0.42, 0.42, 0.42), 20, 4.0, 14.0)
	_blotches(img, rng, Color(0.6, 0.6, 0.6), 14, 3.0, 9.0)
	_cracks(img, rng, 4)
	var tex := _save_cache(key, img)
	_cache[key] = tex
	return tex


## 铺装砖（人行道）：逐砖明暗 + 勾缝 + 污渍
static func pavers(seed_v: int) -> ImageTexture:
	var key := "pavers_%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var cached := _load_cache(key)
	if cached != null:
		return cached
	var s := 256
	var img := _img(s)
	img.fill(Color(0.88, 0.88, 0.88))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var tile := 32
	var ty := 0
	while ty < s:
		var tx := 0
		while tx < s:
			var shade := rng.randf_range(0.86, 1.0)
			for yy in tile:
				for xx in tile:
					var edge := 1.0
					if xx < 2 or yy < 2:
						edge = 0.66
					elif xx < 3 or yy < 3:
						edge = 0.85
					var v := clampf(shade * edge, 0.0, 1.0)
					img.set_pixel(tx + xx, ty + yy, Color(v, v, v))
			tx += tile
		ty += tile
	_value_noise(img, rng, 8, 0.035)
	_speckle(img, rng, 0.04)
	_blotches(img, rng, Color(0.8, 0.8, 0.8), 10, 5.0, 16.0)
	var tex := _save_cache(key, img)
	_cache[key] = tex
	return tex


## 和瓦屋顶：逐片瓦明暗 + 受光边 + 瓦沟阴影
static func roof_tiles(seed_v: int) -> ImageTexture:
	var key := "roof_%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var cached := _load_cache(key)
	if cached != null:
		return cached
	var s := 256
	var img := _img(s)
	img.fill(Color(0.85, 0.85, 0.85))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var row_h := 32
	var col_w := 48
	var y := 0
	while y < s:
		var x := 0
		while x < s:
			var shade := rng.randf_range(0.82, 1.0)
			for yy in row_h:
				var fy := float(yy) / row_h
				var v := shade * (0.72 + 0.3 * fy)
				if yy > row_h - 4:
					v *= 0.6
				for xx in col_w:
					var fx := float(xx) / col_w
					var vv := clampf(v * (0.92 + 0.16 * (1.0 - absf(fx - 0.5) * 2.0)), 0.0, 1.0)
					img.set_pixel((x + xx) % s, (y + yy) % s, Color(vv, vv, vv))
			x += col_w
		y += row_h
	_value_noise(img, rng, 10, 0.03)
	_speckle(img, rng, 0.035)
	var tex := _save_cache(key, img)
	_cache[key] = tex
	return tex


## 外墙小口瓷砖（商店/公寓）：细格 + 逐砖色差 + 勾缝
static func wall_tiles(seed_v: int) -> ImageTexture:
	var key := "walltiles_%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var cached := _load_cache(key)
	if cached != null:
		return cached
	var s := 256
	var img := _img(s)
	img.fill(Color(0.9, 0.9, 0.9))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var t := 16
	var ty := 0
	while ty < s:
		var tx := 0
		while tx < s:
			var shade := rng.randf_range(0.9, 1.0)
			for yy in t:
				for xx in t:
					var v := shade
					if xx == 0 or yy == 0:
						v = shade * 0.62
					img.set_pixel(tx + xx, ty + yy, Color(v, v, v))
			tx += t
		ty += t
	_speckle(img, rng, 0.03)
	var tex := _save_cache(key, img)
	_cache[key] = tex
	return tex


## 外墙抹灰
static func plaster(seed_v: int) -> ImageTexture:
	var key := "plaster_%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var cached := _load_cache(key)
	if cached != null:
		return cached
	var img := _img(256)
	img.fill(Color(0.92, 0.92, 0.92))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	_value_noise(img, rng, 12, 0.03)
	_speckle(img, rng, 0.03)
	_blotches(img, rng, Color(0.86, 0.86, 0.86), 18, 3.0, 10.0)
	var tex := _save_cache(key, img)
	_cache[key] = tex
	return tex


## 木纹板条：木板明暗 + 木纹丝 + 节疤
static func wood(seed_v: int) -> ImageTexture:
	var key := "wood_%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var cached := _load_cache(key)
	if cached != null:
		return cached
	var s := 256
	var img := _img(s)
	img.fill(Color(0.9, 0.9, 0.9))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var plank := 42
	for y in s:
		var shade := rng.randf_range(0.86, 1.0)
		if (y % plank) < 2:
			shade *= 0.55
		elif (y % plank) < 4:
			shade *= 1.08
		for x in s:
			var grain := 0.04 * sin(float(x) * 0.35 + float(y % plank) * 0.8)
			var v := clampf(shade + grain + rng.randf_range(-0.02, 0.02), 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	for i in 5:
		var kx := rng.randi_range(8, s - 8)
		var ky := rng.randi_range(0, s - 1)
		for r in 4:
			for dx in range(-r, r + 1):
				for dy in range(-r, r + 1):
					if dx * dx + dy * dy <= r * r:
						var px := (kx + dx) % s
						var py := (ky + dy) % s
						var c := img.get_pixel(px, py)
						var v := c.r * 0.72
						img.set_pixel(px, py, Color(v, v, v))
	var tex := _save_cache(key, img)
	_cache[key] = tex
	return tex


## 草地：三色斑块 + 草叶点
static func grass(seed_v: int) -> ImageTexture:
	var key := "grass_%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var cached := _load_cache(key)
	if cached != null:
		return cached
	var img := _img(256)
	img.fill(Color(0.86, 0.9, 0.82))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	_value_noise(img, rng, 6, 0.05)
	_blotches(img, rng, Color(0.76, 0.84, 0.68), 34, 5.0, 20.0)
	_blotches(img, rng, Color(0.95, 0.98, 0.9), 22, 3.0, 12.0)
	var y := 0
	while y < 256:
		var x := 0
		while x < 256:
			if rng.randf() < 0.06:
				var c := img.get_pixel(x, y)
				var v := clampf(c.r * rng.randf_range(0.8, 1.15), 0, 1)
				img.set_pixel(x, y, Color(v, v, v))
			x += 1
		y += 1
	var tex := _save_cache(key, img)
	_cache[key] = tex
	return tex


## 程序天空全景图（渐变 + 云），给 PanoramaSkyMaterial
static func sky_panorama() -> ImageTexture:
	var key := "sky"
	if _cache.has(key):
		return _cache[key]
	var cached := _load_cache(key)
	if cached != null:
		return cached
	var w := 1024
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for y in h:
		var fy := float(y) / h
		var col: Color
		if fy < 0.55:
			var t := fy / 0.55
			col = Color(0.29, 0.53, 0.79).lerp(Color(0.83, 0.88, 0.92), pow(t, 0.8))
		else:
			var t := (fy - 0.55) / 0.45
			col = Color(0.83, 0.88, 0.92).lerp(Color(0.62, 0.67, 0.6), t)
		for x in w:
			img.set_pixel(x, y, col)
	var cloud: Array = []
	var cells := 12
	for cy in cells + 1:
		var row: Array = []
		for cx in cells + 1:
			row.append(rng.randf())
		cloud.append(row)
	var cw := float(w) / cells
	var ch := float(h * 0.55) / cells
	for y in int(h * 0.55):
		var gy := y / ch
		var y0 := int(gy)
		var fy := gy - y0
		fy = fy * fy * (3.0 - 2.0 * fy)
		var r0: Array = cloud[y0]
		var r1: Array = cloud[y0 + 1]
		for x in w:
			var gx := x / cw
			var x0 := int(gx)
			var fx := gx - x0
			fx = fx * fx * (3.0 - 2.0 * fx)
			var v: float = lerpf(lerpf(r0[x0], r0[x0 + 1], fx), lerpf(r1[x0], r1[x0 + 1], fx), fx)
			var cover := clampf((v - 0.45) * 3.2, 0.0, 1.0)
			if cover > 0.01:
				var base := img.get_pixel(x, y)
				var fade := 1.0 - float(y) / (h * 0.55) * 0.35
				var c := base.lerp(Color(0.97, 0.97, 0.98), cover * 0.85 * fade)
				img.set_pixel(x, y, c)
	var tex := _save_cache(key, img)
	_cache[key] = tex
	return tex


# ---------------- 磁盘缓存 ----------------

static func _load_cache(key: String) -> ImageTexture:
	var path := CACHE_DIR + "/" + key + ".png"
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _save_cache(key: String, img: Image) -> ImageTexture:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	img.save_png(ProjectSettings.globalize_path(CACHE_DIR + "/" + key + ".png"))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
