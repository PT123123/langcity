extends Node3D
class_name InteriorBuilder
## 室内搭建器：按 data/interiors.json 的模板生成地板 / 墙（带门洞）/ 天花 / 出口门 / 家具。
##
## 坐标：模板里全部是 px（1m = 40px，Interactable.S = 0.025）。
## 原点 (0,0) = 房间西北角；x → 东（世界 +X），y → 南（世界 +Z）。
## 出口门固定开在南墙正中，玩家从那里进出。
##
## 用法（street.gd）：
##     var b := InteriorBuilder.new()
##     add_child(b)
##     var objs := b.setup("house_basic", "int_house")
##     world_m = b.size_px * Interactable.S
## 返回的 Interactable（含出口门）由调用方 add_child 并塞进 street.objects，
## 这样高亮 / 拍照 / TTS / 任务全都零改动复用。
##
## 【注意】室内点光必须是 street 的直接子节点（street._budget_omni() 只遍历 get_children()），
## 所以灯光用 get_parent().add_child() 而不是 add_child()。

const TEMPLATES_PATH := "res://data/interiors.json"

const WALL_T := 0.18        # 墙厚（米）≥0.15，避免碰撞体太薄导致穿模
const KEEP_CLEAR := 8.0     # 家具与墙/彼此之间额外留白（px）
const MAX_TRY := 6          # 家具放置冲突时的重试次数

static var _templates: Dictionary = {}
static var _loaded := false
static var _mat_cache := {}

var size_px := Vector2(400, 320)
var ceil_m := 2.8
var tpl: Dictionary = {}
var rng := RandomNumberGenerator.new()

## 室内墙面材质 key。由模板的 "wall" 字段决定（默认 "wall"）。
## 【为什么不一律用 "wall"】民居内墙是白灰涂装，商店/车站内墙是小口瓷砖或
## 水磨石 —— 7 套模板全用同一张贴图，室内之间就没有区分度了。
var _wall_key := "wall"

## 上屋台参数（px），由 _build_steps 从模板 steps 里读一次，供家具抬高查询。
var _has_deck := false
var _deck_split_px := 0.0
var _deck_rise_px := 0.0

var _zone := {}                       # zone id -> Rect2（px）
var _placed: Array[Rect2] = []         # 已放置家具的占位矩形（px）
var _clear_rects: Array[Rect2] = []    # 门口/门洞前的禁放区（px）
var _out: Array[Interactable] = []


# ---------------- 对外 ----------------

## 建好室内，返回全部可交互物件（含出口门）。调用方负责 add_child。
func setup(template_id: String, seed_key: String) -> Array[Interactable]:
	_ensure_loaded()
	tpl = _templates.get(template_id, {})
	if tpl.is_empty():
		push_warning("未找到室内模板 %s，回退到第一个模板" % template_id)
		if not _templates.is_empty():
			tpl = _templates[_templates.keys()[0]]
	if tpl.is_empty():
		push_error("interiors.json 为空，室内无法生成")
		return []

	var sz: Array = tpl.get("size", [400, 320])
	size_px = Vector2(maxf(160.0, float(sz[0])), maxf(160.0, float(sz[1])))
	ceil_m = maxf(2.2, float(tpl.get("ceil", 112)) * Interactable.S)
	rng.seed = hash(seed_key)
	_wall_key = String(tpl.get("wall", "wall"))

	# 上屋台参数：读一次，地砖 / 台阶 / 家具三处共用同一个数，
	# 免得三处各算一遍哪天改公式漏改一处（家具就会陷进地板里）。
	_has_deck = false
	_deck_split_px = 0.0
	_deck_rise_px = 0.0
	for st: Dictionary in tpl.get("steps", []):
		if String(st.get("kind", "deck")) == "deck":
			_has_deck = true
			_deck_split_px = float(st.get("y", 0.0))
			_deck_rise_px = float(st.get("rise", 8.0))
			break

	_zone.clear()
	var rooms: Array = tpl.get("rooms", [])
	for r: Dictionary in rooms:
		var rect: Array = r.get("rect", [0, 0, 100, 100])
		_zone[String(r.get("id", ""))] = Rect2(
			float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))

	_placed.clear()
	_clear_rects.clear()
	# 出口门 + 出生点正前方留空，别让家具堵住门口。
	# 只留门宽 + 两侧各 26px、进深 70px（1.75m）—— 留太深会把整排靠南墙的家具全判成冲突。
	_clear_rects.append(Rect2(
		Vector2(size_px.x * 0.5 - 48.0, size_px.y - 70.0), Vector2(96.0, 70.0)))
	_out.clear()

	_build_shell()
	_build_props()
	return _out


