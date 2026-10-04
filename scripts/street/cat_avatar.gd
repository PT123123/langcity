class_name CatAvatar
extends Node3D
## 玩家角色外观：程序化拼装的橘白猫 + 步态动画。
## 只管「长什么样、怎么动」—— 物理、相机、输入全在 Player 里。
##
## 造型原则：任何角度都要有连续的剪影，不能出现「浮空零件」。
##   · 躯干/四肢用胶囊（有曲线），不用方盒
##   · 头、颈、躯干必须实体相连
##   · 橘猫特征：背部虎斑环绕、白围脖、白腹、白爪、虎斑虎斑纹

# ---- 尺寸（米）----
const SHOULDER := 0.225      # 肩/髋关节离地高度
const BODY_Y := 0.255# 躯干轴心高度
const BODY_R := 0.068# 躯干半径（要细，否则会吞掉腿）
const BODY_LEN := 0.30# 躯干胶囊长度
const HEAD_Y := 0.385# 头心要明显高出躯干顶，否则后视看不见脸
const HEAD_Z := -0.185
const HEAD_R := 0.076
const TAIL_Z := 0.155

# ---- 配色（玳瑁橘猫）----
const FUR := Color("dd8f3a")     # 主体橘
const FUR_DARK := Color("b96f28") # 虎斑 / 后腿 / 阴影侧
const FUR_LIGHT := Color("f0ad55")# 额头、脸颊高光
const CREAM := Color("f6efe0")   # 腹、围脖、爪、脸斑
const STRIPE := Color("a55f1f")  # 虎斑纹
const EYE := Color("8fc85c")     # 绿眼
const PUPIL := Color("1a1410")
const NOSE := Color("dd8a8f")
const INNER_EAR := Color("eba3a8")
const MOUTH := Color("8a4a44")

const TURN_LEAN := 0.30# 转向时身体最大侧倾（弧度）
const TROT_BASE := 0.0
const TROT_OPP := PI         # 对角同相的小跑（trot）步态

var _root: Node3D            # 整体：呼吸起伏 + 转向侧倾
var _torso: Node3D
var _head: Node3D
var _ear_l: Node3D
var _ear_r: Node3D
var _tail: Array[Node3D] = []
var _legs: Array[Dictionary] = []   # {root, lower, phase}
var _eyes: Array[MeshInstance3D] = []

var _phase := 0.0             # 步态相位
var _idle_t := 0.0
var _blink_t := 2.0
var _blink := 0.0
var _tail_swing := 0.0
var _mats := {}


func _ready() -> void:
	_root = Node3D.new()
	_root.position = Vector3(0, 0.22, 0)
	add_child(_root)
	_build()


# ============================================================ 材质

## 毛质：低金属度 + sheen 边缘绒感 + rim 轮廓光（Godot 4.2+ 有 sheen，退化时也能看）
func _mat(key: String, col: Color, rough := 0.86, sheen := 0.0, rim := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.metallic_specular = 0.16
	# sheen 模拟绒毛边缘的柔光，是「塑料 vs 毛」的关键差别
	if sheen > 0.0 and "sheen_enabled" in m:
		m.sheen_enabled = true
		m.sheen = sheen
		m.sheen_roughness = 0.5
		if "sheen_color" in m:
			m.sheen_color = col.lightened(0.55)
	# rim：把轮廓勾出来。没有 rim，角色在明亮场景里就是一团糊。
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.6
	_mats[key] = m
	return m


# ============================================================ 几何工具

func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, material: StandardMaterial3D,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## 球：r 半径，scl 压扁，seg 分段数（猫身要圆滑，用高一点）
func _sph(parent: Node3D, r: float, pos: Vector3, material: StandardMaterial3D,
		scl := Vector3.ONE, seg := 18) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = maxi(6, seg / 2)
	var mi := _mesh(parent, m, pos, material)
	mi.scale = scl
	return mi


## 胶囊：r 半径，h 总长（含半球），axis "x"/"y"/"z" 决定长轴
func _cap(parent: Node3D, r: float, h: float, pos: Vector3,
		material: StandardMaterial3D, axis := "y", seg := 16) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0 + 0.001)
	m.radial_segments = seg
	m.rings = 4
	var rot := Vector3.ZERO
	if axis == "x":
		rot = Vector3(0, 0, PI * 0.5)
	elif axis == "z":
		rot = Vector3(PI * 0.5, 0, 0)
	return _mesh(parent, m, pos, material, rot)


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3,
		material: StandardMaterial3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = 12
	return _mesh(parent, m, pos, material, rot)


