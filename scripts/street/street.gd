extends Node3D
## 街道主场景：低多边形日本小镇、Stray 式第三人称跟拍、
## 举起相机对准物体「拍照」学单词（Shashingo 式核心循环）。
## 批次 1/2：接入 GraphicsTier 画质分档 + TimeOfDay 时间系统。

var map := {}
var world_m := Vector2(100, 100)
var objects: Array[Interactable] = []
var player: Player
var cam: Camera3D
var popup: WordPopup
var joystick: VirtualJoystick
var minimap: MiniMap
var counter_label: Label
var shoot_btn: Button
var hint_panel: Control
var crosshair: Control
var flash_rect: ColorRect
var highlighted: Interactable = null
var quest_btn: Button
var quest_panel: QuestPanel
var quest_tracker: QuestTracker

var env: Environment
var sun: DirectionalLight3D
var tod: TimeOfDay
var grade_layer: CanvasLayer
var grade_rect: ColorRect
var grade_mat: ShaderMaterial
var tier: int = GraphicsTier.Tier.MEDIUM

var _hl_timer := 0.0
var _last_saved_pos := Vector3.ZERO
var _pending_tap := Vector2.INF
# 轻点检测（含拖动转视角），在 _input 层处理，避免事件路由差异导致转不动视角
var _look_active := false
var _look_start := Vector2.ZERO
var _look_last := Vector2.ZERO
var _look_moved := 0.0
var _shoot_cd := 0.0


func _ready() -> void:
	var f := FileAccess.open("res://data/map.json", FileAccess.READ)
	if f:
		map = JSON.parse_string(f.get_as_text())
	var world_arr: Array = map.get("world", [4000, 4000])
	world_m = Vector2(world_arr[0] * Interactable.S, world_arr[1] * Interactable.S)

	_setup_grade()
	_setup_environment()
	_setup_floor()

	var ground := GroundBuilder.new()
	ground.setup(map.get("ground", {}), world_m, map.get("objects", []))
	add_child(ground)

	for obj: Dictionary in map.get("objects", []):
		var it := Interactable.make(obj)
		add_child(it)
		objects.append(it)

	# 电线杆之间拉电线
	var poles: Array[Vector3] = []
	for it in objects:
		if it.kind == "pole":
			poles.append(it.position)
	Interactable.build_wires(self, poles)

	player = Player.new()
	var spawn_arr: Array = map.get("spawn", [2000, 900])
	var spawn := Vector3(spawn_arr[0] * Interactable.S, 0.1, spawn_arr[1] * Interactable.S)
	if Game.has_last_position and Game.last_position.x > 0 and Game.last_position.y > 0:
		var lp := Vector3(Game.last_position.x * Interactable.S, 0.1, Game.last_position.y * Interactable.S)
		player.position = Vector3(
			clampf(lp.x, 2.0, world_m.x - 2.0), 0.1,
			clampf(lp.z, 2.0, world_m.y - 2.0))
	else:
		player.position = spawn
	# 出生点若卡进建筑碰撞体，逐步外推，避免物理去重把玩家弹飞（瞬移）
	var space := get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 0.3
	for attempt in 10:
		var qp := PhysicsShapeQueryParameters3D.new()
		qp.shape = probe
		qp.collision_mask = 1
		qp.transform = Transform3D(Basis(), player.position + Vector3(0, 0.3, 0))
		if space.intersect_shape(qp, 1).is_empty():
			break
		player.position.z += 1.1
	_last_saved_pos = player.position
	add_child(player)
	cam = player.cam
	cam.make_current()

	_spawn_petals()
	_build_hud()
	# 场景搭完后再扫自发光材质 —— 此时所有 Interactable 的 _ready 都跑完了
	if tod != null:
		tod.scan_emissives(self)
	Game.word_discovered.connect(func(_id): _update_counter())
	Game.xp_changed.connect(func(_t, _l): _update_counter())
	Quests.tracking_changed.connect(_refresh_quest_tracking)
	_update_counter()
	_refresh_quest_tracking()
	_run_debug_hooks()