## 模板的默认室内出生点（px）：南墙门内一步。供 street.gd 进门时作为一次性 spawn。
static func default_spawn_px(place_desc: Dictionary) -> Vector2:
	_ensure_loaded()
	var t: Dictionary = _templates.get(String(place_desc.get("template", "")), {})
	var sz: Array = t.get("size", [400, 320])
	return Vector2(float(sz[0]) * 0.5, maxf(80.0, float(sz[1]) - 70.0))


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(TEMPLATES_PATH, FileAccess.READ)
	if f == null:
		push_error("无法读取室内模板 " + TEMPLATES_PATH)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("室内模板格式错误 " + TEMPLATES_PATH)
		return
	_templates = (data as Dictionary).get("templates", {})


# ---------------- 外壳：地板 / 墙 / 天花 / 出口门 ----------------

func _build_shell() -> void:
	var w_m := size_px.x * Interactable.S
	var d_m := size_px.y * Interactable.S

	# 地板（视觉层；碰撞由 street._setup_floor() 的无限平面承担）
	var floor_mi := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(w_m, 0.12, d_m)
	floor_mi.mesh = fm
	floor_mi.material_override = _mat(String(tpl.get("floor", "wood")))
	floor_mi.position = Vector3(w_m * 0.5, -0.06, d_m * 0.5)
	add_child(floor_mi)

	# 局部地砖/防水地面覆盖（玄关、厨房、浴室）
	# 【为什么要跟着上屋台抬高】deck 把 y<split_y 的室内抬高了 rise，
	# 这一层的地砖如果不跟着抬，就会陷进地板里看不见（原来没高差所以没这问题）。
	var split_y := _deck_split_px * Interactable.S
	var deck_rise := _deck_rise_px * Interactable.S
	var tiles: Array = tpl.get("tiles", [])
	for t: Array in tiles:
		if t.size() < 5:
			continue
		var tw := float(t[2]) * Interactable.S
		var td := float(t[3]) * Interactable.S
		var tile := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(tw, 0.03, td)
		tile.mesh = tm
		tile.material_override = _mat(String(t[4]))
		var tz := (float(t[1]) + float(t[3]) * 0.5) * Interactable.S
		tile.position = Vector3(
			(float(t[0]) + float(t[2]) * 0.5) * Interactable.S,
			0.012 + (deck_rise if tz < split_y else 0.0),
			tz)
		add_child(tile)

	# 天花（纯视觉：猫跳不到 2.8m，不需要碰撞；但相机臂只认碰撞体，所以不加碰撞）
	var ceil_mi := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(w_m, 0.14, d_m)
	ceil_mi.mesh = cm
	ceil_mi.material_override = _mat("ceiling")
	ceil_mi.position = Vector3(w_m * 0.5, ceil_m + 0.07, d_m * 0.5)
	add_child(ceil_mi)

	# 外墙：南墙（下边）留出口门洞
	_wall(Vector2(0, 0), Vector2(size_px.x, 0))                      # 北
	_wall(Vector2(0, 0), Vector2(0, size_px.y))                      # 西
	_wall(Vector2(size_px.x, 0), Vector2(size_px.x, size_px.y))      # 东
	_wall(Vector2(0, size_px.y), Vector2(size_px.x, size_px.y), 44.0)  # 南（门洞）

	# 内部隔墙
	var walls: Array = tpl.get("walls", [])
	for w: Dictionary in walls:
		var a: Array = w.get("a", [0, 0])
		var b: Array = w.get("b", [0, 0])
		_wall(Vector2(float(a[0]), float(a[1])), Vector2(float(b[0]), float(b[1])),
			float(w.get("door", 0.0)))

	_build_exit_door()
	_build_steps()
	_build_lights()