func _prism(parent: Node3D, size: Vector3, pos: Vector3, material: StandardMaterial3D,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = size
	return _mesh(parent, m, pos, material, rot)


## 绕躯干一圈的细环（虎斑纹）
func _ring(parent: Node3D, major: float, minor: float, z: float,
		material: StandardMaterial3D) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = major - minor
	m.outer_radius = major + minor
	m.rings = 24
	m.ring_segments = 8
	# TorusMesh 默认环面在 XZ（绕 Y），要绕身体长轴 Z 就转 90°
	return _mesh(parent, m, Vector3(0, 0, z), material, Vector3(PI * 0.5, 0, 0))


func _node3d(parent: Node3D, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


# ============================================================ 建模

func _build() -> void:
	var fur := _mat("fur", FUR, 0.88, 0.6, 0.55)
	var fur_d := _mat("fur_dark", FUR_DARK, 0.88, 0.5, 0.5)
	var fur_l := _mat("fur_light", FUR_LIGHT, 0.88, 0.6, 0.5)
	var cream := _mat("cream", CREAM, 0.9, 0.7, 0.45)
	var stripe := _mat("stripe", STRIPE, 0.9, 0.4, 0.4)
	var eye := _mat("eye", EYE, 0.15, 0.0)
	var pupil := _mat("pupil", PUPIL, 0.1, 0.0)
	var nose := _mat("nose", NOSE, 0.4, 0.0)
	var inner := _mat("inner", INNER_EAR, 0.9, 0.5)
	var mouth := _mat("mouth", MOUTH, 0.6, 0.0)
	var shine := _mat("shine", Color(1, 1, 1), 0.08, 0.0)
	eye.metallic_specular = 0.8
	shine.metallic_specular = 1.0

	# ================= 躯干 =================
	# 局部原点放在躯干轴心，z 向前为 -Z
	_torso = _node3d(_root, Vector3(0, BODY_Y - 0.22, 0.01))
	# 两段变径胶囊做腰身：胸腔粗、腰细、臀再粗。猫不是香肠。
	_cap(_torso, BODY_R * 0.95, BODY_LEN * 0.55, Vector3(0, -0.004, -0.075), fur, "z", 20)
	_cap(_torso, BODY_R * 1.04, BODY_LEN * 0.5, Vector3(0, 0.004, 0.075), fur, "z", 20)
	# 腰：中间收一下
	_sph(_torso, BODY_R * 0.9, Vector3(0, -0.002, 0.0), fur, Vector3(1.0, 0.96, 1.0), 20)
	# 后臀更壮
	_sph(_torso, BODY_R * 1.02, Vector3(0, 0.006, 0.112), fur, Vector3(1.0, 1.02, 0.8), 20)

	# 虎斑：环绕躯干的细环，颜色只比底色深一档（不能太黑，像刺青）
	for i in 5:
		var t := float(i) / 4.0
		var z := -0.095 + t * 0.185
		# 环的半径跟着腰身轮廓走，不能是等径
		var major := BODY_R * (0.99 - absf(t - 0.5) * 0.28)
		_ring(_torso, major, 0.0045, z, stripe)
	# 背部中线：分两段短脊线，贴着背弧走，避免穿出体外变成凸刺
	_cap(_torso, 0.005, 0.085, Vector3(0, BODY_R * 0.85, -0.052), stripe, "z", 8)
	_cap(_torso, 0.005, 0.085, Vector3(0, BODY_R * 0.88, 0.058), stripe, "z", 8)

	# 白腹：只在躯干下缘，不要铺满整个肚子
	_sph(_torso, 0.048, Vector3(0, -0.048, -0.04), cream, Vector3(0.8, 0.58, 1.6), 16)
	_sph(_torso, 0.043, Vector3(0, -0.046, 0.05), cream, Vector3(0.78, 0.56, 0.95), 14)

	# ================= 颈（关键：把头和躯干连起来）=================
	# 斜向胶囊从肩窝连到头下，藏在围脖里
	_cap(_torso, 0.044, 0.13, Vector3(0, 0.058, -0.115), fur, "y", 14)
	# 围脖：贴着颈根的薄球，压在肩上不要凸成套娃
	_sph(_torso, 0.046, Vector3(0, 0.062, -0.118), cream, Vector3(1.0, 0.46, 0.8), 16)

	# ================= 头 =================
	_head = _node3d(_root, Vector3(0, HEAD_Y - 0.22, HEAD_Z))
	# 颅骨
	_sph(_head, HEAD_R, Vector3.ZERO, fur, Vector3(1.0, 0.96, 0.98), 20)
	# 额头：橘猫额头有白色 M 形，这里给一层浅橘高光面
	_sph(_head, HEAD_R * 0.82, Vector3(0, 0.038, -0.026), fur_l, Vector3(1.0, 0.55, 0.8), 16)
	# 脸颊两侧（让头有宽度，不是纯球）
	for sx: float in [-1.0, 1.0]:
		_sph(_head, 0.046, Vector3(0.05 * sx, -0.012, -0.018), fur, Vector3(0.9, 0.95, 1.0), 14)
	# 吻部：下颌 + 口鼻垫
	_sph(_head, 0.048, Vector3(0, -0.032, -0.05), cream, Vector3(0.95, 0.7, 0.85), 16)
	_sph(_head, 0.026, Vector3(0, -0.026, -0.082), cream, Vector3(1.0, 0.72, 0.75), 12)
	# 鼻头（三角感：压扁 + 微倾）
	var n := _sph(_head, 0.0125, Vector3(0, -0.014, -0.104), nose, Vector3(1.25, 0.85, 0.9), 12)
	n.rotation = Vector3(-0.3, 0, 0)
	# 人中：鼻下到嘴的两道竖线
	for sx: float in [-1.0, 1.0]:
		_cyl(_head, 0.0012, 0.0012, 0.016, Vector3(0.004 * sx, -0.026, -0.099), mouth,
			Vector3(0.25, 0, 0))
	# 嘴：两段弧线
	for sx: float in [-1.0, 1.0]:
		_sph(_head, 0.008, Vector3(0.013 * sx, -0.036, -0.093), mouth, Vector3(1.0, 0.5, 0.5), 8)

	# ---- 眼：大而亮，Stray 的猫眼是招牌 ----
	for sx: float in [-1.0, 1.0]:
		# 眼眶暗色底，让眼睛「陷」进去
		_sph(_head, 0.0215, Vector3(0.036 * sx, 0.016, -0.046), stripe, Vector3(1.0, 1.05, 0.5), 12)
		var e := _sph(_head, 0.0195, Vector3(0.036 * sx, 0.016, -0.052), eye, Vector3(1.0, 1.1, 0.62), 16)
		_eyes.append(e)
		# 竖瞳
		_sph(_head, 0.006, Vector3(0.037 * sx, 0.016, -0.066), pupil, Vector3(0.42, 1.5, 0.35), 10)
		# 眼球高光（两处，大的在下 = 天空反射，小的在上 = 强光）
		_sph(_head, 0.0055, Vector3(0.043 * sx, 0.024, -0.062), shine, Vector3(1, 1, 0.6), 8)
		_sph(_head, 0.0026, Vector3(0.031 * sx, 0.008, -0.065), shine, Vector3(1, 1, 0.6), 6)
		# 眉上虎斑
		_prism(_head, Vector3(0.026, 0.008, 0.012), Vector3(0.036 * sx, 0.043, -0.038), stripe,
			Vector3(0.6, 0.25 * sx, 0))

	# ---- 耳：大而挺立的三角，橘猫耳朵要能看见内侧 ----
	for sx: float in [-1.0, 1.0]:
		var e2 := _node3d(_head, Vector3(0.048 * sx, 0.058, 0.006))
		e2.rotation = Vector3(-0.14, 0.10 * sx, -0.24 * sx)
		_prism(e2, Vector3(0.078, 0.072, 0.03), Vector3(0, 0.034, 0), fur)
		_prism(e2, Vector3(0.05, 0.05, 0.034), Vector3(0, 0.028, -0.006), inner)
		# 耳背虎斑
		_prism(e2, Vector3(0.022, 0.02, 0.034), Vector3(0, 0.052, 0.001), stripe)
		if sx < 0.0:
			_ear_l = e2
		else:
			_ear_r = e2
		# 耳内绒毛
		_sph(e2, 0.012, Vector3(0, 0.004, -0.004), cream, Vector3(1.0, 1.4, 0.4), 8)

	# ---- 胡须：吻部两侧扇形展开 ----
	for sx: float in [-1.0, 1.0]:
		for i in 4:
			var spread: float = (0.34 - i * 0.22) * sx
			var w := _cyl(_head, 0.0013, 0.0013, 0.085,
				Vector3(0.03 * sx, -0.022 - i * 0.009, -0.072), shine,
				Vector3(0, 0, PI * 0.5 + spread))
			w.position += Vector3(0.043 * sx, 0, 0)
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# ================= 腿 =================
	# 0左前 1右前 2左后 3右后（对角同相）
	_legs.append(_build_leg(-0.048, SHOULDER - 0.22, -0.098, fur, cream, false, TROT_BASE))
	_legs.append(_build_leg(0.048, SHOULDER - 0.22, -0.098, fur, cream, false, TROT_OPP))
	_legs.append(_build_leg(-0.05, SHOULDER - 0.22, 0.105, fur_d, cream, true, TROT_OPP))
	_legs.append(_build_leg(0.05, SHOULDER - 0.22, 0.105, fur_d, cream, true, TROT_BASE))

	# ================= 尾 =================
	# 尾根从臀部斜上翘起，三节逐渐变细
	var prev: Node3D = _node3d(_root, Vector3(0, BODY_Y - 0.22 + 0.035, TAIL_Z - 0.03))
	prev.rotation = Vector3(0.62, 0, 0)
	_tail.append(prev)
	for i in 3:
		var r := 0.022 - i * 0.0045
		# 尾巴用胶囊，圆润不折角
		_cap(prev, r, 0.08, Vector3(0, 0, -0.035), fur if i < 2 else cream, "z", 10)
		# 尾环
		_ring(prev, r * 0.95, 0.005, -0.035, stripe if i < 2 else cream)
		var next := _node3d(prev, Vector3(0, 0, -0.07))
		next.rotation = Vector3(0.18, 0, 0)
		prev = next
		_tail.append(next)
	_sph(prev, 0.019, Vector3(0, 0, -0.016), cream, Vector3(1, 1, 1.1), 12)


## 一条腿：root 绕 X 摆动，lower 是折叠的膝/肘。全部用胶囊，避免方盒感。
func _build_leg(x: float, y: float, z: float, upper_mat: StandardMaterial3D,
		paw_mat: StandardMaterial3D, back: bool, phase: float) -> Dictionary:
	var girth := 1.0 if not back else 1.15   # 后腿略粗
	var root := _node3d(_root, Vector3(x, y, z))
	# 髋/肩 关节球
	_sph(root, 0.026 * girth, Vector3.ZERO, upper_mat, Vector3.ONE, 12)
	# 大腿：细长，上粗下细
	var th := 0.095 * girth
	_cap(root, 0.0215 * girth, th + 0.018, Vector3(0, -th * 0.44, 0.006), upper_mat, "y", 12)
	_sph(root, 0.0195 * girth, Vector3(0, -th * 0.88, 0.003), upper_mat, Vector3.ONE, 12)

	var lower := _node3d(root, Vector3(0, -th * 0.93, 0))
	# 小腿：更细，猫的小腿是纤细的
	var sh := 0.09
	_cap(lower, 0.0155 * girth, sh + 0.016, Vector3(0, -sh * 0.48, 0), upper_mat, "y", 12)
	# 脚掌：肉垫 + 三趾
	_sph(lower, 0.021, Vector3(0, -sh - 0.004, -0.014), paw_mat, Vector3(1.0, 0.62, 1.3), 12)
	for tx: float in [-1.0, 0.0, 1.0]:
		_sph(lower, 0.0085, Vector3(0.011 * tx, -sh - 0.006, -0.034), paw_mat,
			Vector3(1.0, 0.8, 1.1), 8)
	# 后腿白袜往上延伸
	if back:
		_cap(lower, 0.017, 0.038, Vector3(0, -sh * 0.4, 0), paw_mat, "y", 10)
	return {"root": root, "lower": lower, "phase": phase}


# ============================================================ 动画

## turn_rate：身体转向速率（rad/s），用来做转弯侧倾
func animate(delta: float, gait: float, turn_rate: float) -> void:
	_idle_t += delta
	_gait(delta, gait)
	_lean(delta, turn_rate)
	_tail_animate(delta, gait)
	_head_animate(delta, gait)
	_blink_animate(delta)


## 步态：四腿小跑 + 身体上下起伏 + 脊柱起伏
func _gait(delta: float, gait: float) -> void:
	_phase += delta * (2.6 + 5.2 * gait) * clampf(gait + 0.12, 0.0, 1.2)
	for leg: Dictionary in _legs:
		var root: Node3D = leg["root"]
		var lower: Node3D = leg["lower"]
		var s := sin(_phase + leg["phase"])
		var amp := 0.58 * gait
		root.rotation.x = s * amp
		# 下腿只在抬起相折叠
		lower.rotation.x = -maxf(0.0, sin(_phase + leg["phase"] - 0.75)) * 0.78 * gait
	# 上下起伏：一步两峰
	var bob := absf(sin(_phase)) * 0.014 * gait
	# 待机呼吸
	var breathe := sin(_idle_t * 1.9) * 0.004 * (1.0 - gait)
	_root.position.y = 0.22 + bob + breathe
	# 左右摇摆
	_root.rotation.z = -sin(_phase) * 0.042 * gait
	# 走时微微前倾；脊柱左右扭（猫走路身体是波浪形的）
	_torso.rotation.x = -0.05 * gait + sin(_idle_t * 1.6) * 0.01 * (1.0 - gait)
	_torso.rotation.y = sin(_phase) * 0.06 * gait
	_torso.position.y = (BODY_Y - 0.22) - absf(sin(_phase)) * 0.008 * gait


## 转向侧倾：像真猫一样先歪身再转
func _lean(delta: float, turn_rate: float) -> void:
	var target := clampf(turn_rate * 0.075, -TURN_LEAN, TURN_LEAN)
	_root.rotation.z = lerpf(_root.rotation.z, target, 1.0 - exp(-9.0 * delta))


## 尾巴：静止慢摆，移动时上翘 + 摆幅加大
func _tail_animate(delta: float, gait: float) -> void:
	_tail_swing += delta * (1.6 + 5.0 * gait)
	var amp := 0.05 + 0.17 * gait
	for i in _tail.size():
		var n: Node3D = _tail[i]
		var w := _tail_swing - i * 0.42
		n.rotation.y = sin(w) * amp * (0.45 + 0.55 * i)
		# 尾根翘得更高；末端节带延迟的上下波动
		if i == 0:
			n.rotation.x = 0.62 - 0.34 * gait + sin(_tail_swing * 0.7) * 0.03
		else:
			n.rotation.x = 0.18 - 0.14 * gait + sin(_tail_swing - i * 0.42) * 0.055 * gait


## 头：走路时朝前下方，待机偶尔歪头，耳朵偶尔抖
func _head_animate(delta: float, gait: float) -> void:
	var target_pitch := -0.04 - 0.11 * gait
	_head.rotation.x = lerpf(_head.rotation.x, target_pitch, 1.0 - exp(-6.0 * delta))
	# 头随身体朝向的惯性偏转（转向时头先到位）
	var tilt := sin(_idle_t * 0.7) * 0.05 * (1.0 - gait) + sin(_phase) * 0.035 * gait
	_head.rotation.z = lerpf(_head.rotation.z, tilt, 1.0 - exp(-5.0 * delta))
	# 耳朵抖动
	var flick := 0.0
	if fmod(_idle_t, 3.7) < 0.12:
		flick = sin(fmod(_idle_t, 3.7) / 0.12 * PI) * 0.28
	_ear_l.rotation.z = -0.24 - flick
	_ear_r.rotation.z = 0.24 + flick * 0.8


## 眨眼
func _blink_animate(delta: float) -> void:
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink_t = randf_range(2.2, 5.5)
		_blink = 1.0
	if _blink > 0.0:
		_blink = maxf(0.0, _blink - delta * 9.0)
	var s := 1.0 - 0.9 * _blink
	for e in _eyes:
		e.scale.y = 1.1 * s