func _setup_environment() -> void:
	# 画质档位：设置页可覆盖，否则按机型嗅探
	tier = int(Game.settings.get("gfx_tier", -1))
	if tier < 0:
		tier = GraphicsTier.detect()

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 太阳：唯一投射实时阴影的光源（规格约束：只照地面 + 建筑）
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-11, 96, 0)   # 黄昏低角度 → 长影
	sun.light_color = Color(1.0, 0.66, 0.38)
	sun.light_energy = 1.15
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)

	# 反向补光：模拟天空/城市 bounced light，避免暗部死黑。不投影。
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24, 148, 0)
	fill.light_color = Color(0.72, 0.82, 1.0)
	fill.light_energy = 0.22
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	add_child(fill)

	# 后处理栈 + 分档
	GraphicsTier.apply(env, sun, tier)

	# 时间系统驱动全部光影
	tod = TimeOfDay.new()
	tod.grade_mat = grade_mat
	add_child(tod)
	tod.setup(sun, env, we, fill)
	# 首次进入用瞬时切换（避免开局 15 秒的过场动画），之后切换走 15s 插值
	tod.set_phase(int(Game.settings.get("time_phase", TimeOfDay.Phase.DUSK)), true)
	_register_street_lights()


## 批次 2：街道人工光布局。
## 规格要求 6~10 盏暖光（灯笼/灯箱/窗户）+ 3~5 盏冷光（招牌/贩卖机）。
## 中档只允许 3 盏 omni 参与光照 —— 所以按距离挑最近的 N 盏，其余只留自发光。
func _register_street_lights() -> void:
	var warm_spots: Array[Vector3] = []
	var cool_spots: Array[Vector3] = []

	for it in objects:
		match it.kind:
			# 暖光：拉面店灯箱 / 居酒屋 / 民居窗户 / 咖啡馆
			"ramen", "cafe", "house", "mansion", "konbini":
				warm_spots.append(it.position + Vector3(0, 2.4, 2.0))
			# 冷光：自动贩卖机灯箱 / 便利店招牌 / 信号灯 / 路灯
			"vending", "traffic", "streetlight", "signboard":
				cool_spots.append(it.position + Vector3(0, 1.9, 0.9))

	# 均匀取样 + 按档位截断，保证暖冷光在街上分布开而不是挤在一处
	var warm_n := mini(warm_spots.size(), GraphicsTier.omni_budget(tier) * 2)
	var cool_n := mini(cool_spots.size(), GraphicsTier.omni_budget(tier))
	for i in _spread(warm_spots, warm_n):
		var l := OmniLight3D.new()
		l.position = warm_spots[i]
		l.light_color = Color(1.0, 0.75, 0.35)     # 规格指定的暖黄
		l.omni_range = 6.5
		l.omni_attenuation = 1.4
		l.light_energy = 0.0                        # 由 TimeOfDay 按时刻点亮
		l.shadow_enabled = false                    # 规格：点光不投实时阴影
		add_child(l)
		tod.register_warm(l)
	for i in _spread(cool_spots, cool_n):
		var c := OmniLight3D.new()
		c.position = cool_spots[i]
		c.light_color = Color(0.85, 0.92, 1.0)
		c.omni_range = 4.5
		c.omni_attenuation = 1.8
		c.light_energy = 0.0
		c.shadow_enabled = false
		add_child(c)
		tod.register_cool(c)

	# 夜晚会亮的自发光物体：统一在场景搭完后由 scan_emissives 扫（见 _ready），
	# 这里只额外处理几个「必须是 UNSHADED 自发光」的关键物件。
	for it in objects:
		match it.kind:
			"vending":
				pass  # 灯箱已用 m_glow()，会被扫描捕获


## 从 n 个位置里均匀取样 count 个（避免灯光全挤在数组开头）
func _spread(src: Array[Vector3], count: int) -> Array[int]:
	var out: Array[int] = []
	if src.is_empty() or count <= 0:
		return out
	var n := mini(count, src.size())
	for i in n:
		out.append(int(round(float(i) * float(src.size() - 1) / maxf(1.0, float(n - 1)))))
	return out


## 批次 1：全屏调色层（Vignette / 色差 / 颗粒）。
## Godot 4.4 的 Environment 没有 vignette_* 属性（4.3+ 拆走了），只能自建。
func _setup_grade() -> void:
	grade_layer = CanvasLayer.new()
	grade_layer.layer = 100# 压在 HUD 之上、UI 之下
	add_child(grade_layer)
	grade_rect = ColorRect.new()
	grade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade_mat = ShaderMaterial.new()
	grade_mat.shader = load("res://assets/shaders/grade.gdshader")
	# 按档位调强度：低档关色差和颗粒
	grade_mat.set_shader_parameter("vignette_strength", 0.3)
	grade_mat.set_shader_parameter("chromatic", 0.08 if tier != GraphicsTier.Tier.LOW else 0.0)
	grade_mat.set_shader_parameter("grain", 0.02 if tier != GraphicsTier.Tier.LOW else 0.0)
	grade_rect.material = grade_mat
	grade_layer.add_child(grade_rect)
	if tod != null:
		tod.grade_mat = grade_mat


