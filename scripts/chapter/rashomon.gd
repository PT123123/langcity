class_name Rashomon
extends Node3D
## 《罗生门·岭南篇》—— 独立线性剧情章节（不进星球地图/Places 管线）。
##
## 竖切流程（docs/rashomon_game_chapter_spec_guangdong.md 的 MVP）：
##   官道（小贩/挑夫 + 词汇载体）→ 南城门门下避雨 → 楼梯（黑暗恐吓）
##   → 城门楼上层（火盆 + 尸体 + 林婆）→ 观察 4 个对象 → 被发现对质
##   → 模式 A 关键词问答（听懂才懂剧情）→ 抢衣服 QTE → 逃离黑屏 → 章节结算。
##
## 复用：Player（平地模式）/ Game.discover + WordPopup / DialogueBox / UiKit / Toast / Tts。
## 坐标约定：+Z 为南（官道起点），-Z 为北（南城门在 z ≈ -16）；墙顶楼面高 TOP_Y。

const CHAPTER_WORDS := ["ame", "kaze", "yoru", "mon", "kaidan", "jouhei", "samui",
	"kurai", "takai", "yasui", "shitai", "kami", "fuku", "roujin", "hito",
	"tabemono", "kome", "mizu", "kau", "uru", "karasu", "hi", "amayadori"]

const FLOOR_Y := 0.0
const WALL_Z := -16.0
const WALL_T := 4.8
const TOP_Y := 5.4
const SPAWN := Vector3(0, 0.1, 52)
const STAIR_X := 6.2
const STAIR_TOP_Z := -13.6
const LINPO_POS := Vector3(3.2, TOP_Y, -15.2)

enum Ph { STREET, SHELTER, CLIMB, UPPER, TALK, GRAB, AWAY, END }

const CHALLENGES := [
	{"line": "この髪は、かつらにするんです。", "zh": "这头发，是要做成假发的。",
		"kw": "髪", "opts": ["髪", "水", "門"]},
	{"line": "死人の服だって、売れるんです。", "zh": "死人的衣服，也是能卖的。",
		"kw": "服", "opts": ["服", "米", "火"]},
	{"line": "私はただ、食べ物が必要なんです。", "zh": "我只是，需要食物而已。",
		"kw": "食べ物", "opts": ["食べ物", "火", "夜"]},
	{"line": "暗い夜は、火がなければ何も見えない。", "zh": "黑暗的夜，没有火光什么也看不见。",
		"kw": "火", "opts": ["火", "雨", "老人"]},
	{"line": "あなただって、水が欲しかったでしょう？", "zh": "就连你，不也想要过水吗？",
		"kw": "水", "opts": ["水", "米", "寒い"]},
]

var phase: Ph = Ph.STREET
var player: Player
var popup: WordPopup
var dlg_box: DialogueBox
var layer: CanvasLayer

var props := []                    # 可拍照载体 {node, ring, word, range, story, shot, rr}
var story_total := 0               # story 观察目标总数
var story_done := 0
var photo_count := 0               # 章节内拍过的载体数
var perfect := 0
var challenge_idx := 0
var challenge_ok := 0
var challenge_first := true
var hunger := 20.0
var _hunger_warn := false
var _shelter_done := false
var _climb_started := false
var _upper_started := false
var _spotted := false
var _talk_done := false
var _scare := [false, false]
var _talked := {}                  # 自动对话去重
var _dlg_cb: Callable = Callable()
var _active := -1                  # 当前高亮 prop 序号
var _shoot_cd := 0.0

# UI（部分延迟创建）
var hud: CanvasLayer
var hint_label: Label
var hunger_bar: ProgressBar
var shoot_btn: Button
var jump_btn: Button
var menu_btn: Button
var _flash_rect: ColorRect
var _fade_rect: ColorRect
var _center_label: Label
var rain: GPUParticles3D

# 问答面板
var chal_panel: PanelContainer
var chal_line: Label
var chal_zh: Label
var chal_opts: VBoxContainer
var chal_note: Label
var _chal_timer := 0.0
var _chal_masked := false
var _chal_cur := {}

# 抢衣 QTE
var grab_panel: PanelContainer
var grab_bar: ProgressBar
var grab_note: Label
var _grab_t := 0.0
var _grab_speed := 0.62
var _grab_try := 0

# 结算
var end_panel: PanelContainer
var _ending_texts := []
var joy: VirtualJoystick


func _ready() -> void:
	_bot = "--chapter-bot" in OS.get_cmdline_user_args()
	if not _bot:
		Game.save_now()   # 进章节先落盘，防 street 侧 3 秒去抖丢档
	_setup_env()
	_build_world()
	_build_props()
	_setup_player()
	_setup_ui()
	_make_rain()
	player.teleport(SPAWN, 0.0)
	_hint("雨が強い。南へ向かおう——先躲进南门再说。")
	if not _bot:
		for a in OS.get_cmdline_user_args():   # 开发截图机位（配 ShotTool --shot=...）
			if a.begins_with("--chapter-pose="):
				_pose(a.substr(15))
				break
	if _bot:
		_bot_run.call_deferred()   # 全链路自测：好好学习自动走完（不写存档，见文件头）
		_bot_timeout.call_deferred()


## 开发截图机位（配合 ShotTool：--shot=out/x.png --shot-frames=50 --chapter-pose=...）
func _pose(which: String) -> void:
	match which:
		"street":
			_pose_at(Vector3(0, 0.12, 40), 0.0, -0.25)
		"gate":
			_pose_at(Vector3(0, 0.12, -6.0), 0.0, -0.1)
		"stairs":
			_pose_at(Vector3(2.2, 0.9, -5.0), -0.785, -0.2)
		"top":
			_pose_at(Vector3(5.0, TOP_Y + 0.12, -13.4), -2.2, -0.28)
		"upstairs":
			_pose_at(Vector3(4.6, TOP_Y + 0.12, -13.0), -1.9, -0.18)
		"fire":
			_pose_at(Vector3(4.9, TOP_Y + 0.3, -14.4), 1.1, -0.3)
	_hint("")


func _pose_at(pos: Vector3, yaw: float, pitch: float) -> void:
	player.teleport(pos, yaw)
	player.look_pitch = pitch
	player.look_yaw = 0.0
	player.cam_follow = false


func _bot_timeout() -> void:
	await _wait(150.0)
	if is_inside_tree():
		print("[bot] TIMEOUT phase=", ph_name(), " dlg=", dlg_box.visible,
			" chal=", chal_panel.visible, " grab=", grab_panel.visible,
			" end=", end_panel.visible, " spotted=", _spotted, " spotted_done=", _talk_done)
		get_tree().quit(1)


# =============================================================
# 环境 / 地形
# =============================================================

