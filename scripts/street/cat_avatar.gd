class_name CatAvatar
extends Node3D
## 玩家角色外观：优先用外部 GLB 猫模型，没有就退回程序化拼装的橘白猫。
## 只管「长什么样、怎么动」—— 物理、相机、输入全在 Player 里。
##
## 【为什么留着手搭的兜底】程序化猫永远上不了台面（见下），但它保证项目永远能跑：
## 美术资产没到位、导入失败、用户临时删了模型，都还能玩。
## 正式模型放 res://assets/models/animals/cat.glb（.gltf 也认）即可自动接管。
##
## 程序化造型的坑（留档，别再犯）：
##   · 躯干/四肢用胶囊（有曲线），不用方盒
##   · 头、颈、躯干必须实体相连
##   · 橘猫特征：体侧短条斑（绝不绕整圈）、白围脖、白腹、白爪
##   · 环形纹路（糖葫芦/念珠感）是大忌：身体不分段、尾巴不加环
##   · **材质别上 sheen + rim**：黄昏场景下会整只猫「发光」，像琥珀冻的
##   · **后臀球别大于头**：臀球一大，猫就变猪

# ---- 外部模型 ----
## 按顺序探测，谁存在用谁。放进去就能换模型，不用改代码。
const MODEL_CANDIDATES := [
	"res://assets/models/animals/Fox.gltf",
	"res://assets/models/animals/cat.glb",
	"res://assets/models/animals/cat.gltf",
]
## GLB 归一化到的目标高度（米）。狐狸的肩高约 0.38m，归一化到 0.34 让它比真狐狸
## 再小一号 —— 在街道家具（0.45m 的桌、0.42m 的长椅）旁边才显得是「小动物」而不是中型犬。
const MODEL_TARGET_H := 0.34
## 模型朝向修正：资源库里的动物大多面朝 +Z，而本项目的角色约定是 -Z 向前。
const MODEL_YAW := PI

# ---- 尺寸（米）----
const SHOULDER := 0.225      # 肩/髋关节离地高度
const BODY_Y := 0.255# 躯干轴心高度
const BODY_R := 0.068# 躯干半径（要细，否则会吞掉腿）
const BODY_LEN := 0.30# 躯干胶囊长度
const HEAD_Y := 0.392# 头心要明显高出躯干顶，否则后视看不见脸
const HEAD_Z := -0.185
const HEAD_R := 0.080
const TAIL_Z := 0.155

# ---- 配色（玳瑁橘猫）----
const FUR := Color("d0863a")     # 主体橘
const FUR_DARK := Color("a8661f") # 虎斑 / 后腿 / 阴影侧
const FUR_LIGHT := Color("e8a852")# 额头、脸颊高光
const CREAM := Color("efe4cd")   # 腹、围脖、爪、脸斑
const STRIPE := Color("9a5519")  # 虎斑纹
const EYE := Color("8fc85c")     # 绿眼
const PUPIL := Color("1a1410")
const NOSE := Color("d4828a")
const INNER_EAR := Color("e79ba1")
const MOUTH := Color("7d423d")


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

# ---- 外部模型模式 ----
var _model: Node3D = null
var _anim: AnimationPlayer = null
var _base_y := 0.22           # _root 的基准高度（程序化 0.22 / GLB 0）
var _idle_only := false       # true = 只播待机，不走动（街头的猫 NPC 用）
var _cur_anim := ""
var _aabb := AABB()
var _aabb_ok := false


func _ready() -> void:
	_root = Node3D.new()
	_root.position = Vector3(0, _base_y, 0)
	add_child(_root)
	if not _build_from_model():
		_build()


## NPC 用：只摆待机姿势，不要腿抖尾摇。
func set_idle_only(v: bool) -> void:
	_idle_only = v


## 尝试挂外部 GLB 猫。返回 false 表示没有可用模型，调用方退回程序化造型。
func _build_from_model() -> bool:
	for p in MODEL_CANDIDATES:
		if not ResourceLoader.exists(p):
			continue
		var packed: PackedScene = load(p)
		if packed == null:
			continue
		var inst := packed.instantiate()
		if inst == null:
			continue
		_model = inst
		_model.rotation = Vector3(0, MODEL_YAW, 0)
		_root.add_child(_model)
		_normalize_model()
		_anim = _find_anim(_model)
		_base_y = 0.0
		_root.position = Vector3(0, 0, 0)
		return true
	return false


