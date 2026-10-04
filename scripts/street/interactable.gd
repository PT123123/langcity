class_name Interactable
extends Area3D
## 街道上的可交互物体（3D）：全部由基础几何体 + 程序纹理拼装（无需美术资源）。
## 根节点是 Area3D：射线点击直接命中；实心物体额外挂 StaticBody3D 挡住玩家。

const S := 0.025  # 地图像素 -> 米（4000px 世界 = 100m）

# kind 元数据：
# click=点击体积(Area3D 盒) solid=碰撞体积(null=不挡路) range=交互距离(米,0=不限)
# novis=不生成外形(隐藏标记) door_win=依附建筑正面（map 里用 host 指定建筑类型）
const META := {
	"vending":      {"click": Vector3(1.0, 1.95, 0.9), "solid": Vector3(0.95, 1.85, 0.8), "range": 7.0},
	"pole":         {"click": Vector3(0.6, 7.2, 0.6), "solid": Vector3(0.3, 7.0, 0.3), "range": 6.0},
	"mailbox":      {"click": Vector3(0.75, 1.15, 0.7), "solid": Vector3(0.62, 1.0, 0.55), "range": 6.0},
	"trash":        {"click": Vector3(0.85, 0.95, 0.85), "solid": Vector3(0.72, 0.85, 0.72), "range": 6.0},
	"bicycle":      {"click": Vector3(1.9, 1.15, 0.75), "solid": Vector3(1.75, 0.9, 0.55), "range": 6.0},
	"car":          {"click": Vector3(4.5, 1.7, 2.0), "solid": Vector3(4.3, 1.5, 1.85), "range": 8.0},
	"traffic":      {"click": Vector3(0.7, 5.6, 3.2), "solid": Vector3(0.35, 4.5, 0.35), "range": 7.0},
	"station":      {"click": Vector3(12.6, 5.4, 8.2), "solid": Vector3(12.5, 4.8, 4.5), "range": 14.0},
	"train":        {"click": Vector3(19.6, 3.4, 2.9), "solid": Vector3(19.0, 2.6, 2.6), "range": 14.0},
	"konbini":      {"click": Vector3(6.6, 3.6, 5.1), "solid": Vector3(6.5, 3.4, 5.0), "range": 11.0},
	"house":        {"click": Vector3(4.3, 4.3, 3.7), "solid": Vector3(4.2, 3.0, 3.6), "range": 9.0},
	"mansion":      {"click": Vector3(4.3, 9.7, 3.9), "solid": Vector3(4.2, 9.5, 3.8), "range": 10.0},
	"super":        {"click": Vector3(7.7, 4.6, 5.5), "solid": Vector3(7.6, 4.4, 5.4), "range": 12.0},
	"cafe":         {"click": Vector3(5.3, 3.8, 4.3), "solid": Vector3(5.2, 3.6, 4.2), "range": 10.0},
	"ramen":        {"click": Vector3(6.3, 4.2, 4.7), "solid": Vector3(6.2, 4.0, 4.6), "range": 11.0},
	"post_office":  {"click": Vector3(5.9, 4.6, 4.3), "solid": Vector3(5.8, 4.4, 4.2), "range": 10.0},
	"signboard":    {"click": Vector3(1.1, 2.8, 0.5), "solid": Vector3(0.9, 2.6, 0.35), "range": 6.0},
	"streetlight":  {"click": Vector3(1.9, 4.5, 0.45), "solid": Vector3(0.25, 4.2, 0.25), "range": 6.0},
	"bench":        {"click": Vector3(2.5, 1.1, 0.95), "solid": Vector3(2.3, 0.85, 0.8), "range": 6.0},
	"busstop":      {"click": Vector3(1.4, 3.1, 0.5), "solid": Vector3(1.15, 2.9, 0.3), "range": 6.0},
	"tree":         {"click": Vector3(2.7, 4.7, 2.7), "solid": Vector3(0.55, 2.6, 0.55), "range": 7.0},
	"sakura":       {"click": Vector3(3.1, 5.3, 3.1), "solid": Vector3(0.55, 2.6, 0.55), "range": 7.0},
	"flower":       {"click": Vector3(1.2, 0.8, 1.2), "solid": null, "range": 5.0},
	"grass":        {"click": Vector3(1.5, 0.6, 1.5), "solid": null, "range": 5.0},
	"parksign":     {"click": Vector3(1.5, 2.4, 0.45), "solid": Vector3(1.25, 2.2, 0.25), "range": 6.0},
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
}

