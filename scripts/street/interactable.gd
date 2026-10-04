class_name Interactable
extends Area3D
## 街道上的可交互物体（3D）：全部由基础几何体 + 程序纹理拼装（无需美术资源）。
## 根节点是 Area3D：射线点击直接命中；实心物体额外挂 StaticBody3D 挡住玩家。

const S := 0.025  # 地图像素 -> 米（4000px 世界 = 100m）

# kind 元数据：
# click=点击体积(Area3D 盒) solid=碰撞体积(null=不挡路) range=交互距离(米,0=不限)
# stand=台面层厚度(米)。>0 时碰撞体只在物件顶部生成该厚度的薄层，脚下是通的 ——
#       猫可以跳上这玩意（Stray 的核心玩法：跳上箱子/长椅/矮墙）。
#       0 或不填 = 实心障碍（建筑、车辆等不可穿越的）。
#
# 【尺度基准】猫肩高 0.23m、碰撞体高 0.36m、跳高 0.66m（1.8 倍体高）。
# 所以能跳的物件台面必须在 0.66m 以下。建模时按这个标准定尺寸：
#   能跳：长椅座面 0.42 / 水泥管 0.38 / 花坛 0.5 / 塑料箱 0.4 / 矮墙 0.55
#   不能跳：窗台 0.9 / 车顶 1.5 / 公交站牌 2.9 —— 猫就是猫，别做超级英雄
# novis=不生成外形(隐藏标记) door_win=依附建筑正面（map 里用 host 指定建筑类型）
const META := {
	# ---- 可跳上去的：台面 ≤ 0.66m ----
	# 长椅：座面降到 0.42m（真人长椅座高约 0.42m，正好在猫的跳跃极限内）
	"bench":        {"click": Vector3(2.5, 1.1, 0.95), "solid": Vector3(2.3, 0.42, 0.8), "stand": 0.12, "range": 6.0},
	"mailbox":      {"click": Vector3(0.75, 0.62, 0.7), "solid": Vector3(0.62, 0.55, 0.55), "stand": 0.12, "range": 6.0},
	"trash":        {"click": Vector3(0.85, 0.58, 0.85), "solid": Vector3(0.72, 0.52, 0.72), "stand": 0.12, "range": 6.0},
	"bicycle":      {"click": Vector3(1.9, 1.05, 0.75), "solid": Vector3(1.75, 0.5, 0.55), "stand": 0.1, "range": 6.0},
	# ---- 不可穿越的实心体 ----
	"vending":      {"click": Vector3(1.0, 1.95, 0.9), "solid": Vector3(0.95, 1.85, 0.8), "range": 7.0},
	"pole":         {"click": Vector3(0.6, 7.2, 0.6), "solid": Vector3(0.3, 7.0, 0.3), "range": 6.0},
	"car":          {"click": Vector3(4.5, 1.7, 2.0), "solid": Vector3(4.3, 1.5, 1.85), "range": 8.0},
	"traffic":      {"click": Vector3(0.7, 5.6, 3.2), "solid": Vector3(0.35, 4.5, 0.35), "range": 7.0},
	"station":      {"click": Vector3(12.6, 5.4, 8.2), "solid": Vector3(12.5, 4.8, 4.5), "range": 14.0},
	"train":        {"click": Vector3(19.6, 3.4, 2.9), "solid": Vector3(19.0, 2.6, 2.6), "range": 14.0},
	"konbini":      {"click": Vector3(6.6, 3.6, 5.1), "solid": Vector3(6.5, 3.4, 5.0), "range": 11.0},
	"house":        {"click": Vector3(4.3, 4.3, 3.7), "solid": Vector3(4.2, 3.0, 3.6), "range": 9.0,
		# 【围墙碰撞】_b_house 里画了一圈院子围墙（后墙/左右墙/前两段/门柱），
		# 之前只有建筑本体这一个碰撞盒 —— 围墙是纯视觉，玩家直接穿墙进院。
		# 这里按 _b_house 的视觉尺寸逐段补碰撞（s=尺寸 p=局部坐标）。
		"extra_solids": [
			{"s": Vector3(7.4, 1.12, 0.2), "p": Vector3(0, 0.56, -3.0)},
			{"s": Vector3(0.2, 1.12, 4.2), "p": Vector3(-3.6, 0.56, -0.9)},
			{"s": Vector3(0.2, 1.12, 4.2), "p": Vector3(3.6, 0.56, -0.9)},
			{"s": Vector3(2.3, 1.0, 0.18), "p": Vector3(-2.5, 0.5, 1.35)},
			{"s": Vector3(2.3, 1.0, 0.18), "p": Vector3(2.5, 0.5, 1.35)},
			{"s": Vector3(0.26, 1.5, 0.26), "p": Vector3(-1.3, 0.75, 1.35)},
			{"s": Vector3(0.26, 1.5, 0.26), "p": Vector3(1.3, 0.75, 1.35)},
		]},
	"mansion":      {"click": Vector3(4.3, 9.7, 3.9), "solid": Vector3(4.2, 9.5, 3.8), "range": 10.0},
	"super":        {"click": Vector3(7.7, 4.6, 5.5), "solid": Vector3(7.6, 4.4, 5.4), "range": 12.0},
	"cafe":         {"click": Vector3(5.3, 3.8, 4.3), "solid": Vector3(5.2, 3.6, 4.2), "range": 10.0},
	"ramen":        {"click": Vector3(6.3, 4.2, 4.7), "solid": Vector3(6.2, 4.0, 4.6), "range": 11.0},
	"post_office":  {"click": Vector3(5.9, 4.6, 4.3), "solid": Vector3(5.8, 4.4, 4.2), "range": 10.0},
	"signboard":    {"click": Vector3(1.1, 2.8, 0.5), "solid": Vector3(0.9, 2.6, 0.35), "range": 6.0},
	"streetlight":  {"click": Vector3(1.9, 4.5, 0.45), "solid": Vector3(0.25, 4.2, 0.25), "range": 6.0},
	"tree":         {"click": Vector3(2.7, 4.7, 2.7), "solid": Vector3(0.55, 2.6, 0.55), "range": 7.0},
	"sakura":       {"click": Vector3(3.1, 5.3, 3.1), "solid": Vector3(0.55, 2.6, 0.55), "range": 7.0},
	"busstop":      {"click": Vector3(1.4, 3.1, 0.5), "solid": Vector3(1.15, 2.9, 0.3), "range": 6.0},
	"parksign":     {"click": Vector3(1.5, 2.4, 0.45), "solid": Vector3(1.25, 2.2, 0.25), "range": 6.0},
	# ---- 不可碰撞的装饰 ----
	"flower":       {"click": Vector3(1.2, 0.8, 1.2), "solid": null, "range": 5.0},
	"grass":        {"click": Vector3(1.5, 0.6, 1.5), "solid": null, "range": 5.0},
	"dog":          {"click": Vector3(1.2, 1.0, 0.9), "solid": null, "range": 5.0},
	"cat":          {"click": Vector3(0.9, 0.9, 0.85), "solid": null, "range": 5.0},
	"bird":         {"click": Vector3(0.6, 0.6, 0.6), "solid": null, "range": 4.0},
	"bowl":         {"click": Vector3(1.1, 0.85, 1.1), "solid": null, "range": 5.0},
	"cans":         {"click": Vector3(0.95, 0.6, 0.75), "solid": null, "range": 5.0},
	"onigiri":      {"click": Vector3(1.0, 0.7, 1.0), "solid": null, "range": 5.0},
	"bread":        {"click": Vector3(1.7, 1.0, 1.15), "solid": null, "range": 5.0},
	"door":         {"click": Vector3(1.4, 2.5, 0.7), "solid": null, "range": 6.0, "door_win": true},
	"window":       {"click": Vector3(1.4, 1.6, 0.7), "solid": null, "range": 6.0, "door_win": true},
	"marker_road":  {"click": Vector3(24.0, 0.5, 6.6), "solid": null, "range": 0.0, "novis": true},
	"marker_walk":  {"click": Vector3(18.0, 0.5, 4.6), "solid": null, "range": 0.0, "novis": true},
	"marker_cross": {"click": Vector3(16.2, 0.5, 16.2), "solid": null, "range": 0.0, "novis": true},
	"crosswalk":    {"click": Vector3(6.7, 0.4, 3.6), "solid": null, "range": 0.0},
	# ---- 批次 5 新增：专为「猫能跳上去」设计的矮物件 ----
	# 水泥管（街边排水管盖）：0.38m，猫跳上去是 Stray 里最经典的画面
	"pipe":         {"click": Vector3(0.7, 0.42, 0.7), "solid": Vector3(0.62, 0.38, 0.62), "stand": 0.1, "range": 5.0},
	# 塑料周转箱（店铺门口的箱子）：0.4m
	"crate":        {"click": Vector3(0.8, 0.46, 0.65), "solid": Vector3(0.72, 0.4, 0.58), "stand": 0.1, "range": 5.0},
	# 花坛矮沿（公园/店铺前）：0.5m
	"planter":      {"click": Vector3(1.6, 0.56, 1.0), "solid": Vector3(1.5, 0.5, 0.9), "stand": 0.14, "range": 5.0},
	# 矮墙（巷口/院落）：0.55m
	"lowwall":      {"click": Vector3(2.4, 0.62, 0.4), "solid": Vector3(2.3, 0.55, 0.32), "stand": 0.14, "range": 5.0},
	# ---- 批次 6 新增：家具（家具屋门前的展示品，矮件猫可跳） ----
	"furniture":    {"click": Vector3(7.7, 4.6, 5.5), "solid": Vector3(7.6, 4.4, 5.4), "range": 12.0},
	"table":        {"click": Vector3(1.6, 0.9, 1.1), "solid": Vector3(1.3, 0.45, 0.85), "stand": 0.12, "range": 5.0},
	"chair":        {"click": Vector3(0.7, 1.05, 0.7), "solid": Vector3(0.5, 0.44, 0.5), "stand": 0.12, "range": 5.0},
	"bed":          {"click": Vector3(2.5, 0.8, 1.6), "solid": Vector3(2.2, 0.35, 1.4), "stand": 0.12, "range": 5.0},
	"sofa":         {"click": Vector3(2.3, 1.0, 1.2), "solid": Vector3(2.0, 0.45, 0.95), "stand": 0.12, "range": 5.0},
	"tv":           {"click": Vector3(1.7, 1.8, 0.8), "solid": Vector3(1.45, 1.2, 0.6), "range": 5.0},
	"shelf":        {"click": Vector3(1.5, 2.0, 0.8), "solid": Vector3(1.3, 1.5, 0.6), "range": 5.0},
	"lamp":         {"click": Vector3(0.7, 1.7, 0.7), "solid": Vector3(0.45, 1.5, 0.45), "range": 5.0},
	"wash":         {"click": Vector3(0.9, 1.1, 0.9), "solid": Vector3(0.78, 0.92, 0.68), "range": 5.0},
	# ---- 批次 7：街景杂物（装饰为主，不参与学词；矮件猫可跳） ----
	# 路牌：map.json 里本来就有 roadsign（还是可学单词「標識」），但 META 漏了
	# 这个 kind —— 两个路牌一直是隐形的。补上建模。
	"roadsign":     {"click": Vector3(0.9, 2.7, 0.5), "solid": Vector3(0.12, 2.5, 0.12), "range": 6.0},
	# 消火栓（柱形）：0.62m，猫能跳上去
	"fireplug":     {"click": Vector3(0.5, 0.72, 0.5), "solid": Vector3(0.36, 0.62, 0.36), "stand": 0.1, "range": 5.0},
	# 鉢植え（盆栽）：店铺/家门口标配，0.4m 台面
	"potplant":     {"click": Vector3(0.85, 0.85, 0.85), "solid": Vector3(0.5, 0.4, 0.5), "stand": 0.08, "range": 5.0},
	# 物干し竿（晾衣杆）：两根 T 杆 + 下垂电线 + 挂着的毛巾，不挡路
	"laundry":      {"click": Vector3(2.6, 2.3, 1.0), "solid": null, "range": 6.0},
	# ゴミ袋（垃圾袋）：清晨收垃圾时段摆在路边，0.4m 可跳
	"trashbags":    {"click": Vector3(1.1, 0.55, 0.9), "solid": Vector3(0.95, 0.4, 0.75), "stand": 0.08, "range": 5.0},
	# タイヤ（旧轮胎堆）：店后巷，0.51m 可跳
	"tires":        {"click": Vector3(0.9, 0.62, 0.9), "solid": Vector3(0.76, 0.51, 0.76), "stand": 0.1, "range": 5.0},
	# 工事コーン（路锥）：路面施工/驻车禁止，不挡路
	"cones":        {"click": Vector3(1.2, 0.6, 0.8), "solid": null, "range": 5.0},
	# ガスボンベ（燃气罐）：拉面店/饮食店后面靠墙一排，实心
	"gasbottle":    {"click": Vector3(1.0, 1.1, 0.8), "solid": Vector3(0.85, 0.95, 0.6), "range": 5.0},
	# 水洼：路面半透明反光片（纯装饰，无碰撞）
	"puddle":       {"click": Vector3(1.6, 0.2, 1.6), "solid": null, "range": 0.0},
}

var word_id := ""
var kind := ""
var no_draw := false
var interact_range := 7.0
var extra := {}

var highlighted := false
var quest_target := false   # 当前被追踪的收集类任务把它当作指路目标 → 显示光圈
var _pulse := 0.0
var _ring: MeshInstance3D
var _car_color := Color("e8e6e0")
var _door_dy := 0.0

static var _mats := {}

static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


## 存在哪些贴图套件（自动扫盘，新增贴图无需改代码）
static var _tex_kinds := {}
static var _tex_scanned := false

static func _scan_tex() -> void:
	if _tex_scanned:
		return
	_tex_scanned = true
	var d := DirAccess.open("res://assets/tex")
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with("_col.jpg"):
			continue
		var kind := f.substr(0, f.length() - 8)
		# 记下有哪些通道可用
		var chans := {"col": true}
		if FileAccess.file_exists("res://assets/tex/%s_nrm.jpg" % kind):
			chans["nrm"] = true
		if FileAccess.file_exists("res://assets/tex/%s_rgh.jpg" % kind):
			chans["rgh"] = true
		_tex_kinds[kind] = chans


static func has_tex(kind: String) -> bool:
	_scan_tex()
	return _tex_kinds.has(kind)


