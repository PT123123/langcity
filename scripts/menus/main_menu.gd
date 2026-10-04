extends Control
## 主菜单：标题 + 四个入口，和纸灯笼配色，樱花飘落。

var _lib_btn: Button
var _t := 0.0


func _ready() -> void:
	theme = UiKit.theme()

	# 樱花花瓣
	var petals := CPUParticles2D.new()
	petals.position = Vector2(640, -30)
	petals.amount = 26
	petals.lifetime = 9.0
	petals.preprocess = 9.0
	petals.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	petals.emission_rect_extents = Vector2(700, 8)
	petals.direction = Vector2(0, 1)
	petals.spread = 12.0
	petals.gravity = Vector2(6, 22)
	petals.initial_velocity_min = 24.0
	petals.initial_velocity_max = 60.0
	petals.scale_amount_min = 2.0
	petals.scale_amount_max = 4.0
	petals.color = Color(0.96, 0.66, 0.78, 0.8)
	add_child(petals)

	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -220
	vbox.offset_right = 220
	vbox.offset_top = -250
	vbox.offset_bottom = 250
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	add_child(vbox)

	var title := UiKit.label("日语街道", 76, UiKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title)

	var sub := UiKit.label("日本の町を歩いて、日本語を学ぼう", 22, Color("aeb4c8"), HORIZONTAL_ALIGNMENT_CENTER)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(sub)
	vbox.add_child(UiKit.vspace(26))

	var start := UiKit.button("▶  开始探索", true, 28)
	start.custom_minimum_size = Vector2(0, 62)
	start.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/street.tscn"))
	vbox.add_child(start)

	_lib_btn = UiKit.button("词汇库", false, 25)
	_lib_btn.custom_minimum_size = Vector2(0, 56)
	_lib_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/vocabulary.tscn"))
	vbox.add_child(_lib_btn)

	var review := UiKit.button("复习", false, 25)
	review.custom_minimum_size = Vector2(0, 56)
	review.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/review.tscn"))
	vbox.add_child(review)

	var settings := UiKit.button("设置", false, 25)
	settings.custom_minimum_size = Vector2(0, 56)
	settings.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/settings.tscn"))
	vbox.add_child(settings)

	vbox.add_child(UiKit.vspace(14))
	var footer := UiKit.label("离线可玩 · 进度保存在本机", 15, Color("7d8298"), HORIZONTAL_ALIGNMENT_CENTER)
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(footer)

	_refresh_lib_btn()
	Game.word_discovered.connect(func(_id): _refresh_lib_btn())


func _refresh_lib_btn() -> void:
	_lib_btn.text = "词汇库   %d / %d" % [Game.discovered_count(), Game.total_words()]


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# ---- 装饰街景（纯矢量） ----
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.NAVY)
	var road_y := h - 86.0

	# 远处建筑剪影
	var sil := Color("343a4e")
	var rects := [
		[0.06, 0.30, 0.10], [0.18, 0.22, 0.14], [0.55, 0.26, 0.12],
		[0.70, 0.34, 0.10], [0.84, 0.24, 0.13],
	]
	for r: Array in rects:
		var bw := w * float(r[2])
		var bh := h * float(r[1])
		var bx := w * float(r[0])
		draw_rect(Rect2(bx, road_y - bh, bw, bh), sil)
		# 亮着的窗
		for i in 4:
			for j in 2:
				if int(i * 3.7 + j * 7.3 + r[0] * 10.0) % 3 != 0:
					continue
				draw_rect(Rect2(bx + 14 + i * (bw - 30) / 4.0, road_y - bh + 16 + j * 30, 10, 14), Color("4d5470"))
	# 电线杆
	draw_rect(Rect2(w * 0.40, road_y - 150, 7, 150), Color("3c4258"))
	draw_rect(Rect2(w * 0.40 - 14, road_y - 140, 35, 5), Color("3c4258"))
	draw_rect(Rect2(w * 0.72, road_y - 170, 7, 170), Color("3c4258"))
	draw_rect(Rect2(w * 0.72 - 14, road_y - 158, 35, 5), Color("3c4258"))
	# 电线
	draw_polyline(PackedVector2Array([
		Vector2(w * 0.40, road_y - 136), Vector2(w * 0.56, road_y - 108), Vector2(w * 0.72, road_y - 154)
	]), Color("3c4258"), 2.0)

	# 马路 + 车道线
	draw_rect(Rect2(0, road_y, w, h - road_y), Color("3a3d47"))
	var x := 20.0
	while x < w:
		draw_rect(Rect2(x, road_y + (h - road_y) * 0.5 - 3, 42, 6), Color("5d6070"))
		x += 110.0

	# 路边自动贩卖机
	var vx := w - 190.0
	var vy := road_y - 6.0
	draw_rect(Rect2(vx, vy - 128, 70, 128), Color("c9463f"), 6.0)
	draw_rect(Rect2(vx + 8, vy - 118, 34, 76), Color("f4efe4"))
	for row in 3:
		for col in 2:
			var cols := [Color("5b8def"), Color("e6b84c"), Color("7fb069"), Color("d64541")]
			draw_rect(Rect2(vx + 11 + col * 16, vy - 114 + row * 24, 12, 16), cols[(row * 2 + col) % 4])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(vx + 48, vy - 114, 14, 66), Color(0.12, 0.13, 0.18, 0.5))

	# 鸟居
	var tx := w * 0.14
	var ty := road_y - 6.0
	var torii := Color("c94f4f")
	draw_rect(Rect2(tx - 60, ty - 150, 160, 14), torii)          # 笠木
	draw_rect(Rect2(tx - 50, ty - 128, 140, 10), torii)          # 贯
	draw_rect(Rect2(tx - 38, ty - 118, 18, 118), torii)          # 左柱
	draw_rect(Rect2(tx + 60, ty - 118, 18, 118), torii)          # 右柱

	# 樱花树（右上）
	var sx := w - 110.0
	var sy := road_y - 10.0
	draw_rect(Rect2(sx - 6, sy - 70, 12, 70), Color("4a4038"))
	var bloom := Color(0.96, 0.66, 0.78, 0.9)
	var bloom2 := Color(0.98, 0.78, 0.87, 0.9)
	draw_circle(Vector2(sx, sy - 108), 46, bloom)
	draw_circle(Vector2(sx - 38, sy - 84), 32, bloom2)
	draw_circle(Vector2(sx + 36, sy - 88), 34, bloom)
	draw_circle(Vector2(sx + 6, sy - 132), 26, bloom2)
	# 微微呼吸
	var pulse := 1.0 + 0.02 * sin(_t * 1.6)
	draw_circle(Vector2(sx, sy - 108), 46 * pulse, Color(1, 1, 1, 0.03))