var word_id := ""
var kind := ""
var no_draw := false
var interact_range := 7.0
var extra := {}

var highlighted := false
var _pulse := 0.0
var _ring: MeshInstance3D
var _car_color := Color("e8e6e0")
var _door_dy := 0.0

static var _mats := {}

static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


## 照片级表面材质（Poly Haven CC0 扫描贴图），文件缺失时回退程序纹理
static func mat_photo(kind: String, tint: Color, tint_amt: float, rough: float, scale: float,
		fallback_tex: ImageTexture = null, fallback_scale := 0.5) -> StandardMaterial3D:
	var key := "ph_%s_%s_%f_%f" % [kind, tint.to_html(), rough, scale]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var col := _tex("res://assets/tex/%s_col.jpg" % kind)
	if col != null:
		m.albedo_texture = col
		m.albedo_color = tint
		var nrm := _tex("res://assets/tex/%s_nrm.jpg" % kind)
		if nrm != null:
			m.normal_enabled = true
			m.normal_texture = nrm
			m.normal_scale = 0.9
		var rgh := _tex("res://assets/tex/%s_rgh.jpg" % kind)
		if rgh != null:
			m.roughness_texture = rgh
			m.roughness = rough
		else:
			m.roughness = 0.95
	else:
		m.albedo_texture = fallback_tex
		m.albedo_color = tint
		m.roughness = 0.95
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


static func glass_mat(tint: Color) -> StandardMaterial3D:
	var key := "g_" + tint.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = 0.07
	m.metallic = 0.55
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
	if solid is Vector3:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var ss := CollisionShape3D.new()
		var sbox := BoxShape3D.new()
		sbox.size = solid
		ss.shape = sbox
		ss.position = Vector3(0, solid.y * 0.5, 0)
		body.add_child(ss)
		add_child(body)

	if not no_draw:
		_build_visual()
		_make_ring(click_size)


func _process(delta: float) -> void:
	if highlighted and _ring != null:
		_pulse += delta
		var p := 1.0 + 0.05 * sin(_pulse * 5.0)
		_ring.scale = Vector3(p, 0.22, p)


func set_highlight(v: bool) -> void:
	if highlighted == v:
		return
	highlighted = v
	_pulse = 0.0
	if _ring != null:
		_ring.visible = v


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
	_ring.position = Vector3(0, 0.07, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)


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