## 供设置页实时切档。灯光点位数变了要重建，环境参数重刷。
func apply_tier(t: int) -> void:
	tier = clampi(t, 0, 2)
	if env != null and sun != null:
		GraphicsTier.apply(env, sun, tier)
	if grade_mat != null:
		grade_mat.set_shader_parameter("chromatic", 0.08 if tier != GraphicsTier.Tier.LOW else 0.0)
		grade_mat.set_shader_parameter("grain", 0.02 if tier != GraphicsTier.Tier.LOW else 0.0)
	# 点光数量超预算时把多出来的关掉（保留最靠前的 N 盏）
	_budget_omni()


## 供设置页切换时刻（15 秒插值，不跳变）
func apply_time_phase(p: int) -> void:
	if tod != null:
		tod.set_phase(p, false)


## 按档位裁剪 omni 点光数量：高档 6 / 中档 3 / 低档 1
func _budget_omni() -> void:
	var cap := GraphicsTier.omni_budget(tier)
	var idx := 0
	for c in get_children():
		if c is OmniLight3D:
			idx += 1
			c.visible = idx <= cap


func _setup_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	floor_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(cs)
	add_child(floor_body)


func _spawn_petals() -> void:
	var sakura_points: Array[Vector3] = []
	for it in objects:
		if it.kind == "sakura":
			sakura_points.append(it.position)
			if sakura_points.size() >= 4:
				break
	# 花瓣是薄片不是球：SphereMesh 会变成一颗颗小球
	var petal_mesh := QuadMesh.new()
	petal_mesh.size = Vector2(0.055, 0.075)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.97, 0.78, 0.85, 0.92)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED   # 薄片要双面可见
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	pmat.roughness = 0.9
	pmat.vertex_color_use_as_albedo = true
	petal_mesh.material = pmat
	for p in sakura_points:
		var pt := CPUParticles3D.new()
		pt.position = p + Vector3(0, 3.4, 0)
		pt.amount = 22
		pt.lifetime = 6.5
		pt.preprocess = 6.5
		pt.mesh = petal_mesh
		pt.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		pt.emission_sphere_radius = 1.5
		pt.direction = Vector3(0.15, -1, 0.05)
		pt.spread = 32.0
		# 花瓣很轻，下落要慢、要被风推着飘
		pt.gravity = Vector3(0.12, -0.28, 0.05)
		pt.initial_velocity_min = 0.2
		pt.initial_velocity_max = 0.65
		pt.angular_velocity_min = -140.0
		pt.angular_velocity_max = 140.0
		pt.damping_min = 0.4
		pt.damping_max = 1.1
		pt.scale_amount_min = 0.7
		pt.scale_amount_max = 1.15
		pt.color = Color(0.97, 0.75, 0.84, 0.9)
		# 尾段淡出，避免花瓣悬在半空突然消失
		pt.color_ramp = _petal_fade()
		add_child(pt)


## 花瓣渐变：尾段淡出（CPUParticles3D.color_ramp 要的是 Gradient）
func _petal_fade() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.75, 0.9, 1.0])
	g.colors = PackedColorArray([
		Color(0.98, 0.8, 0.87, 0.95),
		Color(0.96, 0.74, 0.83, 0.85),
		Color(0.95, 0.72, 0.81, 0.45),
		Color(0.95, 0.7, 0.8, 0.0)])
	return g