## 把 tint「软化」成接近白色的乘数。
## 【为什么需要】albedo_color 是直接乘贴图的，任何明显偏离 1.0 的 tint 都会
## 把贴图的明暗层次压平 —— 墙面会变成一块纯色。
## 做法：取 tint 的**平均亮度**作为「保持多少原色」，色相只保留一点点偏移。
##   strength=0 → 完全用 tint（老行为，会压平贴图）
##   strength=1 → 纯白（完全保留贴图原色）
## 实际用的是 0.75~0.9，保留 75~90% 原色，只做轻微的暖/冷、明/暗偏移。
static func _soft_tint(tint: Color, strength: float) -> Color:
	var lum := (tint.r + tint.g + tint.b) / 3.0
	# 目标亮度也归一化：不管调用方传 (0.93,0.9,0.86) 还是 (0.8,0.85,0.95)，
	# 都只保留其相对明暗关系，映射到 [0.82, 1.0] 这个「几乎不压暗」的区间。
	var norm := inverse_lerp(0.55, 1.0, clampf(lum, 0.0, 1.0))  # 0..1
	var target := lerpf(0.82, 1.0, norm)
	# 色相偏移：把 tint 相对其亮度的偏离量，按 strength 打折后加回去
	var keep := clampf(strength, 0.0, 1.0)
	var ratio := 1.0 / maxf(lum, 0.001)
	return Color(
		clampf(target * lerpf(1.0, clampf(tint.r * ratio, 0.85, 1.12), keep), 0.0, 1.0),
		clampf(target * lerpf(1.0, clampf(tint.g * ratio, 0.85, 1.12), keep), 0.0, 1.0),
		clampf(target * lerpf(1.0, clampf(tint.b * ratio, 0.85, 1.12), keep), 0.0, 1.0),
		1.0)


## 照片级 PBR 表面材质（Poly Haven CC0 扫描贴图）。
## scale = 每米重复次数（0.5 = 一张贴图铺 2 米）。
##
## 【tint 的正确用法 —— 这条之前搞错过，导致所有墙面糊成一片紫灰】
## `albedo_color` 是**直接乘** albedo_texture 的，不是"调色叠加"。
## 所以：
##   tint = 0.93,0.9,0.86 → 贴图被压到 93% 亮度并染上米色，
##     贴图本身的明暗层次（灰缝、污渍、颗粒）全部被压平 → 看起来像纯色块。
## 正确做法：**tint 尽量接近白色（0.9~1.0），只做极轻微的明度/色温偏移**，
## 把"上色"这件事交给不同贴图本身去完成（每种墙用不同的贴图，而不是同一张贴图 × 不同 tint）。
##
## scale = 每米重复次数（0.5 = 一张贴图铺 2 米）。
## detail_scale/detail_amount：叠一层高频细节，打破 1k 贴图在大面上的重复感。
static func mat_photo(kind: String, tint: Color, tint_amt: float, rough: float, scale: float,
		fallback_tex: ImageTexture = null, fallback_scale := 0.5,
		detail_scale := 0.0, detail_amount := 0.35) -> StandardMaterial3D:
	_scan_tex()
	# 缓存 key 里带上 tint_amt（之前漏了，导致不同 tint_amt 命中同一缓存）
	var key := "ph_%s_%s_%f_%f_%f_%f_%f" % [kind, tint.to_html(), tint_amt, rough, scale, detail_scale, detail_amount]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# 三平面世界映射：贴图不会因物体 UV 缺失而拉伸
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = rough
	m.metallic = 0.0
	m.metallic_specular = 0.22
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX

	if _tex_kinds.has(kind):
		m.albedo_texture = _tex("res://assets/tex/%s_col.jpg" % kind)
		# tint 只做「轻微偏移」：把 tint 归一化到接近白色，保住贴图本身的层次。
		# tint_amt = 0 → 完全用 tint（原行为）；tint_amt = 1 → 保留贴图原色。
		# 实用区间是 tint_amt 0.7~1.0。
		m.albedo_color = _soft_tint(tint, tint_amt)
		if _tex_kinds[kind].get("nrm", false):
			m.normal_enabled = true
			m.normal_texture = _tex("res://assets/tex/%s_nrm.jpg" % kind)
			m.normal_scale = 0.75
		if _tex_kinds[kind].get("rgh", false):
			m.roughness_texture = _tex("res://assets/tex/%s_rgh.jpg" % kind)
		# 细节层：同贴图高频叠加，抑制大面积平铺的"壁纸感"
		# 注意：detail 相关的枚举在 Godot 4 里搬到了 StandardMaterial3D 上，
		# 不在 BaseMaterial3D（写 BaseMaterial3D.DETAIL_BLEND_* 会编译失败）。
		# 不要给 detail_mask 赋 roughness 图 —— roughness 的明暗区会当遮罩，
		# 在地面上表现成一块块水渍/油污斑。纯细节叠加才干净。
		if detail_scale > 0.0 and m.albedo_texture != null:
			m.detail_enabled = true
			m.detail_albedo = m.albedo_texture
			m.detail_uv_layer = StandardMaterial3D.DETAIL_UV_1
			m.detail_blend_mode = StandardMaterial3D.BLEND_MODE_MIX
			m.detail_albedoblend_sharpness = 0.35
			m.detail_uv_scale = detail_scale
			m.detail_amount = detail_amount
	else:
		# 回退：程序纹理（三平面）
		m.albedo_texture = fallback_tex
		m.uv1_scale = Vector3.ONE * fallback_scale
		m.roughness = rough
	_mats[key] = m
	return m


## 依实例位置的微小颜色变化，打破整齐划一的"积木感"
func _var(base: Color, amount := 0.05) -> Color:
	var h := int(abs(position.x * 13.37 + position.z * 7.77)) % 100
	var f := 1.0 + (h / 100.0 - 0.5) * 2.0 * amount
	return Color(minf(base.r * f, 1.0), minf(base.g * f, 1.0), minf(base.b * f, 1.0))


## 落水管
func _downspout(pos: Vector3, h: float) -> void:
	box(Vector3(0.11, h, 0.11), pos + Vector3(0, h * 0.5, 0), Color("c9c4b8"))
	box(Vector3(0.11, 0.11, 0.55), pos + Vector3(0, 0.3, 0.28), Color("c9c4b8"))


# ---------------- 材质工具（程序纹理 + 三平面世界映射） ----------------

static func mat(color: Color) -> StandardMaterial3D:
	var key := "c_" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.roughness = 0.95
	_mats[key] = m
	return m


## 带程序纹理的材质：tint 给灰度纹理上色；scale 为每米重复数
static func tex_mat(tex: ImageTexture, tint: Color, scale: float, rough := 0.95, spec_key := "", height := 0.0) -> StandardMaterial3D:
	var key := "t_%s_%s_%f_%s_%f" % [spec_key, tint.to_html(), scale, str(rough), height]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.roughness = rough
	if height > 0.0:
		m.heightmap_enabled = true
		m.heightmap_texture = tex
		m.heightmap_scale = height
	_mats[key] = m
	return m


## 玻璃材质：橱窗 / 窗户 / 车窗。
## 【关键】必须开 TRANSPARENCY_ALPHA，否则橱窗是一块不透明的紫灰板，
## 里面什么都看不见 —— 这是「便利店橱窗像积木」的根本原因。
## roughness 0.05 + metallic 0.55 制造「反射天空」的高光，
## 再给一点自发光让夜里窗户会亮（由 TimeOfDay 调制强度）。
static func glass_mat(tint: Color, glow := 0.0) -> StandardMaterial3D:
	var key := "g_%s_%.2f" % [tint.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(tint.r, tint.g, tint.b, 0.42)   # 半透明：能看见里面的货架
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05# 极光滑 = 镜面反射天空
	m.metallic = 0.55
	m.metallic_specular = 0.9
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.6)                  # 暖色，夜里像室内灯
	m.emission_energy_multiplier = glow                   # 0 = 白天不亮
	m.cull_mode = BaseMaterial3D.CULL_DISABLED            # 双面，从内外都看得到
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats[key] = m
	return m


# ---------------- 实例化 ----------------

static func make(obj: Dictionary) -> Interactable:
	var it := Interactable.new()
	it.word_id = String(obj.get("word", ""))
	it.kind = String(obj.get("kind", ""))
	var meta: Dictionary = META.get(it.kind, {})
	it.interact_range = float(meta.get("range", 7.0))
	it.no_draw = bool(meta.get("novis", false))
	it.extra = obj
	var px := Vector2(float(obj.get("x", 0)), float(obj.get("y", 0)))
	it.position = Vector3(px.x * S, 0, px.y * S)
	# rot：绕 Y 旋转（度）。晾衣杆/路锥这类有方向性的道具用（门/窗的吸附偏移在旋转前算，不受影响）
	it.rotation.y = deg_to_rad(float(obj.get("rot", 0.0)))
	if meta.has("door_win"):
		var host_meta: Dictionary = META.get(String(obj.get("host", "house")), {})
		var hs: Vector3 = host_meta.get("click", Vector3(4, 3, 3))
		var dx := float(obj.get("dx", 0.0))
		it._door_dy = 1.15 if it.kind == "door" else 1.95
		it.position += Vector3(dx, 0, hs.z * 0.5 + 0.12)
	if it.kind == "car":
		var palette := [Color("e8e6e0"), Color("7fa8e0"), Color("c6cbd4"), Color("8fbf9f"), Color("e6d3b3"), Color("d97f7f")]
		it._car_color = palette[int(abs(px.x * 0.37 + px.y * 0.11)) % palette.size()]
	return it


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	monitorable = true

	var meta: Dictionary = META.get(kind, {})
	var click_size: Vector3 = meta.get("click", Vector3(1, 1, 1))
	var click_pos := Vector3(0, click_size.y * 0.5, 0)
	if kind == "door" or kind == "window":
		click_pos = Vector3(0, _door_dy, 0)
	var cs := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = click_size
	cs.shape = cbox
	cs.position = click_pos
	add_child(cs)

	var solid: Variant = meta.get("solid", null)
	var extra_solids: Array = meta.get("extra_solids", [])
	if solid is Vector3 or not extra_solids.is_empty():
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var sv: Vector3 = solid if solid is Vector3 else Vector3.ZERO
		# 【关键】区分「可站上去的平台」与「实心障碍」。
		# 之前所有碰撞体都是从地面到顶的整块实心盒 —— 猫撞上只能绕过去，
		# 跳都跳不上去（垃圾桶 0.85m 高、邮筒 1.0m 高，全都撞墙）。
		# 现在：矮物件只保留"台面层"（顶面能站），高物件保持实心（建筑/车）。
		var top_only: bool = float(meta.get("stand", 0.0)) > 0.0
		var stand_h: float = float(meta.get("stand", 0.0))
		if solid is Vector3 and top_only:
			# 只在物件顶部生成一块薄碰撞体：脚下是通的，猫能从旁边跳上去
			var ss := CollisionShape3D.new()
			var sbox := BoxShape3D.new()
			sbox.size = Vector3(sv.x, stand_h, sv.z)
			# 顶面对齐原 solid 的顶部
			ss.position = Vector3(0, sv.y - stand_h * 0.5, 0)
			ss.shape = sbox
			body.add_child(ss)
		elif solid is Vector3:
			var ss2 := CollisionShape3D.new()
			var sbox2 := BoxShape3D.new()
			sbox2.size = sv
			ss2.shape = sbox2
			ss2.position = Vector3(0, sv.y * 0.5, 0)
			body.add_child(ss2)
		# 附属实心段（如 house 的院子围墙）：按 META 里的视觉尺寸逐段补碰撞
		for ex: Dictionary in extra_solids:
			var ss3 := CollisionShape3D.new()
			var sbox3 := BoxShape3D.new()
			sbox3.size = ex.get("s", Vector3.ONE)
			ss3.shape = sbox3
			ss3.position = ex.get("p", Vector3.ZERO)
			body.add_child(ss3)
		add_child(body)

	if not no_draw:
		_build_visual()
		# 贴地假阴影：太阳落山后（夜里 sun_energy 0.45）实时阴影几乎消失，
		# 没有这层小物件会"浮"在地上 —— 这是视觉升级文档里挂账的遗留问题。
		if BLOB_KINDS.has(kind):
			var br := clampf(maxf(click_size.x, click_size.z) * 0.5 + 0.12, 0.4, 2.4)
			_blob_shadow(br)
	# 光圈统一创建（含 novis 隐形标记）：默认隐藏，靠近高亮或被任务追踪时点亮
	_make_ring(click_size)


func _process(delta: float) -> void:
	if (highlighted or quest_target) and _ring != null:
		_pulse += delta
		var p := 1.0 + 0.05 * sin(_pulse * 5.0)
		_ring.scale = Vector3(p, 0.22, p)


func set_highlight(v: bool) -> void:
	if highlighted == v:
		return
	highlighted = v
	_pulse = 0.0
	if _ring != null:
		_ring.visible = v or quest_target


## 被收集类任务追踪为目标时点亮光圈（隐形标记如「交差点」也靠它显形）
func set_quest_target(v: bool) -> void:
	if quest_target == v:
		return
	quest_target = v
	if _ring != null:
		_ring.visible = v or highlighted


## 玩家是否在交互范围内（水平距离；range<=0 表示不限）
func in_range_of(player_pos: Vector3) -> bool:
	if interact_range <= 0.0:
		return true
	var a := Vector2(player_pos.x, player_pos.z)
	var b := Vector2(position.x, position.z)
	return a.distance_to(b) <= interact_range


func _make_ring(click_size: Vector3) -> void:
	var r := minf(maxf(click_size.x, click_size.z) * 0.5 + 0.2, 2.2)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = r - 0.08
	torus.outer_radius = r + 0.01
	torus.rings = 40
	_ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("f2cc5a")
	m.emission_enabled = true
	m.emission = Color("f2cc5a")
	m.emission_energy_multiplier = 0.9
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = m
	_ring.scale = Vector3(1, 0.22, 1)
	_ring.position = Vector3(0, 0.1, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)


## 需要贴地假阴影的 kind。建筑/门/窗除外（有实时阴影，且贴墙）；
## 花/草丛排除（草地上一团黑斑像枯死）。
const BLOB_KINDS := ["pole", "streetlight", "signboard", "busstop", "vending",
	"mailbox", "trash", "bicycle", "traffic", "fireplug", "potplant", "laundry",
	"trashbags", "tires", "cones", "gasbottle", "crate", "pipe", "bench",
	"planter", "lowwall", "parksign", "wash", "lamp", "tv", "shelf", "table",
	"chair", "sofa", "bed", "tree", "sakura", "car", "roadsign",
	"dog", "cat", "bird", "bowl", "cans", "onigiri", "bread"]