func cyl(top_r: float, bottom_r: float, h: float, pos: Vector3, color: Color, axis_z := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = h
	mesh.radial_segments = 14
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	if axis_z:
		mi.rotation = Vector3(PI * 0.5, 0, 0)
	add_child(mi)
	return mi


func sph(r: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 16
	mesh.rings = 10
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	add_child(mi)
	return mi


func torus(inner: float, outer: float, pos: Vector3, color: Color, upright := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 20
	mi.mesh = mesh
	mi.material_override = mat(color)
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


## 玻璃窗：白框 + 玻璃 + 窗台
func _window_unit(w: float, h: float, pos: Vector3, frame_col := Color("f2efe6")) -> void:
	box(Vector3(w + 0.14, h + 0.14, 0.09), pos + Vector3(0, 0, -0.02), frame_col)
	box(Vector3(w, h, 0.07), pos + Vector3(0, 0, 0.01), Color("b9d2e3"), 0.0, 0.0, 0.0, glass_mat(Color("a9cede")))
	box(Vector3(w, 0.05, 0.08), pos, Color.WHITE)
	box(Vector3(0.05, h, 0.08), pos, Color.WHITE)
	box(Vector3(w + 0.24, 0.09, 0.2), pos + Vector3(0, -h * 0.5 - 0.07, 0.03), Color("c9c2b0"))


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


## 商店玻璃门脸（橱窗 + 白框 + 店内货架）
func _shop_front(width: float, wall_col: Color) -> void:
	var wall_depth := 5.0 if width > 6 else 4.2
	var gz := 2.5 if width > 6 else 2.1
	var wall_c := _var(wall_col)
	box(Vector3(width, 3.4, wall_depth), Vector3(0, 1.7, 0), wall_c, 0.0, 0.0, 0.0,
		mat_photo("tilewall", _var(Color(0.93, 0.93, 0.9)), 0.04, 1.0, 0.5, ProceduralTex.wall_tiles(11), 1.6))
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
		mat_photo("concrete", Color(0.88, 0.86, 0.82), 0.03, 1.0, 0.45, ProceduralTex.pavers(21), 0.5))


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
		mat_photo("plaster", _var(Color(0.95, 0.93, 0.87)), 0.04, 1.0, 0.4, ProceduralTex.plaster(12), 0.55))
	prism(Vector3(3.9, 1.5, 4.8), Vector3(0, 3.45, 0),
		mat_photo("roof", _var(Color(0.95, 0.95, 0.97), 0.06), 1.0, 0.85, 0.7, ProceduralTex.roof_tiles(7), 1.1), PI * 0.5)
	box(Vector3(4.75, 0.14, 0.3), Vector3(0, 4.12, 0), roof_col.darkened(0.25))
	box(Vector3(4.4, 0.1, 0.1), Vector3(0, 2.76, 1.82), Color("d9d2c0"))  # 檐沟
	_window_unit(1.0, 1.0, Vector3(-1.25, 1.7, 1.81))
	_window_unit(1.0, 1.0, Vector3(1.25, 1.7, 1.81))
	# 格子块围墙 + 门柱（前侧留门口）
	var wtex := mat_photo("block", Color(0.9, 0.89, 0.85), 0.04, 1.0, 0.5, ProceduralTex.pavers(31), 0.55)
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
		mat_photo("tilewall", _var(Color(0.92, 0.9, 0.86)), 0.04, 1.0, 0.55, ProceduralTex.wall_tiles(13), 2.0))
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
		mat_photo("wood", _var(Color(0.85, 0.7, 0.55)), 0.05, 1.0, 0.45, ProceduralTex.wood(15), 0.9))
	box(Vector3(5.2, 2.3, 4.2), Vector3(0, 2.45, 0), _var(Color("c9a876")), 0.0, 0.0, 0.0,
		mat_photo("plaster", _var(Color(0.93, 0.85, 0.72)), 0.04, 1.0, 0.4, ProceduralTex.plaster(16), 0.55))
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
		mat_photo("wood", _var(Color(0.88, 0.78, 0.62)), 0.05, 1.0, 0.45, ProceduralTex.wood(17), 0.8))
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
		mat_photo("plaster", _var(Color(0.95, 0.94, 0.9)), 0.03, 1.0, 0.45, ProceduralTex.wall_tiles(18), 1.6))
	box(Vector3(5.8, 1.05, 0.26), Vector3(0, 3.85, 2.12), Color("b91c1c"))
	text3d("〒 郵便局", 110, Vector3(0, 3.85, 2.3), Color.WHITE)
	_window_unit(1.3, 1.1, Vector3(-1.7, 2.2, 2.12))
	_window_unit(1.3, 1.1, Vector3(1.7, 2.2, 2.12))
	box(Vector3(5.8, 0.18, 4.3), Vector3(0, 0.09, 0), Color("c4bcab"), 0.0, 0.0, 0.0,
		mat_photo("concrete", Color(0.9, 0.88, 0.83), 0.03, 1.0, 0.45, ProceduralTex.pavers(41), 0.5))