## 把模型归一化到「脚在 y=0、总高 MODEL_TARGET_H」。资源库里的动物尺寸千差万别
## （同一包里柴犬 2.6m、狐狸 1.2m），不归一化就会出现「巨猫」或「小老鼠」。
func _normalize_model() -> void:
	_aabb = AABB()
	_aabb_ok = false
	_collect_aabb(_model)
	if not _aabb_ok or _aabb.size.y <= 0.001:
		return
	var s := MODEL_TARGET_H / _aabb.size.y
	_model.scale = Vector3.ONE * s
	# 先缩放再平移：脚贴地，XZ 居中
	var mid := _aabb.get_center()
	_model.position += Vector3(-mid.x, -_aabb.position.y, -mid.z) * s


## 递归收集包围盒。蒙皮网格（SkinnedMeshInstance3D）必须额外乘骨架变换，
## 否则取到的是「绑定姿态下顶点还堆在原点」的错包围盒 —— 高度会算成 0。
## 这里不写死类型名（SkinnedMeshInstance3D 在部分上下文解析不到），用方法探测。
func _collect_aabb(n: Node) -> void:
	if n.has_method("get_skeleton") and n is VisualInstance3D:
		var skin := n as VisualInstance3D
		if skin is MeshInstance3D and (skin as MeshInstance3D).mesh != null:
			_merge_aabb(skin.transform * (skin as MeshInstance3D).mesh.get_aabb() * n.call("get_skeleton"))
	elif n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			_merge_aabb(mi.transform * mi.mesh.get_aabb())
	for c in n.get_children():
		_collect_aabb(c)


func _merge_aabb(b: AABB) -> void:
	if not _aabb_ok:
		_aabb = b
		_aabb_ok = true
	else:
		_aabb = _aabb.merge(b)


## 找 AnimationPlayer 并挑一套动画：待机 / 走 / 跑（名字模糊匹配，兼容不同资源包命名）
func _find_anim(root: Node) -> AnimationPlayer:
	for child in root.get_children():
		if child is AnimationPlayer:
			var ap := child as AnimationPlayer
			for a in ap.get_animation_list():
				var an := String(a).to_lower()
				if an.contains("walk"):
					_play_anim(ap, a)
					return ap
			for a in ap.get_animation_list():
				if String(a).to_lower().contains("idle"):
					_play_anim(ap, a)
					return ap
			return ap
		var sub := _find_anim(child)
		if sub != null:
			return sub
	return null


func _play_anim(ap: AnimationPlayer, anim: String) -> void:
	if _cur_anim == anim:
		return
	_cur_anim = anim
	if ap.has_animation(anim):
		ap.play(anim)


## 按速度切动画：停 → 待机，走 → walk，跑 → gallop/run。
## 找不到对应动画就退回待机，绝不「没有动画播」。
func _drive_anim(gait: float) -> void:
	if _anim == null or _idle_only:
		return
	var list := _anim.get_animation_list()
	var want := ""
	if gait < 0.12:
		for a in list:
			if String(a).to_lower().contains("idle"):
				want = a
				break
	elif gait < 0.62:
		for a in list:
			if String(a).to_lower().contains("walk"):
				want = a
				break
	else:
		for a in list:
			var an := String(a).to_lower()
			if an.contains("gallop") or an.contains("run"):
				want = a
				break
	if want == "":
		for a in list:
			if String(a).to_lower().contains("idle"):
				want = a
				break
	if want != "":
		_play_anim(_anim, want)
	# 播放速度跟着速度走，小跑不拖沓、慢走不抽风
	if _anim.has_animation(_cur_anim):
		var target := 0.65 + gait * 0.9
		_anim.speed_scale = lerpf(_anim.speed_scale, target, 0.12)



# ============================================================ 材质