# ---------------- HUD ----------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	# 左下虚拟摇杆（小区域，右半屏留给转视角）
	joystick = VirtualJoystick.new()
	joystick.idle_center = Vector2(90, 90)
	joystick.anchor_left = 0.0
	joystick.anchor_top = 1.0
	joystick.anchor_right = 0.0
	joystick.anchor_bottom = 1.0
	joystick.offset_left = 0
	joystick.offset_top = -300
	joystick.offset_right = 300
	joystick.offset_bottom = 0
	layer.add_child(joystick)
	joystick.moved.connect(func(v: Vector2): player.input_vec = v)
	joystick.released.connect(func(): player.input_vec = Vector2.ZERO)

	# 右下「拍照」按钮
	shoot_btn = Button.new()
	shoot_btn.text = "拍照"
	shoot_btn.focus_mode = Control.FOCUS_NONE
	shoot_btn.add_theme_font_override("font", UiKit.font())
	shoot_btn.add_theme_font_size_override("font_size", 28)
	shoot_btn.add_theme_color_override("font_color", UiKit.WHITE)
	shoot_btn.add_theme_color_override("font_hover_color", UiKit.WHITE)
	shoot_btn.add_theme_color_override("font_pressed_color", UiKit.WHITE)
	var bn := StyleBoxFlat.new()
	bn.bg_color = Color("c94f4f", 0.92)
	bn.set_corner_radius_all(60)
	bn.border_color = Color(1, 1, 1, 0.85)
	bn.set_border_width_all(4)
	var bd := bn.duplicate()
	bd.bg_color = Color("a83e3e", 0.95)
	var bh := bn.duplicate()
	bh.bg_color = Color("d66363", 0.95)
	shoot_btn.add_theme_stylebox_override("normal", bn)
	shoot_btn.add_theme_stylebox_override("hover", bh)
	shoot_btn.add_theme_stylebox_override("pressed", bd)
	shoot_btn.anchor_left = 1.0
	shoot_btn.anchor_right = 1.0
	shoot_btn.anchor_top = 1.0
	shoot_btn.anchor_bottom = 1.0
	shoot_btn.offset_left = -166
	shoot_btn.offset_top = -166
	shoot_btn.offset_right = -36
	shoot_btn.offset_bottom = -36
	shoot_btn.pressed.connect(_on_shoot_pressed)
	layer.add_child(shoot_btn)

	# 右下「跳」按钮：放在拍照键正上方。Stray 的猫能跳上垃圾桶/长椅/窗台，
	# 这是探索感的一半，所以跳跃必须是屏幕上有独立按钮，不能只靠键盘。
	var jump_btn := Button.new()
	jump_btn.text = "跳"
	jump_btn.focus_mode = Control.FOCUS_NONE
	jump_btn.add_theme_font_override("font", UiKit.font())
	jump_btn.add_theme_font_size_override("font_size", 30)
	jump_btn.add_theme_color_override("font_color", UiKit.WHITE)
	jump_btn.add_theme_color_override("font_hover_color", UiKit.WHITE)
	jump_btn.add_theme_color_override("font_pressed_color", UiKit.WHITE)
	var jn := StyleBoxFlat.new()
	jn.bg_color = Color(0.24, 0.4, 0.62, 0.9)     # 蓝，与朱红拍照键区分
	jn.set_corner_radius_all(50)
	jn.border_color = Color(1, 1, 1, 0.8)
	jn.set_border_width_all(3)
	var jp := jn.duplicate()
	jp.bg_color = Color(0.16, 0.28, 0.46, 0.95)
	var jh := jn.duplicate()
	jh.bg_color = Color(0.32, 0.5, 0.74, 0.95)
	jump_btn.add_theme_stylebox_override("normal", jn)
	jump_btn.add_theme_stylebox_override("hover", jh)
	jump_btn.add_theme_stylebox_override("pressed", jp)
	jump_btn.anchor_left = 1.0
	jump_btn.anchor_right = 1.0
	jump_btn.anchor_top = 1.0
	jump_btn.anchor_bottom = 1.0
	jump_btn.offset_left = -150
	jump_btn.offset_top = -280
	jump_btn.offset_right = -52
	jump_btn.offset_bottom = -182
	# button_down / button_up 而不是 pressed：pressed 只在抬起时触发，做可变跳跃高度会失灵
	jump_btn.button_down.connect(func():
		player.jump_pressed = true
		player.jump_held = true)
	jump_btn.button_up.connect(func():
		player.jump_held = false
		player.jump_pressed = false)
	layer.add_child(jump_btn)

	# 左上菜单
	var menu_btn := UiKit.icon_button("≡ 菜单", 22)
	menu_btn.anchor_left = 0.0
	menu_btn.anchor_right = 0.0
	menu_btn.offset_left = 18
	menu_btn.offset_top = 14
	menu_btn.pressed.connect(_on_menu_pressed)
	layer.add_child(menu_btn)

	# 左上「任务」按钮（在菜单下方）：打开任务面板，可接取 / 追踪
	quest_btn = UiKit.icon_button("任务", 22)
	quest_btn.anchor_left = 0.0
	quest_btn.anchor_right = 0.0
	quest_btn.offset_left = 18
	quest_btn.offset_top = 62
	quest_btn.pressed.connect(_on_quest_pressed)
	layer.add_child(quest_btn)

	# 右上进度
	var chip := PanelContainer.new()
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(0.13, 0.14, 0.19, 0.72)
	chip_style.set_corner_radius_all(14)
	chip_style.content_margin_left = 16
	chip_style.content_margin_right = 16
	chip_style.content_margin_top = 7
	chip_style.content_margin_bottom = 7
	chip.add_theme_stylebox_override("panel", chip_style)
	chip.anchor_left = 1.0
	chip.anchor_right = 1.0
	chip.offset_left = -196
	chip.offset_right = -18
	chip.offset_top = 14
	counter_label = UiKit.label("", 20, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	chip.add_child(counter_label)
	layer.add_child(chip)

	# 右上小地图：分类色点 + 玩家箭头；点开放大图（带图例），找家具区用
	minimap = MiniMap.new()
	minimap.setup(world_m, objects, player)
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.anchor_top = 0.0
	minimap.anchor_bottom = 0.0
	minimap.offset_right = -18.0
	minimap.offset_left = -18.0 - MiniMap.SMALL_SIZE.x
	minimap.offset_top = 60.0
	minimap.offset_bottom = 60.0 + MiniMap.SMALL_SIZE.y
	layer.add_child(minimap)

	# 追踪条（左上）：当前任务目标 + 距离 + 指向航点的罗盘箭头
	quest_tracker = QuestTracker.new()
	quest_tracker.player = player
	layer.add_child(quest_tracker)

	# 中央十字准星
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	layer.add_child(crosshair)

	# 拍照白闪
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash_rect)

	# 引导提示
	hint_panel = PanelContainer.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.13, 0.14, 0.19, 0.8)
	hs.set_corner_radius_all(14)
	hs.content_margin_left = 20
	hs.content_margin_right = 20
	hs.content_margin_top = 9
	hs.content_margin_bottom = 9
	hint_panel.add_theme_stylebox_override("panel", hs)
	hint_panel.anchor_left = 0.5
	hint_panel.anchor_right = 0.5
	hint_panel.anchor_top = 1.0
	hint_panel.anchor_bottom = 1.0
	hint_panel.offset_left = -310
	hint_panel.offset_right = 310
	hint_panel.offset_bottom = -30
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_label := UiKit.label("左下摇杆走路 · 拖动屏幕转视角 · 对准发光的物体按【拍照】", 19, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_child(hint_label)
	hint_panel.visible = not bool(Game.settings.get("tutorial_done", false))
	layer.add_child(hint_panel)

	popup = WordPopup.new()
	layer.add_child(popup)
	popup.closed.connect(func():
		player.input_locked = false
		player.input_vec = Vector2.ZERO
	)

	# 任务面板：压在最上层（打开时暂停移动）
	quest_panel = QuestPanel.new()
	layer.add_child(quest_panel)


func _draw_crosshair() -> void:
	var c := crosshair.size * 0.5
	crosshair.draw_circle(c, 3.0, Color(1, 1, 1, 0.9))
	crosshair.draw_arc(c, 14.0, 0, TAU, 32, Color(0, 0, 0, 0.25), 3.0)
	crosshair.draw_arc(c, 14.0, 0, TAU, 32, Color(1, 1, 1, 0.55), 1.4)


# ---------------- 每帧逻辑 ----------------

func _process(delta: float) -> void:
	player.input_locked = popup.visible or quest_panel.visible
	_shoot_cd = maxf(0.0, _shoot_cd - delta)
	_hl_timer += delta
	if _hl_timer >= 0.12:
		_hl_timer = 0.0
		_update_highlight()
	var d3 := player.position.distance_to(_last_saved_pos)
	if d3 > 1.0:
		_last_saved_pos = player.position
		Game.set_position(Vector2(player.position.x / Interactable.S, player.position.z / Interactable.S))


func _update_highlight() -> void:
	if popup.visible:
		return
	var best: Interactable = null
	var best_d := INF
	for it in objects:
		if it.no_draw or it.word_id.is_empty() or not it.in_range_of(player.position):
			continue
		var d := player.position.distance_to(it.position)
		if d < best_d:
			best_d = d
			best = it
	if highlighted != best:
		if highlighted != null and is_instance_valid(highlighted):
			highlighted.set_highlight(false)
		highlighted = best
		if highlighted != null:
			highlighted.set_highlight(true)


# ---------------- 触摸：拖动转视角 / 轻点拍摄（_input 层，路由无关） ----------------

func _in_joystick_zone(p: Vector2) -> bool:
	return joystick != null and joystick.get_global_rect().has_point(p)


## 小地图区域不参与转视角（点它 = 放大/收起地图）
func _in_minimap_zone(p: Vector2) -> bool:
	return minimap != null and minimap.get_global_rect().has_point(p)


func _input(event: InputEvent) -> void:
	if popup.visible or quest_panel.visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _in_joystick_zone(event.position) or _in_minimap_zone(event.position):
				return
			_look_active = true
			_look_start = event.position
			_look_last = event.position
			_look_moved = 0.0
		else:
			if _look_active and _look_moved < 16.0:
				_pending_tap = _look_start
			_look_active = false
	elif event is InputEventScreenDrag:
		if not _look_active:
			return
		if _in_joystick_zone(event.position) or _in_minimap_zone(event.position):
			return
		# 用引擎给的相对增量，并对单次跳变限幅，杜绝坐标基准不一致造成的视角瞬移
		var d: Vector2 = event.relative
		if d == Vector2.ZERO:
			d = event.position - _look_last
		_look_last = event.position
		if d.length() > 90.0:
			d = d.normalized() * 90.0
		_look_moved += d.length()
		player.look(d.x, d.y)


func _physics_process(_delta: float) -> void:
	Quests.tick(player.position)
	if _pending_tap.x != INF:
		var tp := _pending_tap
		_pending_tap = Vector2.INF
		_resolve_tap(tp)


# ---------------- 拍摄 ----------------

func _flash() -> void:
	flash_rect.color.a = 0.55
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 0.22)