func _b_station() -> void:
	var wall_col := _var(Color("efe9da"))
	box(Vector3(12.5, 4.6, 4.5), Vector3(0, 2.3, 0), wall_col, 0.0, 0.0, 0.0,
		mat_photo("tilewall", _var(Color(0.95, 0.94, 0.91)), 0.03, 1.0, 0.5, ProceduralTex.wall_tiles(19), 1.5))
	box(Vector3(12.6, 0.9, 4.6), Vector3(0, 0.45, 0), Color("8a95a8"))
	box(Vector3(12.9, 0.6, 4.9), Vector3(0, 4.8, 0), Color("4a5670"))
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
	box(Vector3(12.0, 0.18, 3.0), Vector3(0, 3.3, -4.6), Color("4a5670"))
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
	var body := Color("d64541") if int(abs(position.x * 40.0)) % 2 == 0 else Color("3b6fb5")
	box(Vector3(0.95, 1.85, 0.8), Vector3(0, 0.925, 0), body)
	box(Vector3(0.95, 0.16, 0.82), Vector3(0, 1.8, 0), body.darkened(0.3))
	box(Vector3(0.72, 1.3, 0.07), Vector3(-0.06, 1.0, 0.41), Color("f4efe4"))
	var drinks := [Color("5b8def"), Color("e6b84c"), Color("7fb069"), Color("d97f7f")]
	for row in 4:
		for col in 2:
			box(Vector3(0.16, 0.26, 0.06), Vector3(-0.22 + col * 0.3, 0.48 + row * 0.32, 0.45), drinks[(row * 2 + col) % 4])
			box(Vector3(0.16, 0.03, 0.07), Vector3(-0.22 + col * 0.3, 0.36 + row * 0.32, 0.45), Color.WHITE)
	box(Vector3(0.22, 1.15, 0.06), Vector3(0.33, 1.05, 0.41), Color(0.12, 0.13, 0.18, 0.85))
	box(Vector3(0.16, 0.4, 0.03), Vector3(0.33, 1.5, 0.44), Color.WHITE)
	box(Vector3(0.95, 0.1, 0.85), Vector3(0, 0.05, 0), body.darkened(0.4))


func _b_pole() -> void:
	cyl(0.09, 0.12, 7.0, Vector3(0, 3.5, 0), Color("9a9da6"))
	box(Vector3(0.55, 0.95, 0.55), Vector3(0, 5.3, 0), Color("b0b3bc"))
	box(Vector3(1.6, 0.13, 0.13), Vector3(0, 6.35, 0), Color("7d8089"))
	box(Vector3(1.1, 0.1, 0.1), Vector3(0, 5.85, 0), Color("7d8089"))
	cyl(0.05, 0.05, 0.24, Vector3(-0.65, 6.55, 0), Color("6f727b"))
	cyl(0.05, 0.05, 0.24, Vector3(0.65, 6.55, 0), Color("6f727b"))
	cyl(0.05, 0.05, 0.2, Vector3(-0.42, 5.95, 0), Color("6f727b"))
	cyl(0.05, 0.05, 0.2, Vector3(0.42, 5.95, 0), Color("6f727b"))
	box(Vector3(0.16, 0.55, 0.16), Vector3(0, 0.27, 0), Color("7d8089"))
	box(Vector3(0.16, 0.1, 0.02), Vector3(0, 2.6, 0.1), Color.WHITE)


func _b_mailbox() -> void:
	box(Vector3(0.5, 0.28, 0.4), Vector3(0, 0.36, 0), Color("8f3333"))
	box(Vector3(0.62, 0.78, 0.55), Vector3(0, 0.9, 0), Color("c94f4f"))
	box(Vector3(0.4, 0.07, 0.06), Vector3(0, 1.16, 0.24), Color(0.15, 0.1, 0.1, 0.7))
	text3d("〒", 90, Vector3(0, 0.9, 0.29), Color.WHITE)
	box(Vector3(0.62, 0.14, 0.56), Vector3(0, 1.26, 0), Color("d96363"))
	box(Vector3(0.62, 0.06, 0.2), Vector3(0, 1.24, 0.2), Color("9a3a3a"))


func _b_trash() -> void:
	cyl(0.33, 0.28, 0.8, Vector3(0, 0.4, 0), Color("6b7f74"))
	cyl(0.37, 0.35, 0.13, Vector3(0, 0.87, 0), Color("49584f"))
	torus(0.12, 0.2, Vector3(0, 0.5, 0.29), Color(1, 1, 1, 0.85), true)
	cyl(0.12, 0.12, 0.02, Vector3(0, 0.01, 0), Color("55575e"))


