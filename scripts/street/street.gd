extends Node3D
## 世界主场景：小星球上的日本町（球形重力，可绕星球走一整圈）、
## Stray 式第三人称跟拍、举起相机对准物体「拍照」学单词（Shashingo 式核心循环）。
## 室内（int_*）仍是普通重力的独立场景，进出门走 planet ↔ interior 切换。

var map := {}
var world_m := Vector2(100, 100)
var world_px := Vector2(5200, 4000)   # 地图像素尺寸（星球上 = 岛冠展开图）
var planet_math: PlanetMath           # 星球参数；室内为 null（平地）
var planet_builder: PlanetBuilder
var place := {}                     # 当前 place 描述（Places.get_place），星球或室内
var objects: Array[Interactable] = []
var player: Player
var cam: Camera3D
var popup: WordPopup
var joystick: VirtualJoystick
var minimap: MiniMap
var counter_label: Label
## 坐标读数（报障用）：显示玩家所在的地图像素 (x,y)，与 data/planet.json 同一坐标系。
var coord_label: Label
var shoot_btn: Button
var hint_panel: Control
var crosshair: Control
var flash_rect: ColorRect
var highlighted: Interactable = null
var quest_btn: Button
var quest_panel: QuestPanel
var dialogue_box: DialogueBox
var teleport_btn: Button
var teleport_menu: TeleportMenu
var quest_tracker: QuestTracker
var context_btn: Button                 # 上下文动作按钮（靠近传送点/门时显示）
## NPC 巡航控制器（带 patrol 路线的 NPC 各挂一个；编辑器画的路线直接生效）
var _patrols: Array[NpcPatrol] = []
## 被出现时段隐藏的 NPC → 隐藏前的 collision_layer（恢复用）。
## 条目带 appear_phase（TimeOfDay.Phase 数组，空/缺省=全时段），时段不符即隐藏。
var _npc_hidden_layers := {}

var env: Environment
var sun: DirectionalLight3D
var tod: TimeOfDay
## 环境装饰层根节点（纯视觉，不进 objects）。见 _setup_scatter()。
var _scatter_root: Node3D
var grade_layer: CanvasLayer
var grade_rect: ColorRect
var grade_mat: ShaderMaterial
var tier: int = GraphicsTier.Tier.MEDIUM

## 城市的门 → 可进入的室内 place（四类建筑）。未列出的 host（邮局/家具店）不可进入。
const INTERIOR_BY_HOST := {
	"house": "int_house",
	"mansion": "int_apartment",
	"konbini": "int_konbini",
	"super": "int_super",
	"cafe": "int_cafe",
	"ramen": "int_ramen",
	"station": "int_station",
}

var interior_size_px := Vector2(400, 320)     # 当前室内尺寸（px）
var interior_spawn_px := Vector2(200, 320)    # 室内默认出生点（px）：南墙门内一步
var _interior_exit_door: Interactable = null  # 室内出口门

var _hl_timer := 0.0
var _quest_timer := 0.0            # 收集类导航的「最近目标」重算节流
var _quest_target_obj: Interactable = null  # 当前被指路的收集目标（画光圈）
var _word_use := {}                # 基础词 -> 已用次数，用于轮换定语变体
var _last_saved_pos := Vector3.ZERO
## 诊断钩子运行期间为 true：冻结存档写入，保证多次运行起点一致（见 _process）
var _no_save := false
var _sea_toast_shown := false      # 软墙提示只弹一次
## 新档首次进星球时置位：出生点传送要等摆件完成后再做（_teleport_to_kind 依赖 objects）
var _spawn_at_konbini_deferred := false
## 摆件协程（_place_all_objects_deferred）完成标志：teleport 诊断钩子要等它
var _objects_placed := false
var _context_target: Interactable = null  # 当前上下文动作对应的物件
var _context_timer := 0.0
# 拖动转视角，在 _input 层处理，避免事件路由差异导致转不动视角
var _look_active := false
var _look_last := Vector2.ZERO
var _shoot_cd := 0.0
# 聚焦取景模式：第一次按【拍照】变焦对准目标，第二次按快门才真正拍摄。
# 进入时锁移动、隐摇杆，画面 FOV 拉近 + 自动瞄准 + 对焦框；此时仍可拖动屏幕微调。
var focus_mode := false
var _focus_target: Interactable = null
var _aim_tween: Tween
var jump_btn: Button
var cancel_btn: Button
var focus_frame: Control


func _ready() -> void:
	# 场景切换后上一张图的目标缓存（世界坐标）必须失效，否则跑腿航点指到旧图
	Quests.clear_target_cache()
	place = Places.get_place(Game.current_place_id)
	if _is_interior():
		_build_interior()
	else:
		_load_planet_map()

	# 【顺序坑】必须先 _setup_environment() 再 _setup_grade()：
	# _setup_grade() 要按画质档位设暗角/描边强度，而 tier 是在
	# _setup_environment() 里从设置或机型嗅探出来的。之前反着写，
	# tier 还是默认值 1(中档)，于是高档也拿不到高档的描边强度。
	_setup_environment()
	_setup_grade()
	_setup_floor()

	if not _is_interior():
		_build_planet()
		# 【顺序坑·实测确认】_setup_environment() 在 _build_planet() **之前**跑，
		# 所以 TimeOfDay.set_phase() 里调用的 IslandMaterials.set_terrain_tint()
		# 执行时地形材质还没被创建（terrain() 首次调用才建），
		# set_terrain_tint 见缓存无 key 就安全返回 → 色温静默不生效（实测 Δ0）。
		# 这里在建好星球后补一次。
		#
		# 【为什么不能只在 _ready 里补】因为「切时刻」是运行时随时发生的
		# （设置页 15 秒插值 tween、以及 viewshot 的 --view-phase）：
		# 那些切换发生在地形已存在之后，_island_tint 本身是好的。
		# 只有「首次进入」这一条路径需要补 —— 即本处。
		_island_tint_again()
		# 摆件 + 装饰撒点 + 灯光点位全部延后到物理就绪后（见 _build_planet 的时序坑注释）：
		# 前两者都要 surface() 射线，_ready 里打不中会整批挂在 51m 兜底球面上；
		# 灯光点位要从 objects 里挑，必须等物件摆完。
		# call_deferred 起的是协程，_ready 继续往下跑（玩家/HUD 不等摆件）。
		_place_all_objects_deferred.call_deferred()

	player = Player.new()
	player.planet = planet_math   # 室内为 null（平地）；星球上则启用球形重力
	var spawn_yaw := 0.0
	var from_px: Variant = null
	var sc := Game.consume_spawn(Game.current_place_id)
	if not sc.is_empty():
		from_px = sc.get("pos", Vector2.ZERO)
		spawn_yaw = float(sc.get("yaw", 0.0))
	else:
		from_px = Game.position_in(Game.current_place_id)
	if _is_interior():
		var spawn_px := interior_spawn_px
		player.position = Vector3(spawn_px.x * Interactable.S, 0.1, spawn_px.y * Interactable.S)
		if from_px != null:
			var fp: Vector2 = from_px
			player.position = Vector3(fp.x * Interactable.S, 0.1, fp.y * Interactable.S)
	else:
		player.position = _planet_spawn_pos(from_px)
	# 出生点若卡进建筑碰撞体：绕切平面 8 向 × 逐圈加大半径找最近的空位。
	# 【为什么不是原来的单向 10 次】原来只朝一个固定切向推 1.1m×10 —— 存档位置若陷在
	# 大建筑内部，那个方向仍然是墙，推不动就永远卡着（玩家报「出生在房子底下动不了」）。
	# 8 向逐圈还出不来，就兜底搬去便利店门口（已知好地）：宁可换出生点也别卡死。
	var space := get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 0.3
	var up := player.up_axis()
	var east := up.cross(Vector3.UP)
	if east.length_squared() < 0.5:
		east = up.cross(Vector3.RIGHT)
	east = east.normalized()
	var north := east.cross(up).normalized()
	var spawn_origin := player.position
	var escaped := false
	for ring in range(1, 9):
		var rad := float(ring) * 1.0
		for k in 8:
			var ang := TAU * float(k) / 8.0 + 0.618 * float(ring)
			var pos := spawn_origin + (east * cos(ang) + north * sin(ang)) * rad
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = probe
			qp.collision_mask = 1
			qp.transform = Transform3D(Basis(), pos + up * 0.3)
			if space.intersect_shape(qp, 1).is_empty():
				player.position = pos
				escaped = true
				break
		if escaped:
			break
	if not escaped and not _is_interior():
		_spawn_at_konbini_deferred = true
	_last_saved_pos = player.position
	add_child(player)
	# 星球上必须 teleport 一次：把身体/相机框架对齐到出生点的切平面；
	# 室内 yaw=0 时无需（_ready 初始化已对齐），yaw≠0 时沿用旧习惯显式摆位。
	var tp_yaw := spawn_yaw if (not _is_interior() or spawn_yaw != 0.0) else NAN
	player.teleport(player.position, tp_yaw)
	# 【延迟落位】_planet_spawn_pos() 里的 surface() 射线在 _ready() 阶段打不到
	# 地形（物理服务器尚未把 trimesh 同步进宽相），会返回标称球面 r=34×scale=51，
	# 而真实岛面在 r≈35.5 —— 出生点悬空 15m，猫一进世界就自由落体。
	# 这里登记一下，让玩家在第一个物理帧用真射线重新贴地（见 Player._ground_snap）。
	if not _is_interior():
		player.request_ground_snap()
	# 【出生点】存档没有任何位置（新档/首次进星球）→ 出生在便利店门口：
	# 小镇中心的平地（车站贴着坑缘陡坡，不适合落脚）。玩过的存档位置不动
	#（传送一次就会刷新存档位置）。
	# 延后到摆件之后：_teleport_to_kind() 要按 kind 找目标物件算门脸朝向，
	# 此刻 objects 还是空的 → 静默 return，新档会留在悬空的地图默认出生点。
	if not _is_interior() and from_px == null:
		_spawn_at_konbini_deferred = true
	cam = player.cam
	cam.make_current()

	if not _is_interior():
		_spawn_petals()
	_build_hud()
	_apply_hud_mode()
	# 场景搭完后再扫自发光材质 —— 此时所有 Interactable 的 _ready 都跑完了
	if tod != null:
		tod.scan_emissives(self)
	Game.word_discovered.connect(func(_id): _update_counter())
	Game.xp_changed.connect(func(_t, _l): _update_counter())
	Quests.tracking_changed.connect(_refresh_quest_tracking)
	_update_counter()
	_refresh_quest_tracking()
	_run_debug_hooks()
	_fade_in_from_black()


## 切场景后全屏淡入：遮住 300+ 物件重建那一两帧的卡顿（城市与室内、进出室内都走这里）。
func _fade_in_from_black() -> void:
	var l := CanvasLayer.new()
	l.layer = 128
	add_child(l)
	var r := ColorRect.new()
	r.color = Color(0.04, 0.04, 0.06, 1.0)
	r.anchor_right = 1.0
	r.anchor_bottom = 1.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(l.queue_free)


# ---------------- 城市 / 室内 分支 ----------------

func _is_interior() -> bool:
	return String(place.get("kind", "")) == "interior"


## 星球建好后，把当前时刻的地形色温重新写进共享地形材质。
##
## 【为什么需要重复应用】TimeOfDay.set_phase() → _apply_preset() 里已经调过
## IslandMaterials.set_terrain_tint()，但那一刻地形材质**还不存在**
## （_build_planet() 在 _setup_environment() 之后才跑，terrain() 首次调用
## 才创建材质并放进缓存）。set_terrain_tint 遇到缓存里没 key 会安全返回，
## 于是第一次调用静默无效 —— 画面 Δ0。
## 这里在正确的时机补一次。材质是全星球共享单例，所以这次调用只是改两个
## uniform：零遍历、零重建、零 draw call。
func _island_tint_again() -> void:
	if tod == null:
		return
	# 复用 TimeOfDay 自己的插值器：它记着当前 phase 与过渡进度，
	# 直接让它按当前状态再走一次 _apply_preset 是最省事且不会与
	# 15 秒插值 tween 打架的做法。
	if tod.has_method("reapply_terrain_tint"):
		tod.call("reapply_terrain_tint")


func _is_planet() -> bool:
	return not _is_interior()


## 读星球地图（schema 与旧 map.json 兼容：world/spawn/objects；planet 段是星球参数）
func _load_planet_map() -> void:
	var map_path := String(place.get("map", "res://data/planet.json"))
	var f := FileAccess.open(map_path, FileAccess.READ)
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			map = d
	var world_arr: Array = map.get("world", [5200, 4000])
	world_px = Vector2(float(world_arr[0]), float(world_arr[1]))
	world_m = world_px * Interactable.S
	planet_math = PlanetMath.new(map.get("planet", {}))


## 地图像素（默认 spawn 或存档 px）→ 星球表面世界坐标。
## 存档 px 可能来自旧平面城（落在可走边界外/海里），此时回退地图默认 spawn。
func _planet_spawn_pos(from_px: Variant) -> Vector3:
	var px := _map_spawn_px()
	if from_px != null:
		var fp: Vector2 = from_px
		var dir := planet_math.dir_from_px(fp, world_px)
		var phi := acos(clampf(dir.y, -1.0, 1.0))
		if phi <= planet_math.walk_phi:
			px = fp
	var sdir := planet_math.dir_from_px(px, world_px)
	var spot := planet_builder.surface(sdir)
	var up: Vector3 = (spot["normal"] as Vector3).normalized()
	return (spot["pos"] as Vector3) + up * 0.15


func _map_spawn_px() -> Vector2:
	var a: Array = map.get("spawn", [2600, 1500])
	return Vector2(float(a[0]), float(a[1]))


## 搭星球本体 + 把物件逐个摆上球面（射线取落点/法线，切平面对齐）。
## 物件的局部构建代码全部假设「站在自己的 +Y 地面上」，对齐基后零改动复用。
##
## 【时序坑·满岛浮空的根因】摆件依赖 surface() 射线，而射线要打在 PlanetBuilder
## 刚建出来的 trimesh 碰撞上 —— 物理服务器要到【下一个物理帧】才把它同步进宽相。
## 在 _ready 里直接摆，射线全部落空 → surface() 静默走标称球面兜底（r=34×1.5=51），
## 而真实岛面在 r≈35~49 —— 245 个物件整整齐齐挂在 1.3~15.8m 的空中。
## 所以这里只建地形，摆件交给 _place_all_objects_deferred()（延后一帧执行）。
## 实测 1 个物理帧即就绪（_tools/audit_float.tscn 实测，非拍脑袋）。
func _build_planet() -> void:
	planet_builder = PlanetBuilder.new()
	planet_builder.name = "Planet"
	add_child(planet_builder)
	planet_builder.setup(planet_math, map.get("planet", {}))