func _setup_env() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.09, 0.11, 0.17)
	sky_mat.sky_horizon_color = Color(0.28, 0.29, 0.34)
	sky_mat.ground_bottom_color = Color(0.05, 0.05, 0.07)
	sky_mat.ground_horizon_color = Color(0.2, 0.21, 0.25)
	sky_mat.sun_angle_max = 18.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.65
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 2.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.33, 0.35, 0.42)
	env.fog_density = 0.014
	env.fog_sky_affect = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.70, 0.88)
	moon.light_energy = 0.55
	moon.light_specular = 0.0
	moon.rotation_degrees = Vector3(-44.0, 26.0, 0.0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.0
	add_child(moon)


func _static(pos: Vector3, size: Vector3, m: Material, layer_v := 1) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer_v
	b.collision_mask = 0
	b.position = pos
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = m
	b.add_child(mi)
	add_child(b)
	return b


func _build_world() -> void:
	var mud := Interactable.mat_photo("dirt", Color(0.55, 0.52, 0.46), 0.85, 0.96, 0.55,
		ProceduralTex.asphalt(11), 0.3, 2.4, 0.4)
	var road := Interactable.mat_photo("road", Color(0.40, 0.38, 0.36), 0.9, 0.95, 0.6,
		ProceduralTex.asphalt(7), 0.3, 2.0, 0.35)
	_floor_plate(Vector3(0, -0.15, 8), Vector3(76, 0.3, 140), mud)
	_floor_plate(Vector3(0, -0.05, 8), Vector3(7.0, 0.1, 140), road)
	_floor_plate(Vector3(0, -0.15, -40), Vector3(76, 0.3, 40), mud)   # 门后北面推不进去，也铺上
	_static(Vector3(-22.5, 4.0, 8), Vector3(1.0, 8.0, 160), mud)
	_static(Vector3(22.5, 4.0, 8), Vector3(1.0, 8.0, 160), mud)
	_static(Vector3(0, 4.0, 62.0), Vector3(60.0, 8.0, 1.0), mud)
	_build_city_wall()


func _floor_plate(pos: Vector3, size: Vector3, m: Material, layer_v := 2) -> void:
	var b := _static(pos, size, m, layer_v)
	var mi := (b.get_child(1) as MeshInstance3D)
	if mi != null:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_city_wall() -> void:
	var stone := Interactable.mat_photo("stone", Color(0.52, 0.50, 0.47), 0.9, 0.9, 0.9,
		ProceduralTex.pavers(3), 0.3, 3.0, 0.4)
	var stone_d := Interactable.mat_photo("brick_old", Color(0.44, 0.42, 0.40), 0.9, 0.9, 1.0,
		ProceduralTex.pavers(5), 0.3, 2.6, 0.4)
	var wood := Interactable.m_wood(Vector3.ZERO)
	var south_z := WALL_Z + WALL_T * 0.5
	var north_z := WALL_Z - WALL_T * 0.5
	# 段墙 x[-20,-2.8] / x[2.8,20]；门洞宽 5.6、高 4.0
	_static(Vector3(-11.4, TOP_Y * 0.5, WALL_Z), Vector3(17.2, TOP_Y, WALL_T), stone)
	_static(Vector3(11.4, TOP_Y * 0.5, WALL_Z), Vector3(17.2, TOP_Y, WALL_T), stone)
	_static(Vector3(0, (TOP_Y + 4.0) * 0.5, WALL_Z), Vector3(5.9, TOP_Y - 4.0, WALL_T), stone_d)
	_static(Vector3(-3.1, 2.0, WALL_Z), Vector3(0.7, 4.0, WALL_T), stone_d)
	_static(Vector3(3.1, 2.0, WALL_Z), Vector3(0.7, 4.0, WALL_T), stone_d)
	# 墙顶行人层
	_floor_plate(Vector3(0, TOP_Y - 0.11, WALL_Z), Vector3(40.0, 0.22, WALL_T + 2.4), stone_d, 2)
	# 北侧女儿墙（防坠）
	_static(Vector3(0, TOP_Y + 0.45, north_z - 0.6), Vector3(40.0, 0.9, 0.5), stone_d)
	# 南檐柱（装饰；两侧让出中央走道，别挡火盆/尸体）
	for i in 9:
		var pxx := -16.0 + float(i) * 4.0
		if absf(pxx) < 5.5:
			continue
		_static(Vector3(pxx, TOP_Y + 1.5, -14.6), Vector3(0.34, 3.0, 0.34), wood)
	# 只剩一半的碎檐
	_static(Vector3(-9.0, TOP_Y + 3.1, WALL_Z + 0.4), Vector3(14.0, 0.2, WALL_T + 2.0),
		Interactable.mat_photo("roof", Color(0.30, 0.32, 0.36), 0.9, 0.85, 0.4,
			ProceduralTex.roof_tiles(9), 0.4, 2.0, 0.35))
	_build_stairs(stone_d)
	# 楼梯两侧护栏
	_static(Vector3(4.55, 2.6, -9.0), Vector3(0.3, 1.0, 10.4), stone_d)
	_static(Vector3(7.85, 2.6, -9.0), Vector3(0.3, 1.0, 10.4), stone_d)
	_static(Vector3(5.6, 0.75, -3.25), Vector3(1.7, 1.5, 0.4), stone_d)


func _build_stairs(m: Material) -> void:
	var steps := 20
	var rise := TOP_Y / steps                 # 0.27
	var tread := 0.52
	for i in steps:
		var z := -3.2 - float(i) * tread
		var top := rise * (float(i) + 1.0)
		_static(Vector3(STAIR_X, top - rise * 0.5, z), Vector3(2.2, rise, tread), m, 2)
		# 台阶下方填实，避免悬空缝隙（也防止猫从侧面钻空）
		_static(Vector3(STAIR_X, i * rise * 0.5, z - tread * 0.5), Vector3(2.2, i * rise, tread * 0.28), m, 1)


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, ry := 0.0,
		mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat if mat != null else Interactable.mat(color, size.x)
	mi.position = pos
	mi.rotation.y = ry
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, color: Color,
		m: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mi.mesh = mesh
	mi.material_override = m if m != null else Interactable.mat(color, r * 2.0)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _sph(parent: Node3D, r: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	mi.mesh = mesh
	mi.material_override = Interactable.mat(color, r * 2.0)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _label3d(parent: Node3D, s: String, px: int, pos: Vector3, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = s
	l.font = UiKit.font()
	l.font_size = px
	l.modulate = color
	l.outline_size = 0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.position = pos
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(l)
	return l


## 注册可拍照载体。ring 为金色光圈（默认隐藏），story 目标与普通目标共用。
func _prop(word: String, pos: Vector3, ring_r := 1.0, rng := 6.0, story := false) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = ring_r - 0.08
	torus.outer_radius = ring_r + 0.01
	torus.rings = 36
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("f2cc5a")
	m.emission_enabled = true
	m.emission = Color("f2cc5a")
	m.emission_energy_multiplier = 0.9
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = m
	ring.scale = Vector3(1, 0.22, 1)
	ring.position = Vector3(0, 0.12, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	n.add_child(ring)
	add_child(n)
	props.append({"node": n, "ring": ring, "word": word, "range": rng, "story": story, "shot": false})
	if story:
		story_total += 1
	return n


## 立式单词木牌（抽象词载体）
func _sign(word: String, pos: Vector3, ja: String) -> void:
	var n := _prop(word, pos, 0.8, 5.5)
	var wood_m := Interactable.m_wood(pos)
	_cyl(n, 0.05, 1.4, Vector3(0, 0.7, 0), Color(0.5, 0.4, 0.3), wood_m)
	_box(n, Vector3(0.74, 0.52, 0.07), Vector3(0, 1.56, 0), Color(0.86, 0.80, 0.68), 0.0,
		Interactable.tex_mat(ProceduralTex.wood(21), Color(0.86, 0.80, 0.68), 1.2, 0.95, "wood"))
	_label3d(n, ja, 62, Vector3(0, 1.57, 0.05), UiKit.INK)


func _npc(id: String, pos: Vector3, ry: float) -> Node3D:
	var n := ArtNpc.new()
	n.npc_id = id
	n.position = pos
	n.rotation.y = ry
	add_child(n)
	return n


# =============================================================
# 词汇载体摆设
# =============================================================

func _build_props() -> void:
	var wood_m := Interactable.m_wood(Vector3.ZERO)
	var dark_wood := Interactable.m_concrete(Vector3.ZERO)

	# ---------- 阿强摊位 ----------
	_npc("aqiang", Vector3(5.6, 0.0, 28.2), deg_to_rad(-95.0))
	_static(Vector3(4.8, 0.55, 30.6), Vector3(4.2, 0.14, 2.6), wood_m)
	_static(Vector3(4.8, 1.1, 31.9), Vector3(4.2, 2.0, 0.2), wood_m)
	_static(Vector3(3.0, 1.32, 30.6), Vector3(0.14, 2.6, 0.14), wood_m)
	_static(Vector3(6.6, 1.32, 30.6), Vector3(0.14, 2.6, 0.14), wood_m)
	_static(Vector3(4.8, 2.55, 30.4), Vector3(4.6, 0.12, 3.0), dark_wood)
	# 米袋
	var rice := _prop("kome", Vector3(5.0, 0.62, 30.0), 0.75, 5.0)
	var r1 := _sph(rice, 0.42, Vector3(-0.26, 0.2, 0.1), Color(0.86, 0.82, 0.72))
	r1.scale = Vector3(1.0, 0.8, 1.0)
	var r2 := _sph(rice, 0.4, Vector3(0.3, 0.16, -0.08), Color(0.82, 0.78, 0.68))
	r2.scale = Vector3(1.0, 0.75, 1.0)
	# 水桶
	_bucket(_prop("mizu", Vector3(6.6, 0.5, 31.6), 0.7, 5.0), -0.2)
	_bucket_deco(Vector3(6.95, 0.0, 31.6))
	# 食物笸箩
	var mono := _prop("tabemono", Vector3(4.0, 0.82, 29.6), 0.7, 5.0)
	_cyl(mono, 0.36, 0.26, Vector3(0, 0.1, 0), Color(0.7, 0.58, 0.42))
	for i in 5:
		var an := float(i) * 1.25
		_sph(mono, 0.11, Vector3(cos(an) * 0.18, 0.28, sin(an) * 0.18), Color(0.78, 0.66, 0.42))
	# 价钱木牌
	_sign("takai", Vector3(3.4, 0.0, 28.2), "高い")
	_sign("yasui", Vector3(2.6, 0.0, 29.4), "安い")
	_sign("kau", Vector3(2.2, 0.0, 27.4), "買う")
	_sign("uru", Vector3(5.2, 0.0, 27.0), "売る")

	# ---------- 何伯（挑夫）+ 拐棍 ----------
	_npc("hebo", Vector3(-4.6, 0.0, 16.0), deg_to_rad(60.0))
	_prop("hito", Vector3(-4.6, 0.0, 16.0), 0.9, 5.5)

	# ---------- 荒废街区 ----------
	var ruin_wood := Interactable.mat_photo("wood", Color(0.4, 0.32, 0.24), 0.9, 0.95, 0.5,
		ProceduralTex.wood(31), 0.5, 2.0, 0.35)
	_static(Vector3(-7.5, 1.1, 12.0), Vector3(4.6, 0.3, 0.4), ruin_wood)
	_static(Vector3(-6.2, 0.6, 13.4), Vector3(0.28, 1.2, 0.28), ruin_wood)
	_static(Vector3(7.6, 0.45, 13.0), Vector3(3.6, 0.25, 0.35), ruin_wood)
	_static(Vector3(-9.0, 1.0, 8.0), Vector3(3.4, 2.0, 0.4),
		Interactable.mat_photo("brick_old", Color(0.5, 0.46, 0.42), 0.9, 0.9, 0.3,
			ProceduralTex.pavers(17), 0.3, 2.6, 0.4))
	# 乌鸦
	var crow := _prop("karasu", Vector3(2.6, 1.3, 11.4), 0.65, 5.5)
	_box(crow, Vector3(0.26, 0.2, 0.42), Vector3(0, -0.06, 0), Color(0.1, 0.1, 0.12))
	_sph(crow, 0.08, Vector3(0, 0.05, -0.24), Color(0.09, 0.09, 0.11))
	var beak := _box(crow, Vector3(0.05, 0.05, 0.1), Vector3(0, 0.04, -0.34), Color(0.65, 0.5, 0.3))
	beak.rotation.x = 0.2
	for i in 2:
		var leg := _cyl(crow, 0.012, 0.14, Vector3(0.06 if i == 0 else -0.06, -0.24, 0.02),
			Color(0.55, 0.42, 0.3))
		# 尾羽
	var tail := _box(crow, Vector3(0.16, 0.04, 0.2), Vector3(0, 0.0, 0.28), Color(0.1, 0.1, 0.12))
	tail.rotation.x = -0.35
	# 晾晒旧衣（fuku）
	var laundry := _prop("fuku", Vector3(-3.2, 0.0, 22.0), 0.9, 5.5)
	_cyl(laundry, 0.045, 2.2, Vector3(-1.6, 1.1, 0), Color(0.55, 0.45, 0.33), wood_m)
	_cyl(laundry, 0.045, 2.2, Vector3(1.6, 1.1, 0), Color(0.55, 0.45, 0.33), wood_m)
	var rope := _cyl(laundry, 0.02, 3.2, Vector3(0, 2.0, 0), Color(0.45, 0.38, 0.3), wood_m)
	rope.rotation.z = PI / 2
	for i in 4:
		_box(laundry, Vector3(0.44, 0.62, 0.02), Vector3(-1.0 + float(i) * 0.62, 1.68, 0.0),
			[Color(0.55, 0.52, 0.46), Color(0.42, 0.45, 0.5), Color(0.62, 0.5, 0.42)][i % 3], 0.0,
			Interactable.tex_mat(ProceduralTex.plaster(i * 3), Color(0.6, 0.56, 0.5), 1.2, 0.95, "cloth"))

	# ---------- 水洼（雨） / 野草（风） ----------
	var pud := _prop("ame", Vector3(2.2, 0.0, 42.0), 1.0, 5.0)
	var pud_mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.2, 1.4)
	pud_mesh.mesh = quad
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.16, 0.19, 0.24, 0.6)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.roughness = 0.08
	pm.metallic = 0.25
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	pud_mesh.material_override = pm
	pud_mesh.rotation = Vector3(-PI / 2, 0.3, 0)
	pud_mesh.position = Vector3(0, 0.1, 0)
	pud_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pud.add_child(pud_mesh)

	var tuft := _prop("kaze", Vector3(-2.8, 0.0, 8.0), 0.75, 5.0)
	for i in 6:
		var blade := _cyl(tuft, 0.02, 0.5 + float(i % 3) * 0.1,
			Vector3(0.14 * ((i % 3) - 1), 0.28, 0.12 * (float(i / 3) - 1.0)),
			Color(0.36, 0.44, 0.3))
		blade.rotation.x = 0.2 * (float(i % 3) - 1.0)
		blade.rotation.z = 0.15 * (float(i % 3) - 1.0)

	# ---------- 抽象词木牌 ----------
	_sign("yoru", Vector3(3.6, 0.0, 4.0), "夜")
	_sign("samui", Vector3(-3.8, 0.0, 2.0), "寒い")
	_sign("amayadori", Vector3(-2.9, 0.0, -10.5), "雨宿り")

	# ---------- 城门 ----------
	_prop("mon", Vector3(0, 0.0, -11.4), 1.4, 8.0)
	_prop("jouhei", Vector3(-13.5, 0.0, -12.8), 1.1, 6.5)
	_sign("kurai", Vector3(8.9, 0.0, -5.4), "暗い")
	# 门洞里的微弱暖光（有人的暗示）
	var hall := OmniLight3D.new()
	hall.position = Vector3(0, 3.2, -15.0)
	hall.light_color = Color(0.9, 0.62, 0.36)
	hall.light_energy = 1.1
	hall.omni_range = 11.0
	add_child(hall)
	# 摊位棚灯（雨夜里唯一的社会温度）
	var stall_lamp := OmniLight3D.new()
	stall_lamp.position = Vector3(4.8, 2.2, 30.4)
	stall_lamp.light_color = Color(1.0, 0.72, 0.42)
	stall_lamp.light_energy = 1.6
	stall_lamp.omni_range = 9.0
	add_child(stall_lamp)
	# 上楼口微弱火光（楼梯顶端）
	var stair_glow := OmniLight3D.new()
	stair_glow.position = Vector3(STAIR_X, TOP_Y + 1.2, STAIR_TOP_Z + 1.0)
	stair_glow.light_color = Color(0.95, 0.66, 0.3)
	stair_glow.light_energy = 3.0
	stair_glow.omni_range = 16.0
	stair_glow.shadow_enabled = true
	add_child(stair_glow)
	# 楼梯底部的补水光（让台阶轮廓可读，别变成纯黑洞）
	var base_glow := OmniLight3D.new()
	base_glow.position = Vector3(STAIR_X, 1.6, -4.6)
	base_glow.light_color = Color(0.6, 0.66, 0.8)
	base_glow.light_energy = 1.3
	base_glow.omni_range = 9.0
	add_child(base_glow)
	# 楼上正式火盆（主光源 + hi 载体）
	_fire_bowl()
	# 楼梯的 kaidan 载体（梯中段）
	_prop("kaidan", Vector3(STAIR_X, 2.6, -8.2), 0.9, 5.0)

	# ---------- 城门楼上层：尸体 ×3 + 头发堆 + 楼面杂物 ----------
	_corpse(Vector3(-2.6, TOP_Y, -15.4), 0.5)
	_corpse(Vector3(2.8, TOP_Y, -17.4), 2.1)
	_corpse(Vector3(-4.6, TOP_Y, -17.6), 1.2)
	var hair := _prop("kami", Vector3(-1.6, TOP_Y, -16.2), 0.55, 4.5, true)
	_sph(hair, 0.16, Vector3(0, 0.07, 0), Color(0.14, 0.12, 0.11)).scale = Vector3(1.5, 0.5, 1.5)
	for i in 3:
		var strand := _cyl(hair, 0.02, 0.36, Vector3(0.05 * float(i), 0.2, 0.02 * float(i)),
			Color(0.16, 0.14, 0.12))
		strand.rotation.x = 0.5 * float(i)
	# 尸体 A 的 word（story 目标：死体）
	_prop("shitai", Vector3(-2.6, TOP_Y, -15.4), 0.9, 5.0, true)
	# 衣物堆（装饰）
	var pile := Node3D.new()
	pile.position = Vector3(1.6, TOP_Y, -18.2)
	add_child(pile)
	for i in 3:
		_box(pile, Vector3(0.5, 0.12, 0.4), Vector3(0.12 * float(i), 0.06 + 0.125 * float(i), 0.1 * float(i)),
			[Color(0.5, 0.44, 0.46), Color(0.4, 0.42, 0.48), Color(0.56, 0.5, 0.44)][i], 0.4 * float(i),
			Interactable.tex_mat(ProceduralTex.plaster(i * 11), Color(0.5, 0.46, 0.42), 1.2, 0.95, "cloth"))

	# ---------- 林婆 ----------
	_linpo()
	# story 目标：老人（林婆本体） / 火（火盆）
	_prop("roujin", Vector3(3.2, TOP_Y, -15.2), 0.95, 6.5, true)
	_prop("hi", Vector3(0, TOP_Y, WALL_Z - 0.4), 1.0, 5.5, true)


func _bucket(parent: Node3D, dx: float) -> void:
	_cyl(parent, 0.26, 0.5, Vector3(dx, 0.25, 0), Color(0.62, 0.52, 0.4), Interactable.m_wood(parent.position))
	_cyl(parent, 0.2, 0.2, Vector3(dx, 0.48, 0), Color(0.35, 0.45, 0.55))


## 装饰水桶（无词，不挡路）
func _bucket_deco(pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	_cyl(n, 0.24, 0.46, Vector3(0, 0.23, 0), Color(0.58, 0.49, 0.38), Interactable.m_wood(pos))
	_cyl(n, 0.19, 0.18, Vector3(0, 0.44, 0), Color(0.35, 0.45, 0.55))


func _fire_bowl() -> void:
	var n := Node3D.new()
	n.position = Vector3(0, TOP_Y, WALL_Z - 0.2)
	add_child(n)
	var dark := Interactable.m_metal_dark(n.position)
	_cyl(n, 0.5, 0.5, Vector3(0, 0.25, 0), Color(0.2, 0.2, 0.22), dark)
	_cyl(n, 0.36, 0.1, Vector3(0, 0.52, 0), Color(1.0, 0.72, 0.35), _glow(Color(1.0, 0.5, 0.2), 1.4))
	for i in 5:
		var fl := _sph(n, 0.13, Vector3(0.12 * sin(float(i) * 2.2), 0.66 + 0.04 * float(i),
			0.1 * cos(float(i) * 1.7)), Color(1.0, 0.62, 0.25))
		fl.scale = Vector3(1.0, 1.4 + 0.2 * float(i % 3), 1.0)
		fl.material_override = _glow(Color(1.0, 0.55, 0.2), 2.2)
	var fire := OmniLight3D.new()
	fire.name = "FireLight"
	fire.position = Vector3(0, 1.1, 0)
	fire.light_color = Color(1.0, 0.6, 0.25)
	fire.light_energy = 2.6
	fire.omni_range = 15.0
	fire.shadow_enabled = true
	n.add_child(fire)


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _corpse(pos: Vector3, ry: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = ry
	add_child(n)
	var skin := Color(0.72, 0.64, 0.55)
	var cloth := Color(0.42, 0.4, 0.44)
	var body := _cyl(n, 0.17, 1.15, Vector3(0, 0.19, 0), cloth)
	body.rotation.x = PI / 2
	body.position = Vector3(0, 0.19, 0.1)
	var head := _sph(n, 0.14, Vector3(0, 0.16, -0.62), skin)
	var belly := _box(n, Vector3(0.36, 0.3, 0.5), Vector3(0, 0.09, 0.06), cloth)
	belly.rotation.x = 0.2
	for i in 2:
		var arm := _cyl(n, 0.07, 0.6, Vector3(0.22 if i == 0 else -0.2, 0.1, 0.3 + 0.1 * float(i)), skin)
		arm.rotation.x = PI / 2 + (0.3 if i == 0 else -0.25)
	var cover := _box(n, Vector3(0.6, 0.06, 0.9), Vector3(0, 0.52, -0.1), Color(0.3, 0.28, 0.34))
	cover.rotation.x = 0.06


func _linpo() -> void:
	var n := _npc("linpo", LINPO_POS, deg_to_rad(-115.0))
	# 僻静处蹲姿模拟不了，就让她靠着火光背对楼梯（贴墙侧身）
	_linpo_node = n


var _linpo_node: Node3D = null


# =============================================================
# 玩家 / UI
# =============================================================

func _setup_player() -> void:
	player = Player.new()
	player.planet = null
	add_child(player)
	player.teleport(SPAWN, 0.0)
	player.cam.make_current()


func _setup_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	# 顶部：章节名 + 饥饿条
	hunger_bar = ProgressBar.new()
	hunger_bar.min_value = 0.0
	hunger_bar.max_value = 100.0
	hunger_bar.value = hunger
	hunger_bar.show_percentage = false
	hunger_bar.anchor_left = 0.5
	hunger_bar.anchor_right = 0.5
	hunger_bar.offset_left = -90
	hunger_bar.offset_right = 90
	hunger_bar.offset_top = 10
	hunger_bar.offset_bottom = 22
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.1, 0.7)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.22, 0.16)
	fill.set_corner_radius_all(4)
	hunger_bar.add_theme_stylebox_override("background", bg)
	hunger_bar.add_theme_stylebox_override("fill", fill)
	layer.add_child(hunger_bar)
	var hl := UiKit.label("飢え", 12, UiKit.PAPER)
	hl.anchor_left = 0.5
	hl.anchor_right = 0.5
	hl.offset_left = -90
	hl.offset_top = -4
	layer.add_child(hl)

	var title := UiKit.label("羅生門・岭南篇", 16, Color(UiKit.PAPER, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 30
	title.offset_bottom = 52
	layer.add_child(title)

	hint_label = UiKit.label("", 19, UiKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	hint_label.anchor_left = 0.0
	hint_label.anchor_right = 1.0
	hint_label.offset_top = 58
	hint_label.offset_bottom = 86
	hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	layer.add_child(hint_label)

	# 摇杆 + 按钮
	joy = VirtualJoystick.new()
	layer.add_child(joy)
	joy.moved.connect(func(v: Vector2):
		player.input_vec = v)
	joy.released.connect(func():
		player.input_vec = Vector2.ZERO)

	jump_btn = UiKit.icon_button("↥", 30)
	jump_btn.anchor_left = 1.0
	jump_btn.anchor_right = 1.0
	jump_btn.anchor_top = 1.0
	jump_btn.anchor_bottom = 1.0
	jump_btn.offset_left = -150
	jump_btn.offset_top = -280
	jump_btn.offset_right = -52
	jump_btn.offset_bottom = -182
	jump_btn.button_down.connect(func():
		player.jump_pressed = true
		player.jump_held = true)
	jump_btn.button_up.connect(func():
		player.jump_held = false
		player.jump_pressed = false)
	layer.add_child(jump_btn)

	shoot_btn = UiKit.icon_button("拍照", 28)
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

	menu_btn = UiKit.icon_button("≡", 26)
	menu_btn.anchor_left = 0.0
	menu_btn.offset_left = 16
	menu_btn.offset_top = 54
	menu_btn.offset_right = 64
	menu_btn.offset_bottom = 102
	menu_btn.pressed.connect(_return_to_menu)
	layer.add_child(menu_btn)

	# 弹窗 / 对话
	popup = WordPopup.new()
	layer.add_child(popup)
	popup.closed.connect(func():
		player.input_locked = false)

	dlg_box = DialogueBox.new()
	layer.add_child(dlg_box)
	dlg_box.finished.connect(_on_dialogue_finished)
	dlg_box.quests_requested.connect(func(_id):
		pass)

	# 全屏闪白 / 淡黑
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash_rect)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade_rect)

	# PERFECT/GREAT 大字
	_center_label = UiKit.label("", 52, Color("f2cc5a"), HORIZONTAL_ALIGNMENT_CENTER)
	_center_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.visible = false
	_center_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_center_label)

	_build_challenge_panel()
	_build_grab_panel()
	_build_end_panel()
	_pre_disc = 0
	for wid in CHAPTER_WORDS:
		if Game.is_discovered(wid):
			_pre_disc += 1


## 把 Panel 居中摆放（容器以 min size 定型后再定位才不跑偏）
func _center_panel(p: Control) -> void:
	p.reset_size()
	var vr := get_viewport().get_visible_rect().size
	var ms := p.get_combined_minimum_size()
	p.position = Vector2((vr.x - ms.x) * 0.5, (vr.y - ms.y) * 0.42)


func _build_challenge_panel() -> void:
	chal_panel = PanelContainer.new()
	chal_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UiKit.PAPER, 0.96), 18))
	chal_panel.anchor_left = 0.5
	chal_panel.anchor_right = 0.5
	chal_panel.anchor_top = 0.5
	chal_panel.anchor_bottom = 0.5
	chal_panel.visible = false
	layer.add_child(chal_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	chal_panel.add_child(vb)
	var head := UiKit.label("林婆 の言葉に耳を澄ます  （听懂她的话）", 17, UiKit.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(head)
	chal_line = UiKit.label("", 30, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	chal_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chal_line.custom_minimum_size = Vector2(520, 0)
	vb.add_child(chal_line)
	chal_zh = UiKit.label("", 18, UiKit.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	chal_zh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(chal_zh)
	chal_opts = VBoxContainer.new()
	chal_opts.add_theme_constant_override("separation", 8)
	vb.add_child(chal_opts)
	chal_note = UiKit.label("", 15, UiKit.VERMILION, HORIZONTAL_ALIGNMENT_CENTER)
	chal_note.visible = false
	vb.add_child(chal_note)


func _build_grab_panel() -> void:
	grab_panel = PanelContainer.new()
	grab_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UiKit.PAPER, 0.96), 18))
	grab_panel.anchor_left = 0.5
	grab_panel.anchor_right = 0.5
	grab_panel.anchor_top = 0.5
	grab_panel.anchor_bottom = 0.5
	grab_panel.visible = false
	layer.add_child(grab_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	grab_panel.add_child(vb)
	vb.add_child(_title_center("一歩前へ。その服を——つかめ。", 26, UiKit.INK))
	vb.add_child(_title_center("再靠近一步。抓住那件衣服。", 17, UiKit.INK_SOFT))
	grab_bar = ProgressBar.new()
	grab_bar.min_value = 0.0
	grab_bar.max_value = 1.0
	grab_bar.value = 0.0
	grab_bar.show_percentage = false
	grab_bar.custom_minimum_size = Vector2(430, 34)
	var bg2 := StyleBoxFlat.new()
	bg2.bg_color = Color(0.12, 0.12, 0.16)
	bg2.set_corner_radius_all(8)
	grab_bar.add_theme_stylebox_override("background", bg2)
	var fill2 := StyleBoxFlat.new()
	fill2.bg_color = Color("f2cc5a")
	fill2.set_corner_radius_all(8)
	grab_bar.add_theme_stylebox_override("fill", fill2)
	grab_bar.gui_input.connect(_on_grab_input)
	vb.add_child(grab_bar)
	vb.add_child(_title_center("ポインターが金色の帯に来たら、ボタンを押せ", 15, UiKit.INK_SOFT))
	grab_note = UiKit.label("", 17, UiKit.VERMILION, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(grab_note)


func _title_center(s: String, px: int, c: Color) -> Label:
	var l := UiKit.label(s, px, c, HORIZONTAL_ALIGNMENT_CENTER)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _build_end_panel() -> void:
	end_panel = PanelContainer.new()
	end_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UiKit.NAVY, 0.97), 20))
	end_panel.anchor_left = 0.5
	end_panel.anchor_right = 0.5
	end_panel.anchor_top = 0.5
	end_panel.anchor_bottom = 0.5
	end_panel.visible = false
	layer.add_child(end_panel)