func _b_bicycle() -> void:
	var frame := Color("c94f4f")
	torus(0.24, 0.32, Vector3(-0.55, 0.32, 0), Color("33363d"), true)
	torus(0.24, 0.32, Vector3(0.55, 0.32, 0), Color("33363d"), true)
	box(Vector3(1.0, 0.05, 0.05), Vector3(0, 0.55, 0), frame, 0.0, 0.25)
	box(Vector3(0.62, 0.05, 0.05), Vector3(0.18, 0.82, 0), frame, 0.0, -0.5)
	box(Vector3(0.05, 0.5, 0.05), Vector3(-0.15, 0.72, 0), frame)
	box(Vector3(0.3, 0.05, 0.08), Vector3(-0.2, 0.97, 0), Color("33363d"))
	box(Vector3(0.05, 0.28, 0.05), Vector3(0.5, 0.86, 0), frame)
	box(Vector3(0.42, 0.05, 0.06), Vector3(0.55, 0.98, 0), Color("33363d"))
	box(Vector3(0.32, 0.2, 0.24), Vector3(0.55, 0.85, 0), Color("8a8d96"))


func _b_car() -> void:
	var c := _car_color
	var paint := StandardMaterial3D.new()
	paint.albedo_color = _var(c, 0.06)
	paint.roughness = 0.28
	paint.metallic = 0.25
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	box(Vector3(4.2, 0.72, 1.75), Vector3(0, 0.72, 0), c, 0.0, 0.0, 0.0, paint)
	box(Vector3(2.2, 0.62, 1.6), Vector3(-0.25, 1.38, 0), c.darkened(0.06))
	box(Vector3(1.95, 0.4, 1.64), Vector3(-0.25, 1.42, 0), Color("a9cede"), 0.0, 0.0, 0.0, glass_mat(Color("a9cede")))
	for wx in [-1.35, 1.35]:
		for wz in [-0.82, 0.82]:
			cyl(0.33, 0.33, 0.22, Vector3(wx, 0.33, wz), Color("26282e"), true)
			cyl(0.14, 0.14, 0.24, Vector3(wx, 0.33, wz), Color("9aa0ab"), true)
	box(Vector3(0.1, 0.12, 0.3), Vector3(2.08, 0.85, 0.45), Color("f5e6a8"))
	box(Vector3(0.1, 0.12, 0.3), Vector3(2.08, 0.85, -0.45), Color("f5e6a8"))
	box(Vector3(0.08, 0.12, 0.3), Vector3(-2.08, 0.85, 0.45), Color("d64541"))
	box(Vector3(0.08, 0.12, 0.3), Vector3(-2.08, 0.85, -0.45), Color("d64541"))
	box(Vector3(0.1, 0.09, 0.16), Vector3(0.85, 1.15, 0.9), c.darkened(0.2))
	box(Vector3(0.1, 0.09, 0.16), Vector3(0.85, 1.15, -0.9), c.darkened(0.2))
	box(Vector3(0.06, 0.16, 0.4), Vector3(2.12, 0.6, 0), Color.WHITE)
	box(Vector3(0.06, 0.16, 0.4), Vector3(-2.11, 0.6, 0), Color.WHITE)


func _b_traffic() -> void:
	cyl(0.08, 0.11, 4.5, Vector3(0, 2.25, 0), Color("6a6d76"))
	box(Vector3(0.14, 0.14, 2.6), Vector3(0, 5.35, 1.3), Color("6a6d76"))
	box(Vector3(0.42, 1.15, 0.5), Vector3(0, 5.1, 2.45), Color("3a3f4a"))
	var emissive := StandardMaterial3D.new()
	emissive.albedo_color = Color("e74c3c")
	emissive.emission_enabled = true
	emissive.emission = Color("e74c3c")
	emissive.emission_energy_multiplier = 1.4
	var red := sph(0.14, Vector3(0, 5.5, 2.15), Color("e74c3c"))
	red.material_override = emissive
	sph(0.13, Vector3(0, 5.1, 2.15), Color(0.65, 0.55, 0.15))
	sph(0.13, Vector3(0, 4.72, 2.15), Color(0.2, 0.5, 0.28))
	box(Vector3(0.45, 1.2, 0.4), Vector3(0, 5.1, 0), Color("3a3f4a"))
	box(Vector3(0.3, 0.3, 0.3), Vector3(0, 0.15, 0), Color("6a6d76"))