static var _blob_mat: StandardMaterial3D


## 程序生成径向渐变圆片：中心 alpha 0.34 → 边缘 0。
## 压在地面以上 9cm（路面顶 0.07 / 井盖顶 0.087 之上，且低于高亮环 0.1）。
## UNSHADED + 不投影：纯暗化贴地，任何时刻都稳定。
func _blob_shadow(radius: float) -> void:
	if _blob_mat == null:
		var tex := GradientTexture2D.new()
		tex.width = 128
		tex.height = 128
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)   # 半径 = 半张图，渐变铺满
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([
			Color(0, 0, 0, 0.34), Color(0, 0, 0, 0.18), Color(0, 0, 0, 0.0)])
		tex.gradient = g
		_blob_mat = StandardMaterial3D.new()
		_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_mat.albedo_texture = tex
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = quad
	mi.material_override = _blob_mat
	mi.rotation = Vector3(-PI * 0.5, 0, 0)
	mi.position = Vector3(0, 0.09, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ================================================================
# 批次 3：材质语义工厂
#
# 病根：全场景所有物体都用同一个默认 StandardMaterial3D，
#       结果满屏同一种塑料反光 —— 这是「demo 感」的第3 大来源。
# 修法：按「材质语义」分工厂，每个语义有明确的 roughness/metallic/emission 参数。
#       关键点是 roughness 与 metallic 要拉开档：
#         塑料 0.35 / 金属 0.4+metallic0.85 / 混凝土 0.85 / 玻璃 0.05 / 和纸 0.95
#       档位拉开后，即使光照相同也能靠「反光形状不同」区分物体。
# ================================================================

## 顶点色微差：按世界坐标伪随机，让同一材质的每块砖/每扇窗颜色都不同。
## 这是 low-poly 不廉价的关键 —— 消除「同一个紫出现 200 次」的塑料感。
static func _jitter_color(base: Color, pos: Vector3, amount := 0.055) -> Color:
	var h := int(abs(pos.x * 12.9898 + pos.z * 78.233 + pos.y * 37.719)) % 1000
	var f := 1.0 + (float(h) / 1000.0 - 0.5) * 2.0 * amount
	# 轻微的色相偏移，不只是明度 —— 纯明度变化在大片墙面上仍显假
	var warm := (float(h % 97) / 97.0 - 0.5) * amount * 0.6
	return Color(
		clampf(base.r * f + warm, 0, 1),
		clampf(base.g * f, 0, 1),
		clampf(base.b * f - warm * 0.5, 0, 1),
		base.a)


## 带微差的工厂包装：缓存 key 含位置哈希，所以每块砖是独立材质实例。
## 面数代价换「无塑料感」，比加面数划算。
static func _mat_j(key: String, base: Color, pos: Vector3,
		rough: float, metal: float, jitter := 0.055) -> StandardMaterial3D:
	var ck := "%s_%d" % [key, int(abs(pos.x * 12.9898 + pos.z * 78.233)) % 997]
	if _mats.has(ck):
		return _mats[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = _jitter_color(base, pos, jitter)
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.4
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats[ck] = m
	return m


## ---- 12 个材质语义 ----

## 自动贩卖机机身：朱红塑料。规格指定 albedo(0.85,0.18,0.18)
static func m_plastic_red(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	var m := _mat_j("pl_red", Color(0.78, 0.17, 0.16), pos, 0.35, 0.1, 0.04)
	return m


## 贩卖机/招牌面板：白塑料
static func m_plastic_white(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("pl_white", Color(0.93, 0.93, 0.9), pos, 0.4, 0.0, 0.03)


## 电柱/护栏/管道：金属。metallic 0.85 是金属感的铁律（0.3 以下看起来还是塑料）
static func m_metal_dark(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("mt_dark", Color(0.3, 0.31, 0.34), pos, 0.42, 0.85, 0.05)


## 镀锌铁皮：空调外机/铁皮屋/水槽。metallic 高但 roughness 高一些 = 旧铁皮
static func m_metal_galva(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("mt_galva", Color(0.66, 0.68, 0.7), pos, 0.55, 0.75, 0.07)


## 混凝土：建筑外墙/台阶/电线杆。roughness 0.85 吃光不反光
static func m_concrete(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("concrete", Color(0.74, 0.72, 0.68), pos, 0.88, 0.0, 0.06)


## 瓦：青灰。用 roughness 0.7，比混凝土略反光一点才像瓦
static func m_tile_roof(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("tile", Color(0.33, 0.37, 0.42), pos, 0.68, 0.05, 0.08)


## 木材：招牌框/长椅/电线杆箱
static func m_wood(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("wood", Color(0.52, 0.38, 0.26), pos, 0.76, 0.0, 0.07)


## 玻璃：窗户/便利店橱窗。roughness 0.05 + transmission 感（移动端用低 roughness 近似）
## 夜晚会亮（emission 微暖）由 TimeOfDay 统一调制
static func m_glass(pos: Vector3 = Vector3.ZERO, warm := true) -> StandardMaterial3D:
	var ck := "glass%s_%d" % ["w" if warm else "c", int(abs(pos.x * 7.7 + pos.z * 3.3)) % 499]
	if _mats.has(ck):
		return _mats[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.72, 0.8, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.06
	m.metallic = 0.4
	m.metallic_specular = 0.85
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.emission_enabled = true
	m.emission = Color(1.0, 0.82, 0.5) if warm else Color(0.8, 0.9, 1.0)
	m.emission_energy_multiplier = 0.0   # 由 TimeOfDay 按时刻点亮
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats[ck] = m
	return m


## 橡胶：轮胎/盲道垫/井盖
static func m_rubber(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("rubber", Color(0.2, 0.2, 0.21), pos, 0.92, 0.0, 0.05)


## 植被：樱/树冠。grass 贴图三平面映射 + 微透光（用浅色模拟 subsurface）
static func m_leaf(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	var ck := "leaf_%d" % (int(abs(pos.x * 9.1 + pos.z * 4.7)) % 499)
	if _mats.has(ck):
		return _mats[ck]
	var base := _jitter_color(Color(0.44, 0.62, 0.34), pos, 0.09)
	# 贴图给叶片明暗层次（tint_amt 0.72 保住大部分贴图色），世界三平面映射无 UV 依赖
	var m := mat_photo("grass", base, 0.72, 0.85, 2.6)
	# 叶片背光透亮：模拟 subsurface scattering
	m.emission_enabled = true
	m.emission = base.lightened(0.4)
	m.emission_energy_multiplier = 0.12
	_mats[ck] = m
	return m


## 樱花瓣：浅粉 + 自发光。emission 让 Bloom 捕获（规格铁律：>1 才被捕获）
static func m_petal() -> StandardMaterial3D:
	if _mats.has("petal"):
		return _mats["petal"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.96, 0.78, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.9)
	m.emission_energy_multiplier = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats["petal"] = m
	return m


## 和纸灯笼：粗糙 0.95 + 自发光（和纸透光）。夜晚是画面亮点
static func m_paper(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	var ck := "paper_%d" % (int(abs(pos.x * 5.3 + pos.z * 8.1)) % 499)
	if _mats.has(ck):
		return _mats[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.96, 0.9, 0.76)
	m.roughness = 0.95
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = Color(1.0, 0.72, 0.36)
	m.emission_energy_multiplier = 0.0   # TimeOfDay 点亮
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats[ck] = m
	return m


## 铺装：人行道砖。顶点色做砖缝明暗交替
static func m_paving(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	var ck := "pave_%d" % (int(abs(pos.x * 2.1 + pos.z * 3.7)) % 499)
	if _mats.has(ck):
		return _mats[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = _jitter_color(Color(0.66, 0.64, 0.6), pos, 0.07)
	m.roughness = 0.8
	m.metallic = 0.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats[ck] = m
	return m


## 霓虹/招牌发光字：UNSHADED + emission 强度 4.0
## 【铁律】emission_energy_multiplier 必须 > 1，否则 Bloom 不捕获，看起来就是块白板
static func m_neon(tint := Color(1.0, 0.45, 0.6), energy := 4.0) -> StandardMaterial3D:
	var ck := "neon_%s_%.1f" % [tint.to_html(), energy]
	if _mats.has(ck):
		return _mats[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = energy
	_mats[ck] = m
	return m


## 亮着的窗户/灯箱：UNSHADED 自发光，TimeOfDay 调制
static func m_glow(tint := Color(1.0, 0.78, 0.4), energy := 2.2) -> StandardMaterial3D:
	var ck := "glow_%s_%.1f" % [tint.to_html(), energy]
	if _mats.has(ck):
		return _mats[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = energy
	_mats[ck] = m
	return m


## 沥青：路面。roughness 高 = 不反光（湿路面才反光，那是另一个材质）
static func m_asphalt(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("asphalt", Color(0.3, 0.3, 0.32), pos, 0.95, 0.0, 0.05)


## 斑马线白漆：粗糙但亮，纯白反光
static func m_paint_white() -> StandardMaterial3D:
	if _mats.has("paint_w"):
		return _mats["paint_w"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.85, 0.82)
	m.roughness = 0.75
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats["paint_w"] = m
	return m


## 饱和朱红（点缀色，占比 < 5%）：朱红邮筒/消火栓/鸟居
static func m_vermilion(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("verm", Color(0.79, 0.24, 0.2), pos, 0.45, 0.05, 0.05)


## 暖黄（灯笼/灯箱的纸）
static func m_warm_paper(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return m_paper(pos)


## 冷色金属（信号灯杆/护栏）
static func m_metal_cool(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("mt_cool", Color(0.42, 0.45, 0.5), pos, 0.5, 0.6, 0.06)


## 树叶/灌木：比 m_leaf 更深更哑（grass 贴图压暗，保留叶影层次）
static func m_foliage(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	var ck := "foliage_%d" % (int(abs(pos.x * 7.7 + pos.z * 3.3)) % 499)
	if _mats.has(ck):
		return _mats[ck]
	var base := _jitter_color(Color(0.28, 0.44, 0.24), pos, 0.1)
	var m := mat_photo("grass", base, 0.55, 0.9, 2.2)
	_mats[ck] = m
	return m


# ---------------- 几何体工具 ----------------

func box(size: Vector3, pos: Vector3, color: Color, ry := 0.0, rx := 0.0, rz := 0.0, material: StandardMaterial3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material if material != null else mat(color)
	mi.position = pos
	mi.rotation = Vector3(rx, ry, rz)
	add_child(mi)
	return mi


func cyl(top_r: float, bottom_r: float, h: float, pos: Vector3, color: Color, axis_z := false, material: StandardMaterial3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = h
	mesh.radial_segments = 14
	mi.mesh = mesh
	mi.material_override = material if material != null else mat(color)
	mi.position = pos
	if axis_z:
		mi.rotation = Vector3(PI * 0.5, 0, 0)
	add_child(mi)
	return mi


func sph(r: float, pos: Vector3, color: Color, material: StandardMaterial3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 16
	mesh.rings = 10
	mi.mesh = mesh
	mi.material_override = material if material != null else mat(color)
	mi.position = pos
	add_child(mi)
	return mi


func torus(inner: float, outer: float, pos: Vector3, color: Color, upright := false, material: StandardMaterial3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 20
	mi.mesh = mesh
	mi.material_override = material if material != null else mat(color)
	mi.position = pos
	if upright:
		mi.rotation = Vector3(PI * 0.5, 0, 0)
	add_child(mi)
	return mi


func prism(size: Vector3, pos: Vector3, material: StandardMaterial3D, ry := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = Vector3(0, ry, 0)
	add_child(mi)
	return mi


# ================================================================
# 外部模型（GLB / glTF）
# ================================================================
# 【为什么换成外部模型】手搭的低多边形只能到「能看」这一档，剪影和比例怎么调都有
# 股「零件拼装」味。树、猫狗、家具、车这类交给现成资产库（Kenney / Quaternius，CC0），
# 画质和手写代码不在一个量级。归一化/染色/动画查找的公共逻辑在 ModelUtil 里。
#
# 选型标准：CC0 或 CC-BY、单文件自带 buffer、纯色材质无贴图（移动端友好）。

const MODEL_ROOT := "res://assets/models/"

## Kenney 家具的原色偏「浅桦木」（0.9/0.6/0.39），在本场景的暖色夕照下会整体发粉。
## 乘一层略深的暖木色压住它，家具才和街道的色调是一家人。
const TINT_WOOD := {"wood": Color("b07440"), "woodDark": Color("8a5527")}
const TINT_WOOD_WARM := {"wood": Color("c08a52"), "woodDark": Color("9a6634")}
## 布艺：灰绿沙发 + 米色坐垫，和旧手搭版一致
const TINT_FABRIC := {"carpet": Color("93a89b"), "carpetWhite": Color("e6e0d2")}


## 摆一个外部模型。tints = {"leafs": 颜色}，按材质名子串染色。
func _glb(rel: String, pos: Vector3, scl := 1.0, ry := 0.0, tints := {}) -> Node3D:
	var n := ModelUtil.spawn(self, rel, pos, 0.0, ry, tints)
	if n != null and scl != 1.0:
		n.scale = Vector3.ONE * scl
	return n


## 摆一个外部模型并归一化到指定高度（米）。家具/树用这个：
## 高度直接对齐 META 里为「猫能跳上去」调好的数值，碰撞体不用动。
func _glb_h(rel: String, height: float, pos := Vector3.ZERO, ry := 0.0, tints := {}) -> Node3D:
	return ModelUtil.spawn(self, rel, pos, height, ry, tints)


func text3d(s: String, px: int, pos: Vector3, color: Color) -> Label3D:
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
	add_child(l)
	return l


## 玻璃窗：白框 + 玻璃 + 窗台。
## 批次 3：玻璃用暖色自发光材质，夜晚由 TimeOfDay 点亮 —— 亮着的窗是「街道感」的核心。
## vary: 同一栋楼的窗给不同亮度，避免整排窗一个样（顶点色微差思路）
func _window_unit(w: float, h: float, pos: Vector3, frame_col := Color("f2efe6"),
		lit := true, vary := 0.0) -> void:
	var frame := m_plastic_white(position)
	box(Vector3(w + 0.14, h + 0.14, 0.09), pos + Vector3(0, 0, -0.02), Color.WHITE, 0,0,0, frame)
	# 窗玻璃：暖色自发光，emission 基准值带随机（模拟不同房间的灯亮度）
	var bright := 1.0 + _var_seed(pos, vary)
	var glass := m_glass(pos, true) if lit else m_glass(pos, false)
	if lit:
		# 每扇窗独立材质实例，才能有不同亮度
		var ck := "win_%.0f_%.2f" % [int(abs(pos.x * 31.7 + pos.y * 17.3)), bright]
		if not _mats.has(ck):
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.72, 0.66, 0.54, 0.6)
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.roughness = 0.08
			gm.metallic = 0.3
			gm.emission_enabled = true
			gm.emission = Color(1.0, 0.84, 0.56)
			gm.emission_energy_multiplier = 0.0   # TimeOfDay 点亮
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			_mats[ck] = gm
		glass = _mats[ck]
		glass.emission_energy_multiplier = 0.0
		# 记下基准值供 TimeOfDay 调制时读取
		if not _win_base.has(glass.get_instance_id()):
			_win_base[glass.get_instance_id()] = bright * 1.8
	box(Vector3(w, h, 0.07), pos + Vector3(0, 0, 0.01), Color.WHITE, 0,0,0, glass)
	box(Vector3(w, 0.05, 0.08), pos, Color.WHITE, 0,0,0, frame)
	box(Vector3(0.05, h, 0.08), pos, Color.WHITE, 0,0,0, frame)
	# 窗台：混凝土质感
	box(Vector3(w + 0.24, 0.09, 0.2), pos + Vector3(0, -h * 0.5 - 0.07, 0.03), Color.WHITE, 0,0,0, m_concrete(pos))


## 窗户基准亮度表（供 TimeOfDay 查询）
static var _win_base := {}

## 位置哈希种子：给同类物件做细微差异
func _var_seed(pos: Vector3, salt := 0.0) -> float:
	var h := int(abs(pos.x * 12.9898 + pos.z * 78.233 + salt * 37.719)) % 1000
	return (float(h) / 1000.0 - 0.5) * 0.9


## 墙挂空调外机
func _ac_unit(pos: Vector3) -> void:
	box(Vector3(0.75, 0.55, 0.32), pos, Color("d8d8d4"))
	box(Vector3(0.6, 0.4, 0.05), pos + Vector3(0, 0, 0.16), Color("a8a8a4"))
	cyl(0.04, 0.04, 1.2, pos + Vector3(0.3, -0.5, 0.1), Color("b8b0a4"))


## 悬挂两点间的电线（中部下垂）
static func _wire(parent: Node3D, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var mid := (a + b) * 0.5 - Vector3(0, 0.45, 0)
	for seg in [[a, mid], [mid, b]]:
		var p0: Vector3 = seg[0]
		var p1: Vector3 = seg[1]
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = r
		mesh.bottom_radius = r
		mesh.height = p0.distance_to(p1)
		mesh.radial_segments = 5
		mi.mesh = mesh
		mi.material_override = mat(col)
		parent.add_child(mi)
		mi.position = (p0 + p1) * 0.5
		var dir := p1 - p0
		if dir.length() > 0.01:
			mi.look_at_from_position(mi.position, p1)
			mi.rotate_object_local(Vector3(1, 0, 0), PI * 0.5)


## 在一组电线杆之间拉电线（按行/列自动连接）
static func build_wires(parent: Node3D, poles: Array[Vector3]) -> void:
	var rows := {}
	var cols := {}
	for p in poles:
		rows.get_or_add(roundi(p.z), []).append(p)
		cols.get_or_add(roundi(p.x), []).append(p)
	for key in rows:
		var arr: Array = rows[key]
		if arr.size() < 2:
			continue
		arr.sort_custom(func(a, b): return a.x < b.x)
		for i in arr.size() - 1:
			var a: Vector3 = arr[i]
			var b: Vector3 = arr[i + 1]
			if b.x - a.x > 16.0:
				continue
			for off in [-0.55, 0.0, 0.55]:
				_wire(parent, a + Vector3(0, 5.55, off), b + Vector3(0, 5.55, off), 0.022, Color("34363d"))
			_wire(parent, a + Vector3(0.2, 6.1, 0), b + Vector3(0.2, 6.1, 0), 0.018, Color("3d4048"))
	for key in cols:
		var arr: Array = cols[key]
		if arr.size() < 2:
			continue
		arr.sort_custom(func(a, b): return a.z < b.z)
		for i in arr.size() - 1:
			var a: Vector3 = arr[i]
			var b: Vector3 = arr[i + 1]
			if b.z - a.z > 16.0:
				continue
			for off in [-0.55, 0.0, 0.55]:
				_wire(parent, a + Vector3(off, 5.55, 0), b + Vector3(off, 5.55, 0), 0.022, Color("34363d"))


# ---------------- 外形构建 ----------------

func _build_visual() -> void:
	match kind:
		"vending": _b_vending()
		"pole": _b_pole()
		"mailbox": _b_mailbox()
		"trash": _b_trash()
		"bicycle": _b_bicycle()
		"car": _b_car()
		"traffic": _b_traffic()
		"station": _b_station()
		"train": _b_train()
		"konbini": _b_konbini()
		"house": _b_house()
		"mansion": _b_mansion()
		"super": _b_super()
		"cafe": _b_cafe()
		"ramen": _b_ramen()
		"post_office": _b_post()
		"signboard": _b_signboard()
		"streetlight": _b_streetlight()
		"bench": _b_bench()
		"busstop": _b_busstop()
		"tree": _b_tree()
		"sakura": _b_sakura()
		"flower": _b_flower()
		"grass": _b_grass()
		"parksign": _b_parksign()
		"dog": _b_dog()
		"cat": _b_cat()
		"bird": _b_bird()
		"bowl": _b_bowl()
		"cans": _b_cans()
		"onigiri": _b_onigiri()
		"bread": _b_bread()
		"door": _b_door()
		"window": _b_window()
		"crosswalk": _b_crosswalk()
		"pipe": _b_pipe()
		"crate": _b_crate()
		"planter": _b_planter()
		"lowwall": _b_lowwall()
		"furniture": _b_furniture()
		"table": _b_table()
		"chair": _b_chair()
		"bed": _b_bed()
		"sofa": _b_sofa()
		"tv": _b_tv()
		"shelf": _b_shelf()
		"lamp": _b_lamp()
		"wash": _b_wash()
		"roadsign": _b_roadsign()
		"fireplug": _b_fireplug()
		"potplant": _b_potplant()
		"laundry": _b_laundry()
		"trashbags": _b_trashbags()
		"tires": _b_tires()
		"cones": _b_cones()
		"gasbottle": _b_gasbottle()
		"puddle": _b_puddle()


## 商店玻璃门脸（橱窗 + 白框 + 店内货架）
func _shop_front(width: float, wall_col: Color) -> void:
	var wall_depth := 5.0 if width > 6 else 4.2
	var gz := 2.5 if width > 6 else 2.1
	var wall_c := _var(wall_col)
	# scale 0.28 = 一张贴图铺 3.5m。墙面比地面需要更密的贴图，否则瓷砖/砖缝全糊掉。
	box(Vector3(width, 3.4, wall_depth), Vector3(0, 1.7, 0), wall_c, 0.0, 0.0, 0.0,
		mat_photo("plaster_brick_01", wall_c, 0.85, 0.93, 0.42, ProceduralTex.wall_tiles(11), 1.6, 2.2, 0.45))
	_downspout(Vector3(width * 0.5 - 0.28, 0, wall_depth * 0.5 - 0.05), 3.3)
	box(Vector3(width - 1.2, 1.75, 0.08), Vector3(0, 1.02, gz - 0.03), Color("a9cede"), 0.0, 0.0, 0.0, glass_mat(Color("a9cede")))
	var n := int(width / 1.35)
	for i in n + 1:
		box(Vector3(0.09, 1.78, 0.13), Vector3(-(width - 1.2) * 0.5 + i * (width - 1.2) / n, 1.02, gz), Color.WHITE)
	box(Vector3(width - 1.2, 0.09, 0.13), Vector3(0, 0.22, gz), Color.WHITE)
	box(Vector3(width - 1.2, 0.09, 0.13), Vector3(0, 1.85, gz), Color.WHITE)
	box(Vector3(width - 1.6, 1.6, 0.2), Vector3(0, 1.05, gz - 0.9), Color("4a5560"))
	for i in 3:
		box(Vector3(width - 2.0, 0.06, 0.5), Vector3(0, 0.5 + i * 0.45, gz - 0.75), Color("d9d4c6"))
	box(Vector3(width, 0.16, wall_depth + 0.15), Vector3(0, 0.08, 0), Color("b5aea0"), 0.0, 0.0, 0.0,
		mat_photo("pavers", Color(0.82, 0.8, 0.75), 0.0, 0.94, 0.5, ProceduralTex.pavers(21), 0.5, 2.2, 0.35))


func _b_konbini() -> void:
	_shop_front(6.5, Color("f4f1e8"))
	box(Vector3(6.5, 1.0, 0.3), Vector3(0, 3.0, 2.42), Color("2f6fb2"))
	text3d("コンビニ", 130, Vector3(0, 3.0, 2.6), Color.WHITE)
	box(Vector3(6.6, 0.16, 0.4), Vector3(0, 3.55, 2.42), Color("245a91"))
	var awn := box(Vector3(6.3, 0.1, 1.45), Vector3(0, 2.42, 2.9), Color("2f6fb2"))
	awn.rotation = Vector3(-0.28, 0, 0)
	box(Vector3(6.3, 0.07, 0.2), Vector3(0, 2.2, 3.55), Color.WHITE)
	box(Vector3(0.06, 1.1, 0.8), Vector3(3.26, 2.0, 0.9), Color("e05a5a"))
	box(Vector3(0.06, 1.1, 0.8), Vector3(3.26, 2.0, 1.9), Color("e6b84c"))
	_ac_unit(Vector3(-3.0, 2.6, 1.2))


func _b_super() -> void:
	_shop_front(7.6, Color("eef0e6"))
	box(Vector3(7.6, 1.1, 0.3), Vector3(0, 3.9, 2.6), Color("2f855a"))
	text3d("スーパー", 140, Vector3(0, 3.9, 2.78), Color.WHITE)
	var awn := box(Vector3(7.4, 0.1, 1.55), Vector3(0, 3.15, 3.1), Color("2f855a"))
	awn.rotation = Vector3(-0.26, 0, 0)
	box(Vector3(7.4, 0.07, 0.2), Vector3(0, 2.9, 3.82), Color.WHITE)
	box(Vector3(1.0, 1.3, 0.06), Vector3(-2.4, 1.2, 2.72), Color("d64541"))
	box(Vector3(1.0, 1.3, 0.06), Vector3(2.4, 1.2, 2.72), Color("e6b84c"))
	_ac_unit(Vector3(-3.4, 2.9, 1.3))
	_ac_unit(Vector3(3.4, 2.9, 1.3))


func _b_house() -> void:
	var wall_col := _var(Color("f2ead9"))
	var roof_col := _var(Color("4d5a74"), 0.08)
	box(Vector3(4.2, 2.7, 3.6), Vector3(0, 1.35, 0), wall_col, 0.0, 0.0, 0.0,
		mat_photo("grey_plaster", _var(Color(0.98, 0.96, 0.92)), 0.9, 0.95, 0.4, ProceduralTex.plaster(12), 0.55, 2.0, 0.4))
	prism(Vector3(3.9, 1.5, 4.8), Vector3(0, 3.45, 0),
		mat_photo("roof", _var(Color(0.8, 0.82, 0.88), 0.06), 0.88, 0.78, 1.3, ProceduralTex.roof_tiles(7), 1.1, 3.2, 0.45), PI * 0.5)
	box(Vector3(4.75, 0.14, 0.3), Vector3(0, 4.12, 0), roof_col.darkened(0.25))
	box(Vector3(4.4, 0.1, 0.1), Vector3(0, 2.76, 1.82), Color("d9d2c0"))  # 檐沟
	_window_unit(1.0, 1.0, Vector3(-1.25, 1.7, 1.81))
	_window_unit(1.0, 1.0, Vector3(1.25, 1.7, 1.81))
	# 格子块围墙 + 门柱（前侧留门口）
	var wtex := mat_photo("rustic_stone_wall", Color(0.9, 0.87, 0.82), 0.9, 0.96, 0.85, ProceduralTex.pavers(31), 0.55, 2.6, 0.5)
	box(Vector3(7.4, 1.12, 0.2), Vector3(0, 0.56, -3.0), Color("bdb6a6"), 0.0, 0.0, 0.0, wtex)
	box(Vector3(0.2, 1.12, 4.2), Vector3(-3.6, 0.56, -0.9), Color("bdb6a6"), 0.0, 0.0, 0.0, wtex)
	box(Vector3(0.2, 1.12, 4.2), Vector3(3.6, 0.56, -0.9), Color("bdb6a6"), 0.0, 0.0, 0.0, wtex)
	box(Vector3(2.3, 1.0, 0.18), Vector3(-2.5, 0.5, 1.35), Color("bdb6a6"), 0.0, 0.0, 0.0, wtex)
	box(Vector3(2.3, 1.0, 0.18), Vector3(2.5, 0.5, 1.35), Color("bdb6a6"), 0.0, 0.0, 0.0, wtex)
	box(Vector3(0.26, 1.5, 0.26), Vector3(-1.3, 0.75, 1.35), Color("a8a294"), 0.0, 0.0, 0.0, wtex)
	box(Vector3(0.26, 1.5, 0.26), Vector3(1.3, 0.75, 1.35), Color("a8a294"), 0.0, 0.0, 0.0, wtex)
	sph(0.45, Vector3(-3.0, 0.42, 1.9), Color("5e8f52"))
	sph(0.34, Vector3(-2.5, 0.32, 2.15), Color("6faf5f"))
	sph(0.4, Vector3(3.0, 0.38, 1.95), Color("5e8f52"))
	_ac_unit(Vector3(1.9, 2.35, 1.75))
	box(Vector3(0.34, 0.12, 0.03), Vector3(0.75, 2.1, 1.83), Color.WHITE)


func _b_mansion() -> void:
	var wall_col := _var(Color("ddd6c8"))
	box(Vector3(4.2, 9.5, 3.8), Vector3(0, 4.75, 0), wall_col, 0.0, 0.0, 0.0,
		mat_photo("plaster_alt", _var(Color(0.97, 0.95, 0.9)), 0.9, 0.93, 0.42, ProceduralTex.wall_tiles(13), 2.0, 2.0, 0.4))
	_downspout(Vector3(-2.05, 0, 1.85), 9.4)
	box(Vector3(4.6, 0.4, 4.2), Vector3(0, 9.65, 0), Color("6a6d76"))
	for f in 5:
		var y := 1.55 + f * 1.62
		box(Vector3(3.9, 0.12, 0.85), Vector3(0, y, 2.2), Color("c4bcab"))
		box(Vector3(3.9, 0.06, 0.06), Vector3(0, y + 0.55, 2.6), Color("9aa0ab"))
		for bx in 9:
			box(Vector3(0.045, 0.55, 0.045), Vector3(-1.8 + bx * 0.45, y + 0.28, 2.6), Color("9aa0ab"))
		for wx in [-1.1, 1.1]:
			box(Vector3(1.2, 1.3, 0.1), Vector3(wx, y + 0.75, 1.88), Color("efe9da"))
			box(Vector3(1.1, 1.2, 0.08), Vector3(wx, y + 0.75, 1.92), Color("a8c4d8"), 0.0, 0.0, 0.0, glass_mat(Color("9dbfd6")))
	box(Vector3(2.2, 0.14, 1.15), Vector3(0, 2.5, 2.3), Color("8b7f6a"))
	box(Vector3(0.18, 2.5, 0.18), Vector3(-0.9, 1.25, 2.75), Color("8b7f6a"))
	box(Vector3(0.18, 2.5, 0.18), Vector3(0.9, 1.25, 2.75), Color("8b7f6a"))
	cyl(0.55, 0.55, 1.0, Vector3(-1.1, 10.3, -0.6), Color("6b8bab"))
	cyl(0.2, 0.2, 0.5, Vector3(-1.1, 9.75, -0.6), Color("55575e"))
	cyl(0.35, 0.35, 0.85, Vector3(1.2, 10.25, -0.7), Color("6b8bab"))
	for rx in [-2.0, 2.0]:
		box(Vector3(0.06, 0.7, 0.06), Vector3(rx, 10.15, 1.9), Color("8a8d96"))
	box(Vector3(4.1, 0.06, 0.06), Vector3(0, 10.5, 1.9), Color("8a8d96"))
	cyl(0.03, 0.03, 2.2, Vector3(0.6, 10.8, -0.8), Color("8a8d96"))


func _b_cafe() -> void:
	box(Vector3(5.2, 1.3, 4.2), Vector3(0, 0.65, 0), Color("b08d5e"), 0.0, 0.0, 0.0,
		mat_photo("brown_planks_08", _var(Color(0.86, 0.72, 0.56)), 0.88, 0.95, 0.55, ProceduralTex.wood(15), 0.9, 2.2, 0.45))
	box(Vector3(5.2, 2.3, 4.2), Vector3(0, 2.45, 0), _var(Color("c9a876")), 0.0, 0.0, 0.0,
		mat_photo("plaster_brick_01", _var(Color(0.95, 0.86, 0.7)), 0.88, 0.95, 0.44, ProceduralTex.plaster(16), 0.55, 2.0, 0.4))
	box(Vector3(5.5, 0.32, 4.5), Vector3(0, 3.7, 0), Color("6b4a2f"))
	box(Vector3(4.6, 0.95, 0.2), Vector3(0, 3.1, 2.12), Color("6b4a2f"))
	text3d("喫茶店", 120, Vector3(0, 3.1, 2.26), Color("f2e6cf"))
	var win := cyl(0.5, 0.5, 0.1, Vector3(-1.5, 2.0, 2.1), Color("c8dcc8"), true)
	win.rotation = Vector3(PI * 0.5, 0, 0)
	win.material_override = glass_mat(Color("c8dcc8"))
	torus(0.5, 0.6, Vector3(-1.5, 2.0, 2.14), Color("6b4a2f"), true)
	box(Vector3(1.06, 0.09, 0.12), Vector3(-1.5, 2.0, 2.16), Color("6b4a2f"))
	box(Vector3(0.09, 1.06, 0.12), Vector3(-1.5, 2.0, 2.16), Color("6b4a2f"))
	_window_unit(1.0, 0.9, Vector3(1.35, 2.05, 2.11), Color("6b4a2f"))
	box(Vector3(1.2, 0.26, 0.3), Vector3(1.35, 1.35, 2.2), Color("7a5a3a"))
	for i in 3:
		sph(0.09, Vector3(1.05 + i * 0.3, 1.52, 2.2), [Color("e86a92"), Color("e6b84c"), Color("d97fb0")][i])
	var awn := box(Vector3(1.7, 0.08, 0.9), Vector3(0, 2.35, 2.5), Color("6b4a2f"))
	awn.rotation = Vector3(-0.3, 0, 0)
	sph(0.09, Vector3(0, 2.62, 2.28), Color("f2cc5a"))


func _b_ramen() -> void:
	box(Vector3(6.2, 4.0, 4.6), Vector3(0, 2.0, 0), _var(Color("d9c49a")), 0.0, 0.0, 0.0,
		mat_photo("dark_planks", _var(Color(0.88, 0.74, 0.58)), 0.85, 0.95, 0.5, ProceduralTex.wood(17), 0.8, 2.2, 0.5))
	box(Vector3(6.4, 0.4, 4.8), Vector3(0, 4.1, 0), Color("5a4a3a"))
	box(Vector3(6.2, 0.55, 0.24), Vector3(0, 3.3, 2.28), Color("5a4a3a"))
	text3d("ラーメン", 110, Vector3(0, 3.3, 2.45), Color("f2e6cf"))
	for i in 3:
		box(Vector3(1.35, 1.2, 0.07), Vector3(-1.45 + i * 1.45, 2.42, 2.36), Color("3a4a6b"))
		box(Vector3(1.35, 0.06, 0.1), Vector3(-1.45 + i * 1.45, 3.05, 2.36), Color("2c3a55"))
	box(Vector3(1.6, 2.15, 0.1), Vector3(0, 1.08, 2.33), Color("4a3f33"))
	box(Vector3(1.3, 1.0, 0.08), Vector3(-2.3, 1.7, 2.3), Color("c8b890"), 0.0, 0.0, 0.0, glass_mat(Color("c8b890")))
	box(Vector3(0.07, 0.55, 0.07), Vector3(2.75, 3.62, 2.6), Color("5a4a3a"))
	var lamp := sph(0.42, Vector3(2.75, 3.05, 2.6), Color("c94f4f"))
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color("c94f4f")
	lm.emission_enabled = true
	lm.emission = Color("c94f4f")
	lm.emission_energy_multiplier = 0.45
	lamp.material_override = lm
	text3d("麺", 80, Vector3(2.75, 3.05, 3.05), Color.WHITE)
	box(Vector3(0.5, 2.0, 0.08), Vector3(-2.7, 2.1, 2.4), Color("f2e6cf"))
	box(Vector3(0.56, 0.1, 0.14), Vector3(-2.7, 3.15, 2.4), Color("5a4a3a"))
	text3d("ら\nー\nめ\nん", 56, Vector3(-2.7, 2.15, 2.47), Color("2b2b33"))
	box(Vector3(6.2, 0.18, 4.7), Vector3(0, 0.09, 0), Color("8a7a5e"))


func _b_post() -> void:
	var wall_col := _var(Color("f0ede6"))
	box(Vector3(5.8, 4.4, 4.2), Vector3(0, 2.2, 0), wall_col, 0.0, 0.0, 0.0,
		mat_photo("yellow_brick", _var(Color(0.98, 0.95, 0.88)), 0.9, 0.94, 0.5, ProceduralTex.wall_tiles(18), 1.6, 2.4, 0.5))
	box(Vector3(5.8, 1.05, 0.26), Vector3(0, 3.85, 2.12), Color("b91c1c"))
	text3d("〒 郵便局", 110, Vector3(0, 3.85, 2.3), Color.WHITE)
	_window_unit(1.3, 1.1, Vector3(-1.7, 2.2, 2.12))
	_window_unit(1.3, 1.1, Vector3(1.7, 2.2, 2.12))
	box(Vector3(5.8, 0.18, 4.3), Vector3(0, 0.09, 0), Color("c4bcab"), 0.0, 0.0, 0.0,
		mat_photo("pavers", Color(0.84, 0.82, 0.77), 0.0, 0.94, 0.5, ProceduralTex.pavers(41), 0.5, 2.2, 0.35))


func _b_station() -> void:
	var wall_col := _var(Color("efe9da"))
	box(Vector3(12.5, 4.6, 4.5), Vector3(0, 2.3, 0), wall_col, 0.0, 0.0, 0.0,
		mat_photo("grey_plaster", _var(Color(0.96, 0.95, 0.93)), 0.92, 0.92, 0.44, ProceduralTex.wall_tiles(19), 1.5, 2.0, 0.35))
	# 车站基座：混凝土贴图（裸色会在暖光下泛紫蓝，像一条塑料带）
	box(Vector3(12.6, 0.9, 4.6), Vector3(0, 0.45, 0), Color.WHITE, 0,0,0,
		mat_photo("concrete_pavers", Color(0.72, 0.73, 0.78), 0.9, 0.9, 0.55, ProceduralTex.pavers(51), 0.5, 2.4, 0.45))
	# 雨棚檐口：镀锌铁皮
	box(Vector3(12.9, 0.6, 4.9), Vector3(0, 4.8, 0), Color.WHITE, 0,0,0, m_metal_galva(position))
	box(Vector3(4.2, 1.4, 0.2), Vector3(-2.6, 4.0, 2.3), Color("2b6cb0"))
	text3d("駅", 132, Vector3(-2.6, 4.0, 2.44), Color.WHITE)
	var clock := cyl(0.5, 0.5, 0.07, Vector3(2.8, 3.7, 2.28), Color.WHITE, true)
	clock.rotation = Vector3(PI * 0.5, 0, 0)
	box(Vector3(0.06, 0.3, 0.03), Vector3(2.8, 3.78, 2.33), Color("3a3f4a"))
	box(Vector3(0.2, 0.06, 0.03), Vector3(2.9, 3.7, 2.33), Color("3a3f4a"))
	box(Vector3(9.5, 2.4, 0.1), Vector3(0, 1.35, 2.24), Color("a9cede"), 0.0, 0.0, 0.0, glass_mat(Color("a9cede")))
	for i in 7:
		box(Vector3(0.12, 2.45, 0.16), Vector3(-4.5 + i * 1.5, 1.35, 2.26), Color("d8d2c4"))
	# 候车亭：站台雨棚 + 立柱 + 长椅 + 售卖机（装饰）
	box(Vector3(12.0, 0.18, 3.0), Vector3(0, 3.3, -4.6), Color.WHITE, 0,0,0, m_metal_galva(position))
	for px in [-5.0, 0.0, 5.0]:
		box(Vector3(0.22, 3.2, 0.22), Vector3(px, 1.75, -3.4), Color("8a95a8"))
	for bx in [-3.0, 1.0]:
		box(Vector3(1.8, 0.08, 0.5), Vector3(bx, 1.17, -5.1), Color("6b8bab"))
		box(Vector3(1.8, 0.45, 0.07), Vector3(bx, 1.43, -5.32), Color("7a95b5"))
		box(Vector3(0.08, 0.5, 0.4), Vector3(bx - 0.8, 0.92, -5.1), Color("55575e"))
		box(Vector3(0.08, 0.5, 0.4), Vector3(bx + 0.8, 0.92, -5.1), Color("55575e"))
	box(Vector3(0.9, 1.8, 0.75), Vector3(-4.2, 1.45, -5.3), Color("d64541"))


func _b_train() -> void:
	for ci in 3:
		var cx := -6.5 + ci * 6.5
		box(Vector3(6.1, 2.3, 2.4), Vector3(cx, 1.75, 0), Color("e8eaee"))
		box(Vector3(6.1, 0.42, 2.44), Vector3(cx, 1.0, 0), Color("1d4ed8"))
		box(Vector3(5.7, 0.55, 2.2), Vector3(cx, 0.35, 0), Color("3a3d45"))
		for wi in 4:
			box(Vector3(1.0, 0.75, 0.06), Vector3(cx - 2.2 + wi * 1.45, 2.1, 1.22), Color("a8c4d8"), 0.0, 0.0, 0.0, glass_mat(Color("a8c4d8")))
		for dx in [-2.9, 2.9]:
			box(Vector3(0.95, 1.5, 0.07), Vector3(cx + dx, 1.45, 1.21), Color("9aa4b0"))
			box(Vector3(0.06, 1.5, 0.09), Vector3(cx + dx, 1.45, 1.22), Color("6a7480"))
		if ci == 1:
			box(Vector3(0.08, 0.9, 0.08), Vector3(cx - 0.5, 3.1, 0), Color("3a3d45"), 0.0, 0.0, 0.5)
			box(Vector3(0.08, 0.9, 0.08), Vector3(cx + 0.5, 3.1, 0), Color("3a3d45"), 0.0, 0.0, -0.5)
			box(Vector3(1.4, 0.06, 0.12), Vector3(cx, 3.5, 0), Color("3a3d45"))
		if ci < 2:
			box(Vector3(0.5, 0.8, 0.8), Vector3(cx + 3.25, 1.3, 0), Color("8a8d96"))
	box(Vector3(0.9, 0.24, 0.05), Vector3(-9.2, 2.4, 1.23), Color("1d4ed8"))
	box(Vector3(0.3, 2.0, 2.1), Vector3(-9.75, 1.75, 0), Color("c4c8d0"))
	box(Vector3(0.3, 2.0, 2.1), Vector3(9.75, 1.75, 0), Color("c4c8d0"))


func _b_vending() -> void:
	# 规格指定：朱红塑料机身（roughness 0.35）+ 白面板 + 冷白灯箱自发光。
	# 两种配色交替摆放（红/蓝），是日本街头的真实样貌。
	var is_red := int(abs(position.x * 40.0)) % 2 == 0
	var body_col := Color(0.78, 0.17, 0.16) if is_red else Color(0.16, 0.35, 0.62)
	var body := m_plastic_red(position) if is_red else _mat_j("pl_blue", body_col, position, 0.35, 0.1, 0.04)
	var panel := m_plastic_white(position)
	# 机身
	box(Vector3(0.95, 1.85, 0.8), Vector3(0, 0.925, 0), Color.WHITE, 0,0,0, body)
	box(Vector3(0.95, 0.16, 0.82), Vector3(0, 1.8, 0), Color.WHITE, 0,0,0, body)
	# 灯箱：冷白自发光，夜晚会被 Bloom 捕获 —— 街道氛围的重要来源
	var lit := m_glow(Color(0.86, 0.94, 1.0), 2.6)
	box(Vector3(0.72, 1.3, 0.07), Vector3(-0.06, 1.0, 0.41), Color.WHITE, 0,0,0, lit)
	# 饮料格：每排颜色不同，制造"里面有货"的密度感
	var drinks := [Color(0.35, 0.55, 0.9), Color(0.9, 0.72, 0.3), Color(0.5, 0.7, 0.4), Color(0.85, 0.5, 0.5)]
	for row in 4:
		for col in 2:
			var ci := (row * 2 + col) % 4
			box(Vector3(0.16, 0.26, 0.06), Vector3(-0.22 + col * 0.3, 0.48 + row * 0.32, 0.45),
				Color.WHITE, 0,0,0, _mat_j("drink%d" % ci, drinks[ci], position + Vector3(row, col, 0), 0.45, 0.0, 0.1))
			box(Vector3(0.16, 0.03, 0.07), Vector3(-0.22 + col * 0.3, 0.36 + row * 0.32, 0.45), Color.WHITE, 0,0,0, panel)
	# 取物口 + 操作面板
	box(Vector3(0.22, 1.15, 0.06), Vector3(0.33, 1.05, 0.41), Color(0.1, 0.11, 0.14), 0,0,0, m_rubber(position))
	box(Vector3(0.16, 0.4, 0.03), Vector3(0.33, 1.5, 0.44), Color.WHITE, 0,0,0, panel)
	box(Vector3(0.95, 0.1, 0.85), Vector3(0, 0.05, 0), Color.WHITE, 0,0,0, m_metal_dark(position))


func _b_pole() -> void:
	# 电线杆：混凝土杆（roughness 0.88）+ 镀锌横担（metallic 0.75）
	# 材质反差是"这看起来像真电线杆"的关键：哑光水泥 + 亮金属横担
	var cm := mat_photo("concrete", Color(0.6, 0.61, 0.64), 0.0, 0.94, 1.4,
		null, 0.5, 2.5, 0.4)
	_cyl_m(Vector3(0.09, 0.12, 7.0), Vector3(0, 3.5, 0), cm)
	var galva := m_metal_galva(position)
	var dark := m_metal_dark(position)
	box(Vector3(0.55, 0.95, 0.55), Vector3(0, 5.3, 0), Color.WHITE, 0,0,0, galva)
	box(Vector3(1.6, 0.13, 0.13), Vector3(0, 6.35, 0), Color.WHITE, 0,0,0, dark)
	box(Vector3(1.1, 0.1, 0.1), Vector3(0, 5.85, 0), Color.WHITE, 0,0,0, dark)
	for ox in [-0.65, 0.65, -0.42, 0.42]:
		var h := 0.24 if absf(ox) > 0.5 else 0.2
		cyl(0.05, 0.05, h, Vector3(ox, 6.55 if absf(ox) > 0.5 else 5.95, 0), Color.WHITE, false, m_glass_insulator())
	box(Vector3(0.16, 0.55, 0.16), Vector3(0, 0.27, 0), Color.WHITE, 0,0,0, dark)
	box(Vector3(0.16, 0.1, 0.02), Vector3(0, 2.6, 0.1), Color.WHITE)


## 绝缘子：白瓷，高光泽（roughness 0.12）
func m_glass_insulator() -> StandardMaterial3D:
	if _mats.has("insul"):
		return _mats["insul"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.88, 0.9, 0.88)
	m.roughness = 0.14
	m.metallic = 0.05
	m.metallic_specular = 0.7
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats["insul"] = m
	return m


## 圆柱（电线杆、树干等）带贴图版本
func _cyl_m(size: Vector3, pos: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = size.x
	mesh.bottom_radius = size.y
	mesh.height = size.z
	mesh.radial_segments = 12
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi


## 金属/涂装表面材质（铁杆、铁轨、空调外机等）
func mat_metal(tint: Color, rough := 0.55) -> StandardMaterial3D:
	var key := "mt_%s_%f" % [tint.to_html(), rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = 0.35
	m.metallic_specular = 0.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats[key] = m
	return m


## 树皮材质（按 kind 区分树种）
func mat_bark(kind: String, tint: Color) -> StandardMaterial3D:
	var key := "bk_%s_%s" % [kind, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	# 树皮是竖纹，拉伸的 UV 更像真树皮
	m.uv1_scale = Vector3(2.5, 0.35, 2.5)
	m.albedo_color = tint
	m.roughness = 0.98
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var col := _tex("res://assets/tex/%s_col.jpg" % kind)
	if col != null:
		m.albedo_texture = col
		var nrm := _tex("res://assets/tex/%s_nrm.jpg" % kind)
		if nrm != null:
			m.normal_enabled = true
			m.normal_texture = nrm
			m.normal_scale = 1.0
	_mats[key] = m
	return m


func _b_mailbox() -> void:
	# 【尺度】0.55m —— 矮型邮筒（日本街头常见的那种圆筒矮邮筒）。
	# 朱红点缀色（规格：画面占比 <5% 但吸走 80% 注意力），猫可以跳上去。
	var red := m_vermilion(position)
	var red_dark := _mat_j("verm_d", Color(0.62, 0.18, 0.15), position, 0.5, 0.05, 0.04)
	var metal := m_metal_galva(position)
	# 圆筒形（经典日式邮筒），比方形矮墩更适合猫尺度
	cyl(0.24, 0.26, 0.44, Vector3(0, 0.22, 0), Color.WHITE, false, red)
	# 顶盖：平顶圆盘，不要半球 —— 半球直径 0.5m 会在近景里大得离谱，
	# 而且猫踩半球不方便（曲面站不稳）。平顶也更像真实邮筒。
	cyl(0.27, 0.27, 0.06, Vector3(0, 0.465, 0), Color.WHITE, false, red_dark)
	cyl(0.1, 0.1, 0.04, Vector3(0, 0.51, 0), Color.WHITE, false, red_dark)
	# 投信口
	box(Vector3(0.3, 0.05, 0.05), Vector3(0, 0.36, -0.23), Color(0.1, 0.08, 0.08), 0,0,0, m_rubber(position))
	text3d("〒", 76, Vector3(0, 0.24, -0.26), Color.WHITE)
	# 底座
	cyl(0.27, 0.27, 0.05, Vector3(0, 0.025, 0), Color.WHITE, false, metal)
## 街边分类垃圾桶：【Kenney City Kit Roads】dumpster。
## 【尺度】原版是大号市政桶（约 1.2m），这里归一化到 0.85m —— 猫跳得上去，
## 又不像之前 0.52m 的圆柱那样「像个铁罐」。倒扣的桶盖 + 侧板加强筋是模型自带的。
## 成组摆放（位置哈希决定旁边是否再来一个），街边垃圾桶从来不是孤零零一个。
func _b_trash() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/dumpster.glb", 0.85, Vector3.ZERO, ry + PI)
	if _var_seed(position + Vector3(3, 0, 7)) > 0.55:
		_glb_h("kenney/dumpster.glb", 0.85, Vector3(0.95, 0, 0.1), ry + PI + 1.3)
func _b_bicycle() -> void:
	# 【Poly Pizza / Poly by Google,CC-BY】带车把、车筐、辐条、车座的完整自行车。
	# 手搭版(torus 轮 + 方盒车架)远看就是两个圆圈扛着几根棍。
	# 归一化到 1.0m(带车把的真实停车高度),车头朝向按位置哈希随机。
	var ry := _var_seed(position) * TAU
	_glb_h("polypizza/bicycle.glb", 1.0, Vector3.ZERO, ry)


func _b_car() -> void:
	# 【Kenney Car Kit / CC0】原来这台车是 1 个车身方盒 + 1 个玻璃方盒 + 4 个圆柱轮子，
	# 停在街边一眼就是「积木」。Kenney 的车有引擎盖/车窗/保险杠/后视镜的层次。
	# 归一化到 1.45m 高（对齐 META 的 solid 高度，碰撞体不用动）。
	# 车头沿街（沿 +X / -X 停），随机左右 + 一点角度歪
	# 不染色：Kenney 的 colormap 贴图自带车漆色，乘色反而会脏。
	# 车型按位置哈希轮换，一整条街不会全是同一台车。
	var kinds := ["sedan.glb", "hatchback-sports.glb", "suv.glb", "van.glb"]
	var h := _var_seed(position)
	var rel: String = kinds[int(h * 313.0) % kinds.size()]
	var ry := (0.0 if int(h * 97.0) % 2 == 0 else PI) + (h - 0.5) * 0.16
	_glb_h("kenney/" + rel, 1.45, Vector3.ZERO, ry)


func _b_traffic() -> void:
	# 金属杆(metal 0.85) + 三色信号灯(UNSHADED 自发光，Bloom 会捕获)
	var dark := m_metal_dark(position)
	cyl(0.08, 0.11, 4.5, Vector3(0, 2.25, 0), Color.WHITE, false, dark)
	box(Vector3(0.14, 0.14, 2.6), Vector3(0, 5.35, 1.3), Color.WHITE, 0,0,0, dark)
	box(Vector3(0.42, 1.15, 0.5), Vector3(0, 5.1, 2.45), Color.WHITE, 0,0,0, m_metal_cool(position))
	# 红(停) 黄(待) 绿(行)：只点亮当前相位，夜景里是街道的节奏点
	box(Vector3(0.34, 0.32, 0.1), Vector3(0, 5.1, 2.72), Color.WHITE, 0,0,0, m_glow(Color(0.95, 0.22, 0.18), 3.0))
	box(Vector3(0.34, 0.32, 0.1), Vector3(0, 5.42, 2.72), Color.WHITE, 0,0,0, m_glow(Color(0.95, 0.75, 0.2), 0.5))
	box(Vector3(0.34, 0.32, 0.1), Vector3(0, 4.78, 2.72), Color.WHITE, 0,0,0, m_glow(Color(0.3, 0.95, 0.4), 0.5))
	box(Vector3(0.45, 1.2, 0.4), Vector3(0, 5.1, 0), Color.WHITE, 0,0,0, dark)
	box(Vector3(0.3, 0.3, 0.3), Vector3(0, 0.15, 0), Color.WHITE, 0,0,0, m_rubber(position))
func _b_signboard() -> void:
	box(Vector3(0.15, 1.5, 0.15), Vector3(0, 0.75, 0), Color("6b5d4a"))
	box(Vector3(0.95, 1.7, 0.12), Vector3(0, 2.2, 0), Color("f2e6cf"), 0.0, 0.0, 0.0,
		tex_mat(ProceduralTex.wood(23), Color("f2e6cf"), 1.2, 0.9, "sb"))
	box(Vector3(1.06, 0.1, 0.2), Vector3(0, 3.08, 0), Color("6b5d4a"))
	text3d("営\n業\n中", 78, Vector3(0, 2.2, 0.09), Color("2b2b33"))
	box(Vector3(0.95, 0.12, 0.14), Vector3(0, 1.42, 0), Color("b5484d"))


func _b_streetlight() -> void:
	# 金属杆 + 暖白灯箱。灯箱是 UNSHADED 自发光，Bloom 会捕获 → 夜里街道的锚点
	var dark := m_metal_dark(position)
	cyl(0.07, 0.1, 4.2, Vector3(0, 2.1, 0), Color.WHITE, false, dark)
	box(Vector3(1.15, 0.09, 0.09), Vector3(0.48, 4.15, 0), Color.WHITE, 0,0,0, dark)
	# 灯罩：金属外壳
	box(Vector3(0.6, 0.16, 0.24), Vector3(1.0, 4.05, 0), Color.WHITE, 0,0,0, m_metal_galva(position))
	# 发光面（朝下，路面会被照亮 —— 配合 OmniLight 效果更真）
	box(Vector3(0.5, 0.05, 0.18), Vector3(1.0, 3.97, 0), Color.WHITE, 0,0,0, m_glow(Color(1.0, 0.85, 0.6), 3.2))
	box(Vector3(0.42, 0.32, 0.42), Vector3(0, 0.16, 0), Color.WHITE, 0,0,0, m_concrete(position))
## 长椅：【Kenney Holiday Kit】bench（条板座面 + 铸铁腿 + 靠背一体）。
## 【尺度】归一化到 0.45m —— 真人座高标准 0.42m，猫的跳跃极限 0.66m，两者都满足。
## 手搭版的「木块 + 4 根方腿」远看就是一条板凳，模型的靠背曲线和椅腿弯折
## 才是让长椅「像长椅」的关键。
func _b_bench() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/bench.glb", 0.45, Vector3.ZERO, ry + PI * 0.5)
func _b_busstop() -> void:
	var dark := m_metal_cool(position)
	cyl(0.05, 0.07, 2.7, Vector3(0, 1.35, 0), Color.WHITE, false, dark)
	# 站牌灯箱：蓝色自发光，夜晚是街边的一个光点
	box(Vector3(0.85, 0.85, 0.08), Vector3(0, 2.45, 0), Color.WHITE, 0,0,0, m_glow(Color(0.25, 0.5, 0.8), 2.0))
	box(Vector3(0.45, 0.24, 0.03), Vector3(0, 2.56, 0.06), Color.WHITE, 0,0,0, m_plastic_white(position))
	box(Vector3(0.1, 0.1, 0.03), Vector3(-0.12, 2.42, 0.06), Color(0.1,0.2,0.4), 0,0,0, m_rubber(position))
	box(Vector3(0.1, 0.1, 0.03), Vector3(0.12, 2.42, 0.06), Color(0.1,0.2,0.4), 0,0,0, m_rubber(position))
	text3d("バス", 52, Vector3(0, 2.16, 0.06), Color.WHITE)
	# 时刻表：纸张质感
	box(Vector3(0.5, 0.65, 0.04), Vector3(0, 1.45, 0.06), Color.WHITE, 0,0,0, m_paper(position))
	for i in 4:
		box(Vector3(0.36, 0.04, 0.05), Vector3(0, 1.62 - i * 0.13, 0.07), Color(0.35,0.33,0.3), 0,0,0, m_plastic_white(position))
func _b_tree() -> void:
	# 【Kenney Nature Kit / CC0】树的剪影是这类模型最难手搭的部分 —— 球堆树冠一眼假。
	# 5 种基础形按位置哈希轮换，再各自随机大小/朝向，整条街就不重样。
	var variants := [
		"kenney/tree_default.glb", "kenney/tree_oak.glb", "kenney/tree_cone.glb",
		"kenney/tree_fat.glb", "kenney/tree_detailed.glb",
	]
	var h := _var_seed(position)
	var rel: String = variants[int(h * variants.size()) % variants.size()]
	# 模型原始高度 1.2~1.7m，街道树要 3.4~4.6m
	var s := 2.3 + h * 0.9
	# 树冠颜色微差：同一种绿连着出现 3 棵就很假。
	# 必须染 —— Kenney 原色是青绿（0.16,0.79,0.67），在暖色黄昏里会跳出来。
	var tint := Color("8fbf6a").lerp(Color("5f9e52"), h)
	var n := _glb(rel, Vector3.ZERO, s, h * TAU, {"leafs": tint})
	if n == null:
		return
	n.scale = Vector3(s * (0.92 + h * 0.16), s, s * (0.92 + h * 0.16))


func _b_sakura() -> void:
	# 【樱树 = Kenney 树 + 粉色染叶】比手搭粉球树耐看得多：
	# Kenney 的树冠是三角面片，染粉之后有真实的樱花团块感。
	var rel := "kenney/tree_default.glb"
	if _var_seed(position + Vector3(7, 0, 3)) > 0.45:
		rel = "kenney/tree_detailed.glb"
	var h := _var_seed(position + Vector3(1, 0, 9))
	var s := 2.7 + h * 0.7
	var pinks := [Color("f2a8c4"), Color("f7bfd2"), Color("e894b4")]
	var pink: Color = pinks[int(h * 997.0) % pinks.size()]
	_glb(rel, Vector3.ZERO, s, h * TAU, {"leafs": pink})
	# 落樱的地面圆盘：淡粉半透明
	var disc := cyl(1.3, 1.3, 0.012, Vector3(0.3, 0.085, 0.3), Color.WHITE, false, m_petal())
	disc.scale = Vector3(1.0, 1.0, 0.8)


func _b_flower() -> void:
	# Kenney 的花是三片交叉面片，一丛 3~5 株才有「花丛」的感觉
	var kinds := ["flower_redA", "flower_yellowA", "flower_purpleA"]
	var h := _var_seed(position)
	for i in 3:
		var rel := "kenney/%s.glb" % kinds[int(h * 31.0 + i * 7.0) % kinds.size()]
		var ox := -0.28 + i * 0.28
		var oz := float((i * 5) % 3 - 1) * 0.22
		_glb(rel, Vector3(ox, 0, oz), 1.5 + h * 0.8, h * TAU + i * 1.7)


func _b_grass() -> void:
	var h := _var_seed(position)
	for i in 4:
		var ox := -0.3 + i * 0.2
		_glb("kenney/grass.glb", Vector3(ox, 0, float((i * 7) % 3 - 1) * 0.16),
			1.6 + h * 1.0, h * TAU + i * 1.3)
	if h > 0.6:
		_glb("kenney/plant_bushSmall.glb", Vector3(0.1, 0, 0.1), 1.8, h * 2.0)


func _b_parksign() -> void:
	box(Vector3(0.12, 1.6, 0.12), Vector3(0, 0.8, 0), Color("6b5d4a"))
	box(Vector3(1.4, 0.8, 0.07), Vector3(0, 1.98, 0), Color("5e7d4a"))
	box(Vector3(1.28, 0.68, 0.08), Vector3(0, 1.98, 0.01), Color("f2e6cf"))
	text3d("公園", 120, Vector3(0, 1.98, 0.08), Color("2b2b33"))
	sph(0.15, Vector3(0, 2.56, 0), Color("7fb069"))
	box(Vector3(0.05, 0.16, 0.05), Vector3(0, 2.4, 0), Color("6b4f3a"))


func _b_dog() -> void:
	# 【Quaternius Ultimate Animated Animal Pack / CC0】自带 12 条动画
	# （Idle / Walk / Gallop / Jump / Eating / Attack…），狗会自己甩尾踱步。
	# 归一化到 0.52m 肩高 —— 大型犬只在这个尺寸里才像「街边小狗」而不是「马」。
	var rel := "animals/dog.gltf"
	if not ResourceLoader.exists(MODEL_ROOT + rel):
		rel = "quaternius/ShibaInu.gltf"
	var n := _glb_h(rel, 0.52, Vector3.ZERO, _var_seed(position) * TAU)
	if n == null:
		return
	var ap := ModelUtil.find_anim(n, ["idle"])
	var a := ModelUtil.pick_anim(ap, ["idle", "walk"])
	if ap != null and a != "":
		ap.play(a)


func _b_cat() -> void:
	# 街头的猫用玩家猫那套外观（CatAvatar），这样玩家和 NPC 是同一个「角色资产」，
	# 以后换模型只改一个地方。缩到 0.9 并转向街边，背对镜头蹲着。
	var av := CatAvatar.new()
	av.scale = Vector3.ONE * 0.9
	av.position = Vector3(0, 0.0, 0)
	add_child(av)
	av.rotation.y = PI * 0.5 + _var_seed(position)
	av.animate(0.0, 0.0, 0.0)
	av.set_idle_only(true)


func _b_bird() -> void:
	# 【Poly Pizza / Poly by Google,CC-BY】麻雀自带喙/尾/胸腹的色彩分层。
	# 手搭版(两团圆球 + 方片尾巴)远看就是一颗石头。0.22m 一只,朝向随机。
	var ry := _var_seed(position) * TAU
	_glb_h("polypizza/sparrow.glb", 0.22, Vector3.ZERO, ry)


func _b_bowl() -> void:
	# 【Kenney Food Kit / CC0】bowl-broth 自带汤面 + 碗沿层次,
	# 手搭版(圆柱碗 + 圆环沿 + 两颗球)远看就是一摞圆盘。
	_glb_h("kenney/bowl-broth.glb", 0.3, Vector3.ZERO, _var_seed(position) * TAU)


func _b_cans() -> void:
	# 【Kenney Food Kit / CC0】can-open 自带拉环 + 顶盖凹陷。
	# 一罐立着、两罐倒下,空罐才有的散乱感。
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/can-open.glb", 0.18, Vector3(-0.2, 0, 0.05), ry)
	var t1 := _glb_h("kenney/can-open.glb", 0.18, Vector3(0.12, 0.06, -0.08), ry + 1.4)
	if t1 != null:
		t1.rotation.z = PI * 0.5
	var t2 := _glb_h("kenney/can-open.glb", 0.18, Vector3(0.3, 0.06, 0.12), ry + 2.3)
	if t2 != null:
		t2.rotation.z = PI * 0.5
		t2.rotation.x = 0.12


func _b_onigiri() -> void:
	# 【Kenney Food Kit / CC0】rice-ball 自带海苔贴片三角饭团。
	_glb_h("kenney/rice-ball.glb", 0.28, Vector3.ZERO, _var_seed(position) * TAU)


func _b_bread() -> void:
	box(Vector3(1.35, 0.4, 0.75), Vector3(0, 0.2, 0), Color("a8794e"), 0.0, 0.0, 0.0,
		tex_mat(ProceduralTex.wood(29), Color("a8794e"), 1.1, 0.9, "cr"))
	box(Vector3(1.37, 0.06, 0.77), Vector3(0, 0.42, 0), Color("8f6540"))
	for i in 3:
		var b := sph(0.17, Vector3(-0.42 + i * 0.42, 0.56, 0), Color("e6b84c"))
		b.scale = Vector3(1.0, 0.62, 0.75)


func _b_door() -> void:
	var col := Color("8b5e3c")
	var host := String(extra.get("host", ""))
	if host == "konbini":
		col = Color("9fc2d6")
	elif host == "mansion":
		col = Color("6b5d4a")
	box(Vector3(1.05, 2.2, 0.1), Vector3(0, 1.1, 0), col, 0.0, 0.0, 0.0, glass_mat(col.lightened(0.1)))
	box(Vector3(0.05, 2.2, 0.12), Vector3(0, 1.1, 0), Color(0.9, 0.9, 0.88, 0.6))
	sph(0.045, Vector3(0.38, 1.05, 0.08), Color("d8d2c4"))
	box(Vector3(1.2, 0.09, 0.18), Vector3(0, 2.26, 0), Color(0.25, 0.22, 0.2, 0.9))


func _b_window() -> void:
	_window_unit(1.15, 1.15, Vector3(0, _door_dy if _door_dy > 0 else 1.95, 0))


func _b_crosswalk() -> void:
	var dir := String(extra.get("dir", "v"))
	for i in 7:
		var off := -2.7 + i * 0.9
		if dir == "v":
			box(Vector3(0.5, 0.03, 2.9), Vector3(off, 0.075, 0), Color(1, 1, 1, 0.9))
		else:
			box(Vector3(2.9, 0.03, 0.5), Vector3(0, 0.075, off), Color(1, 1, 1, 0.9))


# ================================================================
# 批次 5 前置：专为「猫能跳上去」设计的矮物件
# 尺度基准：猫跳高 0.66m，所以台面全部 ≤ 0.5m。
# 这些是 Stray 里「猫在城市里钻来钻去」的主要落脚点。
# ================================================================

## 街边窨井盖（水泥井盖）：0.38m 高的凸台。Stray 里猫最爱跳的东西之一。
## 【坑】CylinderMesh 是开口的，横放时能直接看进内壁 → 变成一个黑洞。
## 做法：竖放 + 顶盖盖住口 + 井盖花纹。做实心的最稳。
func _b_pipe() -> void:
	var conc := m_concrete(position)
	var dark := m_metal_dark(position)
	# 井壁（竖放圆筒，不用 axis_z）
	cyl(0.3, 0.32, 0.34, Vector3(0, 0.17, 0), Color.WHITE, false, conc)
	# 井盖（顶面，猫踩这里）—— 略微凸出 + 深色金属
	cyl(0.31, 0.31, 0.06, Vector3(0, 0.35, 0), Color.WHITE, false, dark)
	# 盖面花纹（十字筋，让井盖一眼可认）
	for a in [0.0, PI * 0.5]:
		box(Vector3(0.52, 0.025, 0.05), Vector3(0, 0.385, 0), Color(0.16, 0.16, 0.17), a, 0, 0)
	# 提手小孔
	_sph2(0.035, Vector3(0, 0.39, 0), Color(0.1, 0.1, 0.11))
	# 井壁竖向裂纹（打破水泥的平整感）
	for i in 3:
		var an := float(i) * 2.1
		box(Vector3(0.02, 0.2, 0.02), Vector3(cos(an) * 0.3, 0.16, sin(an) * 0.3),
			Color(0.56, 0.54, 0.5), an, 0, 0)


## 纯色球（不接材质工厂的简版，用于小装饰）
func _sph2(r: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	add_child(mi)
	return mi


## 店铺门口的塑料周转箱：0.4m。猫跳上去可以俯瞰街面。
func _b_crate() -> void:
	# 三种颜色随机，跟街道色调协调（不是纯蓝塑料）
	var cols := [Color(0.42, 0.5, 0.56), Color(0.56, 0.44, 0.36), Color(0.4, 0.52, 0.44)]
	var c: Color = cols[int(abs(position.x * 7.3 + position.z * 3.1)) % 3]
	var m := _mat_j("crate", c, position, 0.5, 0.0, 0.07)
	# 箱体（略微收口，像真的周转箱）
	box(Vector3(0.72, 0.34, 0.58), Vector3(0, 0.17, 0), Color.WHITE, 0,0,0, m)
	box(Vector3(0.68, 0.06, 0.54), Vector3(0, 0.36, 0), Color.WHITE, 0,0,0, m)
	# 边缘加强筋
	for ex in [-0.34, 0.34]:
		box(Vector3(0.05, 0.3, 0.6), Vector3(ex, 0.17, 0), Color.WHITE, 0,0,0, m)
	# 里面露一点东西（空箱子太假）
	box(Vector3(0.4, 0.1, 0.3), Vector3(0.05, 0.33, 0.05), Color(0.7, 0.68, 0.6), 0,0,0.3, m)


## 花坛矮沿（公园/店铺前）：【Kenney City Kit Suburban】planter 自带池壁 + 泥土 +
## 植株，0.5m 沿口高度不变。手搭版的四面墙 + 单独一排「草杆」远看是一块空水泥台。
func _b_planter() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/planter.glb", 0.5, Vector3.ZERO, ry)
	# 位置哈希决定边上再插一株灌木，让花坛不至于千篇一律
	if _var_seed(position + Vector3(7, 0, 3)) > 0.45:
		_glb_h("kenney/plant_bushSmall.glb", 0.34, Vector3(0.86, 0.06, 0.28), ry + 1.7)


## 巷口矮墙：0.55m。猫能跳上去看过去，Stray 里爬墙是标志性动作。
func _b_lowwall() -> void:
	var conc := m_concrete(position)
	# 墙帽（顶面比墙体略宽，猫踩着有 overhang 的感觉）
	box(Vector3(2.3, 0.1, 0.4), Vector3(0, 0.5, 0), Color(0.66, 0.64, 0.6), 0,0,0, conc)
	# 墙体
	box(Vector3(2.2, 0.45, 0.32), Vector3(0, 0.225, 0), Color(0.72, 0.7, 0.66), 0,0,0, conc)
	# 压顶纹（横向凹槽，让大面积水泥不那么平）
	for i in 3:
		box(Vector3(2.24, 0.02, 0.34), Vector3(0, 0.12 + i * 0.13, 0), Color(0.64, 0.62, 0.58), 0,0,0, conc)


# ================================================================
# 批次 6：家具（家具屋门口的沿街展示品）
# 尺度沿用批次 5 的铁律：能跳的台面 ≤ 0.5m（桌子 0.45 / 椅子 0.44 /
# 沙发座 0.45 / 床台 0.33），柜子电视这种高的保持实心不可跳。
# ================================================================

## 家具屋：木色门脸 + 橱窗里透出店内家具的剪影
func _b_furniture() -> void:
	_shop_front(7.0, Color("e8dcc4"))
	box(Vector3(7.0, 1.0, 0.3), Vector3(0, 3.9, 2.6), Color("8b5e3c"))
	text3d("家具屋", 130, Vector3(0, 3.9, 2.78), Color("f2e6cf"))
	var awn := box(Vector3(6.8, 0.1, 1.5), Vector3(0, 3.15, 3.1), Color("8b5e3c"))
	awn.rotation = Vector3(-0.26, 0, 0)
	box(Vector3(6.8, 0.07, 0.2), Vector3(0, 2.9, 3.8), Color.WHITE)
	# 店内剪影：透过橱窗能看见本棚 + 桌子，暗示「这里面卖家具」
	var in_wood := tex_mat(ProceduralTex.wood(43), Color(0.55, 0.4, 0.28), 1.1, 0.9, "fw")
	box(Vector3(1.3, 1.4, 0.5), Vector3(-2.2, 0.7, 1.4), Color.WHITE, 0,0,0, in_wood)
	for i in 3:
		box(Vector3(1.16, 0.035, 0.44), Vector3(-2.2, 0.35 + i * 0.42, 1.4), Color.WHITE, 0,0,0, in_wood)
		for b in 4:
			box(Vector3(0.08, 0.24, 0.26), Vector3(-2.6 + b * 0.2, 0.52 + i * 0.42, 1.42),
				Color.WHITE, 0,0,0, _mat_j("fib%d%d" % [i, b],
				[Color("c94f4f"), Color("4a6fa5"), Color("5e9c54"), Color("e6b84c")][(i + b) % 4],
				position + Vector3(i, b, 0), 0.85, 0.0, 0.1))
	box(Vector3(1.1, 0.05, 0.7), Vector3(2.1, 0.43, 1.4), Color.WHITE, 0,0,0, in_wood)
	for lx in [-0.45, 0.45]:
		for lz in [-0.25, 0.25]:
			box(Vector3(0.06, 0.41, 0.06), Vector3(2.1 + lx, 0.21, 1.4 + lz), Color.WHITE, 0,0,0, in_wood)


## 木桌：0.45m 台面（猫可跳），四条腿留出可以钻的桌底
## 【Kenney Furniture Kit / CC0】手搭的方盒桌在近景里就是四根柱子一块板。
## 归一化到 0.45m 台面高 —— 正好卡在 META 的 stand 数值上，碰撞体不用动。
func _b_table() -> void:
	_glb_h("kenney/tableRound.glb", 0.45, Vector3.ZERO, _var_seed(position) * TAU, TINT_WOOD)


## 木椅：座面 0.44m + 靠背，四条腿
func _b_chair() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/chair.glb", 0.9, Vector3.ZERO, ry, TINT_WOOD)
	# 坐垫：给猫一个更愿意趴的平面，也让木椅不至于太硬
	_glb_h("kenney/chairCushion.glb", 0.5, Vector3(0, 0.44, 0.02), ry)


## 和式矮床：木台 + 布団 + 枕头 —— 猫最爱卧的那种
func _b_bed() -> void:
	var ry := _var_seed(position) * 0.6 - 0.3
	_glb_h("kenney/bedSingle.glb", 0.42, Vector3.ZERO, ry, TINT_WOOD)
	_glb_h("kenney/pillow.glb", 0.16, Vector3(0.62, 0.4, -0.28), ry + 0.2, TINT_FABRIC)
	_glb_h("kenney/rugRectangle.glb", 0.02, Vector3(1.1, 0.005, 0.5), ry)


## 布艺沙发：灰绿底座 + 靠背扶手 + 米色坐垫
func _b_sofa() -> void:
	_glb_h("kenney/loungeSofa.glb", 0.72, Vector3.ZERO, PI * 0.5 + _var_seed(position) * 0.4,
		TINT_FABRIC)


## 电视机：木电视柜 + 深色屏（玻璃反射天空）
func _b_tv() -> void:
	var ry := _var_seed(position) * 0.5 - 0.25
	_glb_h("kenney/cabinetTelevision.glb", 0.5, Vector3.ZERO, ry, TINT_WOOD)
	_glb_h("kenney/televisionModern.glb", 0.62, Vector3(0, 0.5, 0.02), ry)


## 本棚：四层隔板 + 彩色书脊
func _b_shelf() -> void:
	_glb_h("kenney/bookcaseOpen.glb", 1.5, Vector3.ZERO, PI + _var_seed(position) * 0.3, TINT_WOOD)
	# 书：按位置哈希塞几排，空书架太干净
	var h := _var_seed(position)
	for i in 3:
		if fmod(h * 7.0 + float(i) * 3.0, 2.0) < 0.6:
			continue
		_glb_h("kenney/books.glb", 0.24, Vector3(-0.1 + i * 0.06, 0.34 + i * 0.42, 0.06),
			h * 2.0 + i * 0.4)


## 落地灯：金属杆 + 米色和纸灯罩（m_paper 的 emission 由 TimeOfDay 点亮，白天不发假光）
func _b_lamp() -> void:
	_glb_h("kenney/lampRoundFloor.glb", 1.5, Vector3.ZERO, _var_seed(position) * TAU)


## 洗濯機：日本人家门口的标配。白机身 + 圆窗 + 控制面板
## 换 Kenney 的 washer：圆窗、面板、脚座都是现成的，比方盒上贴两个圆柱像洗衣机得多
func _b_wash() -> void:
	_glb_h("kenney/washer.glb", 0.9, Vector3.ZERO, PI + _var_seed(position) * 0.6)


# ================================================================
# 批次 7：街景杂物
# 定位：不参与学词的「生活痕迹」道具。日式街道的质感一半靠这些
# 零碎：消火栓、盆栽、晾衣杆、垃圾袋、旧轮胎、路锥、燃气罐、水洼。
# 矮件台面全部 ≤ 0.66m（猫的跳跃极限），沿袭批次 5 铁律。
# ================================================================

## 道路標識：灰色杆 + 板面。修复 map.json 里 roadsign 无 META 的隐形 bug。
## 两种板面（止まれ 红色 / 一方通行 蓝色）按位置哈希交替。
## 道路標識：【Kenney City Kit Roads】三款按位置哈希轮换（街名牌 / 止まれ /
## 警告牌）。手搭版用 Label3D 贴「止まれ」，近距离看字是贴图糊的；Kenney 的牌面
## 是真几何 + 原生 CC0 图文，远看轮廓也更接近现实路牌。
## 高度 2.4m 不变（猫爬电线杆那一段的尺度参照）。
func _b_roadsign() -> void:
	var ry := _var_seed(position) * TAU
	var pick := int(abs(position.x * 13.7 + position.z * 5.1)) % 3
	var rel := "kenney/roadsign_stop.glb"
	if pick == 1:
		rel = "kenney/roadsign_street.glb"
	elif pick == 2:
		rel = "kenney/roadsign_warning.glb"
	_glb_h(rel, 2.4, Vector3.ZERO, ry)


## 消火栓（柱形）：0.62m，猫可跳。
## 【Poly Pizza,CC0】firehydrant 自带侧出水口盖 + 顶盖链条造型,
## 手搭版(圆柱堆)远看就是一根红柱子,完全认不出是消火栓。
func _b_fireplug() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("polypizza/fire_hydrant.glb", 0.62, Vector3.ZERO, ry)


## 鉢植え：陶盆 + 土面 + 两种植物（灌木 / 开花）按位置哈希。
func _b_potplant() -> void:
	# 【Kenney Furniture Kit】原来的「陶盆 + 两团圆球」远看就是一团绿疙瘩。
	# pottedPlant 自带盆 + 土 + 植株，0.45m 台面高度不变。
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/pottedPlant.glb", 0.62, Vector3.ZERO, ry)
	# 高的那盆：多摆一株小盆栽，门口才不会只有一盆
	if _var_seed(position + Vector3(3, 0, 1)) > 0.5:
		_glb_h("kenney/plantSmall1.glb", 0.34, Vector3(0.42, 0, 0.16), ry + 1.2)


## 物干し竿：两根镀锌 T 杆 + 3 条下垂电线 + 4 条毛巾 + 1 张床单。
## solid = null：杆太细不值得碰撞，布是布（猫穿过去也算钻晾衣杆）。
func _b_laundry() -> void:
	var pole_m := m_metal_galva(position)
	for px in [-1.15, 1.15]:
		cyl(0.03, 0.042, 1.9, Vector3(px, 0.95, 0), Color.WHITE, false, pole_m)
		box(Vector3(0.52, 0.045, 0.045), Vector3(px, 1.87, 0), Color.WHITE, 0, 0, 0, pole_m)
	for lz in [-0.14, 0.0, 0.14]:
		_wire(self, Vector3(-1.15, 1.85, lz), Vector3(1.15, 1.85, lz), 0.008, Color("3a3d44"))
	# 毛巾：四种颜色，微差明度
	var tcols := [Color("e8e2d4"), Color("9fc2d6"), Color("e6b84c"), Color("d97fb0")]
	for i in 4:
		var tx := -0.75 + i * 0.5
		box(Vector3(0.4, 0.5, 0.02), Vector3(tx, 1.58, 0.0), Color.WHITE, 0, 0, 0,
			_mat_j("towel%d" % i, tcols[i], position + Vector3(i, 0, 0), 0.9, 0.0, 0.07))
	# 床单：更大更白，挂中间偏后
	box(Vector3(0.62, 0.72, 0.02), Vector3(-0.35, 1.47, 0.12), Color.WHITE, 0, 0, 0,
		_mat_j("sheet", Color(0.94, 0.94, 0.96), position + Vector3(5, 0, 0), 0.92, 0.0, 0.04))


## ゴミ袋：半透明乙烯基袋（清晨收垃圾堆在路边）。
## 材质要带一点 alpha（0.9）+ 低 roughness，才有「塑料袋反光」的感觉。
func _b_trashbags() -> void:
	if not _mats.has("gbag"):
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.87, 0.89, 0.92, 0.9)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.roughness = 0.28
		bm.metallic = 0.05
		bm.metallic_specular = 0.6
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_mats["gbag"] = bm
	if not _mats.has("gbag_b"):
		var bb := StandardMaterial3D.new()
		bb.albedo_color = Color(0.55, 0.68, 0.8, 0.9)
		bb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bb.roughness = 0.28
		bb.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_mats["gbag_b"] = bb
	var bag_m: StandardMaterial3D = _mats["gbag"]
	var bag_b: StandardMaterial3D = _mats["gbag_b"]
	# 大袋 + 小袋 + 蓝袋，扁球形（装满垃圾的下坠感）
	var b1 := sph(0.28, Vector3(-0.2, 0.22, 0.05), Color.WHITE, bag_m)
	b1.scale = Vector3(1.0, 0.75, 0.95)
	var b2 := sph(0.22, Vector3(0.16, 0.17, -0.1), Color.WHITE, bag_m)
	b2.scale = Vector3(1.0, 0.72, 1.0)
	var b3 := sph(0.24, Vector3(0.1, 0.19, 0.22), Color.WHITE, bag_b)
	b3.scale = Vector3(1.0, 0.75, 0.9)
	# 扎口：袋顶一小节深色结
	cyl(0.05, 0.07, 0.09, Vector3(-0.2, 0.46, 0.05), Color.WHITE, false, m_rubber(position))
	cyl(0.045, 0.06, 0.08, Vector3(0.16, 0.35, -0.1), Color.WHITE, false, m_rubber(position))


## 旧轮胎堆：店后巷/修车铺门口。三层 torus 叠放，0.51m 可跳。
func _b_tires() -> void:
	var rubber := m_rubber(position)
	for i in 3:
		# 每层稍微错位 + 微倾，堆过的轮胎不会齐得像烤架
		var t := torus(0.26, 0.37, Vector3(0.02 * (i - 1), 0.09 + i * 0.17, -0.01 * i), Color.WHITE, false, rubber)
		t.rotation = Vector3(0.03 * (i % 2 - 1), float(i) * 0.7, 0.02 * i)
	# 顶上放一盆野草（久置的轮胎会长草——生活痕迹）
	cyl(0.1, 0.13, 0.09, Vector3(0.02, 0.55, -0.01), Color.WHITE, false, _mat_j("tpot", Color(0.4, 0.36, 0.3), position, 0.85, 0.0, 0.1))
	sph(0.12, Vector3(0.02, 0.66, -0.01), Color.WHITE, m_foliage(position + Vector3(1, 0, 0)))


## 工事コーン：【Kenney City Kit Roads】construction-cone 自带橙身 + 白反光圈，
## 手搭版的「圆锥 + 单独 torus 反光圈」远看只是一个橙三角，连不成「施工道具」。
## 两个锥按位置哈希错开摆放，保持「不挡路」的施工边缘语义。
func _b_cones() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/construction_cone.glb", 0.48, Vector3(-0.25, 0, 0.0), ry + 0.4)
	_glb_h("kenney/construction_cone.glb", 0.48, Vector3(0.3, 0, 0.12), ry + 2.1)


## ガスボンベ：饮食店后面靠墙的液化气罐 ×3。
## 【Poly Pizza,CC0】PropaneTank 自带罐身收肩 + 顶阀 + 提手,
## 手搭版(两根圆柱 + 方箍)被看成「油桶」——收肩和阀才是「煤气罐」的识别特征。
func _b_gasbottle() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("polypizza/propane_tank.glb", 0.7, Vector3(-0.26, 0, -0.12), ry + 0.3)
	_glb_h("polypizza/propane_tank.glb", 0.7, Vector3(0.26, 0, -0.06), ry + 1.1)
	_glb_h("polypizza/propane_tank.glb", 0.7, Vector3(0.0, 0, 0.16), ry + 2.2)


## 水洼：路面的半透明反光片。roughness 0.06 + metallic 0.4 ——
## 白天反射天空发亮、夜里反射灯光，是「雨后街道」最便宜的假象。
func _b_puddle() -> void:
	if not _mats.has("puddle"):
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.3, 0.34, 0.4, 0.38)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.roughness = 0.06
		pm.metallic = 0.4
		pm.metallic_specular = 0.85
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_mats["puddle"] = pm
	var h := int(abs(position.x * 3.3 + position.z * 9.7)) % 1000
	var s := 0.9 + float(h % 40) / 40.0 * 1.1   # 0.9~2.0m
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(s, s * (0.55 + float(h % 20) / 20.0 * 0.3))
	mi.mesh = quad
	mi.material_override = _mats["puddle"]
	mi.rotation = Vector3(-PI * 0.5, 0, float(h) / 1000.0 * TAU)
	mi.position = Vector3(0, 0.078, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