## 室内高差：玄关 + 上屋台 + 内部楼梯。
##
## 【为什么要这个】日式住宅最标志性的空间特征就是「玄关（土間）比室内低一格」——
## 进门要抬腿上一级。原来室内是一整块平地，玩家看不出这是房子，
## 所有房间像贴在同一个平面上的贴图。加上这一级高差之后，一进门就是
## 「哦这是屋台」的空间感，而且是玩家每天都要走、每天都会看的面。
##
## 【方向只能是「室内抬高」，不能「玄关下沉」】室内地板碰撞是
## `street._setup_floor()` 建的 `WorldBoundaryShape3D` **无限平面**（y=0）。
## 往下挖任何东西都会被这张无限平面填平 —— 玄关挖到 y=-0.2，玩家脚底仍然是
## y=0 的无限平面，站上去毫无区别。所以反过来做：玄关留在 y=0，
## 室内主体（y < split_y 的部分）整体抬高 rise。
##
## 【rise 上限】`Player.STEP_CLIMB = 0.34` 是玩家能自动跨过的最大高度。
## 日式玄关真实高差 0.15~0.2m，取 rise=8px=0.2m 既有真实感又一定跨得上去。
## 取 0.42m（17px）会直接卡在门槛前上不去。
##
## 模板字段（全部 px，与坐标系一致）：
##   "steps": [
##     {"kind":"deck", "y":split_y, "h":.., "rise":8}          室内主体抬高
##     {"kind":"run", "x":..,"y":..,"w":..,"rise":7,"steps":3}  内部楼梯
##   ]
## 没写 steps 的模板保持原样（平地），零回归。
func _build_steps() -> void:
	for s: Dictionary in tpl.get("steps", []):
		match String(s.get("kind", "deck")):
			"deck":
				_raised_deck(s)
			"run":
				_stair_run(s)


## 上屋台：把房间 y ∈ [0, split_y) 的部分整体抬高 rise px。
## 抬高用「一层薄地板 + 侧面裙板」实现：薄地板顶面 = 抬高后的地面（玩家踩它），
## 裙板挡住侧面/正面，让台阶立面有厚度（不然远看是一张悬空的纸片）。
func _raised_deck(s: Dictionary) -> void:
	var split_y := float(s.get("y", 0.0))
	if split_y <= 0.5:
		return
	var rise_m := float(s.get("rise", 8.0)) * Interactable.S
	var w_m := size_px.x * Interactable.S
	var deck_d := split_y * Interactable.S
	# 薄地板（碰撞顶面在 rise_m）：玩家站上去的高度就是它
	_box(Vector3(w_m, 0.12, deck_d),
		Vector3(w_m * 0.5, rise_m - 0.06, deck_d * 0.5),
		_mat(String(s.get("mat", String(tpl.get("floor", "wood"))))), true)
	# 正面裙板（台阶立面）
	_box(Vector3(w_m, rise_m, 0.12),
		Vector3(w_m * 0.5, rise_m * 0.5, deck_d + 0.06),
		_mat(String(s.get("fascia", "wall"))), false)
	# 一级踏步：贴在裙板南侧，踏面与上屋台齐平，踏步本身是「半级」的视觉
	var tread_m := float(s.get("tread", 26.0)) * Interactable.S
	_box(Vector3(w_m, rise_m, tread_m),
		Vector3(w_m * 0.5, rise_m * 0.5, deck_d + 0.12 + tread_m * 0.5),
		_mat(String(s.get("step_mat", "threshold"))), false)


## 一段真楼梯：n 级踏步逐级升起，可指定朝向。
## dir = [dx, dy]（px 单位，指向爬升方向），默认朝北（-y，朝室内深处）。
## 每级踏步都是独立实体 box（自带碰撞），玩家可以一级一级踩上去。
## 每级 rise 默认 7px = 0.175m，远低于 STEP_CLIMB 0.34，单步必过。
func _stair_run(s: Dictionary) -> void:
	var n := maxi(1, int(s.get("steps", 3)))
	var x0 := float(s.get("x", 0.0))
	var y0 := float(s.get("y", 0.0))
	var w := float(s.get("w", 120.0))
	var rise_m := float(s.get("rise", 7.0)) * Interactable.S
	var run_m := float(s.get("run", 24.0)) * Interactable.S
	var dir: Array = s.get("dir", [0, -1])
	var dx := float(dir[0])
	var dy := float(dir[1])
	var l := sqrt(dx * dx + dy * dy)
	if l < 0.001:
		dx = 0.0
		dy = -1.0
	else:
		dx /= l
		dy /= l
	var mat := _mat(String(s.get("mat", "wood")))
	var w_m := w * Interactable.S
	# 每级踏步：从地面一路补齐到该级高度（既是台阶体，也让侧面看有厚度）
	for i in n:
		var h := rise_m * float(i + 1)
		var off := run_m * (float(i) + 0.5)
		var cx := (x0 + w * 0.5) * Interactable.S + dx * off
		var cz := y0 * Interactable.S + dy * off
		_box(Vector3(w_m, h, run_m * 1.04), Vector3(cx, h * 0.5, cz), mat, true)