func _make_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 640
	rain.lifetime = 1.15
	rain.preprocess = 1.2
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 0.5, 16)
	pm.direction = Vector3(0, -1, 0.08)
	pm.spread = 1.0
	pm.initial_velocity_min = 15.0
	pm.initial_velocity_max = 15.0
	pm.gravity = Vector3(0, -3.0, 0)
	rain.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.5)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(0.72, 0.8, 1.0, 0.2)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mm
	rain.draw_pass_1 = quad
	rain.position = SPAWN + Vector3(0, 9, 0)
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)


# =============================================================
# 主循环：触发器 / 目标高亮 / 对话链
# =============================================================

func _process(delta: float) -> void:
	# 饥饿压力
	hunger = minf(100.0, hunger + delta * (0.25 if phase < Ph.UPPER else 0.4))
	hunger_bar.value = hunger
	if hunger > 85.0 and not _hunger_warn:
		_hunger_warn = true
		Game.play_sfx("wrong")
		_hint("お腹が……もう限界だ。（肚子……快到极限了）")

	# 雨跟人
	if rain != null:
		rain.global_position = player.position + Vector3(0, 9, 0)

	# 火光晃动
	var fire := get_tree().root.find_child("FireLight", true, false)
	if fire != null:
		(fire as OmniLight3D).light_energy = 2.3 + 0.5 * sin(Time.get_ticks_msec() * 0.011)

	_shoot_cd = maxf(0.0, _shoot_cd - delta)
	_update_highlight()

	if chal_panel.visible:
		_process_challenge(delta)
	if grab_panel.visible:
		_process_grab(delta)

	if popup.visible or dlg_box.visible or end_panel.visible or grab_panel.visible or chal_panel.visible:
		return

	match phase:
		Ph.STREET:
			_check_vendor("aqiang", Vector3(5.6, 0.0, 28.2))
			_check_vendor("hebo", Vector3(-4.6, 0.0, 16.0))
			_check_shelter()
		Ph.SHELTER, Ph.CLIMB:
			_check_stairs()
			_check_scares()
			_check_top()
		Ph.UPPER:
			_check_spotted()
			_check_story_done()
		_:
			pass