## 拍摄指定物体：白闪 + 快门音 + 单词卡
func _shoot(it: Interactable) -> void:
	if it == null or it.word_id.is_empty() or _shoot_cd > 0.0:
		return
	_shoot_cd = 0.45
	_flash()
	Game.play_sfx("shutter")
	open_word(it)


## 十字准星拍摄：优先最近的可学物体，其次准星射线（可拍到地面类词条）
func _on_shoot_pressed() -> void:
	if popup.visible:
		return
	if highlighted != null:
		_shoot(highlighted)
		return
	var hit := _ray_from_screen(crosshair.size * 0.5)
	if hit != null and hit.in_range_of(player.position):
		_shoot(hit)
	else:
		Toast.show_once(self, "附近没有可拍摄的单词，走近一点吧")


## 轻点拍摄：只有点到看得见的物体（非隐形标记）才响应
func _resolve_tap(screen_pos: Vector2) -> void:
	var it := _ray_from_screen(screen_pos)
	if it == null or it.no_draw or it.word_id.is_empty():
		return
	if not it.in_range_of(player.position):
		if it.interact_range > 0.0:
			Toast.show_once(self, "再走近一点才能拍清楚哦")
		return
	_shoot(it)


func _ray_from_screen(screen_pos: Vector2) -> Interactable:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 90.0, 4)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit["collider"] as Interactable