## 毛质：低金属度 + 一点 sheen 绒感。
## 【rim 要克制】之前 sheen 0.6 / rim 0.55，在黄昏那种暗环境里整只猫会「自发光」，
## 远看像一块琥珀。rim 0.2 上下才够勾轮廓，又不至于发光。
func _mat(key: String, col: Color, rough := 0.88, sheen := 0.0, rim := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.metallic_specular = 0.12
	# sheen 模拟绒毛边缘的柔光，是「塑料 vs 毛」的关键差别
	if sheen > 0.0 and "sheen_enabled" in m:
		m.sheen_enabled = true
		m.sheen = sheen
		m.sheen_roughness = 0.6
		if "sheen_color" in m:
			m.sheen_color = col.lightened(0.35)
	# rim：把轮廓勾出来。0.2 是「刚好看清边」的上限，再高就发光了。
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.3
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


func _node3d(parent: Node3D, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


# ============================================================ 建模

func _build() -> void:
	var fur := _mat("fur", FUR, 0.9, 0.35, 0.2)
	var fur_d := _mat("fur_dark", FUR_DARK, 0.9, 0.3, 0.18)
	var fur_l := _mat("fur_light", FUR_LIGHT, 0.9, 0.35, 0.2)
	var cream := _mat("cream", CREAM, 0.92, 0.4, 0.16)
	var stripe := _mat("stripe", STRIPE, 0.92, 0.25, 0.15)
	var eye := _mat("eye", EYE, 0.15, 0.0)
	var pupil := _mat("pupil", PUPIL, 0.1, 0.0)
	var nose := _mat("nose", NOSE, 0.4, 0.0)
	var inner := _mat("inner", INNER_EAR, 0.9, 0.3)
	var mouth := _mat("mouth", MOUTH, 0.6, 0.0)
	var shine := _mat("shine", Color(1, 1, 1), 0.08, 0.0)
	# 胡须单独一根「灰白」材质：纯白 + 低粗糙 = 四根荧光棒，比胡须本身还抢戏
	var whisker := _mat("whisker", Color("d8d2c6"), 0.45, 0.0)
	eye.metallic_specular = 0.8
	shine.metallic_specular = 1.0

	# ================= 躯干 =================
	# 局部原点放在躯干轴心，z 向前为 -Z
	_torso = _node3d(_root, Vector3(0, BODY_Y - 0.22, 0.01))
	# 一整根连续胶囊打底：不做分段变径、不做收腰，杜绝「糖葫芦」
	_cap(_torso, BODY_R * 0.98, BODY_LEN * 1.05, Vector3(0, 0, 0.01), fur, "z", 20)
	# 胸腔前端 / 后臀：只微微隆起，球心沉在主胶囊里，接缝不可见。
	# 后臀球半径必须 < 头半径的视觉量级 —— 臀球一大，猫就变猪。
	_sph(_torso, BODY_R * 1.0, Vector3(0, 0.002, -0.105), fur, Vector3(0.92, 1.0, 0.72), 20)
	_sph(_torso, BODY_R * 0.9, Vector3(0, 0.002, 0.1), fur, Vector3(0.94, 0.98, 0.7), 20)
	# 背部中线：分两段短脊线，贴着背弧走，避免穿出体外变成凸刺
	_cap(_torso, 0.005, 0.085, Vector3(0, BODY_R * 0.85, -0.052), stripe, "z", 8)
	_cap(_torso, 0.005, 0.085, Vector3(0, BODY_R * 0.88, 0.058), stripe, "z", 8)

	# 体侧虎斑：短条斑贴在躯干侧上方，只「沉」在皮里露出一条。
	# 绝不绕整圈 —— 整圈环是「一串一串」的元凶
	for i in 4:
		var z := -0.085 + i * 0.058
		for sx: float in [-1.0, 1.0]:
			var a := atan2(0.026, 0.056)   # 斑块所在角度，长轴顺着体表切线
			var p := _sph(_torso, 0.014, Vector3(0.056 * sx, 0.026, z), stripe,
				Vector3(0.45, 1.25, 0.45), 10)
			p.rotation.z = a * sx

	# 白腹：一整条连贯的腹斑，不再分两坨
	_sph(_torso, 0.05, Vector3(0, -0.05, -0.01), cream, Vector3(0.72, 0.55, 1.75), 16)

	# ================= 颈（关键：把头和躯干连起来）=================
	# 斜向胶囊从肩窝连到头下，藏在围脖里
	_cap(_torso, 0.044, 0.13, Vector3(0, 0.058, -0.115), fur, "y", 14)
	# 围脖：贴着颈根的薄球，压在肩上不要凸成套娃。
	# 颜色用浅橘而不是纯白 —— 纯白围脖在侧视里就是一块白膏药贴脖子上
	_sph(_torso, 0.044, Vector3(0, 0.058, -0.116), fur_l, Vector3(0.95, 0.4, 0.75), 16)

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

	# ---- 胡须：吻部两侧扇形展开。灰白细杆，不是白荧光棒 ----
	for sx: float in [-1.0, 1.0]:
		for i in 3:
			var spread: float = (0.30 - i * 0.24) * sx
			var w := _cyl(_head, 0.0009, 0.0009, 0.075,
				Vector3(0.03 * sx, -0.022 - i * 0.009, -0.072), whisker,
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
	# 【别做成棒棒糖】半径太细 + 纯白尾尖 = 一根白棍插在屁股上。尾要够粗，尖用浅橘。
	var prev: Node3D = _node3d(_root, Vector3(0, BODY_Y - 0.22 + 0.035, TAIL_Z - 0.03))
	prev.rotation = Vector3(0.62, 0, 0)
	_tail.append(prev)
	for i in 3:
		var r := 0.026 - i * 0.004
		# 尾巴用胶囊，节与节之间加大重叠、半径平滑过渡，看不出分节
		_cap(prev, r, 0.095, Vector3(0, 0, -0.042), fur, "z", 12)
		var next := _node3d(prev, Vector3(0, 0, -0.07))
		next.rotation = Vector3(0.14, 0, 0)
		prev = next
		_tail.append(next)
	_sph(prev, 0.022, Vector3(0, 0, -0.014), fur_l, Vector3(1, 1, 1.15), 12)


## 一条腿：root 绕 X 摆动，lower 是折叠的膝/肘。全部用胶囊，避免方盒感。
func _build_leg(x: float, y: float, z: float, upper_mat: StandardMaterial3D,
		paw_mat: StandardMaterial3D, back: bool, phase: float) -> Dictionary:
	var girth := 1.0 if not back else 1.15   # 后腿略粗
	var root := _node3d(_root, Vector3(x, y, z))
	# 髋/肩 关节球：只比大腿大一圈，藏在轮廓里，不鼓包
	_sph(root, 0.0235 * girth, Vector3.ZERO, upper_mat, Vector3.ONE, 12)
	# 大腿：细长，上粗下细
	var th := 0.095 * girth
	_cap(root, 0.0215 * girth, th + 0.018, Vector3(0, -th * 0.44, 0.006), upper_mat, "y", 12)
	_sph(root, 0.0175 * girth, Vector3(0, -th * 0.88, 0.003), upper_mat, Vector3.ONE, 12)

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
	if _model != null:
		_animate_model(delta, gait, turn_rate)
		return
	_gait(delta, gait)
	_lean(delta, turn_rate)
	_tail_animate(delta, gait)
	_head_animate(delta, gait)
	_blink_animate(delta)


## GLB 模式：四肢/尾巴交给骨骼动画，这里只做「整体位移」——
## 上下起伏、走路前倾、转向侧倾。动画切换按速度分档。
func _animate_model(delta: float, gait: float, turn_rate: float) -> void:
	_drive_anim(gait)
	var bob := absf(sin(_phase)) * 0.012 * gait
	var breathe := sin(_idle_t * 1.9) * 0.004 * (1.0 - gait)
	_root.position.y = _base_y + bob + breathe
	# 转向侧倾保留 —— 猫转弯时先歪身，这是 Stray 手感的一部分
	var target := clampf(turn_rate * 0.06, -TURN_LEAN, TURN_LEAN)
	_root.rotation.z = lerpf(_root.rotation.z, target, 1.0 - exp(-9.0 * delta))
	# 走时整体微微前倾（绕 X，负值 = 低头向前）
	_root.rotation.x = lerpf(_root.rotation.x, -0.05 * gait, 1.0 - exp(-6.0 * delta))
	_phase += delta * (2.6 + 5.2 * gait) * clampf(gait + 0.12, 0.0, 1.2)


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
	_root.position.y = _base_y + bob + breathe
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