func _check_vendor(id: String, pos: Vector3) -> void:
	if _talked.has(id):
		return
	if _flat_dist(pos) < 3.4:
		_talked[id] = true
		_play_dialogue(id, null)


func _flat_dist(pos: Vector3) -> float:
	var a := player.position
	var b := pos
	a.y = 0.0
	b.y = 0.0
	return a.distance_to(b)


func _check_shelter() -> void:
	if _shelter_done:
		return
	if player.position.z < -6.0 and player.position.z > -13.6 and absf(player.position.x) < 3.0:
		_shelter_done = true
		_play_dialogue("sheng", null)


func _check_stairs() -> void:
	if _climb_started:
		return
	if absf(player.position.x - STAIR_X) < 2.0 and player.position.z < -2.8 and player.position.z > -4.6:
		_climb_started = true
		phase = Ph.CLIMB
		_hint("上へのぼる。薄暗い。（往上走。光线很暗）")


func _check_scares() -> void:
	var pts := [Vector3(STAIR_X, 0, -7.6), Vector3(STAIR_X, 0, -11.2)]
	for i in 2:
		var p: Vector3 = pts[i]
		if _scare[i]:
			continue
		if Vector2(player.position.x, player.position.z).distance_to(Vector2(p.x, p.z)) < 1.6:
			_scare[i] = true
			_scare_flash()