func open_word(it: Interactable) -> void:
	if it.word_id.is_empty():
		return
	var is_new := Game.discover(it.word_id)
	if is_new:
		Game.play_sfx("discover")
		if not bool(Game.settings.get("tutorial_done", false)):
			Game.settings["tutorial_done"] = true
			Game.save_soon()
			hint_panel.visible = false
	Game.play_sfx("open")
	player.input_locked = true
	popup.show_word(Game.word(it.word_id), is_new)
	_update_highlight.call_deferred()


func _update_counter() -> void:
	counter_label.text = "单词 %d / %d   Lv.%d" % [
		Game.discovered_count(), Game.total_words(), Game.player_level()]
	_refresh_quest_button()


func _refresh_quest_button() -> void:
	if quest_btn == null:
		return
	var n := Quests.active_count()
	quest_btn.text = "任务 %d" % n if n > 0 else "任务"


## 刷新 HUD 追踪条 + 小地图航点（追踪目标或跑腿步进变化时调用）
func _refresh_quest_tracking() -> void:
	if quest_tracker == null:
		return
	var q := Quests.tracked_quest()
	var wp: Variant = Quests.tracked_waypoint()
	quest_tracker.set_quest(String(q.get("title_zh", "")), Quests.objective_text(), wp)
	if minimap != null:
		minimap.set_waypoint(wp)
	_refresh_quest_button()


func _on_quest_pressed() -> void:
	player.input_vec = Vector2.ZERO
	quest_panel.open()


func _on_menu_pressed() -> void:
	Game.save_now()
	Tts.stop()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			Game.save_now()
			if what == NOTIFICATION_WM_GO_BACK_REQUEST:
				get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ---------------- 自动化截图钩子 ----------------

## 通用物件检视钩子（match 里的 "look" 分支用）：
## 用法 --shot-action=look:<kind> [;<dx>;<dz>;<dist>;<pitch>]
## 自动找到该 kind 的第一个实例，把玩家摆到它附近并按指定距离摆相机。
## 之前给每种物件手写死坐标，一旦 map.json 挪位就拍到空地 —— 改成按节点定位，
## 坐标永远跟着数据走。默认：南侧 4m、俯视 0.35、相机臂 5m。
## 【GDScript 坑】注释不能放在 match 体第一个分支之前（会报
## "Expected indented block after match pattern block"），所以说明写在 match 外面。