## 建一个 box mesh（可选带碰撞）。室内墙面/家具已有各自的碰撞生成路径，
## 楼梯这类「贴着实体的台阶」必须自带碰撞，否则玩家会直接穿过台阶走到下面。
func _box(size: Vector3, pos: Vector3, material: Material, collide: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		body.position = pos
		add_child(body)
	return mi


## 一段墙（可留门洞）。door_px > 0 时在正中留洞，并把洞前设为家具禁放区。
func _wall(a: Vector2, b: Vector2, door_px := 0.0) -> void:
	var total := a.distance_to(b)
	if total < 8.0:
		return
	var segs: Array = []
	if door_px > 12.0 and total > door_px + 16.0:
		var t0 := (total * 0.5 - door_px * 0.5) / total
		var t1 := (total * 0.5 + door_px * 0.5) / total
		segs.append([a, a.lerp(b, t0)])
		segs.append([a.lerp(b, t1), b])
		var mid := (a + b) * 0.5
		# 门洞前禁放区：横向墙 → 门洞沿 x 展开、沿 y 留 48px；纵向墙反之
		var horiz := absf(b.x - a.x) >= absf(b.y - a.y)
		var ext := Vector2(door_px + 24.0, 48.0) if horiz else Vector2(48.0, door_px + 24.0)
		_clear_rects.append(Rect2(mid - ext * 0.5, ext))
	else:
		segs.append([a, b])

	for s: Array in segs:
		var p0: Vector2 = s[0]
		var p1: Vector2 = s[1]
		var len_px := p0.distance_to(p1)
		if len_px < 8.0:
			continue
		var mid := (p0 + p1) * 0.5
		# 世界方向 (cos ang, sin ang) 在 (x,z) 平面；绕 Y 旋转 θ 会把 +X 映射到 (cosθ, -sinθ)
		var theta := -atan2(p1.y - p0.y, p1.x - p0.x)
		var size3 := Vector3(len_px * Interactable.S, ceil_m, WALL_T)
		var pos := Vector3(mid.x * Interactable.S, ceil_m * 0.5, mid.y * Interactable.S)

		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size3
		mi.mesh = bm
		mi.material_override = _mat(_wall_key)
		mi.position = pos
		mi.rotation.y = theta
		add_child(mi)

		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size3
		cs.shape = bs
		cs.position = pos
		cs.rotation.y = theta
		body.add_child(cs)
		add_child(body)


## 出口门：南墙正中的可交互门，靠近后底部按钮显示【出门】。
## 不做触发体积 —— 按钮交互可避免进出互相触发的死循环。
func _build_exit_door() -> void:
	var ex := Interactable.new()
	ex.kind = "door"
	ex.word_id = "door"
	ex.interact_range = 4.5
	ex.extra = {"exit": true}
	ex.position = Vector3(size_px.x * 0.5 * Interactable.S, 0, size_px.y * Interactable.S)
	ex.rotation.y = PI
	ex._door_dy = 1.15
	# 门槛 + 门口踏垫，让门看起来是「通向外面的口」而不是贴图
	var sill := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.3, 0.06, 0.34)
	sill.mesh = sm
	sill.material_override = _mat("threshold")
	sill.position = Vector3(size_px.x * 0.5 * Interactable.S, 0.03,
		(size_px.y - 8.0) * Interactable.S)
	add_child(sill)
	_out.append(ex)


func _build_lights() -> void:
	var host := get_parent()
	if host == null:
		host = self
	var lights: Array = tpl.get("lights", [])
	for L: Dictionary in lights:
		var o := OmniLight3D.new()
		o.position = Vector3(float(L.get("x", 0.0)) * Interactable.S,
			maxf(0.4, ceil_m - 0.22), float(L.get("y", 0.0)) * Interactable.S)
		o.light_color = Color(String(L.get("color", "#ffd9a0")))
		o.light_energy = float(L.get("energy", 1.2))
		o.omni_range = float(L.get("range", 7.0))
		o.omni_attenuation = 1.35
		o.shadow_enabled = false
		host.add_child(o)

		# 灯罩：常亮自发光（室内没有 TimeOfDay 调制，直接恒亮）
		var shade := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.16
		sph.height = 0.28
		sph.radial_segments = 10
		sph.rings = 5
		shade.mesh = sph
		shade.material_override = Interactable.m_glow(o.light_color, 1.6)
		shade.position = o.position + Vector3(0, 0.02, 0)
		add_child(shade)