func _scare_flash() -> void:
	Game.play_sfx("wrong")
	_flash_rect.color = Color(0, 0, 0, 0.5)
	Toast.show_once(self, "……何かが見えた。長い影。")
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, 0.6)


func _check_top() -> void:
	if _upper_started:
		return
	if player.position.y > TOP_Y - 0.6 and player.position.z < -12.0:
		_upper_started = true
		phase = Ph.UPPER
		_hint("静かに。……声を出すな。（安静……别出声）")


func _check_spotted() -> void:
	if _spotted:
		return
	# 全部观察完成后她才会惊觉玩家走近（把流程还给"偷窥→被发现"）。
	# 但靠得实在太近（<3m）也会暴露。
	if story_done >= story_total and player.position.distance_to(LINPO_POS) < 5.2:
		_spotted = true
		if _bot:
			print("[bot] spotted (observed) dist=%.1f" % player.position.distance_to(LINPO_POS))
		_play_dialogue("linpo", _linpo_node)
	elif player.position.distance_to(LINPO_POS) < 3.0:
		_spotted = true
		if _bot:
			print("[bot] spotted (too close)")
		_play_dialogue("linpo", _linpo_node)


func _check_story_done() -> void:
	if _talk_done:
		return
	if story_done >= story_total and story_total > 0:
		_talk_done = true
		_hint("観察し終えた。より近くへ……（观察完了……再走近一些）")