func _b_signboard() -> void:
	box(Vector3(0.15, 1.5, 0.15), Vector3(0, 0.75, 0), Color("6b5d4a"))
	box(Vector3(0.95, 1.7, 0.12), Vector3(0, 2.2, 0), Color("f2e6cf"), 0.0, 0.0, 0.0,
		tex_mat(ProceduralTex.wood(23), Color("f2e6cf"), 1.2, 0.9, "sb"))
	box(Vector3(1.06, 0.1, 0.2), Vector3(0, 3.08, 0), Color("6b5d4a"))
	text3d("営\n業\n中", 78, Vector3(0, 2.2, 0.09), Color("2b2b33"))
	box(Vector3(0.95, 0.12, 0.14), Vector3(0, 1.42, 0), Color("b5484d"))


func _b_streetlight() -> void:
	cyl(0.07, 0.1, 4.2, Vector3(0, 2.1, 0), Color("6a6d76"))
	box(Vector3(1.15, 0.09, 0.09), Vector3(0.48, 4.15, 0), Color("6a6d76"))
	box(Vector3(0.6, 0.16, 0.24), Vector3(1.0, 4.05, 0), Color("e8e2c8"))
	var lamp := box(Vector3(0.5, 0.05, 0.18), Vector3(1.0, 3.97, 0), Color("f5eec8"))
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color("f5eec8")
	lm.emission_enabled = true
	lm.emission = Color("f5e6a8")
	lm.emission_energy_multiplier = 0.5
	lamp.material_override = lm
	box(Vector3(0.42, 0.32, 0.42), Vector3(0, 0.16, 0), Color("5f626b"))


func _b_bench() -> void:
	var wm := tex_mat(ProceduralTex.wood(25), Color("a8794e"), 1.1, 0.9, "bw")
	box(Vector3(2.2, 0.09, 0.55), Vector3(0, 0.45, 0), Color("a8794e"), 0.0, 0.0, 0.0, wm)
	box(Vector3(2.2, 0.45, 0.08), Vector3(0, 0.72, -0.24), Color("b5855a"), 0.0, 0.0, 0.0, wm)
	box(Vector3(0.09, 0.45, 0.5), Vector3(-0.95, 0.22, 0), Color("6b5d4a"))
	box(Vector3(0.09, 0.45, 0.5), Vector3(0.95, 0.22, 0), Color("6b5d4a"))


func _b_busstop() -> void:
	cyl(0.05, 0.07, 2.7, Vector3(0, 1.35, 0), Color("6a6d76"))
	box(Vector3(0.85, 0.85, 0.08), Vector3(0, 2.45, 0), Color("2b6cb0"))
	box(Vector3(0.45, 0.24, 0.03), Vector3(0, 2.56, 0.06), Color.WHITE)
	box(Vector3(0.1, 0.1, 0.03), Vector3(-0.12, 2.42, 0.06), Color("2b6cb0"))
	box(Vector3(0.1, 0.1, 0.03), Vector3(0.12, 2.42, 0.06), Color("2b6cb0"))
	text3d("バス", 52, Vector3(0, 2.16, 0.06), Color.WHITE)
	box(Vector3(0.5, 0.65, 0.04), Vector3(0, 1.45, 0.06), Color("f2efe6"))
	for i in 4:
		box(Vector3(0.36, 0.04, 0.05), Vector3(0, 1.62 - i * 0.13, 0.07), Color("b5aea0"))


func _b_tree() -> void:
	cyl(0.15, 0.22, 2.4, Vector3(0, 1.2, 0), Color("6b4f3a"))
	cyl(0.06, 0.08, 1.1, Vector3(-0.35, 2.3, 0.1), Color("6b4f3a"))
	var g1 := Color("5e9c54")
	var g2 := Color("6faf5f")
	var g3 := Color("4f8b4a")
	sph(1.1, Vector3(0, 3.2, 0), g1)
	sph(0.8, Vector3(-0.85, 2.6, 0.2), g2)
	sph(0.78, Vector3(0.8, 2.7, -0.15), g3)
	sph(0.6, Vector3(0.1, 3.95, 0.05), g2)
	sph(0.5, Vector3(-0.45, 3.6, -0.35), g1)