## 延后到物理帧再摆所有地图物件（真正的摆件在这里，不在 _build_planet）。
## 等一个物理帧让 trimesh 进宽相，然后一次摆对 —— 不做「先兜底摆一遍再重摆」
## 的两段式：那样会让物件节点在 51m 处先存在一帧，既浪费又容易漏掉重摆。
func _place_all_objects_deferred() -> void:
	await get_tree().physics_frame
	for obj: Dictionary in map.get("objects", []):
		var it := Interactable.make(obj)
		_place_on_planet(it, obj)
		_assign_variant_word(it)
		add_child(it)
		objects.append(it)
		if it.kind == "npc" and (it.extra as Dictionary).has("patrol"):
			_attach_patrol(it)
	# 出现时段（appear_phase）按当前时刻显隐；之后每次时段切换重算
	_apply_npc_appearances()


## 按 TimeOfDay.Phase 应用 NPC 出现/隐藏。条目 appear_phase 缺省或空 = 全时段出现。
func _apply_npc_appearances() -> void:
	if tod == null:
		return
	var cur := tod.phase
	for it in objects:
		if it == null or not is_instance_valid(it) or it.kind != "npc":
			continue
		var pv: Variant = (it.extra as Dictionary).get("appear_phase", null)
		var ok := true
		if pv is Array and not (pv as Array).is_empty():
			ok = false
			for p: Variant in pv:
				if int(p) == cur:
					ok = true
					break
		var hidden: bool = _npc_hidden_layers.has(it)
		if ok and hidden:
			it.collision_layer = int(_npc_hidden_layers[it])
			it.visible = true
			_npc_hidden_layers.erase(it)
			for p in _patrols:
				if p.it == it:
					p.active = true   # 恢复巡航
		elif not ok and not hidden:
			_npc_hidden_layers[it] = it.collision_layer
			it.collision_layer = 0   # Area 层清零：射线点不到、高亮选不中
			it.visible = false
			for p in _patrols:
				if p.it == it:
					p.active = false   # 隐身期间停走；现身从原地继续
	# 环境装饰层：填空白格。跟在摆件之后 —— 它同样走 surface()，一起等物理就绪。
	_setup_scatter()
	# 灯光点位从 objects 里挑，必须等物件摆完（顺序要求同 _ready 旧版）。
	_register_street_lights()
	# 补一次任务追踪：_ready 里那次跑的时候 objects 还是空的，收集类任务的
	# 「最近未发现目标」光圈会丢。_process 的 0.25s 节流能自愈，但首帧到摆完
	# 之间是空窗 —— 在这里补齐。（本函数只在星球路径被调用。）
	_refresh_quest_tracking()
	# 新档出生传送：_teleport_to_kind() 要遍历 objects 找门脸朝向，必须排在摆件后
	if _spawn_at_konbini_deferred:
		_spawn_at_konbini_deferred = false
		_teleport_to_kind("konbini", true)
	_objects_placed = true


## make() 是按平面地图摆的（position = px*S + 世界轴吸附偏移）。星球上重算：
## 落点 = 射线命中点，朝向 = 切平面基 × yaw，make() 里的吸附偏移改为沿切平面
## 加回（dx=东、+Z=门店朝南，与旧图语义一致）。
func _place_on_planet(it: Interactable, obj: Dictionary) -> void:
	var px := Vector2(float(obj.get("x", 0)), float(obj.get("y", 0)))
	var dir := planet_math.dir_from_px(px, world_px)
	var spot := planet_builder.surface(dir)
	var up: Vector3 = (spot["normal"] as Vector3).normalized()
	var yaw := deg_to_rad(float(obj.get("rot", 0.0)))
	var b := planet_math.basis_at(dir, yaw)
	# 斜坡上让物件跟着法线倾斜。阈值 0.8（≈37°）：再陡的侧面贴上去东西会半悬空
	# 或整栋躺倒（悬崖壁上的楼），宁可立着插进坡里一点，靠整备工具把它挪到平地。
	#
	# 【坑：坡度必须比「命中点的径向」，不能比 dir】dir 是标称球面方向（r=51 的
	# 理想球），而真实岛面 r 只有 35~49 —— 两者差好几个度，dot 会被系统性压低，
	# 高海拔的平地被误判成斜坡（物件白白歪向一边）。真落点的径向才是「此处朝外」。
	# 【别把大楼拧到坡面上】整栋楼跟着坡面倾斜 → 底边一端翘起，底下裂开一条缝，猫
	# 能钻进去、进去以后四面是碰撞体出不来（玩家报 temple 在 (4015,883) 翘起可钻入）。
	# 大件一律保持竖直（歪着插进坡里，观感也比"翘起来"正常）；只有小道具才贴坡倾斜。
	var half := Vector2(0.5, 0.5)
	var meta_v: Dictionary = Interactable.META.get(it.kind, {})
	var solid_v: Variant = meta_v.get("solid", null)
	if solid_v is Vector3:
		half = Vector2((solid_v as Vector3).x * 0.5, (solid_v as Vector3).z * 0.5)
	var is_big := maxf(half.x, half.y) >= 1.0
	if not is_big and up.dot((spot["pos"] as Vector3).normalized()) > 0.8:
		b = Basis(Quaternion(b.y, up)) * b
	var base := Vector3(px.x * Interactable.S, 0, px.y * Interactable.S)
	var off := it.position - base   # make() 加的世界轴偏移（门/窗吸附），当作切平面局部量重放
	it.transform = Transform3D(b, (spot["pos"] as Vector3) + b * off)


## 室内：由 InteriorBuilder 按模板搭建，家具节点仍进 objects（高亮/拍照/任务零改动）
func _build_interior() -> void:
	var b := InteriorBuilder.new()
	b.name = "Interior"
	add_child(b)
	var objs := b.setup(String(place.get("template", "")), Game.current_place_id)
	interior_size_px = b.size_px
	interior_spawn_px = InteriorBuilder.default_spawn_px(place)
	world_m = interior_size_px * Interactable.S
	for it in objs:
		_assign_variant_word(it)
		add_child(it)
		if it.kind == "door" and bool(it.extra.get("exit", false)):
			_interior_exit_door = it
		objects.append(it)


## 室内 HUD 模式：隐藏小地图（航点无意义）、压短相机臂、收掉街道引导
func _apply_hud_mode() -> void:
	if not _is_interior():
		return
	if minimap != null:
		minimap.set_waypoint(null)
		minimap.visible = false
	if teleport_btn != null:
		teleport_btn.visible = false   # 室内没有星球坐标，传送无意义
	if hint_panel != null:
		hint_panel.visible = false
	if player != null and player._arm != null:
		# 室内空间小，相机臂长了会穿墙/顶天花
		player._arm.spring_length = 1.1	# 室内点光按画质档位裁剪（低档只留 1 盏），避免低端机被 3 盏 omni 拖慢
	_budget_omni()


func _setup_environment() -> void:
	# 画质档位：设置页可覆盖，否则按机型嗅探
	tier = int(Game.settings.get("gfx_tier", -1))
	if tier < 0:
		tier = GraphicsTier.detect()

	env = Environment.new()
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	add_child(sun)

	if _is_interior():
		# 室内：无天空 / 无昼夜循环，灯光由 InteriorBuilder 的暖色点光 + 灯罩自发光承担
		InteriorLighting.apply(env, sun, tier)
		return

	env.background_mode = Environment.BG_SKY
	# 太阳：唯一投射实时阴影的光源（规格约束：只照地面 + 建筑）
	sun.rotation_degrees = Vector3(-11, 96, 0)   # 黄昏低角度 → 长影
	sun.light_color = Color(1.0, 0.78, 0.58)
	sun.light_energy = 1.15
	sun.directional_shadow_fade_start = 0.85

	# 反向补光：模拟天空/大气 bounced light，避免暗部死黑。不投影。
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24, 148, 0)
	fill.light_color = Color(0.78, 0.83, 0.92)
	fill.light_energy = 0.28
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	add_child(fill)

	# 后处理栈 + 分档
	GraphicsTier.apply(env, sun, tier)

	# 时间系统驱动全部光影（星球上天空固定为宇宙星空，只随时刻调太阳/灯火）
	tod = TimeOfDay.new()
	tod.space_sky = _is_planet()
	# 【为什么这里不赋 grade_mat】grade_mat 由 _setup_grade() 创建，
	# 而 _setup_environment() 现在跑在它之前，所以此刻还是 null。
	# 改由 _setup_grade() 末尾反向注入（见该函数），避免依赖调用顺序。
	add_child(tod)
	tod.setup(sun, env, we, fill)
	# 时段切换 → 重算 NPC 出现时段（appear_phase）。物件摆放完成后还会先算一遍初值。
	tod.phase_changed.connect(func(_p: int): _apply_npc_appearances())
	# 首次进入用瞬时切换（避免开局 15 秒的过场动画），之后切换走 15s 插值
	tod.set_phase(int(Game.settings.get("time_phase", TimeOfDay.Phase.DUSK)), true)
	if _is_planet():
		_setup_space_backdrop()


## 宇宙星空背景板：程序星点天球。
## 【为什么没有星系板】intro_galaxies.glb 的贴图没随 Draco→glB 转换出来，
## 平涂成色块就是一排突兀的彩色方块 —— 等美术管线补上贴图再挂回来。
## 星点放在半径 205-245 的天球上，相机 far=260 刚好罩住；夜里 glow 抬起来更明显。
func _setup_space_backdrop() -> void:
	# 程序星点：远天球上撒一层大小/色温不一的星，UNSHADED + 自发光
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 0.5
	star_mesh.height = 1.0
	star_mesh.radial_segments = 8
	star_mesh.rings = 4
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.vertex_color_use_as_albedo = true
	smat.emission_enabled = true
	smat.emission = Color(1, 1, 1)
	smat.emission_energy_multiplier = 1.6
	# 【关键】星点天球必须排除雾 —— 这是「天空发青」的真凶，不是调色问题。
	# 420 颗星摊在一个半径 205~245 的球壳上，等于一层**实体几何穹顶**。
	# `env.fog_sky_affect = 0.0` 只保证「雾不影响 sky 背景」，管不到实体网格 ——
	# 于是整个星点穹顶被 100% 雾色染满。取色实测：星点区天空是
	# #2d5962（青绿），而 SPACE_SKY[DUSK].sky_horizon 预设是 #160926（暗紫），
	# 差了十万八千里 —— 中间这段全是被雾洗出来的。
	# 正确做法：让雾对这层穹顶不生效，星点才能保持自己的颜色，
	# 「宇宙星空」才真的是星空而不是一片青色噪声。
	#
	# 【属性名踩坑】Godot 4.4 里叫 `disable_fog`，**不是** `fog_disabled`
	# （后者是 3.x SpatialMaterial 的旧名，设上去只会报
	#  "Godot 3.x SpatialMaterial remapped parameter not found" 然后静默无效）。
	# 用 ClassDB.class_get_property_list("BaseMaterial3D", true) 实测确认。
	smat.disable_fog = true
	star_mesh.material = smat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = star_mesh
	var count := 420
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261005   # 固定种子：每颗星的位置稳定，不会每次进游戏重排
	var tints := [Color(1, 1, 1), Color(0.85, 0.9, 1.0), Color(1.0, 0.92, 0.78), Color(0.8, 0.86, 1.0)]
	for i in count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		while dir.length_squared() < 0.01 or dir.length_squared() > 1.0:
			dir = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		dir = dir.normalized()
		var dist := rng.randf_range(205.0, 245.0)
		var t := Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.6)), dir * dist)
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, tints[rng.randi() % tints.size()] * rng.randf_range(0.5, 1.0))
	var stars := MultiMeshInstance3D.new()
	stars.name = "Stars"
	stars.multimesh = mm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)


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
				# 沿物件自身朝向偏移（星球上物件贴着球面站，世界 +Y 可能指向海）
				warm_spots.append(it.to_global(Vector3(0, 2.4, 2.0)))
			# 冷光：自动贩卖机灯箱 / 便利店招牌 / 信号灯 / 路灯
			"vending", "traffic", "streetlight", "signboard":
				cool_spots.append(it.to_global(Vector3(0, 1.9, 0.9)))

	# 均匀取样 + 按档位截断，保证暖冷光在街上分布开而不是挤在一处
	var warm_n := mini(warm_spots.size(), GraphicsTier.omni_budget(tier) * 2)
	var cool_n := mini(cool_spots.size(), GraphicsTier.omni_budget(tier))
	for i in _spread(warm_spots, warm_n):
		var l := OmniLight3D.new()
		l.position = warm_spots[i]
		l.light_color = Color(1.0, 0.80, 0.52)     # 暖黄（去饱和）
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


## 全屏后处理层（Messenger 移植：色彩分级 + 幽微暗角）。
## Godot 4.4 的 Environment 没有 vignette_* 属性（4.3+ 拆走了），只能自建。
##
## 【Messenger 视觉】色彩分级 —— 替代 Messenger 的 lut.ktx2（那张 LUT 属
## abeto 所有，不能用），改用 grade.gdshader 里的解析式分级，效果接近。
##
## 【为什么这里没有描边】Messenger 的屏幕空间深度描边需要 hint_depth_texture，
## 而 Godot 只在 spatial shader 里提供它，canvas_item 里引用会导致编译失败
## → ColorRect 退回纯白 → 满屏刷白。详见 grade.gdshader 文件头。
## 描边改走「反向外壳」纯几何方案，是独立一轮工作。
func _setup_grade() -> void:
	grade_layer = CanvasLayer.new()
	grade_layer.layer = 100# 压在 HUD 之上、UI 之下
	add_child(grade_layer)
	grade_rect = ColorRect.new()
	grade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade_mat = ShaderMaterial.new()
	grade_mat.shader = load("res://assets/shaders/grade.gdshader")
	# 暗角非常轻，低档更轻
	grade_mat.set_shader_parameter("vignette_strength",
		0.16 if tier == GraphicsTier.Tier.LOW else 0.20)
	grade_rect.material = grade_mat
	grade_layer.add_child(grade_rect)
	# 反向注入给时间系统：_setup_environment() 先跑完并创建了 tod，
	# 由它来按时刻调制暗角强度（见 TimeOfDay._apply_preset）
	if tod != null:
		tod.grade_mat = grade_mat