func _run_debug_hooks() -> void:
	var action := ShotTool.shot_action
	if not action.is_empty():
		print("[hooks] action=", action)
	# 通用物件检视：--shot-action=look:<kind> [;<dx>;<dz>;<dist>;<pitch>]
	# 【为什么必须在 match 之前】match 是整串相等比较，"look" 永远匹配不上
	# "look:bench;1.5;..."，所以不能写成 match 的一个分支。
	# 参数形如 "look:bench;1.6;-2.4;3.0;-0.28"
	# 【坑】分隔符是 ";"，但前缀和 kind 之间是 ":"，所以先 substr(5) 砍掉
	# "look:" 再按 ";" 切 —— 直接 action.split(";") 拿到的第 0 段是
	# "look:bench"，判断 == "look" 永远不成立，整段静默跳过。
	var args: Array = []
	if action.begins_with("look:"):
		args = action.substr(5).split(";")
	if args.size() > 0:
		var want := str(args[0])
		var dx := float(args[1]) if args.size() > 1 else 0.0
		var dz := float(args[2]) if args.size() > 2 else -4.0
		var dist := float(args[3]) if args.size() > 3 else 5.0
		var pit := float(args[4]) if args.size() > 4 else -0.35
		var hit: Interactable = null
		for it in objects:
			if it.kind == want or it.word_id == want:
				hit = it
				break
		if hit != null:
			var spot := hit.position + Vector3(dx, 0.1, dz)
			player.teleport(spot, 0.0)
			player.look_pitch = pit
			# 面向目标：cam_forward() = (-sin(yaw), 0, -cos(yaw))，
			# 反解出yaw = atan2(-dx, -dz)（注意两个分量都要取负）。
			var to_obj := hit.position + Vector3(0, 0.5, 0) - spot
			player.look_yaw = atan2(-to_obj.x, -to_obj.z)
			player._apply_cam_rotation()
			player._arm.spring_length = dist
			print("[look] %s @%s -> stand %s, cam_len %.1f" % [
				want, str(hit.position), str(spot), dist])
		else:
			print("[look] 没找到 kind=", want)
		return
	match action:
		"demo_popup":
			player.teleport(Vector3(56.5, 0.1, 29.5), PI * 0.0)
			var target: Interactable = null
			for it in objects:
				if it.word_id == "vending":
					target = it
					break
			if target != null:
				await get_tree().process_frame
				await get_tree().process_frame
				open_word(target)
		"demo_park":
			player.teleport(Vector3(82.5, 0.1, 46.0), 0.0)
		# 仰视树冠：检查叶片/樱花冠贴图材质
		"demo_leaf":
			player.teleport(Vector3(84.5, 0.1, 44.5), PI * 0.75)
			player.look_pitch = 0.55
			player._apply_cam_rotation()
		"demo_station":
			player.teleport(Vector3(48.5, 0.1, 20.5), 0.0)
		"demo_cross":
			player.teleport(Vector3(31.5, 0.1, 23.0), 0.35)
		"demo_shop":
			player.teleport(Vector3(11.25, 0.1, 28.5), 0.0)
		"demo_sign":
			player.teleport(Vector3(50, 0.1, 17.5), 0.0)
		"demo_back":
			player.teleport(Vector3(50, 0.1, 17.0), PI)
		# 侧视：检查猫的建模与腿/尾
		"demo_cat_side":
			player.teleport(Vector3(82.5, 0.1, 46.0), 0.0)
			player.look_pitch = -0.06
			player.look_yaw = PI * 0.5
			player._apply_cam_rotation()
		# 正脸：相机绕到猫前面（look_yaw = 角色朝向 + PI），检查脸/朝向/模型是否装反
		"demo_cat_front":
			player.teleport(Vector3(82.5, 0.1, 46.0), 0.0)
			player.look_pitch = -0.16
			player.look_yaw = PI
			player._apply_cam_rotation()
			player._arm.spring_length = 0.72
		# 街边的狗（Quaternius 柴犬 + Idle 动画）
		# 【钩子坐标规律】站在物件正上方、pitch 压到 -0.8 俯视。
		# 之前把玩家放在物件南侧 3m，相机退到 -Z 侧容易一头撞进墙里（拍到一片砖）。
		"demo_dog":
			player.teleport(Vector3(22.5, 0.1, 13.6), 0.0)
			player.look_pitch = -0.8
			player.look_yaw = PI
			player._apply_cam_rotation()
		# 街边停车（Kenney 车）
		"demo_car":
			player.teleport(Vector3(17.5, 0.1, 27.9), 0.0)
			player.look_pitch = -0.62
			player.look_yaw = PI
			player._apply_cam_rotation()
		# 家具（Kenney 桌/椅）：站物件南侧、相机退后 3.5m，
		# 弹簧臂默认只有 1.32m，不拉长的话镜头会怼在猫身上什么都看不见。
		"demo_props":
			player.teleport(Vector3(52.5, 0.1, 23.2), 0.0)
			player.look_pitch = -0.34
			player.look_yaw = PI
			player._apply_cam_rotation()
			player._arm.spring_length = 3.6
		# 和式床 / 洗衣机一带的家具
		"demo_bed":
			player.teleport(Vector3(76.0, 0.1, 86.6), 0.0)
			player.look_pitch = -0.3
			player.look_yaw = PI
			player._apply_cam_rotation()
			player._arm.spring_length = 3.6
		# 街头的猫 NPC（用玩家猫的外观）
		"demo_catnpc":
			player.teleport(Vector3(11.25, 0.1, 40.4), 0.0)
			player.look_pitch = -0.55
			player.look_yaw = PI
			player._apply_cam_rotation()
		# 行走中：检查步态动画
		"demo_cat_walk":
			player.teleport(Vector3(50.0, 0.1, 40.0), 0.0)
			player.look_yaw = PI * 0.72
			player._apply_cam_rotation()
			player.input_vec = Vector2(0.0, -1.0)
		# 特写：怼到猫脸前看建模细节
		"demo_cat_face":
			player.teleport(Vector3(82.5, 0.1, 46.0), 0.0)
			player.look_pitch = -0.12
			player._apply_cam_rotation()
			player._arm.spring_length = 0.62
		"demo_cat_face_back":
			player.teleport(Vector3(82.5, 0.1, 46.0), PI)
			player.look_pitch = -0.12
			player._apply_cam_rotation()
			player._arm.spring_length = 0.62
		# 跳跃验证：站在可跳物件（井盖/长椅/花坛）旁，起跳瞬间抓拍
		"demo_jump":
			# 优先找新加的矮物件，它们的台面高度就是猫的跳跃目标
			var target: Interactable = null
			for kind in ["pipe", "planter", "lowwall", "bench", "crate", "trash"]:
				for it in objects:
					if it.kind == kind:
						target = it
						break
				if target != null:
					break
			if target != null:
				# 站远一点、退一步，相机拉远，才能看清猫和台面的相对高度
				player.teleport(target.position + Vector3(1.6, 0.1, 1.9), 0.0)
				player.look_pitch = -0.30
				player.look_yaw = PI * 0.78
				player._apply_cam_rotation()
				player._arm.spring_length = 1.9
			# 模拟一次跳跃（停在上升途中）
			player.velocity.y = Player.JUMP_VELOCITY
			player._coyote = Player.COYOTE

		# 批次 7 道具检视：燃气罐 + 垃圾袋（饮食店后巷）
		"demo_props_back":
			player.teleport(Vector3(15.2, 0.1, 53.2), -0.58)
			player.look_pitch = -0.08
			player._apply_cam_rotation()
		# 批次 7 道具检视：晾衣杆 + 盆栽 + 垃圾袋（民宅旁）
		"demo_props_laundry":
			player.teleport(Vector3(116.6, 0.1, 49.2), -0.52)
			player.look_pitch = -0.06
			player._apply_cam_rotation()
			player._arm.spring_length = 2.0
		# 批次 7 道具检视：路锥 + 消火栓 + 水洼 + 井盖（路口西南）
		"demo_props_road":
			player.teleport(Vector3(21.0, 0.1, 76.5), 0.28)
			player.look_pitch = -0.2
			player._apply_cam_rotation()
		# 四时刻对照：--shot-action=demo_tod_morning/day/dusk/night
		"demo_tod_dusk", "demo_tod_night", "demo_tod_day", "demo_tod_morning":
			player.teleport(Vector3(50.0, 0.1, 30.0), 0.0)
			player.look_pitch = -0.16
			player._apply_cam_rotation()
			var ph := TimeOfDay.Phase.DUSK
			if action.ends_with("night"):
				ph = TimeOfDay.Phase.NIGHT
			elif action.ends_with("day"):
				ph = TimeOfDay.Phase.DAY
			elif action.ends_with("morning"):
				ph = TimeOfDay.Phase.MORNING
			tod.set_phase(ph, true)   # 瞬时切换，截图用