func _b_sakura() -> void:
	cyl(0.14, 0.2, 2.2, Vector3(0, 1.1, 0), Color("6b4a3a"))
	box(Vector3(0.1, 1.2, 0.1), Vector3(-0.45, 2.2, 0.1), Color("6b4a3a"), 0.0, 0.0, 0.55)
	box(Vector3(0.1, 1.3, 0.1), Vector3(0.5, 2.3, -0.1), Color("6b4a3a"), 0.0, 0.0, -0.6)
	var p1 := Color("f5a8c6")
	var p2 := Color("f7c6d9")
	var p3 := Color("efa3c4")
	sph(1.25, Vector3(0, 3.4, 0), p1)
	sph(0.9, Vector3(-0.9, 2.85, 0.3), p2)
	sph(0.92, Vector3(0.9, 2.95, -0.25), p3)
	sph(0.68, Vector3(0.1, 4.35, 0.05), p2)
	sph(0.5, Vector3(-0.55, 3.8, -0.4), p1)
	var disc := cyl(1.3, 1.3, 0.012, Vector3(0.3, 0.085, 0.3), Color("f5c3d6"))
	disc.scale = Vector3(1.0, 1.0, 0.8)


func _b_flower() -> void:
	box(Vector3(0.9, 0.3, 0.5), Vector3(0, 0.15, 0), Color("9a8f7a"), 0.0, 0.0, 0.0,
		tex_mat(ProceduralTex.wood(27), Color("9a8f7a"), 1.1, 0.9, "fp"))
	box(Vector3(0.95, 0.06, 0.55), Vector3(0, 0.31, 0), Color("6b5d4a"))
	var cols := [Color("e86a92"), Color("e6b84c"), Color("d97fb0")]
	for i in 5:
		var x := -0.3 + i * 0.15
		cyl(0.016, 0.016, 0.3, Vector3(x, 0.48, float((i * 7) % 3 - 1) * 0.08), Color("5e9c54"))
		sph(0.075, Vector3(x, 0.66, float((i * 7) % 3 - 1) * 0.08), cols[i % 3])


func _b_grass() -> void:
	for i in 5:
		var x := -0.35 + i * 0.18
		cyl(0.0, 0.055, 0.3, Vector3(x, 0.15, float((i * 7) % 3 - 1) * 0.1), Color("6faf5f"))
		cyl(0.0, 0.04, 0.2, Vector3(x + 0.07, 0.1, float((i * 5) % 3 - 1) * 0.08), Color("5e9c54"))
	cyl(0.28, 0.28, 0.015, Vector3(0, 0.09, 0), Color("7fb069"))


func _b_parksign() -> void:
	box(Vector3(0.12, 1.6, 0.12), Vector3(0, 0.8, 0), Color("6b5d4a"))
	box(Vector3(1.4, 0.8, 0.07), Vector3(0, 1.98, 0), Color("5e7d4a"))
	box(Vector3(1.28, 0.68, 0.08), Vector3(0, 1.98, 0.01), Color("f2e6cf"))
	text3d("公園", 120, Vector3(0, 1.98, 0.08), Color("2b2b33"))
	sph(0.15, Vector3(0, 2.56, 0), Color("7fb069"))
	box(Vector3(0.05, 0.16, 0.05), Vector3(0, 2.4, 0), Color("6b4f3a"))