func _update_highlight() -> void:
	var can := (not popup.visible and not dlg_box.visible and not chal_panel.visible \
		and not grab_panel.visible and not end_panel.visible and phase != Ph.AWAY and phase != Ph.END)
	var best := -1
	var best_score := 0.0
	if can:
		var fwd := -player.cam.global_basis.z
		for i in props.size():
			var p: Dictionary = props[i]
			if String(p["word"]).is_empty():
				continue
			var node := (p["node"] as Node3D)
			var to := node.global_position + Vector3(0, 0.6, 0) - player.cam.global_position
			var dist := to.length()
			if dist > float(p["range"]) + 3.0:
				continue
			to.y = 0.0
			if to.length_squared() < 0.01:
				continue
			var dot := to.normalized().dot(Vector3(fwd.x, 0.0, fwd.z).normalized())
			if dot < 0.3:
				continue
			if dist > float(p["range"]):
				continue
			var score := dot / maxf(dist, 0.5)
			if score > best_score:
				best_score = score
				best = i
	if best != _active:
		if _active >= 0:
			var old := props[_active]["ring"] as MeshInstance3D
			old.visible = false
		_active = best
		if best >= 0:
			var ring := props[best]["ring"] as MeshInstance3D
			ring.visible = true
	# 光圈脉冲
	if _active >= 0:
		var ring2 := props[_active]["ring"] as MeshInstance3D
		var pulse := 1.0 + 0.05 * sin(Time.get_ticks_msec() * 0.005)
		ring2.scale = Vector3(pulse, 0.22, pulse)


# =============================================================
# 拍照学词
# =============================================================