## 供设置页实时切档。灯光点位数变了要重建，环境参数重刷。
func apply_tier(t: int) -> void:
	tier = clampi(t, 0, 2)
	if env != null and sun != null:
		if _is_interior():
			InteriorLighting.apply(env, sun, tier)
		else:
			GraphicsTier.apply(env, sun, tier)
	if grade_mat != null:
		grade_mat.set_shader_parameter("vignette_strength",
			0.16 if tier == GraphicsTier.Tier.LOW else 0.20)
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


## 只有室内需要无限地板（房间没有底板网格，碰撞一直委托给这张平面）；
## 星球的地形碰撞由 PlanetBuilder 生成，不能再铺 y=0 平面 —— 会把玩家顶在天上。
func _setup_floor() -> void:
	if not _is_interior():
		return
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	floor_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(cs)
	add_child(floor_body)


## 环境装饰层：纯视觉，不进 objects、不参与拍照/高亮/任务。
##
## 【为什么单独一层，而不是往 map.json 里加物件】
## 实测密度热力图（每格 260px，共 21×16=336 格）：
##   有物件 107 格 / 空 229 格 = **68% 全空**，且物件全挤在顶部 6 行，
##   下半张图（y>1800）几乎空白 —— 这就是「场景显得空」的直接原因。
## 但 map.json 里每个物件都是**可拍照学单词的学习目标**（META 里都有 click/range，
## 还能进任务系统）。往里塞 200 个草和花会直接稀释玩法 —— 玩家点任何东西都能弹词卡。
## 所以：装饰必须是**旁路**的一层，不触碰玩法数据。
##
## 【成本】用 InstancedMesh/MultiMesh 承载，单个装饰 8~24 面。
## 数量按画质档位给（低 0 / 中 60 / 高 140），高档也只增加 ~2.7K 面 —— 换整条街
## 不再空旷，这个交换比很划算。
func _setup_scatter() -> void:
	if _is_interior():
		return
	var budget := 0
	match tier:
		GraphicsTier.Tier.HIGH: budget = 140
		GraphicsTier.Tier.MEDIUM: budget = 60
		_: budget = 0
	if budget <= 0:
		return
	_scatter_root = Node3D.new()
	_scatter_root.name = "ScatterDecor"
	add_child(_scatter_root)

	# 收集可散布的落点：只在有物件的格子里撒（空白区没有可参照的地表语义），
	# 且与最近建筑保持距离，避免糊在墙上。
	var spots := _scatter_spots(budget)
	# 按 kind 分桶进 MultiMesh —— 每类一个 draw call，与件数无关。
	_build_scatter_batch(spots)
	print("[Scatter] 环境装饰 %d 件（画质档 %d）" % [spots.size(), tier])


## 撒点选址：在有物件的格子中心附近随机取点，并排除建筑占位。
## 用确定性哈希（不用 randf）—— 每次进游戏布局一致，便于对比调参。
##
## 【关键：返回的是球面世界坐标，不是地图像素】
## 星球上物件必须走 _place_on_planet 那套投影（dir_from_px → builder.surface →
## 切平面基），否则装饰会浮在太空里或埋进地形。这里直接复用同一条路径，
## 顺带用切平面基把「草叶朝上」对齐到当地法线 —— 平地上的装饰不会歪向一边。
func _scatter_spots(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if planet_math == null or planet_builder == null:
		return out
	var cell := 260.0
	var occupied: Dictionary = {}
	for o in map.get("objects", []):
		if not o is Dictionary:
			continue
		occupied[Vector2i(int(float(o.get("x", 0.0)) / cell),
			int(float(o.get("y", 0.0)) / cell))] = true
	# 建筑占位（大件，周围 2 格留空，避免糊在墙上）
	var big_kinds := ["house", "mansion", "station", "konbini", "super", "cafe", "ramen", "train"]
	for o in map.get("objects", []):
		if not o is Dictionary:
			continue
		if not big_kinds.has(String(o.get("kind", ""))):
			continue
		var bx := int(float(o.get("x", 0.0)) / cell)
		var by := int(float(o.get("y", 0.0)) / cell)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				occupied[Vector2i(bx + dx, by + dy)] = true

	var keys := occupied.keys()
	if keys.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261005          # 固定种子：布局稳定，便于 A/B 对比
	var tries := n * 12
	for i in tries:
		if out.size() >= n:
			break
		var k: Vector2i = keys[rng.randi() % keys.size()]
		# 格内随机偏移（避免全挤在格心）
		var px := Vector2((float(k.x) + rng.randf()) * cell, (float(k.y) + rng.randf()) * cell)
		# 与 _place_on_planet 完全相同的投影链
		var dir := planet_math.dir_from_px(px, world_px)
		var spot := planet_builder.surface(dir)
		if spot.is_empty():
			continue
		var up: Vector3 = (spot["normal"] as Vector3).normalized()
		# 法线与视线方向夹角太大 = 陡坡，装饰会歪着插进去或悬空 → 跳过
		if up.dot(dir) < 0.55:
			continue
		out.append(spot["pos"] as Vector3)
	return out


## 装饰几何体定义：每种给出一个「原型网格 + 颜色」。
## 用 MultiMesh 把同类装饰合并成**一个 draw call** —— 这是本层最关键的设计。
##
## 【为什么不逐件 MeshInstance】第一版就是逐件建的，实测：
##   draw_call 1735 → 2492（+757，+44%），三角面只 +64K（+12%），FPS 70→60。
## 三角面几乎不要钱，**draw call 才是瓶颈**（每件装饰一次材质切换）。
## 改成 MultiMesh 后：4 种装饰 = 4 个 draw call，与件数无关。
## 这正是 performance-optimization skill 说的「identical meshes → MultiMesh」。
const SCATTER_KINDS := [
	{"name": "grass", "tint": Color(0.40, 0.52, 0.28)},
	{"name": "flower", "tint": Color(0.90, 0.84, 0.62)},
	{"name": "pebble", "tint": Color(0.56, 0.55, 0.52)},
	{"name": "weed", "tint": Color(0.32, 0.44, 0.28)},
]

## 散落装饰的表面贴图（按类别）。找不到就返回 null → 纯色兜底，
## 但正常情况下 assets/tex 里这几套都在（tools/fetch_tex.py 抓的 Poly Haven CC0）。
const SCATTER_TEX := {
	"grass": "res://assets/tex/grass_col.jpg",
	"flower": "res://assets/tex/grass_col.jpg",
	"weed": "res://assets/tex/grass_col.jpg",
	"pebble": "res://assets/tex/pebbles_col.jpg",
}


func _scatter_tex(kind: String) -> Texture2D:
	var p: String = SCATTER_TEX.get(kind, "")
	if p.is_empty() or not ResourceLoader.exists(p):
		return null
	return load(p) as Texture2D


## 建一个装饰原型网格（只建一次，被该类所有实例共享）。
##
## 【几何预算】全部是最便宜的基础体，单件 8~24 面：
##   grass  = 3 片 BoxMesh 交叉 = 36 面（剪影比单片好，远处才看得出是草丛）
##   flower = 5 边 Cylinder 茎 + 6x4 Sphere 花头 = 34 面
##   pebble = 5x3 Sphere 压扁 = 30 面
##   weed   = 6x4 Sphere 灌木 = 48 面
## 140 件混合分布 → 总量约 5K 面，相对星球 52.6 万面可忽略。
func _scatter_proto(name: String) -> Mesh:
	match name:
		"grass":
			# 三片交叉薄板。手写三角形而不是用 BoxMesh 再合并：
			# BoxMesh 需要 12 个三角形才能做一个薄板，而一片草叶从剪影上
			# 只需要 2 个三角形（双面单片）。**双面渲染已经在材质里开了**
			# （ToonKit 用默认 cull_back，草是单面片所以要开双面 ——
			#  见下方说明），所以省下的 10 个面是真的省。
			# 用双面材质时法线要手动给两个方向，否则背面全黑。
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var h := 0.38
			for i in 3:
				# 每片绕 Y 转 120°，绕 Z 微倾 ±7°（避免完全对称成十字）
				var yaw := TAU * float(i) / 3.0
				var tilt := 0.13 * (float(i) - 1.0)
				var up := Vector3(sin(tilt), cos(tilt), 0.0)
				var side := Vector3(cos(yaw), 0.0, sin(yaw))
				# 叶片在 up/side 定义的平面内，底边贴地
				var half := 0.028
				var base_c := Vector3.ZERO
				var tip := up * h
				var l := base_c - side * half
				var r := base_c + side * half
				# 正面（法线朝外）
				_add_tri(st, l, r, tip)
				# 背面：法线相反，构成双面片
				_add_tri(st, r, l, tip)
			return st.commit()
		"flower":
			var st2 := SurfaceTool.new()
			st2.begin(Mesh.PRIMITIVE_TRIANGLES)
			_add_prim(st2, _proto_cyl(0.012, 0.016, 0.28, 5), Vector3(0, 0.14, 0))
			_add_prim(st2, _proto_sphere(0.055, 6, 4), Vector3(0, 0.30, 0))
			return st2.commit()
		"pebble":
			var st3 := SurfaceTool.new()
			st3.begin(Mesh.PRIMITIVE_TRIANGLES)
			_add_prim(st3, _proto_sphere(0.09, 5, 3), Vector3.ZERO)
			return st3.commit()
		"weed":
			var st4 := SurfaceTool.new()
			st4.begin(Mesh.PRIMITIVE_TRIANGLES)
			_add_prim(st4, _proto_sphere(0.20, 6, 4), Vector3(0, 0.12, 0))
			return st4.commit()
	return BoxMesh.new()


## 写入一个三角形：按「法线朝外」自动纠正缠绕方向。
## 判断内外用「法线是否背离局部原点」—— 对球面/圆柱/薄板都成立，
## 比和固定轴比较可靠（不同面的朝向差别很大）。
func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.000001:
		return
	n = n.normalized()
	# 原点应在这面三角形的内侧；法线背离原点 = 朝外 = 缠绕正确
	if n.dot(a + b + c) > 0.0:
		var t := b
		b = c
		c = t
		n = -n
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## 把一个 PrimitiveMesh 的三角面写入 SurfaceTool，并整体平移。
##
## 【Godot 4.4 坑·实测确认】PrimitiveMesh.get_faces() 返回的是**扁平的**
## PackedVector3Array（BoxMesh = 36 个 Vector3 = 12 个三角形），
## **不是**「数组的数组」。所以正确写法是按 3 个一组步进：
##     for i in range(0, faces.size(), 3):
##         _add_tri(st, faces[i] + off, faces[i+1] + off, faces[i+2] + off)
## 写成 `for f in faces: f[0]` 会报 "Invalid operands float and Vector3"——
## 因为 f 是单个 Vector3，f[0] 取的是它的 x 分量（float）。
## 用 typeof() 实测：type=36 (TYPE_PACKED_VECTOR3_ARRAY)，f[0] 也是 Vector3。
func _add_prim(st: SurfaceTool, pm: PrimitiveMesh, off: Vector3) -> void:
	var faces := pm.get_faces()
	var i := 0
	while i + 2 < faces.size():
		_add_tri(st, faces[i] + off, faces[i + 1] + off, faces[i + 2] + off)
		i += 3


func _proto_cyl(rt: float, rb: float, h: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


func _proto_sphere(r: float, seg: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m


## 按 kind 把所有落点灌进一个 MultiMesh。
##
## 关键细节：
##   · use_colors=true + instance_color → 每实例颜色走顶点色路径，
##     这样**同一类装饰也能有颜色变化**（草的深浅、花的三色），
##     而不必为每种颜色各建一个 MultiMesh。代价是要让材质
##     vertex_color_use_as_albedo = true。
##   · cast_shadow = OFF —— 装饰不投影。这不只是省阴影 pass：
##     草叶这种薄片投影会在地面留下高频锯齿噪点，视觉上更糟。
##   · 变换里带上随机 Y 旋转和微小倾斜，避免整片草地看起来是复制粘贴。
func _build_scatter_batch(spots: Array[Vector3]) -> void:
	# 按 kind 分桶
	var buckets := {}
	for i in spots.size():
		var kind: String = SCATTER_KINDS[i % SCATTER_KINDS.size()]["name"]
		if not buckets.has(kind):
			buckets[kind] = []
		buckets[kind].append(i)

	for kind in buckets:
		var idxs: Array = buckets[kind]
		var proto := _scatter_proto(kind)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = proto
		mm.instance_count = idxs.size()

		var base_col: Color = SCATTER_KINDS[0]["tint"]
		for ki in SCATTER_KINDS.size():
			if SCATTER_KINDS[ki]["name"] == kind:
				base_col = SCATTER_KINDS[ki]["tint"]
		for n in idxs.size():
			var si: int = idxs[n]
			var pos: Vector3 = spots[si]
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector2i(int(pos.x * 7.0), int(pos.z * 7.0))) + si
			var sc := rng.randf_range(0.75, 1.35)
			# 草/花是竖直的：只绕 Y 转。weed/pebble 是球体：可以任意转。
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc)
			if kind == "grass" or kind == "flower":
				# 竖直类保留 Y 朝上 + 轻微倾斜（别让草全朝一个方向倒）
				basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc)
			mm.set_instance_transform(n, Transform3D(basis, pos))
			# 颜色变化：同类内部做明度扰动，幅度小（保持低饱和的统一观感）
			var f := rng.randf_range(0.86, 1.14)
			mm.set_instance_color(n, Color(
				clampf(base_col.r * f, 0, 1),
				clampf(base_col.g * f, 0, 1),
				clampf(base_col.b * f, 0, 1), 1.0))

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Scatter_" + kind
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 【Godot 4.4】MultiMeshInstance3D **没有** receive_shadow 属性
		# （GeometryInstance3D 只有 cast_shadow）。想「不接收阴影」得在材质上设
		# shadow_to_opacity 或直接用 unshaded —— 装饰本身是纯色平涂，
		# 不需要接收阴影，省不下什么，直接不设即可。
		# 材质：顶点色（逐件明度扰动）× 一张表面贴图（三平面世界映射）。
		# 【为什么不留纯色】140 件装饰是玩家视线扫得最频繁的东西，纯色=塑料片。
		# 贴图按类别选：草/花/weed 用草叶贴图，pebble 用碎石贴图 ——
		# 允许重复用同一张，不能没有。
		mmi.material_override = ToonKit.vertex_tinted(_scatter_tex(kind), 3.0)
		_scatter_root.add_child(mmi)
		print("[Scatter]   %-7s %3d 件 -> 1 draw call" % [kind, idxs.size()])