# ---------------- 家具 ----------------

func _build_props() -> void:
	var props: Array = tpl.get("props", [])
	for p: Dictionary in props:
		var it := _try_place(p)
		if it != null:
			_out.append(it)


## 放置单件家具：按 zone + jitter 取位，与已放置集合 + 门口禁放区做矩形相交测试。
## 6 次重试仍冲突则跳过（push_warning），绝不叠在一起。
func _try_place(p: Dictionary) -> Interactable:
	var kind := String(p.get("kind", ""))
	if kind.is_empty():
		return null
	var meta: Dictionary = Interactable.META.get(kind, {})
	var click: Vector3 = meta.get("click", Vector3(1, 1, 1))
	var half := Vector2(click.x, click.z) * (0.5 / Interactable.S)   # px 半尺寸
	# 纯装饰件（没有碰撞体：地毯/挂画/窗帘/空调/站名标）不占地面，
	# 既不挤掉实体家具，也不会被实体家具挤掉 —— 否则「桌下地毯/墙面挂画」永远放不下。
	var deco := meta.get("solid", null) == null

	var zone_id := String(p.get("zone", ""))
	var base := Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	var jit: Dictionary = tpl.get("jitter", {})
	var jpos := float(jit.get("pos", 10.0))
	var jrot := float(jit.get("rot", 6.0))
	# 膨胀量取模板 clear 的一半：模板坐标本身就是按「家具净尺寸 + 少量缝」排的，
	# 膨胀太大（原为 clear + 4px）会把并排的椅子和桌子全判成冲突。
	var clear := float(jit.get("clear", KEEP_CLEAR)) * 0.5

	for attempt in MAX_TRY:
		var pos := base
		if attempt > 0:
			pos = base + Vector2(rng.randf_range(-jpos, jpos), rng.randf_range(-jpos, jpos))
		if _zone.has(zone_id):
			var r: Rect2 = _zone[zone_id]
			pos.x = clampf(pos.x, r.position.x + half.x + 6.0, r.end.x - half.x - 6.0)
			pos.y = clampf(pos.y, r.position.y + half.y + 6.0, r.end.y - half.y - 6.0)
		pos.x = clampf(pos.x, half.x + KEEP_CLEAR, size_px.x - half.x - KEEP_CLEAR)
		pos.y = clampf(pos.y, half.y + KEEP_CLEAR, size_px.y - half.y - KEEP_CLEAR)

		var box := Rect2(pos - half - Vector2(clear, clear), half * 2.0 + Vector2(clear, clear) * 2.0)
		if _blocked(box, deco):
			continue

		var rot := float(p.get("rot", 0.0)) + rng.randf_range(-jrot, jrot)
		var word := String(p.get("word", kind))
		var obj := {
			"kind": kind,
			"x": pos.x,
			"y": pos.y,
			"rot": rot,
			"no_snap": true,
		}
		# 上屋台抬高的区域里，家具整体抬上去，否则会陷进地板里半截。
		# 判定用家具中心的 py 坐标（比用 zone 更稳，跨区家具也能取对高度）。
		var y_lift := _deck_lift_px(pos.y)
		if y_lift > 0.0:
			obj["y_lift"] = y_lift
		if not word.is_empty():
			obj["word"] = word
		# 装饰件不占地面，不进 _placed，后续实体家具可以正常压在它上面
		if not deco:
			_placed.append(box)
		return Interactable.make(obj)

	push_warning("室内家具 %s 放置冲突，已跳过" % kind)
	return null


## 上屋台高度查询（px → 米）。py 小于 split_y 的部分在台面上，
## 返回该处应抬起的高度（米）；台面外返回 0。
## 缓存 split_y / rise，避免每次放家具都遍历 steps。
func _deck_lift_px(py: float) -> float:
	if not _has_deck:
		return 0.0
	if py >= _deck_split_px:
		return 0.0
	return _deck_rise_px * Interactable.S