func _on_shoot_pressed() -> void:
	if phase == Ph.GRAB:
		_on_grab_input(null)
		return
	if popup.visible or dlg_box.visible or chal_panel.visible or grab_panel.visible or end_panel.visible:
		return
	if phase == Ph.END or phase == Ph.AWAY:
		return
	if _shoot_cd > 0.0:
		return
	if _active < 0:
		Toast.show_once(self, "近くに写せる対象がない。（附近没有可拍摄的单词）")
		return
	_shoot_cd = 0.5
	var p: Dictionary = props[_active]
	var word_id := String(p["word"])
	_flash_rect.color = Color(1, 1, 1, 0.9)
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, 0.28)
	Game.play_sfx("shutter")
	var is_new := false
	if _bot:
		is_new = true   # 干跑：不把练习用的词条写进真实存档
	else:
		is_new = Game.discover(word_id)
	if is_new:
		Game.play_sfx("discover")
		perfect += 1
		_show_center("PERFECT", Color("f2cc5a"))
	else:
		_show_center("GREAT", Color("8fbf9f"))
	if bool(p["story"]):
		story_done += 1
	photo_count += 1
	if not _bot:
		Game.save_soon()
	player.input_locked = true
	popup.show_word(Game.word(word_id), is_new)


func _show_center(txt: String, c: Color) -> void:
	_center_label.text = txt
	_center_label.modulate = c
	_center_label.visible = true
	_center_label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_center_label, "modulate:a", 1.0, 0.12)
	tw.tween_interval(0.55)
	tw.tween_property(_center_label, "modulate:a", 0.0, 0.4)


# =============================================================
# 对话链 / 问答
# =============================================================

func _play_dialogue(id: String, talker: Node3D) -> void:
	if _bot:
		print("[bot] play dlg=", id, " size=", (Dialogues.get_dialogue(id) as Dictionary).size())
	player.input_locked = true
	dlg_box.open_for(id, talker)
	_dlg_cb = _dlg_chain(id)


func _dlg_chain(id: String) -> Callable:
	if id == "sheng":
		return func():
			phase = Ph.SHELTER
			_hint("雨宿りの間、確かめよう——耳を澄ますと、上階に火の気がある。（避雨时……楼上好像有火光）")
	elif id == "linpo":
		return func():
			Game.save_soon()
			_play_dialogue("linpo_talk", _linpo_node)
	elif id == "linpo_talk":
		return func():
			Game.save_soon()
			start_challenges()
	return func():
		pass


func _on_dialogue_finished() -> void:
	if _bot:
		print("[bot] dlg finished id=", dlg_box._npc_id)
	player.input_locked = false
	if _dlg_cb.is_valid():
		var cb := _dlg_cb
		_dlg_cb = Callable()
		cb.call()


func start_challenges() -> void:
	phase = Ph.TALK
	challenge_idx = 0
	challenge_ok = 0
	chal_panel.visibility_changed.connect(func():
		if chal_panel.visible:
			_center_panel(chal_panel))
	chal_panel.visible = true
	_show_challenge()


func _show_challenge() -> void:
	_chal_cur = CHALLENGES[challenge_idx]
	_masked_off()
	chal_line.text = String(_chal_cur["line"])
	chal_zh.text = String(_chal_cur["zh"])
	chal_note.visible = false
	_chal_timer = 3.2
	_chal_masked = false


func _masked_off() -> void:
	for ch in chal_opts.get_children():
		ch.queue_free()
	chal_opts.visible = false


func _process_challenge(delta: float) -> void:
	if _chal_masked:
		return
	_chal_timer -= delta
	if _chal_timer > 0.0:
		return
	_chal_masked = true
	# 句子被抹去：只剩听懂了的人才选得出来
	chal_line.text = "……？"
	chal_zh.text = ""
	var opts: Array = _chal_cur["opts"]
	var pool := opts.duplicate()
	pool.shuffle()
	for o in pool:
		var b := UiKit.button(String(o), false, 22)
		b.custom_minimum_size = Vector2(0, 46)
		b.pressed.connect(func():
			_on_chal_pick(String(b.text)))
		chal_opts.add_child(b)
	chal_opts.visible = true
	chal_note.text = "聞こえた言葉を選べ（选你听到的词 · 首答为 PERFECT）"
	chal_note.visible = true


func _on_chal_pick(txt: String) -> void:
	if txt == String(_chal_cur["kw"]):
		Game.play_sfx("correct")
		challenge_ok += 1 if challenge_first else 0
		_show_center("PERFECT", Color("f2cc5a"))
		chal_line.text = String(_chal_cur["line"])
		chal_zh.text = String(_chal_cur["zh"])
		chal_note.text = "わかった。（听懂了）"
		var tw := create_tween()
		tw.tween_interval(1.1)
		tw.tween_callback(func():
			challenge_idx += 1
			challenge_first = true
			if challenge_idx < CHALLENGES.size():
				_show_challenge()
			else:
				_finish_challenges())
	else:
		Game.play_sfx("wrong")
		challenge_first = false
		chal_note.text = "もう一度、聞き取る。（没听懂，再听一遍）"
		_show_challenge()


func _finish_challenges() -> void:
	chal_panel.visible = false
	_start_grab()


# =============================================================
# 抢衣服 QTE
# =============================================================

func _start_grab() -> void:
	phase = Ph.GRAB
	_center_panel(grab_panel)
	grab_panel.visible = true
	grab_note.text = ""
	grab_bar.value = 0.0
	_grab_speed = 0.62
	_grab_try = 0
	shoot_btn.text = "つかめ!"


func _on_grab_input(_e: InputEvent) -> void:
	if phase != Ph.GRAB:
		return
	Game.play_sfx("click")
	_grab_try += 1
	var v := float(grab_bar.value)
	var center_gap := absf(v - 0.5)
	if center_gap < 0.055:
		Game.play_sfx("correct")
		grab_note.text = "掴んだ——！（抓住了！）"
		_show_center("PERFECT", Color("f2cc5a"))
		if _grab_try == 1:
			perfect += 1
		_begin_away()
	else:
		_grab_speed += 0.14
		Game.play_sfx("wrong")
		grab_note.text = "外れた……林婆は気づいた！（抓空了……她察觉了！）"


func _process_grab(delta: float) -> void:
	_grab_t += delta * _grab_speed
	var v := 0.5 + 0.5 * sin(_grab_t)
	grab_bar.value = v


func _begin_away() -> void:
	grab_panel.visible = false
	shoot_btn.text = "拍照"
	jump_btn.visible = false
	phase = Ph.AWAY
	player.input_locked = true
	_flash_rect.color = Color(1, 1, 1, 0.55)
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, 0.25)
	if challenge_ok >= 4:
		_ending_texts = [
			{"ja": "雨、やんだ。", "zh": "雨，停了。"},
			{"ja": "あなたは、何をした？", "zh": "你，做了什么？"},
			{"ja": "暖かい。……服が、温かい。", "zh": "很暖和。这件衣服——是暖的。"},
		]
	else:
		_ending_texts = [
			{"ja": "雨、やんだ。", "zh": "雨，停了。"},
			{"ja": "背の高くなった影が、二つ。", "zh": "两个瘦长的影子。"},
			{"ja": "夜は、まだ長い。", "zh": "夜还长。"},
		]
	_run_away(0)


func _run_away(i: int) -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.9 if i == 0 else 0.1)
	tw.tween_callback(func():
		player.input_vec = Vector2.ZERO)
	if i >= _ending_texts.size():
		tw.tween_callback(_show_end_panel)
		return
	var t: Dictionary = _ending_texts[i]
	tw.tween_callback(func():
		_hint("%s\n%s" % [String(t["ja"]), String(t["zh"])])
		Tts.speak(String(t["ja"])))
	tw.tween_interval(3.0)
	tw.tween_callback(func():
		_run_away(i + 1))


