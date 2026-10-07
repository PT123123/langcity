extends Control
## 主菜单：标题 + 四个入口，和纸灯笼配色，樱花飘落。

var _lib_btn: Button
var _t := 0.0
## 3D 悬浮岛是否接管了背景。false 时保持原来的纯矢量街景。
var _island_up := false


func _ready() -> void:
	theme = UiKit.theme()

	# 3D 悬浮岛背景。必须最先加：子节点的绘制顺序决定谁压谁，
	# 它是全屏的底层，樱花粒子和按钮 UI 都要画在它上面。
	_setup_island()

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

	var title := UiKit.label("日语星球", 76, UiKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title)

	var sub := UiKit.label("小さな星の町を歩いて、日本語を学ぼう", 22, Color("aeb4c8"), HORIZONTAL_ALIGNMENT_CENTER)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(sub)
	vbox.add_child(UiKit.vspace(26))

	var start := UiKit.button("▶  登上星球", true, 28)
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

	# 章节：《罗生门·岭南篇》（独立剧情场景，见 docs/rashomon_game_chapter_spec_guangdong.md）
	var chapter := UiKit.button("◆ 章节・罗生门 岭南篇", false, 25)
	chapter.custom_minimum_size = Vector2(0, 56)
	chapter.pressed.connect(func():
		Game.save_now()
		Tts.stop()
		get_tree().change_scene_to_file("res://scenes/rashomon.tscn"))
	vbox.add_child(chapter)

	vbox.add_child(UiKit.vspace(14))
	var footer := UiKit.label("离线可玩 · 进度保存在本机", 15, Color("7d8298"), HORIZONTAL_ALIGNMENT_CENTER)
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(footer)

	_refresh_lib_btn()
	Game.word_discovered.connect(func(_id): _refresh_lib_btn())


func _refresh_lib_btn() -> void:
	_lib_btn.text = "词汇库   %d / %d" % [Game.discovered_count(), Game.total_words()]


## 铺一层全屏 3D 背景：SubViewportContainer → SubViewport → 悬浮岛。
## 任何一步失败都把整层清掉并保留矢量街景 —— 主菜单不能因为美术资源没到位就开天窗。
func _setup_island() -> void:
	var holder := SubViewportContainer.new()
	holder.name = "IslandLayer"
	# 全屏铺满；IGNORE 才不会把樱花粒子和按钮的鼠标事件吃掉
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.stretch = true
	add_child(holder)

	var vp := SubViewport.new()
	vp.name = "IslandViewport"
	# 美术资源（Draco→glB）是另一条线在出，产物没到位时必须安静降级，不能报错
	vp.own_world_3d = true
	# 手动物理世界没必要，也省掉一份 3D 物理的开销
	vp.physics_object_picking = false
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	holder.add_child(vp)

	vp.add_child(_make_world_env())
	vp.add_child(_make_sun())

	var island := MenuIsland.new()
	vp.add_child(island)
	if not island.build():
		# 一个可用模型都没有：拆掉整层，回到矢量街景
		holder.queue_free()
		queue_redraw()
		return

	_island_up = true
	queue_redraw()


## SubViewport 自带 3D 世界，但没有 WorldEnvironment —— 天空和环境光得自己搭。
## 配色沿用 TimeOfDay 的黄昏预设（柔和蓝顶 + 暖白地平线），
## 氛围光必须取自天空（AMBIENT_SOURCE_SKY），否则阴面会死黑。
func _make_world_env() -> WorldEnvironment:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.46, 0.56, 0.70)
	sky_mat.sky_horizon_color = Color(0.93, 0.85, 0.74)
	sky_mat.ground_bottom_color = Color(0.30, 0.28, 0.30)
	sky_mat.ground_horizon_color = Color(0.78, 0.72, 0.64)
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# 主菜单不想要后期。主菜单是静态构图，glow/SSAO 在这里只会添噪点。
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_white = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	env.fog_light_color = Color(0.90, 0.85, 0.79)
	env.fog_density = 0.004
	env.fog_light_energy = 0.7

	var we := WorldEnvironment.new()
	we.name = "IslandEnv"
	we.environment = env
	return we


## 暖色主光。悬浮岛悬在半空、要读出体积，侧上 45° 打得比街面平一点，
## 阴影开着但压软，主菜单里不做剧烈的明暗对比。
func _make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "IslandSun"
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.1
	sun.light_specular = 0.0   # Messenger 视觉：画面里没有高光
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.rotation_degrees = Vector3(-38.0, 42.0, 0.0)
	return sun


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# 悬浮岛接管背景时，这层矢量街景必须让位 —— 否则等于在 3D 岛上又画一张
	# 2D 街景，两层背景叠在一起。
	if _island_up:
		return
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
