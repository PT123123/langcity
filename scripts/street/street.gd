extends Node3D
## 街道主场景（3D 第一人称）：低多边形日本小镇、拖动转视角、
## 举起相机对准物体「拍照」学单词（Shashingo 式核心循环）。

var map := {}
var world_m := Vector2(100, 100)
var objects: Array[Interactable] = []
var player: Player
var cam: Camera3D
var popup: WordPopup
var joystick: VirtualJoystick
var counter_label: Label
var shoot_btn: Button
var hint_panel: Control
var crosshair: Control
var flash_rect: ColorRect
var highlighted: Interactable = null

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
	probe.radius = 0.55
	for attempt in 10:
		var qp := PhysicsShapeQueryParameters3D.new()
		qp.shape = probe
		qp.collision_mask = 1
		qp.transform = Transform3D(Basis(), player.position + Vector3(0, 0.6, 0))
		if space.intersect_shape(qp, 1).is_empty():
			break
		player.position.z += 1.1
	_last_saved_pos = player.position
	add_child(player)
	cam = player.cam
	cam.make_current()

	_spawn_petals()
	_build_hud()
	Game.word_discovered.connect(func(_id): _update_counter())
	_update_counter()
	_run_debug_hooks()


func _setup_environment() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = ProceduralTex.sky_panorama()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.03
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	env.fog_enabled = true
	env.fog_light_color = Color("dfe8ec")
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -34, 0)
	sun.light_color = Color(1.0, 0.94, 0.83)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_blur = 1.2
	add_child(sun)


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
	var petal_mesh := SphereMesh.new()
	petal_mesh.radius = 0.045
	petal_mesh.height = 0.09
	for p in sakura_points:
		var pt := CPUParticles3D.new()
		pt.position = p + Vector3(0, 3.4, 0)
		pt.amount = 14
		pt.lifetime = 5.0
		pt.preprocess = 5.0
		pt.mesh = petal_mesh
		pt.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		pt.emission_sphere_radius = 1.3
		pt.direction = Vector3(0, -1, 0)
		pt.spread = 25.0
		pt.gravity = Vector3(0, -0.6, 0)
		pt.initial_velocity_min = 0.3
		pt.initial_velocity_max = 0.9
		pt.angular_velocity_min = -90.0
		pt.angular_velocity_max = 90.0
		pt.color = Color(0.97, 0.72, 0.82, 0.9)
		add_child(pt)


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

	# 左上菜单
	var menu_btn := UiKit.icon_button("≡ 菜单", 22)
	menu_btn.anchor_left = 0.0
	menu_btn.anchor_right = 0.0
	menu_btn.offset_left = 18
	menu_btn.offset_top = 14
	menu_btn.pressed.connect(_on_menu_pressed)
	layer.add_child(menu_btn)

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
	var hint_label := UiKit.label("左下摇杆走路 · 拖动屏幕看四周 · 对准发光的物体按【拍照】", 19, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
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


func _draw_crosshair() -> void:
	var c := crosshair.size * 0.5
	crosshair.draw_circle(c, 3.0, Color(1, 1, 1, 0.9))
	crosshair.draw_arc(c, 14.0, 0, TAU, 32, Color(0, 0, 0, 0.25), 3.0)
	crosshair.draw_arc(c, 14.0, 0, TAU, 32, Color(1, 1, 1, 0.55), 1.4)


# ---------------- 每帧逻辑 ----------------

func _process(delta: float) -> void:
	player.input_locked = popup.visible
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


func _input(event: InputEvent) -> void:
	if popup.visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _in_joystick_zone(event.position):
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
		if _in_joystick_zone(event.position):
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
	counter_label.text = "单词 %d / %d" % [Game.discovered_count(), Game.total_words()]


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

func _run_debug_hooks() -> void:
	match ShotTool.shot_action:
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