## box 是否不可放置。门口/门洞前的禁放区对「装饰件」同样生效（别把画挂在门洞里）；
## 但装饰件不参与彼此/与家具的地面占位比较。
func _blocked(box: Rect2, deco := false) -> bool:
	for r: Rect2 in _clear_rects:
		if r.intersects(box):
			return true
	if deco:
		return false
	for r: Rect2 in _placed:
		if r.intersects(box):
			return true
	return false


# ---------------- 材质 ----------------

## 室内表面材质（全部走 Interactable.mat_photo 的**真实 CC0 扫描贴图**）。
##
## 【为什么不留ProceduralTex 回退】原来这里给每种 key 都传了一张程序纹理
## （ProceduralTex.wood/pavers/plaster 当 fallback）。而 `wood_floor` / `tiles`
## 这两个 kind **在磁盘上根本没有对应文件**（tools/fetch_tex.py 的清单里漏了），
## 于是室内地板/地砖/墙面 100% 都在跑「自己画的灰度图案」——正是用户说的
## 「楼梯墙面啥的不要自己画，找现成的」。现在补下载了真实贴图，
## fallback 参数全部置空：kind 缺失时退回纯色，而不是退回一张假贴图。
##
## 各 key 的选图依据（日式住宅的实际做法，不是随机挑）：
##   wood       木地板 → wood_floor（拼花直铺）
##   tatami    和室     → tatami_mat（草编榻榻米，绿色调）
##   tile       玄关/厨房/店铺 → interior_tiles
##   tile_cool  浴室     → anti_skid_tiles（防滑砖，浴室标配）
##   terrazzo   车站/商店 → terrazzo_tiles（水磨石，公共空间标配）
##   wall       室内墙   → white_plaster_rough_01（白灰墙，室内比室外干净）
##   wall_tile  厨房/浴室墙 → concrete_tile_facade（小口瓷砖，防水墙裙）
##   ceiling    天花     → hinoki_planks（檜木板天花，和室感）
##   threshold  门槛     → step_granite（花岗岩条石）
func _mat(key: String) -> Material:
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: Material
	match key:
		"wood":
			m = Interactable.mat_photo("wood_floor", Color(0.99, 0.94, 0.87), 0.9, 0.62, 0.5)
		"tatami":
			m = Interactable.mat_photo("tatami", Color(0.93, 0.95, 0.86), 0.92, 0.72, 0.42)
		"tile":
			m = Interactable.mat_photo("tiles", Color(0.97, 0.97, 0.96), 0.88, 0.30, 0.85)
		"tile_cool":
			m = Interactable.mat_photo("step_antiskid", Color(0.90, 0.93, 0.95), 0.9, 0.42, 1.0)
		"terrazzo":
			m = Interactable.mat_photo("tiles_terrazzo", Color(0.95, 0.94, 0.92), 0.9, 0.35, 0.6)
		"wall":
			m = Interactable.mat_photo("wall_white_rough", Color(0.98, 0.96, 0.92), 0.93, 0.95, 0.4)
		"wall_tile":
			m = Interactable.mat_photo("plaster_brick_01", Color(0.97, 0.97, 0.96), 0.9, 0.28, 1.1)
		# 商业内墙（便利店/超市/车站）：小口浅色瓷砖，比住宅白墙亮、反光更强
		"wall_shop":
			m = Interactable.mat_photo("concrete_tile_facade", Color(0.97, 0.98, 0.98), 0.9, 0.26, 1.2)
		# 车站候车厅：浅色大理石/水磨石墙面
		"wall_station":
			m = Interactable.mat_photo("step_grey", Color(0.93, 0.94, 0.95), 0.9, 0.42, 0.7)
		# 咖啡厅/拉面店：暖木墙裙
		"wall_wood":
			m = Interactable.mat_photo("wood_hinoki", Color(0.96, 0.90, 0.80), 0.9, 0.72, 0.7)
		# 浴室：防滑小砖（湿区墙地同砖）
		"wall_bath":
			m = Interactable.mat_photo("step_antiskid", Color(0.94, 0.96, 0.96), 0.9, 0.42, 1.4)
		"ceiling":
			m = Interactable.mat_photo("wood_hinoki", Color(0.99, 0.96, 0.90), 0.94, 0.72, 0.4)
		"threshold":
			m = Interactable.mat_photo("step_granite", Color(0.86, 0.83, 0.78), 0.9, 0.75, 0.8)
		_:
			m = Interactable.mat_photo("wall_white_rough", Color(0.96, 0.94, 0.90), 0.9, 0.9, 0.45)
	_mat_cache[key] = m
	return m