func _spawn_petals() -> void:
	var sakura_points: Array[Interactable] = []
	for it in objects:
		if it.kind == "sakura":
			sakura_points.append(it)
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
		# 星球上「树的上方」= 物件自身 +Y（世界 +Y 可能指向海底）
		pt.position = p.to_global(Vector3(0, 3.4, 0))
		pt.amount = 22
		pt.lifetime = 6.5
		pt.preprocess = 6.5
		pt.mesh = petal_mesh
		pt.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		pt.emission_sphere_radius = 1.5
		var tb: Basis = p.global_transform.basis
		pt.direction = (-tb.y + tb.x * 0.15 + tb.z * 0.05).normalized()
		pt.spread = 32.0
		# 花瓣很轻，下落要慢、要被风推着飘（重力沿脚下法线，风沿切向）
		pt.gravity = -tb.y * 0.28 + tb.x * 0.12 + tb.z * 0.05
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
	jump_btn = Button.new()
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

	# 底部中央上下文按钮（默认隐藏）：靠近传送点时显示【前往 ▸ 目的地】。
	# 与摇杆/小地图同理，它的矩形要排除在拖动转视角之外，否则点它会顺带转镜头。
	context_btn = Button.new()
	context_btn.focus_mode = Control.FOCUS_NONE
	context_btn.visible = false
	context_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	context_btn.add_theme_font_override("font", UiKit.font())
	context_btn.add_theme_font_size_override("font_size", 24)
	context_btn.add_theme_color_override("font_color", UiKit.WHITE)
	context_btn.add_theme_color_override("font_hover_color", UiKit.WHITE)
	context_btn.add_theme_color_override("font_pressed_color", UiKit.WHITE)
	var cn := StyleBoxFlat.new()
	cn.bg_color = Color(0.16, 0.35, 0.62, 0.92)
	cn.set_corner_radius_all(26)
	cn.border_color = Color(1, 1, 1, 0.85)
	cn.set_border_width_all(2)
	var ch := cn.duplicate()
	ch.bg_color = Color(0.22, 0.45, 0.74, 0.95)
	var cp := cn.duplicate()
	cp.bg_color = Color(0.12, 0.26, 0.48, 0.95)
	context_btn.add_theme_stylebox_override("normal", cn)
	context_btn.add_theme_stylebox_override("hover", ch)
	context_btn.add_theme_stylebox_override("pressed", cp)
	context_btn.anchor_left = 0.5
	context_btn.anchor_right = 0.5
	context_btn.anchor_top = 1.0
	context_btn.anchor_bottom = 1.0
	context_btn.offset_left = -160
	context_btn.offset_right = 160
	context_btn.offset_top = -172
	context_btn.offset_bottom = -114
	context_btn.pressed.connect(_on_context_pressed)
	layer.add_child(context_btn)

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

	# 左上「传送」按钮（在任务下方）：打开传送面板，一键回车站/商店街。
	# 室内没有星球坐标，按钮隐藏（_apply_hud_mode 统一管）。
	teleport_btn = UiKit.icon_button("传送", 22)
	teleport_btn.anchor_left = 0.0
	teleport_btn.anchor_right = 0.0
	teleport_btn.offset_left = 18
	teleport_btn.offset_top = 110
	teleport_btn.pressed.connect(_on_teleport_pressed)
	layer.add_child(teleport_btn)

	# 坐标读数：报告地图问题时报这个 (x,y) 即可（与 data/planet.json 同坐标系）。
	# 紧挨「菜单」按钮右侧的空当，不压任务/传送按钮。
	coord_label = UiKit.label("", 20, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	coord_label.position = Vector2(168, 22)   # 「菜单」按钮右侧的空当，不压任务/传送按钮
	coord_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(coord_label)

	# 右上进度
	var chip := PanelContainer.new()
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(0.13, 0.14, 0.19, 0.84)
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
	if planet_math != null:
		minimap.setup_planet(planet_math, world_px, objects, player)
	else:
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

	# 中央十字准星：只在【取景/拍照模式】显示。
	# 【为什么平时隐藏】日常走路时屏幕正中悬浮一个圆点既无信息量又干扰画面
	# （拍照的"原点"只在取景时有意义）；_ray_from_screen 只读 crosshair.size
	# 算屏幕中心，不依赖它的可见性，所以隐藏不影响瞄准判定。
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	crosshair.visible = false
	layer.add_child(crosshair)

	# 拍照白闪
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash_rect)

	# 聚焦取景框：进入变焦模式时显示四角括号 + 中心红点
	focus_frame = Control.new()
	focus_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	focus_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_frame.visible = false
	focus_frame.draw.connect(_draw_focus_frame)
	layer.add_child(focus_frame)

	# 聚焦模式的「✕ 退出」按钮：复用跳键的位置（进入取景后跳键已隐藏）
	cancel_btn = Button.new()
	cancel_btn.text = "✕ 退出"
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.add_theme_font_override("font", UiKit.font())
	cancel_btn.add_theme_font_size_override("font_size", 24)
	cancel_btn.add_theme_color_override("font_color", UiKit.WHITE)
	cancel_btn.add_theme_color_override("font_hover_color", UiKit.WHITE)
	cancel_btn.add_theme_color_override("font_pressed_color", UiKit.WHITE)
	var xn := StyleBoxFlat.new()
	xn.bg_color = Color(0.2, 0.2, 0.24, 0.9)
	xn.set_corner_radius_all(50)
	xn.border_color = Color(1, 1, 1, 0.6)
	xn.set_border_width_all(3)
	var xp := xn.duplicate()
	xp.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	cancel_btn.add_theme_stylebox_override("normal", xn)
	cancel_btn.add_theme_stylebox_override("pressed", xp)
	cancel_btn.anchor_left = 1.0
	cancel_btn.anchor_right = 1.0
	cancel_btn.anchor_top = 1.0
	cancel_btn.anchor_bottom = 1.0
	cancel_btn.offset_left = -150
	cancel_btn.offset_top = -280
	cancel_btn.offset_right = -52
	cancel_btn.offset_bottom = -182
	cancel_btn.visible = false
	cancel_btn.pressed.connect(_on_cancel_pressed)
	layer.add_child(cancel_btn)

	# 引导提示
	hint_panel = PanelContainer.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.13, 0.14, 0.19, 0.86)
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
	var hint_label := UiKit.label("左下摇杆走路 · 拖动屏幕转视角 · 对准发光的物体按【拍照】取景，再点快门完成拍摄", 19, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
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

	# NPC 对话框：点 NPC 先聊天，选项里再进任务面板
	dialogue_box = DialogueBox.new()
	dialogue_box.quests_requested.connect(func(npc_id: String): quest_panel.open(npc_id))
	layer.add_child(dialogue_box)

	# 传送面板（与任务面板同一层级；星球上才有意义）
	teleport_menu = TeleportMenu.new()
	teleport_menu.picked.connect(_on_teleport_picked)
	layer.add_child(teleport_menu)


func _draw_crosshair() -> void:
	var c := crosshair.size * 0.5
	crosshair.draw_circle(c, 3.0, Color(1, 1, 1, 0.9))
	crosshair.draw_arc(c, 14.0, 0, TAU, 32, Color(0, 0, 0, 0.25), 3.0)
	crosshair.draw_arc(c, 14.0, 0, TAU, 32, Color(1, 1, 1, 0.55), 1.4)


# ---------------- 每帧逻辑 ----------------

func _process(delta: float) -> void:
	var ui_busy := popup.visible or quest_panel.visible or dialogue_box.visible \
		or (teleport_menu != null and teleport_menu.visible)
	player.input_locked = ui_busy or focus_mode
	for p in _patrols:
		p.paused = ui_busy   # 对话/弹窗期间 NPC 原地驻足，别聊着天对方走远了
	_shoot_cd = maxf(0.0, _shoot_cd - delta)
	_hl_timer += delta
	if _hl_timer >= 0.12:
		_hl_timer = 0.0
		if not focus_mode:
			_update_highlight()
	# 收集类的「最近未发现目标」会随移动变化：低频重算，变了才刷新 HUD，避免每帧重设
	_quest_timer += delta
	if _quest_timer >= 0.25:
		_quest_timer = 0.0
		if Quests.tracked_target_object(player.position) != _quest_target_obj:
			_refresh_quest_tracking()
		_update_coord_label()
	# 上下文动作（传送点/门）：低频检测，避免每帧遍历 objects
	_context_timer += delta
	if _context_timer >= 0.15:
		_context_timer = 0.0
		_update_context_action()
	# 【诊断钩子期间冻结存档写入】demo_* 会把玩家到处瞬移，而这里每移动 1m 就
	# 把新位置写进存档 —— 于是"上一次测试的终点"变成"下一次测试的出生点"，
	# 四方向/网格对照全部失去可比性（本次排查反复被这个坑绊倒）。
	# _no_save 期间只更新 _last_saved_pos，不落盘。
	var d3 := player.position.distance_to(_last_saved_pos)
	if d3 > 1.0:
		_last_saved_pos = player.position
		if _no_save:
			return
		# 星球：把世界坐标逆映射回岛冠展开图的 px（存档 schema 不变）；
		# 室内/平地：沿用 x/S, z/S
		if planet_math != null:
			Game.set_position(planet_math.px_from_world(player.position, world_px))
		else:
			Game.set_position(Vector2(player.position.x / Interactable.S, player.position.z / Interactable.S))


func _update_highlight() -> void:
	if popup.visible:
		return
	# 被任务追踪的隐形标记（如「交差点」marker_cross）range=0，若纳入常规高亮会全图常亮，
	# 故只在玩家靠近（≤14m）时优先高亮它 —— 否则准星会锁定旁边的车/红绿灯，拍不到目标。
	var best: Interactable = null
	var qt := _quest_target_obj
	if qt != null and is_instance_valid(qt) and qt.no_draw \
			and player.position.distance_to(qt.position) <= 14.0:
		best = qt
	if best == null:
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


## 小地图区域不参与转视角（点它 = 放大/收起地图）。室内小地图是隐藏的，不算热区。
func _in_minimap_zone(p: Vector2) -> bool:
	return minimap != null and minimap.visible and minimap.get_global_rect().has_point(p)


func _input(event: InputEvent) -> void:
	if popup.visible or quest_panel.visible or dialogue_box.visible \
			or (teleport_menu != null and teleport_menu.visible):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if not focus_mode and (_in_joystick_zone(event.position) or _in_minimap_zone(event.position) \
					or _in_context_zone(event.position)):
				return
			_look_active = true
			_look_last = event.position
		else:
			_look_active = false
	elif event is InputEventScreenDrag:
		if not _look_active:
			return
		if not focus_mode and (_in_joystick_zone(event.position) or _in_minimap_zone(event.position)):
			return
		# 用引擎给的相对增量，并对单次跳变限幅，杜绝坐标基准不一致造成的视角瞬移
		var d: Vector2 = event.relative
		if d == Vector2.ZERO:
			d = event.position - _look_last
		_look_last = event.position
		if d.length() > 90.0:
			d = d.normalized() * 90.0
		if focus_mode:
			# 变焦后视野窄，同距离拖动画面位移大好几倍：降灵敏度，微调才不抖
			if _aim_tween != null and _aim_tween.is_valid():
				_aim_tween.kill()   # 手动微调打断自动瞄准补间
			player.look(d.x * 0.35, d.y * 0.35)
		else:
			player.look(d.x, d.y)


func _physics_process(_delta: float) -> void:
	# 星球软墙：猫不许下水。判定看「脚下地面是否低于水线」，不用固定的纬度阈值 ——
	# 固定 walk_lat_deg 是个等纬度切帽，可岛屿海岸线不等纬度：实测 x=3900 一线
	# 52~57° 全是陆地（还有路），软墙却卡在内陆 62° 上，玩家看着前面的路走不过去。
	# 改成：只有真站到水上才往回推，推到最近的水线以上。
	if planet_math != null and planet_builder != null:
		var rel := player.position - planet_math.center
		if rel.length_squared() > 0.01:
			var dir := rel.normalized()
			if _over_sea(dir):
				var land := _nearest_land(dir)
				if land == Vector3.ZERO:
					var cl: Variant = planet_math.clamp_walk(dir)
					if cl != null:
						land = cl as Vector3
				if land != Vector3.ZERO:
					player.position = planet_math.center + land * rel.length()
					if not _sea_toast_shown:
						_sea_toast_shown = true
						Toast.show_once(self, "前面是大海，猫不敢下水～")
	Quests.tick(player.position)
	for p in _patrols:
		p.player_pos = player.position   # 玩家走近时 NPC 驻足（巡航控制器自己判定）


## 给带 patrol 数据的 NPC 挂巡航控制器（编辑器「人物」页画的路线直接生效）。
func _attach_patrol(it: Interactable) -> void:
	var p := NpcPatrol.new()
	p.it = it
	p.math = planet_math
	p.builder = planet_builder
	p.world_px = world_px
	p.talker = _npc_talker(it)
	it.add_child(p)
	if p.setup():
		_patrols.append(p)
	else:
		p.queue_free()   # 路线缺失/没有可走航点：安静回退成站桩 NPC


## dir 正下方是不是「水」：没打到地面，或地面低于水线，都算。
func _over_sea(dir: Vector3) -> bool:
	if planet_builder.water_radius <= 0.0:
		return false
	var sp := planet_builder.surface(dir)
	if not bool(sp.get("hit", false)):
		return true
	return (sp["pos"] as Vector3).length() < planet_builder.water_radius + 0.35


## 从 dir 朝极点（φ 减小 = 往岛心）逐步退，找最近一处水线以上的地面方向；找不到返回 ZERO。
func _nearest_land(dir: Vector3) -> Vector3:
	var lam := atan2(dir.x, dir.z)
	var phi := acos(clampf(dir.y, -1.0, 1.0))
	for _i in 80:
		phi = maxf(deg_to_rad(0.5), phi - deg_to_rad(0.4))
		var d := Vector3(sin(phi) * sin(lam), cos(phi), sin(phi) * cos(lam))
		var sp := planet_builder.surface(d)
		if bool(sp.get("hit", false)) \
				and (sp["pos"] as Vector3).length() >= planet_builder.water_radius + 0.35:
			return d
	return Vector3.ZERO


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
	Quests.notify_photo(it.kind, it.word_id)   # 拍照类任务：拍到目标即完成
	open_word(it)


## 两段式拍摄：第一次按 = 进入变焦取景（自动对准目标 + 拉近），
## 第二次按 = 快门（白闪 + 快门音 + 单词卡）。取景中可拖屏微调、可 ✕ 退出。
func _on_shoot_pressed() -> void:
	if popup.visible or dialogue_box.visible or quest_panel.visible:
		return
	if not focus_mode:
		_enter_focus()
		return
	# 快门：优先拍正对准星的东西（用户可能微调过了），拍不到再用进取景时锁定的目标
	var it := _focus_target
	var hit := _ray_from_screen(crosshair.size * 0.5)
	if hit != null and hit.in_range_of(player.position):
		it = hit
	_exit_focus()
	if it != null and is_instance_valid(it) and it.in_range_of(player.position):
		_shoot(it)
	else:
		Toast.show_once(self, "附近没有可拍摄的单词，走近一点吧")


## 进入变焦取景：锁定目标 → 自动瞄准 → FOV 拉近 → 换取景 UI
func _enter_focus() -> void:
	var it := highlighted
	if it == null:
		it = _ray_from_screen(crosshair.size * 0.5)
	if it == null or it.word_id.is_empty() or not it.in_range_of(player.position):
		Toast.show_once(self, "附近没有可拍摄的单词，走近一点吧")
		return
	_focus_target = it
	focus_mode = true
	player.input_vec = Vector2.ZERO
	joystick.visible = false
	jump_btn.visible = false
	context_btn.visible = false
	cancel_btn.visible = true
	hint_panel.visible = false
	shoot_btn.text = "咔嚓!"
	focus_frame.visible = true
	crosshair.visible = true   # 取景模式下显示中心原点（平时隐藏，见 _build_hud 注释）
	focus_frame.queue_redraw()
	Game.play_sfx("click")
	# 瞄准 + 变焦同时补间；yaw 走最短弧（wrapf），pitch 夹在相机限位内。
	# aim_angles 在星球上沿切平面解算（室内等价于旧的水平 yaw 公式）
	var angles := player.aim_angles(it.global_position + Vector3(0, 0.5, 0))
	var want_pitch := clampf(angles.y, Player.CAM_PITCH_MIN, Player.CAM_PITCH_MAX)
	var want_yaw := angles.x
	var y0 := player.look_yaw
	var p0 := player.look_pitch
	if _aim_tween != null and _aim_tween.is_valid():
		_aim_tween.kill()
	_aim_tween = create_tween().set_parallel()
	_aim_tween.tween_method(_aim_step.bind(y0, want_yaw, p0, want_pitch),
		0.0, 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_aim_tween.tween_property(cam, "fov", 26.0, 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 自动瞄准插值步进（tween_method 回调：t ∈ 0..1）
func _aim_step(t: float, y0: float, y1: float, p0: float, p1: float) -> void:
	player.look_yaw = wrapf(lerpf(y0, y1, t), -PI, PI)
	player.look_pitch = lerpf(p0, p1, t)
	player._apply_cam_rotation()


## 退出取景：恢复 FOV 和 HUD。不播放快门，只是收起。
func _exit_focus() -> void:
	focus_mode = false
	_focus_target = null
	if _aim_tween != null and _aim_tween.is_valid():
		_aim_tween.kill()
	cancel_btn.visible = false
	focus_frame.visible = false
	crosshair.visible = false   # 退出取景一并收起中心原点
	joystick.visible = true
	jump_btn.visible = true
	shoot_btn.text = "拍照"
	hint_panel.visible = not bool(Game.settings.get("tutorial_done", false))
	var tw := create_tween()
	# 恢复到玩家当前的视场角（含滚轮缩放）—— 硬写 Player.CAM_FOV 会把缩放吞掉
	tw.tween_property(cam, "fov", player.zoom_fov(), 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_cancel_pressed() -> void:
	Game.play_sfx("click")
	_exit_focus()


## 取景框：中央四角括号 + 红点，模拟相机对焦 UI
func _draw_focus_frame() -> void:
	if focus_frame.size == Vector2.ZERO:
		return
	var c := focus_frame.size * 0.5
	var r := minf(focus_frame.size.x, focus_frame.size.y) * 0.27
	var ln := r * 0.32
	var col := Color(1, 1, 1, 0.92)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := c + Vector2(sx * r, sy * r)
			focus_frame.draw_line(corner, corner - Vector2(sx * ln, 0), col, 3.0)
			focus_frame.draw_line(corner, corner - Vector2(0, sy * ln), col, 3.0)
	focus_frame.draw_circle(c, 3.5, Color(0.95, 0.3, 0.3, 0.95))
	focus_frame.draw_arc(c, r * 1.28, 0, TAU, 48, Color(1, 1, 1, 0.14), 2.0)


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
	# NPC 点击分流：NPC 是任务发布者（giver），点击它 = 打开「TA 的任务」面板而非词汇弹窗。
	# 分流放在 discover 之后 —— NPC 自带的称呼词（如「シェフ」）点一下顺便学会。
	# 放在 popup.show_word 调用点之前，extra.npc 没配时自然落到普通词汇弹窗。
	if it.kind == "npc":
		var giver := String(it.extra.get("npc", ""))
		if not giver.is_empty():
			player.input_vec = Vector2.ZERO
			Quests.notify_talk(giver)   # 对话类任务：搭上话就算完成（不管走不走对话 UI）
			var talker := _npc_talker(it)
			# 配了对话的 NPC：先聊天，选项里再进任务面板；没配的保持旧行为直接开面板
			if Dialogues.has(giver):
				dialogue_box.open_for(giver, talker)   # 移动锁定由 _process 统一接管
				return
			quest_panel.open(giver)
			if talker != null:
				talker.call("talk")   # 让 NPC 开口说话；模型未接入（无 talk 方法）时静默跳过
			return
	popup.show_word(Game.word(it.word_id), is_new)
	_update_highlight.call_deferred()


## 找能开口说话的节点：talk() 可能在 Interactable 本体上，也可能挂在它名下的
## NPC 模型（ArtNpc）子节点上 —— 两处都探一遍，谁有就返回谁；都没有返回 null。
func _npc_talker(node: Node) -> Node:
	if node.has_method("talk"):
		return node
	for c in node.get_children():
		var t := _npc_talker(c)
		if t != null:
			return t
	return null


## 同一个基础词在地图里重复出现时（12 栋房子、14 棵树…），按出现顺序轮换到
## 该词条 variants 里的定语变体（如 家→大きい家/古い家），避免整条街千篇一律同一个词。
func _assign_variant_word(it: Interactable) -> void:
	var base := it.word_id
	if base.is_empty():
		return
	var variants: Array = Game.word(base).get("variants", [])
	if variants.is_empty():
		return
	var n := int(_word_use.get(base, 0))
	_word_use[base] = n + 1
	var pool: Array = [base]
	pool.append_array(variants)
	it.word_id = String(pool[n % pool.size()])


## 刷新左上角坐标读数：玩家当前所在地图的像素 (x,y)（与 data/planet.json 一致，
## 1m = 40px）。报「哪里悬空/穿模/堵路」时读这个数，就不用描述方位了。
func _update_coord_label() -> void:
	if coord_label == null:
		return
	if _is_interior() or planet_math == null:
		coord_label.text = "室内 (%.0f, %.0f)" % [
			player.position.x / Interactable.S, player.position.z / Interactable.S]
		return
	var px := planet_math.px_from_world(player.position, world_px)
	coord_label.text = "px (%d, %d)" % [int(px.x), int(px.y)]


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
	# 室内不显示世界航点：航点坐标属于城市/其它地图，指过去毫无意义
	var wp: Variant = null if _is_interior() else Quests.tracked_waypoint(player.position)
	quest_tracker.set_quest(String(q.get("title_zh", "")), Quests.objective_text(), wp)
	if minimap != null and not _is_interior():
		minimap.set_waypoint(wp)
	_set_quest_target(Quests.tracked_target_object(player.position))
	_refresh_quest_button()


## 给收集类任务的「最近未发现目标」点亮光圈（隐形标记如「交差点」靠它显形）
func _set_quest_target(obj: Variant) -> void:
	var next: Interactable = null
	if obj is Interactable:
		next = obj
	if next == _quest_target_obj:
		return
	if _quest_target_obj != null and is_instance_valid(_quest_target_obj):
		_quest_target_obj.set_quest_target(false)
	_quest_target_obj = next
	if _quest_target_obj != null:
		_quest_target_obj.set_quest_target(true)


func _on_quest_pressed() -> void:
	player.input_vec = Vector2.ZERO
	quest_panel.open()


# ---------------- 传送（重要地点一键直达） ----------------

func _on_teleport_pressed() -> void:
	player.input_vec = Vector2.ZERO
	var kinds := {}
	for it in objects:
		kinds[it.kind] = true
	teleport_menu.open(kinds)


func _on_teleport_picked(kind: String) -> void:
	teleport_menu.close()
	_teleport_to_kind(kind)


## 瞬移到该 kind 的第一个物件门口：站位 = 物件正前方 ~2.4m、沿脚下法线
## 下探到实际地面（坡地上径向投影会滑走，必须从切平面向下打射线）；
## 身体朝向正对物件；黑场淡入遮住跳变。室内没有星球，不会走到这里。
## silent=true（出生点复用）不播提示音/提示条 —— 只摆位。
func _teleport_to_kind(kind: String, silent := false) -> void:
	if _is_interior() or planet_math == null or planet_builder == null:
		return
	var it := _first_kind(kind)
	if it == null:
		return
	var up: Vector3 = (it.global_position - planet_math.center).normalized()
	# 锚点优先用门：kind 对应室内有门物件时，门的 +Z 就是朝外的门脸，
	# 比建筑本体的朝向可靠（建筑的 +Z 可能朝坡上）。没有门再用建筑本体，
	# 且正/背两侧都试 —— 取落地高度更接近物件基座的一侧（门侧是平地，
	# 背面往往是上坡）。
	var anchor := it
	var front := (it.global_transform.basis.z - up * it.global_transform.basis.z.dot(up)).normalized()
	for o in objects:
		if o.kind == "door" and String(o.extra.get("host", "")) == kind:
			anchor = o
			var aup: Vector3 = (o.global_position - planet_math.center).normalized()
			var az := o.global_transform.basis.z
			up = aup
			front = (az - aup * az.dot(aup)).normalized()
			break
	var space := get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 0.3
	# 基准地面 = 锚点脚下（物件原点可能悬在半空，必须先落到真实地面）
	var base_ground := _ground_below(anchor.global_position + up * 1.0, up)
	if base_ground == Vector3.INF:
		base_ground = anchor.global_position
	if ShotTool.shot_action.begins_with("teleport:"):
		print("[tp] kind=%s 锚点r=%.2f base_ground_r=%.2f front=%v" % [kind,
				anchor.global_position.length(), base_ground.length(), front])
	# 正/背两侧各找落点：先用正面（门脸侧）。候选必须同时满足
	#   · 距基座 < 4.5m（没滑到陡坡上方/崖下）
	#   · 地面法线可走 dot > 0.55（与物件摆放同一条规则 —— 站上去不打滑）
	#   · 与基座沿法线高差 < 1.2m（否则会站上旁边的土丘/棚顶，出生先跳 1.8m 崖）
	# 两侧都无效就贴基座站（基座本身是按可走法线摆的）。
	var stand := Vector3.INF
	for side: Vector3 in [front, -front]:
		var q := PhysicsRayQueryParameters3D.create(
			base_ground + side * 2.4 + up * 5.0, base_ground + side * 2.4 - up * 12.0, 2)
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var cpos: Vector3 = hit["position"]
		var cn: Vector3 = (hit["normal"] as Vector3).normalized()
		if cpos.distance_to(base_ground) < 4.5 and cn.dot(up) > 0.55 \
				and absf((cpos - base_ground).dot(up)) < 1.2:
			stand = cpos + cn * 0.15
			break
	if stand == Vector3.INF:
		stand = base_ground + front * 1.1
	# 卡进实心体（门框/台阶）就沿正面继续外推
	for i in 8:
		var qp := PhysicsShapeQueryParameters3D.new()
		qp.shape = probe
		qp.collision_mask = 1
		qp.transform = Transform3D(Basis(), stand + up * 0.3)
		if space.intersect_shape(qp, 1).is_empty():
			break
		stand += front * 0.8
	# 身体朝向正对物件（yaw = 切平面北 → 目标方向的旋转角）
	var north := planet_math.north_at(up)
	var to := it.global_position - stand
	to = (to - up * to.dot(up)).normalized()
	var yaw := atan2(north.cross(to).dot(up), north.dot(to))
	if not silent:
		Game.play_sfx("click")
	if ShotTool.shot_action.begins_with("teleport:"):
		print("[tp] stand_r=%.2f (%v)" % [stand.length(), stand])
	player.teleport(stand, yaw)
	_last_saved_pos = player.position
	if not silent:
		_fade_in_from_black()
		Toast.show_once(self, "已传送到「%s」" % _teleport_label(kind))


func _teleport_label(kind: String) -> String:
	for spot: Dictionary in TeleportMenu.SPOTS:
		if String(spot["kind"]) == kind:
			return String(spot["label"])
	return kind


## 从切平面点正上方沿 -up 打射线取地面落点（坡地上贴着门脸的关键）。
## 落空返回 Vector3.INF。world 需已在场景树里。
func _ground_below(tangent_point: Vector3, up: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(tangent_point + up * 5.0, tangent_point - up * 12.0, 2)
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	return (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.15


# ---------------- 上下文动作（传送点 / 室内门） ----------------

## 该物件是否有可执行的上下文动作。
## portal = 多地图传送点；door 带 interior 字段 = 可进入的室内（Phase 2 接入）。
func _has_context_action(it: Interactable) -> bool:
	if it.kind == "portal":
		return true
	if it.kind == "door":
		if bool(it.extra.get("exit", false)):
			return true
		return not _door_interior(it).is_empty()
	return false


## 城里的门 → 目标室内 place  id：显式 interior 字段优先，否则按门所属建筑 host 映射
func _door_interior(it: Interactable) -> String:
	var explicit := String(it.extra.get("interior", ""))
	if not explicit.is_empty():
		return explicit
	return String(INTERIOR_BY_HOST.get(String(it.extra.get("host", "")), ""))


func _context_text(it: Interactable) -> String:
	if it.kind == "portal":
		var label := String(it.extra.get("label", ""))
		return "前往 ▸ " + label if not label.is_empty() else "前往"
	if bool(it.extra.get("exit", false)):
		return "出门"
	return "进入"


## 低频检测最近的上下文目标，显示/隐藏底部按钮并刷新文案
func _update_context_action() -> void:
	if context_btn == null or popup.visible or quest_panel.visible or dialogue_box.visible \
			or focus_mode:
		return
	var best: Interactable = null
	var best_d := INF
	for it in objects:
		if not _has_context_action(it):
			continue
		var d := player.position.distance_to(it.position)
		if d <= it.interact_range and d < best_d:
			best_d = d
			best = it
	if best == _context_target:
		return
	_context_target = best
	if best == null:
		context_btn.visible = false
		return
	context_btn.text = _context_text(best)
	context_btn.visible = true


func _on_context_pressed() -> void:
	var it := _context_target
	if it == null or not is_instance_valid(it):
		return
	if it.kind == "portal":
		_travel_via(it)
	elif it.kind == "door":
		if bool(it.extra.get("exit", false)):
			_exit_interior()
		else:
			_enter_interior(it)


## 进门：记下门外返回点（门朝外 1.2m，球体探测外推防卡墙），再切到室内 place。
## 星球上返回点要逆映射回岛冠展开图的 px（存档 schema 对室内/星球一视同仁）。
func _enter_interior(door: Interactable) -> void:
	var target := _door_interior(door)
	if target.is_empty() or not Places.has_place(target):
		Toast.show_once(self, "这扇门打不开")
		return
	Game.play_sfx("click")
	var stand := _safe_outdoor_spot(door)
	var back_px: Vector2
	if planet_math != null:
		back_px = planet_math.px_from_world(stand, world_px)
	else:
		back_px = Vector2(stand.x / Interactable.S, stand.z / Interactable.S)
	Game.remember_return(Game.current_place_id, back_px, PI)
	Game.travel_to(target, InteriorBuilder.default_spawn_px(Places.get_place(target)), 0.0)


## 出门：回父城记录的门外点（没有记录时兜底回该城默认出生点）
func _exit_interior() -> void:
	var parent := Places.parent_of(Game.current_place_id)
	if parent.is_empty():
		parent = Places.default_id()
	var r := Game.take_return(parent)
	if not r.is_empty():
		Game.play_sfx("click")
		Game.travel_to(parent, r.get("pos", Vector2.ZERO), float(r.get("yaw", 0.0)))
		return
	Game.play_sfx("click")
	Game.travel_to(parent, _default_spawn_px_of(parent), 0.0)


## 读某城市的默认出生点（px）。仅在出门兜底路径上调用。
func _default_spawn_px_of(place_id: String) -> Vector2:
	var p: Dictionary = Places.get_place(place_id)
	var path := String(p.get("map", ""))
	if path.is_empty():
		return Vector2(2000, 900)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return Vector2(2000, 900)
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return Vector2(2000, 900)
	var a: Array = (d as Dictionary).get("spawn", [2000, 900])
	return Vector2(float(a[0]), float(a[1]))


## 门外站位：门的世界朝向 +Z 方向外推 1.2m，若仍卡在实心体里就继续外推。
## 星球上 +Z 是门自身切平面的「南」，法向抬高也沿物件自身 +Y。
func _safe_outdoor_spot(door: Interactable) -> Vector3:
	var out_dir := door.global_transform.basis.z
	var up := door.global_transform.basis.y
	var spot := door.global_position + out_dir * 1.2
	var space := get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 0.3
	for i in 8:
		var qp := PhysicsShapeQueryParameters3D.new()
		qp.shape = probe
		qp.collision_mask = 1
		qp.transform = Transform3D(Basis(), spot + up * 0.3)
		if space.intersect_shape(qp, 1).is_empty():
			break
		spot += out_dir * 0.6
	return spot


## 走传送点：目的地的一次性出生点交给 Game，切图后由新场景 _ready 消费
func _travel_via(it: Interactable) -> void:
	var to_map := String(it.extra.get("to_map", ""))
	if to_map.is_empty():
		return
	Game.play_sfx("click")
	Game.travel_to(to_map,
		Vector2(float(it.extra.get("to_x", 0.0)), float(it.extra.get("to_y", 0.0))),
		float(it.extra.get("to_yaw", 0.0)))


## 上下文按钮区域不参与拖动转视角（点它 = 前往）
func _in_context_zone(p: Vector2) -> bool:
	return context_btn != null and context_btn.visible and context_btn.get_global_rect().has_point(p)


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
## 【星球版】站位沿物件自身切平面偏移（世界 +Z 在南半球可能指向海底），
## 瞄准走 aim_angles —— 坐标永远跟着数据走，不再写死城市绝对坐标。
## 【GDScript 坑】注释不能放在 match 体第一个分支之前（会报
## "Expected indented block after match pattern block"），所以说明写在 match 外面。

func _run_debug_hooks() -> void:
	var action := ShotTool.shot_action
	if not action.is_empty():
		print("[hooks] action=", action)
		player.cam_follow = false   # 截图/演示时锁定相机，别被自动跟随转走
		# 凡是会移动玩家的诊断钩子都要冻结存档，否则下次运行的出生点 = 上次终点
		if action.begins_with("demo_walk") or action.begins_with("demo_stuck") \
				or action.begins_with("demo_climb") or action.begins_with("demo_wall") \
				or action.begins_with("teleport"):
			_no_save = true
	# 悬空审计：量真实场景里每个物件的离地空隙（走的是真实摆件路径，不是复刻）
	# 用法：--shot-action=audit_float
	if action == "audit_float":
		await _audit_float()
		return
	# NPC 出现时段诊断：--shot-action=demo_phase:N（0朝/1昼/2夕/3夜）
	# 切到指定时段后打印每个 NPC 的显隐——验证 appear_phase 配置用。
	if action.begins_with("demo_phase:"):
		var ph := clampi(int(action.substr(11)), 0, 3)
		tod.set_phase(ph, true)
		await get_tree().create_timer(0.3).timeout
		for it in objects:
			if it != null and is_instance_valid(it) and it.kind == "npc":
				print("[npc-vis] phase=%d %s visible=%s" % [tod.phase,
					String((it.extra as Dictionary).get("npc", "?")), it.visible])
		return
	# 通用物件检视：--shot-action=look:bench;1.6;-2.4;3.0;-0.28
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
		_look_at_object(want, dx, dz, dist, pit)
		return
	# 星球全景：拉长相机臂从高处俯瞰（验证球面摆放/岛冠范围/海线）
	if action == "demo_planet":
		player.look_pitch = -0.9
		player._apply_cam_rotation()
		player._arm.spring_length = 60.0
		tod.set_phase(TimeOfDay.Phase.DAY, true)   # 全景图强制白天，配色才看得清
		return
	# 裸岛：隐藏全部地图物件，只剩岛屿模型 —— 诊断「悬浮物是地图物件还是烘焙几何」
	if action == "demo_bare":
		player.look_pitch = -0.9
		player._apply_cam_rotation()
		player._arm.spring_length = 60.0
		tod.set_phase(TimeOfDay.Phase.DAY, true)
		for it in objects:
			it.visible = false
		return
	# 楼梯/贴图验收探针：--shot-action=probe_stairs
	# 【为什么挂在这里而不是 --script 独立脚本】`--script` 模式不加载 autoload，
	# Interactable 依赖全局 Game（编译期就报 Identifier not found: Game），
	# 整类加载失败 → has_tex / make 全都不存在。走主场景才有完整环境。
	if action == "probe_stairs":
		_probe_stairs()
		return
	# 贴图覆盖率审计：--shot-action=probe_tex
	# 遍历真实场景 + 全部 kind + 全部外部模型 + 全部室内模板，逐材质问「挂了图吗」。
	# 产物 out/tex_probe.txt。这是「几乎所有模型都要有贴图」这条要求的唯一验收手段。
	if action == "probe_tex":
		await TexAudit.run_all(self)
		return
	# 性能对照：--shot-action=probe_perf —— 给「加了贴图之后掉不掉帧」一个数。
	# 【为什么要单独一个 action】贴图覆盖率探针会把上百个模型实例化进场景里，
	# 那个状态下的 FPS 没有参考价值；这里只跑真实世界。
	# 【坑】Performance.XXX 是枚举常量，必须包在 get_monitor() 里；
	# 直接把常量当键写进字典会拿到常量本身，draw call 恒等于 13。
	if action == "probe_perf":
		await TexAudit.perf(self)
		return
	# 行走阻力诊断：--shot-action=demo_walk[:yaw_deg] —— 向前走 3 秒打印切向位移。
	# 四个朝向各跑一次，位移应当一致；某方向明显短 = 撞了隐形碰撞（查残留 decor 碰撞）。
	# 注意：demo_walk_all 必须排在 demo_walk 前面 —— begins_with("demo_walk")
	# 对 "demo_walk_all" 也成立，顺序反了四方向对照会静默走成单方向。
	if action == "demo_walk_all":
		_demo_walk_all()
		return
	if action == "demo_stuck":
		_demo_stuck()
		return
	if action == "demo_climb":
		_demo_climb()
		return
	# 90° 垂直墙爬墙验证：--shot-action=demo_wall
	if action == "demo_wall":
		_demo_wall()
		return
	if action.begins_with("demo_walk"):
		_demo_walk(action.substr(10))
		return
	# 传送面板演示：直接打开面板（截图 UI 用）
	if action == "demo_teleport_panel":
		var kinds := {}
		for it in objects:
			kinds[it.kind] = true
		teleport_menu.open(kinds)
		return
	# 传送落点验证：--shot-action=teleport:konbini —— 瞬移过去并摆好相机
	if action.begins_with("teleport:"):
		# 摆件是 call_deferred 协程：_ready 时 objects 还是空的，_first_kind
		# 会拿 null 静默返回 —— 必须等目标 kind 真的摆上来再传送。
		# 【为什么不等 _objects_placed 标志】实测 _ready 期间协程尾部会被提前
		# 执行一遍（objects=0 就置位，head 未跑，成因未明）——标志不可信，
		# 以「目标物件在场景里」为准，300 帧兜底防挂死。
		var want := action.substr(9)
		for i in 300:
			if _first_kind(want) != null:
				break
			await get_tree().process_frame
		print("[tp] hook 就绪 objects=%d" % objects.size())
		_teleport_to_kind(want)
		player.cam_follow = true
		player._arm.spring_length = 4.2
		return
	# 弹窗演示：走近最近的贩卖机并打开单词卡
	if action == "demo_popup":
		var target := _first_kind("vending")
		if target == null:
			target = _first_kind("signboard")
		if target != null:
			_look_at_object(target.kind, 0.0, 2.6, 3.2, -0.3)
			await get_tree().process_frame
			await get_tree().process_frame
			open_word(target)
		return
	# 四时刻对照：--shot-action=demo_tod_morning/day/dusk/night
	if action.begins_with("demo_tod_"):
		var mark := _first_kind("station")
		if mark == null:
			mark = _first_kind("house")
		if mark != null:
			_look_at_object(mark.kind, 0.0, 6.0, 7.0, -0.16)
		var ph := TimeOfDay.Phase.DUSK
		if action.ends_with("night"):
			ph = TimeOfDay.Phase.NIGHT
		elif action.ends_with("day"):
			ph = TimeOfDay.Phase.DAY
		elif action.ends_with("morning"):
			ph = TimeOfDay.Phase.MORNING
		tod.set_phase(ph, true)   # 瞬时切换，截图用
		return
	# 仰视树冠：检查叶片/樱花冠贴图材质
	if action == "demo_leaf":
		var tree := _first_kind("sakura")
		if tree == null:
			tree = _first_kind("tree")
		if tree != null:
			_look_at_object(tree.kind, 0.0, 2.4, 3.4, 0.55)
		return
	# 侧视/正脸：检查猫的建模与腿/尾（不挪位，用出生点附近的开阔地）
	if action == "demo_cat_side":
		player.look_pitch = -0.06
		player.look_yaw = PI * 0.5
		player._apply_cam_rotation()
	elif action == "demo_cat_front":
		player.look_pitch = -0.16
		player.look_yaw = PI
		player._apply_cam_rotation()
		player._arm.spring_length = 0.72
	elif action == "demo_cat_face":
		player.look_pitch = -0.12
		player._apply_cam_rotation()
		player._arm.spring_length = 0.62
	elif action == "demo_cat_walk":
		# 行走中：检查步态动画
		player.look_yaw = PI * 0.72
		player._apply_cam_rotation()
		player.input_vec = Vector2(0.0, -1.0)
	elif action == "demo_jump":
		# 跳跃验证：站在可跳物件（井盖/长椅/花坛）旁，起跳瞬间抓拍
		var jump_target: Interactable = null
		for kind in ["pipe", "planter", "lowwall", "bench", "crate", "trash"]:
			jump_target = _first_kind(kind)
			if jump_target != null:
				break
		if jump_target != null:
			# 站远一点、退一步，相机拉远，才能看清猫和台面的相对高度
			player.teleport(jump_target.to_global(Vector3(1.6, 0.1, 1.9)), 0.0)
			player.look_pitch = -0.30
			player.look_yaw = PI * 0.78
			player._apply_cam_rotation()
			player._arm.spring_length = 1.9
		# 模拟一次跳跃（停在上升途中）—— 星球上沿脚下法线起跳
		player.do_jump_impulse()


## look: 钩子的实现：找到 kind/word 的第一个实例，摆位 + 对焦 + 拉相机臂
func _look_at_object(want: String, dx: float, dz: float, dist: float, pit: float) -> void:
	var hit := _first_kind(want)
	if hit == null:
		for it in objects:
			if it.word_id == want:
				hit = it
				break
	if hit == null:
		print("[look] 没找到 kind=", want)
		return
	var spot := hit.to_global(Vector3(dx, 0.1, dz))
	player.teleport(spot, 0.0)
	var angles := player.aim_angles(hit.global_position + Vector3(0, 0.5, 0))
	player.look_yaw = angles.x
	player.look_pitch = clampf(pit, Player.CAM_PITCH_MIN, Player.CAM_PITCH_MAX)
	player._apply_cam_rotation()
	player._arm.spring_length = dist
	print("[look] %s @%s -> stand %s, cam_len %.1f" % [want, str(hit.position), str(spot), dist])


## 攀爬逻辑单元测试：--shot-action=demo_climb
## 程序化摆一排不同高度的台阶，每个都朝不同方向走 2 秒，看能不能跨过去。
## 【判据用"最终高度"而不是"走多远"】位移会被地形起伏干扰，登上台阶必然
## 表现为"离地高度增加了台阶高"，这个量最干净。
## 【坑】不要在物理帧里反复 add_child/queue_free StaticBody3D —— headless 下会段错误
## （实测 exit=139）。复用一个 body，只改它的 shape/位置。
func _demo_climb() -> void:
	player.cam_follow = false
	player.input_locked = false
	for i in 12:
		await get_tree().physics_frame
	var base := player.global_position
	var up := player.up_axis()
	# 【必须在人工平面上测】直接拿岛上的斜坡当地面，判据会被地形污染：
	# 爬上去之后继续走 2 秒会顺坡下溜，净高度变化可正可负（实测 +2.23m / -1.54m），
	# 完全反映不了"有没有跨上台阶"。所以先铺一块绝对水平的平板，
	# 全部朝向共用同一个 yaw，唯一的变量就是台阶高度。
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fcs := CollisionShape3D.new()
	var fbx := BoxShape3D.new()
	fbx.size = Vector3(14.0, 0.4, 14.0)
	fcs.shape = fbx
	# 平板顶面 = base 脚下（往下埋 0.2）
	var flat_basis := _basis_from_up(up)
	fcs.global_transform = Transform3D(flat_basis, base - up * 0.2)
	floor_body.add_child(fcs)
	add_child(floor_body)
	for i in 3:
		await get_tree().physics_frame
	var origin := base + up * 0.1
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.0, 0.3, 2.0)
	cs.shape = bx
	body.add_child(cs)
	add_child(body)
	print("[climb] STEP_CLIMB=%.2f CLIMB_PROBE=%.2f 理论可爬坡度上限≈%.0f°" % [
		Player.STEP_CLIMB, Player.CLIMB_PROBE,
		rad_to_deg(atan(Player.STEP_CLIMB / Player.CLIMB_PROBE))])
	var heights := [0.12, 0.2, 0.28, 0.34, 0.4, 0.6, 1.0]
	var pass_n := 0
	for k in heights.size():
		var h: float = heights[k]
		player.teleport(origin, 0.0)
		for i in 4:
			await get_tree().physics_frame
		var fwd := player.facing()
		# 台阶摆在正前方 1.1m。底面必须落在【平板顶面】上：
		# 平板顶面 = base，所以台阶中心 = base + up*(h*0.5)。
		# （之前写成 origin + up*(h*0.5)，而 origin 高出平板 0.1m，台阶等于浮空，
		#   判定基准和几何都对不上。）
		var c := base + fwd * 1.1
		bx.size = Vector3(2.0, h, 2.0)
		cs.global_transform = Transform3D(flat_basis, c + up * (h * 0.5))
		for i in 2:
			await get_tree().physics_frame
		# 起点摆到台阶正前方 0.7m
		player.teleport(base + fwd * 0.4, 0.0)
		for i in 4:
			await get_tree().physics_frame
		# 判据：整个行走过程中【曾经】达到台阶顶面高度。
		# 【为什么取峰值而不是终值】台阶只有 2m 深，2 秒能走 4.7m ——
		# 跨上去之后会从远边走下来摔回地面，终值又变回地面高度，
		# 于是"跨过去了"被误判成"被挡住"（实测 0.28m 明明跨过去了却判失败）。
		var peak := -INF
		for f in 120:
			player.input_vec = Vector2(0.0, -1.0)
			await get_tree().physics_frame
			# 相对台阶【顶面】的高度：站上去 = 0，停在台阶前 = -h
			peak = maxf(peak, (player.global_position - (c + up * h)).dot(up))
		# 严格判据：站上台阶 = 高度达到顶面（容差 0.06m）。
		# 【别把阈值放太松】实测 0.40m 台阶时峰值 -0.15m（爬了 0.25 但没上去），
		# 用 -h*0.45 当阈值会把它误判成"跨过去了"。
		var got_up: bool = peak > -0.06
		var expect_up: bool = h < Player.STEP_CLIMB
		var ok: bool = got_up == expect_up
		if ok:
			pass_n += 1
		print("[climb] 台阶高=%.2fm 期望=%s 实测=%s(峰值相对顶面%+0.2fm) %s" % [
			h, ("应跨过" if expect_up else "应被挡"),
			("跨过了" if got_up else "被挡住"), peak, ("OK" if ok else "≠ 不符")])
	print("[climb] 通过 %d/%d" % [pass_n, heights.size()])
	body.queue_free()
	floor_body.queue_free()


## 90° 垂直墙爬墙验证：--shot-action=demo_wall
## 【场景】人工平板上立一面高墙（远高于 STEP_CLIMB=0.34，台阶攀爬必然过不去），
## 狐狸贴墙推前进 4 秒。判据与 _demo_climb 一致取【峰值相对墙顶的高度】：
##   ① climbing 状态被置位过（状态机真的进了爬墙分支，不是靠别的机制飘上去）
##   ② 峰值高于墙顶（真的翻上去了，不是在墙根打滑）
##   ③ 结束时站在墙顶另一侧的高度附近（mantle 后落稳，不是翻上去又滚下来）
## 【坑】沿用 _demo_climb 的教训：不在物理帧里 add/free 刚体（headless 会段错误），
## 复用同一个 StaticBody3D；判据不用位移量（会被墙沿卡住的零位移骗到）。
func _demo_wall() -> void:
	player.cam_follow = false
	player.input_locked = false
	for i in 12:
		await get_tree().physics_frame
	var base := player.global_position
	var up := player.up_axis()
	var flat_basis := _basis_from_up(up)
	# 绝对水平的人工平板（顶面 = base），排除地形起伏对判据的污染
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fcs := CollisionShape3D.new()
	var fbx := BoxShape3D.new()
	fbx.size = Vector3(14.0, 0.4, 14.0)
	fcs.shape = fbx
	fcs.global_transform = Transform3D(flat_basis, base - up * 0.2)
	floor_body.add_child(fcs)
	add_child(floor_body)
	for i in 3:
		await get_tree().physics_frame

	var fwd := player.facing()
	var wall_h := 2.0     # 高于 STEP_CLIMB 一个数量级，必须走爬墙
	var wall_top := base + up * wall_h
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(3.0, wall_h, 0.3)   # 宽 3m 厚 0.3m 的垂直墙
	cs.shape = bx
	# 墙立在正前方 1.0m：底面贴平板顶面（中心 = 底面 + up*h/2）
	cs.global_transform = Transform3D(flat_basis, base + fwd * 1.0 + up * (wall_h * 0.5))
	body.add_child(cs)
	add_child(body)
	for i in 3:
		await get_tree().physics_frame

	# 起点到墙 0.6m，推满前进（摇杆 y 上推 = drive>0）。【mantle 一发生就松杆】——
	# 墙顶只有 0.3m 宽，继续推狐狸会从另一侧走下去（正常行为），判据就全是假的。
	# 判据取 mantle 落点 + 站稳（与隔离环境 walltest 的结论一致）。
	player.teleport(base + fwd * 0.6, 0.0)
	for i in 4:
		await get_tree().physics_frame
	var saw_climb := false
	var peak := -INF
	var mantle_rel := INF
	var was_climbing := false
	for f in 300:
		player.input_vec = Vector2(0.0, -1.0)
		await get_tree().physics_frame
		saw_climb = saw_climb or player.climbing
		# 相对墙顶的高度：站上墙顶 = 0，墙根 = -wall_h
		peak = maxf(peak, (player.global_position - wall_top).dot(up))
		if was_climbing and not player.climbing and not is_finite(mantle_rel):
			mantle_rel = (player.global_position - wall_top).dot(up)
			player.input_vec = Vector2.ZERO
			break
		was_climbing = player.climbing
	player.input_vec = Vector2.ZERO
	# 松手后落稳：mantle 之后应停在墙顶平面上，而不是滑落回墙根
	for i in 60:
		await get_tree().physics_frame
	var end_rel := (player.global_position - wall_top).dot(up)
	var ok_climb := saw_climb
	var ok_peak := peak > -0.12
	var ok_end := mantle_rel > -0.4 and absf(end_rel) < 0.35
	print("[wall] 爬墙状态=%s 峰值相对墙顶=%+0.2fm mantle落点=%+0.2fm 结束=%+0.2fm" % [
		("进入过" if saw_climb else "从未进入"), peak, mantle_rel, end_rel])
	print("[wall] 进入爬墙=%s 翻上墙顶=%s 落稳墙顶=%s → %s" % [
		ok_climb, ok_peak, ok_end, ("PASS" if (ok_climb and ok_peak and ok_end) else "FAIL")])
	body.queue_free()
	floor_body.queue_free()


## 以 up 为 Y 轴构造正交基（人工平面用；岛上的切平面基不能直接复用）
func _basis_from_up(up: Vector3) -> Basis:
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)


## 卡死普查：--shot-action=demo_stuck
## 全岛网格撒点，每点向 8 个朝向各走 2.5 秒，统计走不动的点，并给每个卡死点
## 测量"挡路障碍物的高度"（沿 up 打射线找挡住前进方向的碰撞体顶面）。
## 用途：区分三类卡死 ——
##   ① 台阶太高（顶面 < STEP_HEIGHT 就能跨，说明缺攀爬逻辑）
##   ② 死局（8 个方向全走不动 = 被围住，必须给脱困机制）
##   ③ 模型碰撞体过大（META.solid 明显大于视觉，猫被空气墙挡住）
func _demo_stuck() -> void:
	player.cam_follow = false
	player.input_locked = false
	for i in 12:
		await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var stuck_pts := 0
	var dead_ends := 0
	var total := 0
	var low_step := 0     # 障碍顶面 < 0.35m：属于"矮台阶"，加攀爬即可
	var tall_block := 0  # 障碍顶面 >= 0.35m：真障碍，得绕
	for gy in range(1, 9):
		for gx in range(1, 11):
			var px := Vector2(world_px.x * float(gx) / 11.0, world_px.y * float(gy) / 9.0)
			var dir := planet_math.dir_from_px(px, world_px)
			var spot := planet_builder.surface(dir)
			var sp: Vector3 = spot["pos"]
			var sn: Vector3 = (spot["normal"] as Vector3).normalized()
			var origin := sp + sn * 0.15
			# 起点若卡在建筑里，先推到空处
			var probe := SphereShape3D.new()
			probe.radius = Player.CAT_RADIUS + 0.19
			for attempt in 12:
				var qp := PhysicsShapeQueryParameters3D.new()
				qp.shape = probe
				qp.collision_mask = 1
				qp.transform = Transform3D(Basis(), origin + sn * 0.3)
				if space.intersect_shape(qp, 1).is_empty():
					break
				origin += sn * 0.8
			var moved_list := PackedFloat32Array()
			var block_h := -1.0
			var block_name := ""
			for k in 8:
				var yaw := deg_to_rad(float(k) * 45.0)
				player.teleport(origin, yaw)
				player.input_vec = Vector2.ZERO
				for i in 3:
					await get_tree().physics_frame
				var from := player.global_position
				for f in 150:
					player.input_vec = Vector2(0.0, -1.0)
					await get_tree().physics_frame
				var moved := from.distance_to(player.global_position)
				moved_list.append(moved)
				total += 1
				if moved < 0.6:
					stuck_pts += 1
					# 测挡路物体：从猫前方 0.5m 沿 up 向上打射线，找最近的障碍顶面高度
					if block_h < 0.0:
						var up := player.up_axis()
						var hd := player.facing()
						var base: Vector3 = player.global_position + hd * (Player.CAT_RADIUS + 0.35)
						var hq := PhysicsRayQueryParameters3D.create(
								base + up * 0.05, base + up * 3.0, 1)
						var hh := space.intersect_ray(hq)
						if not hh.is_empty():
							block_h = (hh["position"] as Vector3).dot(up) - (player.global_position).dot(up)
							var oc: Variant = hh.get("collider")
							block_name = str((oc as Node).name) if oc is Node else "?"
						else:
							block_h = -0.5   # 前方没障碍却是墙 → 地形陡
							block_name = "<陡坡>"
			var stuck_dirs := 0
			for m in moved_list:
				if m < 0.6:
					stuck_dirs += 1
			if stuck_dirs == 8:
				dead_ends += 1
				print("[stuck] 死局! px=(%4d,%4d) 起点=%s" % [int(px.x), int(px.y), str(origin.round())])
			elif stuck_dirs > 0:
				print("[stuck] 卡死 %d/8 方向 px=(%4d,%4d) 位移=%s 障碍高=%.2f(%s)" % [
					stuck_dirs, int(px.x), int(px.y),
					str(Array(moved_list).map(func(x): return round(x * 10.0) / 10.0)),
					block_h, block_name])
			if block_h >= 0.0:
				if block_h < 0.35:
					low_step += 1
				else:
					tall_block += 1
	print("[stuck] 合计 %d 次尝试，卡死 %d 次，其中完全死局 %d 个点" % [total, stuck_pts, dead_ends])
	print("[stuck] 障碍高度分类：矮台阶(<0.35m，缺攀爬) %d 处 / 高障碍(需绕) %d 处" % [low_step, tall_block])


## 四方向对照：--shot-action=demo_walk_all
## 固定同一起点 + 同一步长，四个朝向各走一遍，打印位移/末速/顶住帧数/地面坡度/撞到的碰撞体。
## 【为什么不能只跑 demo_walk 四次】单方向跑时，玩家出生点来自存档，而上一次运行
## 写回存档的位置会变成这一次的起点 —— 四份日志起点不同，横向比毫无意义
## （本次排查就被这个坑误导过一轮：四向位移 6.1/5.0/3.6/7.9 看似随机）。
## 用法：godot --headless --path . --quit-after 2500 -- --shot=out/x.png
##       --shot-frames=99999 --shot-scene=res://scenes/street.tscn --shot-action=demo_walk_all
## 判读：四个位移应当接近（期望≈6.5m）。某方向明显短 → 看该方向的"平均坡"与
## "顶住"帧数：坡度大 = 地形陡；坡度小却顶住 = 隐形碰撞（看"撞到"里的名字）。
## 楼梯 / 现成贴图验收探针。产物：out/stair_probe.txt
## 用法：godot --headless --path . --quit-after 900 -- --shot-action=probe_stairs
##
## 【这一轮在验什么】用户要求「楼梯、墙面这些应该多弄点贴图，不要自己画」，
## 改完之后必须证明四件事真的落地，而不是「代码看起来对」：
##   1. 21 套新贴图的 kind 真被 mat_photo 命中（有图，不是回退纯色）
##   2. 室外楼梯几何真生成了（StairStep 节点 + 碰撞体 + 挂着真贴图）
##   3. 室内上屋台真抬起来了（deck 顶面高度 + 家具 y_lift 生效）
##   4. 12 栋民居墙面贴图真分散了（改前恒为 grey_plaster 一种）
func _probe_stairs() -> void:
	var out: Array[String] = []
	out.append("=== 1. 贴图 kind 命中检查 ===")
	for k in ["step_concrete", "step_grey", "step_wood", "step_antiskid",
			"step_granite", "wood_floor", "tatami", "tiles", "tiles_terrazzo",
			"wall_white_rough", "wall_white_plank", "wall_plank_siding",
			"wall_yellow", "wall_mossy", "wall_block", "stone_jp",
			"plaster_stone", "wood_hinoki", "floor_old_wood", "concrete_tile_facade"]:
		out.append("  has_tex(%s) = %s" % [k, str(Interactable.has_tex(k))])

	out.append("=== 2. 室外楼梯几何 ===")
	for kind in ["house", "station", "konbini", "cafe", "ramen", "post_office", "mansion"]:
		var it := Interactable.make({"kind": kind, "x": 0, "y": 0})
		add_child(it)
		await get_tree().process_frame
		var steps := 0
		var bodies := 0
		var step_mats := {}
		for c in it.get_children():
			if c is MeshInstance3D and str(c.name).begins_with("StairStep"):
				steps += 1
				var pname := "null"
				var m: Material = c.material_override
				if m is ShaderMaterial:
					var sp: ShaderMaterial = m
					if sp.get_shader_parameter("use_albedo_tex") == false:
						pname = "NO_TEX(回退纯色!)"
					else:
						var tex: Texture2D = sp.get_shader_parameter("albedo_tex")
						pname = str(tex.resource_path).get_file() if tex != null else "NULL_TEX"
				step_mats[pname] = int(step_mats.get(pname, 0)) + 1
			elif c is StaticBody3D and not str(c.name).begins_with("Stair"):
				bodies += 1
		out.append("  %-12s StairStep=%d  建筑碰撞体=%d  贴图=%s" % [kind, steps, bodies, str(step_mats)])
		it.queue_free()
	await get_tree().process_frame

	out.append("=== 3. 室内上屋台 / 楼梯 ===")
	for tid in ["house_basic", "apartment", "station_hall"]:
		var b := InteriorBuilder.new()
		add_child(b)
		var objs: Array = b.setup(tid, "probe")
		await get_tree().process_frame
		var deck_top := -99.0
		var tiles_lifted := 0
		var mesh_count := 0
		for c in b.get_children():
			if c is MeshInstance3D:
				mesh_count += 1
				var mi: MeshInstance3D = c
				if mi.mesh is BoxMesh:
					var bs: BoxMesh = mi.mesh
					var top: float = mi.position.y + bs.size.y * 0.5
					# 上屋台面：又宽又薄、顶面在 0.1~0.4m 之间
					if top > 0.10 and top < 0.4 and bs.size.x > 3.0 and bs.size.y < 0.3:
						deck_top = maxf(deck_top, top)
					if mi.position.y > 0.15 and bs.size.x > 3.0 and bs.size.y < 0.1:
						tiles_lifted += 1
		var lifted := 0
		for o in objs:
			var ob: Node3D = o
			if ob.position.y > 0.01:
				lifted += 1
		out.append("  %-14s 上屋台顶面=%.3fm  抬高地砖=%d  家具抬高=%d/%d  mesh=%d"
			% [tid, deck_top, tiles_lifted, lifted, objs.size(), mesh_count])
		b.queue_free()
		for o in objs:
			var ob2: Node3D = o
			if is_instance_valid(ob2):
				ob2.queue_free()
	await get_tree().process_frame

	out.append("=== 4. 民居墙面贴图分布（模拟 12 栋不同位置） ===")
	var probe := Interactable.make({"kind": "house", "x": 0, "y": 0})
	var kinds := {}
	for i in 12:
		probe.position = Vector3(400.0 + float(i) * 137.0, 0.0, 300.0 + float(i) * 211.0)
		var k: String = probe._house_wall_tex(probe.position)
		kinds[k] = int(kinds.get(k, 0)) + 1
	out.append("  12 栋分布 = " + str(kinds))
	out.append("  不同贴图种类 = %d （改前恒为 1）" % kinds.size())
	probe.free()

	DirAccess.make_dir_recursive_absolute("res://out")
	var f := FileAccess.open("res://out/stair_probe.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(out))
		f.close()
		print("[probe] 已写出 out/stair_probe.txt")
	for l in out:
		print("[probe] ", l)


## 四方向对照行走（demo_walk跑四次的正确替代，见上）。
func _demo_walk_all() -> void:
	player.cam_follow = false
	player.input_locked = false
	# 【必须先等物理帧】本钩子在 _ready() 里跑，此时玩家的延迟落位（_ground_snap）
	# 还没执行，global_position 还是悬空的标称球面点（r≈51）。直接拿它当固定起点，
	# 四轮都会从空中起步，测出来的全是落地姿态，横向比没有意义。
	for i in 12:
		await get_tree().physics_frame
	var origin := player.global_position
	player.input_vec = Vector2.ZERO
	print("[walkall] 固定起点 r=%.2f pos=%v" % [origin.length(), origin])
	for yaw_deg in [0.0, 90.0, 180.0, 270.0]:
		# 每轮都回固定起点，且等物理稳定（否则上一轮的落点/速度会污染这一轮）
		player.teleport(origin, deg_to_rad(yaw_deg))
		for i in 4:
			await get_tree().physics_frame
		var from := player.global_position
		var hits := {}
		var stalled := 0
		var floor_frames := 0
		var worst_tilt := 0.0
		var sum_slope := 0.0
		var slope_n := 0
		var max_slope := 0.0
		var trace := PackedStringArray()
		var prev := from
		for f in 180:
			player.input_vec = Vector2(0.0, -1.0)
			for c in player.get_slide_collision_count():
				var col := player.get_slide_collision(c)
				var o: Variant = col.get_collider()
				var nm := str((o as Node).name) if o is Node else str(o)
				hits[nm] = int(hits.get(nm, 0)) + 1
			# 连续多帧速度≈0 = 顶住了
			if player.tangent_speed() < 0.15:
				stalled += 1
			if player.is_on_floor():
				floor_frames += 1
				# 地面法线与「世界上方向 +Y」的夹角：is_on_floor() 判的就是这个
				var tilt := rad_to_deg(player.get_floor_normal().angle_to(Vector3.UP))
				worst_tilt = maxf(worst_tilt, tilt)
			# 真正决定费劲程度的：地面法线与【当地径向】的夹角 = 坡度。
			# 上坡时速度要分一份去爬升，下坡时重力反而加成 —— 这才是方向不对称的来源。
			if f % 20 == 19:
				var u := player.up_axis()
				var slope := rad_to_deg(player.get_floor_normal().angle_to(u))
				sum_slope += slope
				slope_n += 1
				max_slope = maxf(max_slope, slope)
				if f % 60 == 59:
					trace.append("f%3d v=%.2f 坡=%2.0f° r=%.1f" % [
						f + 1, player.tangent_speed(), slope, player.global_position.length()])
			prev = player.global_position
			await get_tree().physics_frame
		var up := player.up_axis()
		var rel := player.global_position - from
		var tang := rel - up * rel.dot(up)
		print("[walkall] yaw=%5.0f 位移=%.2fm 期望≈6.5m 末速=%.2f 站地=%s 撞墙=%s 顶住=%d 站地帧=%d/180 法线偏+Y最大=%.0f° 平均坡=%.0f° 最大坡=%.0f° 撞到=%s" % [
			yaw_deg, tang.length(), player.tangent_speed(),
			str(player.is_on_floor()), str(player.is_on_wall()), stalled, floor_frames, worst_tilt,
			(0.0 if slope_n == 0 else sum_slope / float(slope_n)), max_slope, str(hits)])
		if trace.size() > 0:
			print("[walkall]   轨迹 %s" % " | ".join(trace))
	player.input_vec = Vector2.ZERO
	player.teleport(origin, 0.0)



## 打印切向位移与速度。位移 ≈2.35m/s×t（去掉起步加速 ≈6.5m/3s）；某方向明显
## 短 = 该方向有隐形碰撞。
func _demo_walk(arg: String) -> void:
	var yaw := deg_to_rad(float(arg) if not arg.is_empty() else 0.0)
	player.teleport(player.global_position, yaw)
	player.cam_follow = false
	var from := player.global_position
	print("[walk] 起点 r=%.2f  pos=%v" % [from.length(), from])
	var konb := _first_kind("konbini")
	if konb != null:
		print("[walk] konbini r=%.2f pos=%v" % [konb.global_position.length(), konb.global_position])
	for f in 180:
		player.input_vec = Vector2(0.0, -1.0)
		if f % 30 == 29:
			var up := player.up_axis()
			var rel := player.global_position - from
			var tang := rel - up * rel.dot(up)
			# 脚下诊断：沿 -up 打射线（排除玩家自身），看离地高度与地面坡度
			var space := get_world_3d().direct_space_state
			var dq := PhysicsRayQueryParameters3D.create(player.global_position + up * 0.5,
					player.global_position - up * 3.0, 3)
			dq.exclude = [player.get_rid()]
			var gh := space.intersect_ray(dq)
			var gap := -1.0
			var slope := -2.0
			if not gh.is_empty():
				gap = (player.global_position - (gh["position"] as Vector3)).dot(up)
				slope = (gh["normal"] as Vector3).normalized().dot(up)
			var fn := player.get_floor_normal()
			print("[walk] yaw=%5.1f f=%3d 切向位移=%.2fm 速度=%.2f 站地=%s 撞墙=%s 离地=%.2f 地面坡dot=%.2f floor坡dot=%.2f 锁=%s" % [
				rad_to_deg(yaw), f + 1, tang.length(), player.tangent_speed(),
				str(player.is_on_floor()), str(player.is_on_wall()), gap, slope, fn.dot(up),
				str(player.input_locked)])
		await get_tree().physics_frame
	player.input_vec = Vector2.ZERO


func _first_kind(kind: String) -> Interactable:
	for it in objects:
		if it.kind == kind:
			return it
	return null


## 悬空审计（--shot-action=audit_float）：在**真实场景**里量每个物件的离地空隙。
## 与 _tools/audit_float.tscn 的区别：那个工具复刻 street 的调用时序来证明根因，
## 这个直接查摆完之后的 Interactable.global_position —— 验的是修复本身有没有生效。
##
## 空隙 = 物件原点到当地地面，沿当地法线量的有符号距离（负 = 嵌进地里）。
## 物件的局部几何假设「原点站在自己 y=0 平面上」，所以原点离地多远 = 有多悬空。
const AUDIT_FLOAT_M := 0.35    ## 判定悬空的空隙阈值（米）
const AUDIT_SINK_M := -1.2     ## 判定「埋进地里看不见」的阈值（米）


func _audit_float() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var lines: PackedStringArray = []
	var n_ok := 0
	var n_float := 0
	var n_sink := 0
	var worst: Array[Dictionary] = []
	for it in objects:
		var pos: Vector3 = it.global_position
		var up: Vector3 = pos.normalized()
		var q := PhysicsRayQueryParameters3D.create(pos + up * 30.0, pos - up * 30.0, 2)
		q.collide_with_bodies = true
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			n_float += 1
			worst.append({"kind": it.kind, "gap": 999.0, "r": pos.length()})
			continue
		var gp: Vector3 = hit["position"]
		var gap := (pos - gp).dot((hit["normal"] as Vector3).normalized())
		if gap > AUDIT_FLOAT_M:
			n_float += 1
			if worst.size() < 25:
				worst.append({"kind": it.kind, "gap": gap, "r": pos.length()})
		elif gap < AUDIT_SINK_M:
			n_sink += 1
		else:
			n_ok += 1
	worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["gap"]) > float(b["gap"]))
	lines.append("=== 悬空审计（真实场景） ===")
	lines.append("物件总数 %d：贴地 %d / 悬空 %d / 埋进地下 %d" % [
		objects.size(), n_ok, n_float, n_sink])
	lines.append("（判定：悬空 = 离地 > %.2fm，埋地 = 离地 < %.1fm）" % [
		AUDIT_FLOAT_M, AUDIT_SINK_M])
	lines.append("悬空最大的（kind / 离地 / 当前 r）：")
	for w: Dictionary in worst:
		lines.append("  %-14s 离地=%6.2fm  r=%.1f" % [
			String(w["kind"]), float(w["gap"]), float(w["r"])])
	var txt := "\n".join(lines)
	print(txt)
	var rf := FileAccess.open("out/audit_float_live.txt", FileAccess.WRITE)
	for l in lines:
		rf.store_line(l)
	rf.close()
	print("[audit] 报告 → out/audit_float_live.txt")
	get_tree().quit()