func _b_dog() -> void:
	var fur := Color("b08968")
	var dark := Color("96745c")
	box(Vector3(0.72, 0.38, 0.3), Vector3(-0.05, 0.5, 0), fur)
	for lx in [-0.3, 0.12]:
		box(Vector3(0.09, 0.32, 0.09), Vector3(lx, 0.16, 0.1), dark)
		box(Vector3(0.09, 0.32, 0.09), Vector3(lx, 0.16, -0.1), dark)
	box(Vector3(0.3, 0.3, 0.28), Vector3(0.4, 0.72, 0), fur)
	box(Vector3(0.08, 0.16, 0.05), Vector3(0.32, 0.92, 0.09), dark, 0.0, 0.3)
	box(Vector3(0.08, 0.16, 0.05), Vector3(0.32, 0.92, -0.09), dark, 0.0, 0.3)
	box(Vector3(0.09, 0.09, 0.12), Vector3(0.58, 0.68, 0), Color("3a3230"))
	box(Vector3(0.05, 0.28, 0.05), Vector3(-0.45, 0.68, 0), dark, 0.0, 0.0, 0.6)
	box(Vector3(0.03, 0.06, 0.28), Vector3(0.22, 0.62, 0), Color("c94f4f"))


func _b_cat() -> void:
	var fur := Color("9aa0ab")
	var dark := Color("878d99")
	box(Vector3(0.34, 0.4, 0.24), Vector3(0, 0.3, 0), fur)
	box(Vector3(0.28, 0.26, 0.25), Vector3(0.02, 0.62, 0), fur)
	box(Vector3(0.07, 0.12, 0.04), Vector3(-0.07, 0.79, 0.06), dark, 0.0, 0.25)
	box(Vector3(0.07, 0.12, 0.04), Vector3(0.11, 0.79, 0.06), dark, 0.0, 0.25)
	box(Vector3(0.3, 0.05, 0.05), Vector3(-0.12, 0.35, 0.1), dark, 0.0, 0.6)
	box(Vector3(0.06, 0.18, 0.05), Vector3(-0.24, 0.62, 0.1), dark, 0.0, 0.0, 0.5)
	sph(0.025, Vector3(0.1, 0.64, 0.13), Color("3a4a3a"))
	sph(0.025, Vector3(-0.04, 0.64, 0.13), Color("3a4a3a"))


func _b_bird() -> void:
	sph(0.11, Vector3(0, 0.14, 0), Color("8a7f6a"))
	sph(0.07, Vector3(0.08, 0.26, 0), Color("8a7f6a"))
	box(Vector3(0.09, 0.03, 0.03), Vector3(0.17, 0.25, 0), Color("e6b84c"))
	box(Vector3(0.14, 0.03, 0.05), Vector3(-0.12, 0.17, 0), Color("6b6255"), 0.0, 0.0, 0.35)
	box(Vector3(0.02, 0.07, 0.02), Vector3(0, 0.04, 0.03), Color("6b6255"))
	box(Vector3(0.02, 0.07, 0.02), Vector3(0.04, 0.04, -0.03), Color("6b6255"))


func _b_bowl() -> void:
	cyl(0.34, 0.2, 0.24, Vector3(0, 0.14, 0), Color("c94f4f"))
	cyl(0.3, 0.3, 0.05, Vector3(0, 0.26, 0), Color("f2ede2"))
	torus(0.2, 0.28, Vector3(0, 0.3, 0), Color("f0d878"))
	cyl(0.012, 0.012, 0.42, Vector3(-0.1, 0.34, 0.12), Color("b5855a"))
	cyl(0.012, 0.012, 0.42, Vector3(-0.06, 0.34, 0.16), Color("b5855a"))
	sph(0.07, Vector3(0.1, 0.32, -0.05), Color("a06a4a"))
	sph(0.05, Vector3(-0.12, 0.33, 0.06), Color("8fb069"))


func _b_cans() -> void:
	var cols := [Color("d64541"), Color("5b8def"), Color("7fb069")]
	for i in 3:
		cyl(0.075, 0.075, 0.26, Vector3(-0.2 + i * 0.2, 0.13, float(i % 2) * 0.08), cols[i])
		cyl(0.075, 0.075, 0.03, Vector3(-0.2 + i * 0.2, 0.27, float(i % 2) * 0.08), Color("c8ccd4"))


func _b_onigiri() -> void:
	prism(Vector3(0.38, 0.3, 0.24), Vector3(0, 0.15, 0), mat(Color("ffffff")))
	box(Vector3(0.16, 0.14, 0.03), Vector3(0, 0.12, 0.11), Color("2b3a4a"))


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