func _show_end_panel() -> void:
	phase = Ph.END
	_hint("")
	var disc := 0
	for wid in CHAPTER_WORDS:
		if Game.is_discovered(wid):
			disc += 1
	var coverage := int(round(100.0 * photo_count / float(CHAPTER_WORDS.size())))
	var text := "CHAPTER COMPLETE\n\n羅生門・岭南篇\n\n新词汇：%d / %d\n探索率：%d%%\nPERFECT：%d" % \
		[disc - _pre_disc, CHAPTER_WORDS.size(), coverage, perfect]
	var xp := 30 + photo_count * 2 + perfect * 5
	if not _bot:
		Game.add_xp(xp)
		Game.save_now()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	end_panel.add_child(vb)
	vb.add_child(_title_center(text, 22, UiKit.PAPER))
	vb.add_child(_title_center("獲得 XP +%d" % xp, 18, Color("f2cc5a")))
	var back := UiKit.button("主菜单へ", true, 24)
	back.custom_minimum_size = Vector2(360, 56)
	back.pressed.connect(func():
		Game.save_now()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	vb.add_child(back)
	var again := UiKit.button("もう一度", false, 22)
	again.custom_minimum_size = Vector2(360, 50)
	again.pressed.connect(func():
		Game.save_now()
		get_tree().reload_current_scene())
	vb.add_child(again)
	end_panel.reset_size()
	var vr := get_viewport().get_visible_rect().size
	var min_size := end_panel.get_combined_minimum_size()
	end_panel.position = Vector2((vr.x - min_size.x) * 0.5, (vr.y - min_size.y) * 0.5)
	end_panel.visible = true


var _pre_disc := 0


func _return_to_menu() -> void:
	Game.save_now()
	Tts.stop()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _hint(s: String) -> void:
	hint_label.text = s


# =============================================================
# 输入 / 窗口
# =============================================================

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_return_to_menu()
		return
	if phase == Ph.GRAB and grab_panel.visible and event.is_pressed() \
			and (event is InputEventKey and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]):
		_on_grab_input(null)
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _over_ui(event.position):
				return
			_look_active = true
			_look_last = event.position
		else:
			_look_active = false
	elif event is InputEventScreenDrag:
		if not _look_active:
			return
		if _over_ui(event.position):
			return
		var d: Vector2 = event.relative
		if d.length() > 90.0:
			d = d.normalized() * 90.0
		player.look(d.x, d.y)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if phase == Ph.GRAB and grab_panel.visible and not _over_ui(event.position):
			_on_grab_input(null)


var _look_active := false
var _look_last := Vector2.ZERO


func _over_ui(pos: Vector2) -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered is Control and (hovered as Control).get_global_rect().has_point(pos)


# =============================================================
# --chapter-bot 自动通关自测（headless 全链路冒烟，不他杀游戏流程）
# 用法：Godot --headless --path . res://scenes/rashomon.tscn -- --chapter-bot
# =============================================================

var _bot := false
var _bot_started := false


func _bot_run() -> void:
	_bot_started = true
	print("[bot] start")
	await _wait(0.6)
	# ① 门下避雨（sheng 旁白）
	player.teleport(Vector3(0, 0.12, -9.0), 0.0)
	await _wait_dialogue()
	await _drain_dialogue()
	await _wait(0.4)
	print("[bot] after shelter phase=", ph_name())
	if phase != Ph.SHELTER:
		push_error("[bot] expected SHELTER, got %s" % ph_name())
	# ② 楼梯 → 楼上
	player.teleport(Vector3(STAIR_X, 0.12, -3.6), 0.0)
	await _wait(0.4)
	if phase != Ph.CLIMB:
		push_error("[bot] expected CLIMB, got %s" % ph_name())
	player.teleport(Vector3(STAIR_X, 2.6, -8.2), 0.0)
	await _wait(0.3)
	player.teleport(Vector3(STAIR_X, TOP_Y + 0.12, -13.2), 0.0)
	await _wait(0.5)
	if phase != Ph.UPPER:
		push_error("[bot] expected UPPER, got %s" % ph_name())
	# ③ 观察 4 个 story 目标
	for wid in ["shitai", "kami", "hi", "roujin"]:
		var idx := _prop_index(wid)
		if idx < 0:
			push_error("[bot] missing story prop %s" % wid)
			continue
		_active = idx
		_on_shoot_pressed()
		await _wait(0.7)
		if popup.visible:
			popup.close()
		await _wait(0.25)
	print("[bot] story_done=", story_done)
	# ④ 走近林婆 → 发现（linpo → linpo_talk) → 对质
	player.teleport(LINPO_POS + Vector3(1.2, 0.0, 2.0), 0.0)
	await _wait(0.5)
	print("[bot] near linpo: dlg=", dlg_box.visible, " spotted=", _spotted,
		" story=", story_done, "/", story_total)
	await _wait_dialogue()
	await _drain_dialogue()
	await _wait_dialogue()
	await _drain_dialogue()
	var guard := 0
	while not chal_panel.visible and guard < 80:
		await _wait(0.3)
		guard += 1
	if not chal_panel.visible:
		push_error("[bot] challenge panel never showed")
		get_tree().quit(1)
		return
	print("[bot] challenges begin")
	# ⑤ 问答：首答都对（PERFECT×5）
	guard = 0
	while chal_panel.visible and guard < 120:
		if _chal_masked and chal_line.text == "……？":
			_on_chal_pick(String(_chal_cur["kw"]))
		await _wait(0.3)
		guard += 1
	print("[bot] challenges done, ok=", challenge_ok)
	# ⑥ 抢衣 QTE
	guard = 0
	while not grab_panel.visible and guard < 60:
		await _wait(0.3)
		guard += 1
	if not grab_panel.visible:
		push_error("[bot] grab panel never showed")
		get_tree().quit(1)
		return
	grab_bar.value = 0.5
	_grab_t = 0.0
	_grab_try = 0
	_on_grab_input(null)
	# ⑦ AWAY → 结算
	guard = 0
	while not end_panel.visible and guard < 200:
		await _wait(0.3)
		guard += 1
	if not end_panel.visible:
		push_error("[bot] end panel never showed")
		get_tree().quit(1)
		return
	print("[bot] OK  photos=%d challenge_ok=%d perfect=%d  (dry-run, 存档未污染)" %
		[photo_count, challenge_ok, perfect])
	get_tree().quit(0)


## 等 dialogue 第一次弹出（触发器在 _process 里生效）
func _wait_dialogue() -> void:
	var guard := 0
	while not dlg_box.visible and guard < 60:
		await _wait(0.2)
		guard += 1


## 像玩家一样把当前对话一路点到底
func _drain_dialogue() -> void:
	var guard := 0
	while dlg_box.visible and guard < 240:
		var b := _first_dlg_choice()
		if b != null:
			b.pressed.emit()
		else:
			dlg_box.advance()
		await _wait(0.22)
		guard += 1
	await _wait(0.2)


func _first_dlg_choice() -> Button:
	for ch in dlg_box._choices_box.get_children():
		if ch is Button:
			return ch
	return null


func _prop_index(word: String) -> int:
	for i in props.size():
		if String(props[i]["word"]) == word and not bool(props[i]["shot"]):
			return i
	return -1


func ph_name() -> String:
	return Ph.keys()[int(phase)]


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
