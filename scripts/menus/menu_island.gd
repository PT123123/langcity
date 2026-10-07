class_name MenuIsland
extends Node3D
## 主菜单背景的悬浮岛。
##
## 首选方案：用 planets_present_full_0..9 十块行星地形拼出整座岛（转换时保留了
## 原始顶点坐标，十块的世界坐标是对齐的，直接实例化即可拼合）。
## 【重要】十块不是拼图也不是十座岛 —— 是同一座岛的**穿插分层**：每块的 AABB
## 都接近全岛尺寸、两两大量重叠，但几何体互不重叠，合起来正好是一座完整岛。
## （2026-10-05 之前版本用 AABB 重叠率判定「拼不上」是误判，已废弃该判定。）
## 退化方案：拼不上（glb 还没转出来）时，只用 intro_planet 单体 + intro 树/水。
##
## 【材质】星球族模型统一走 IslandMaterials（原版着色逻辑移植：16×16 调色板
## 按 UV 采样 + 山体草地掩码 + 离岸距离波浪），不再平涂。
##
## 【为什么自转要绕岛心】分块是「世界坐标已对齐」的，合并包围盒的原点往往离
## 岛心很远。直接绕本节点原点转的话，整座岛会绕着远处某点公转，像卫星绕地球。
## 所以先把所有子节点整体平移到岛心，再转。


const ART_DIR := "res://assets/art/env/"
const CHUNK_COUNT := 10

## 运动参数（rad/s）。主菜单背景要「慢到注意不到」，一快就抢 UI 的注意力。
const SPIN_SPEED := 0.02       # 岛屿自转
const CLOUD_SPIN := 0.006      # 云自转（比岛慢，两者相对运动才看得出云在飘）
const CLOUD_BOB_SPEED := 0.22
const CLOUD_BOB_RATIO := 0.05  # 云上下浮动幅度 = 岛半径 × 此值
const CAM_AZIM_SPEED := 0.045  # 相机绕岛缓慢漂移
const CAM_ELEV_BASE := 0.30    # 略微俯视
const CAM_ELEV_AMP := 0.06
const CAM_ELEV_SPEED := 0.11
const CAM_MARGIN := 0.95       # 全岛可见 + 5% 边距（拼上树冠后岛屿更大，取景收紧些）

## 构造结果（供调用方决定要不要挂这一层）。
var built := false
var mode := "none"  ## "full" = 十块地形拼合；"fallback" = intro_planet 单体
var camera: Camera3D

var _spin: Node3D
var _clouds: Node3D
var _merged := AABB()      # 岛在 _spin 空间的合并包围盒（已把岛心挪到原点）
var _cloud_base_y := 0.0
var _azim := 0.0
var _t := 0.0


## 搭岛。返回 false 表示一个可用模型都没有 —— 调用方应把整层 3D 背景撤掉，
## 回到 main_menu 原来的矢量街景，而不是留一块空画面。
## 不放在 _ready 里自动跑：谁挂它、什么时候建，由调用方决定。
func build() -> bool:
	name = "MenuIsland"
	_spin = Node3D.new()
	_spin.name = "Spin"
	add_child(_spin)
	_clouds = Node3D.new()
	_clouds.name = "Clouds"
	add_child(_clouds)

	if not _build_chunks() and not _build_single_planet():
		return false

	_build_clouds()
	# 云再飘也得在画面里：没拼上任何东西就没有岛，也就不该有云。
	return _center_and_frame()


func _build_chunks() -> bool:
	var insts: Array[Node3D] = []
	for i in CHUNK_COUNT:
		var inst := _instantiate(ART_DIR + "planets_present_full_%d.glb" % i, IslandMaterials.terrain())
		if inst == null:
			for done: Node3D in insts:
				done.queue_free()
			push_warning("MenuIsland: 缺 planets_present_full_%d.glb，用 intro_planet 退化方案" % i)
			return false
		insts.append(inst)
		_spin.add_child(inst)
	# 高模树冠叠加（与地形同一套烘焙坐标）
	for i in 5:
		var leaves := _instantiate(ART_DIR + "planets_present_tree-leaves_%d.glb" % i, IslandMaterials.leaves())
		if leaves != null:
			_spin.add_child(leaves)
	# 海面
	var water := _instantiate(ART_DIR + "planets_present_water.glb", IslandMaterials.water())
	if water != null:
		_spin.add_child(water)
	mode = "full"
	return true


func _build_single_planet() -> bool:
	var planet := _instantiate(ART_DIR + "planets_present_intro_planet.glb", IslandMaterials.terrain())
	if planet == null:
		push_warning("MenuIsland: intro_planet.glb 也没有，主菜单退回矢量街景")
		return false
	_spin.add_child(planet)
	var trees := _instantiate(ART_DIR + "planets_present_intro_trees.glb", IslandMaterials.terrain())
	if trees != null:
		_spin.add_child(trees)
	var water := _instantiate(ART_DIR + "planets_present_intro_water.glb", IslandMaterials.water())
	if water != null:
		_spin.add_child(water)
	mode = "fallback"
	return true


## 把岛心挪到本节点原点，再按合并包围盒给相机取景。
func _center_and_frame() -> bool:
	var merged := _mesh_aabb(_spin)
	if merged.size.length() <= 0.0001:
		return false
	var c := merged.get_center()
	# 岛和云必须一起平移：两者本来就在同一套世界坐标里摆好了相对位置，
	# 只挪岛的话云会整体偏出岛心（实测偏移约 14 单位 = 云宽的 1/3）。
	# 平移的是这两组节点的**子节点**，_clouds 自己留在原点当上下浮动的支点。
	for child in _spin.get_children():
		(child as Node3D).position -= c
	for child in _clouds.get_children():
		(child as Node3D).position -= c
	_merged = AABB(merged.position - c, merged.size)

	camera = Camera3D.new()
	camera.name = "IslandCamera"
	camera.fov = 50.0
	camera.current = true
	add_child(camera)
	_update_camera()
	built = true
	return true


func _build_clouds() -> void:
	var cl := _instantiate(ART_DIR + "planets_present_intro_clouds.glb", IslandMaterials.cloud())
	if cl == null:
		return
	_clouds.add_child(cl)
	_cloud_base_y = _clouds.position.y


func _process(delta: float) -> void:
	if not built:
		return
	_t += delta
	_spin.rotation.y += SPIN_SPEED * delta
	# 云不跟着岛转，靠两者的相对运动才看得出在飘
	_clouds.rotation.y += CLOUD_SPIN * delta
	_clouds.position.y = _cloud_base_y + sin(_t * CLOUD_BOB_SPEED) * _merged.size.length() * 0.5 * CLOUD_BOB_RATIO
	_azim += CAM_AZIM_SPEED * delta
	_update_camera()


## 按合并包围盒自动取景：包围球内切于视锥，全岛可见并留 CAM_MARGIN 边距。
## 每帧重算，窗口尺寸变了（stretch=expand）也能跟上。
func _update_camera() -> void:
	if camera == null:
		return
	var vs := get_viewport().get_visible_rect().size
	if vs.x <= 1.0 or vs.y <= 1.0:
		return  # 还没布局好（headless / 刚 add_child），先不动相机
	var radius := _merged.size.length() * 0.5
	var fov_v := deg_to_rad(camera.fov)
	# 横向 FOV 由画布宽高比推出；包围球要同时塞进两个方向，取更窄的那个
	var fov_h := 2.0 * atan(tan(fov_v * 0.5) * (vs.x / vs.y))
	var half := minf(fov_v, fov_h) * 0.5
	if half <= 0.0001:
		return
	var dist := radius * CAM_MARGIN / sin(half)
	# 模型尺度未知（转换器给的原始世界坐标可能很大），近远裁剪面跟着距离走
	camera.far = maxf(1000.0, dist * 4.0)
	camera.near = maxf(0.05, dist * 0.01)

	var elev := CAM_ELEV_BASE + sin(_t * CAM_ELEV_SPEED) * CAM_ELEV_AMP
	var dir := Basis(Vector3.UP, _azim) * Vector3(0.0, sin(elev), cos(elev))
	camera.position = dir * dist
	camera.look_at(Vector3.ZERO, Vector3.UP)


# ---------------------------------------------------------------- 资源加载

func _instantiate(path: String, mat: Material) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	# 用 set_surface_override_material 而不是改 mesh 材质：GLB 实例化的
	# ArrayMesh 是共享资源，直接改会互相串色。
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					mi.set_surface_override_material(i, mat)
		for c in n.get_children():
			stack.append(c)
	return inst


## 递归合并子树里所有可见网格的包围盒（节点空间）。没有网格时返回零尺寸 AABB。
static func _mesh_aabb(n: Node) -> AABB:
	var acc := AABB()
	var has := false
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null:
				var box: AABB = mi.transform * mi.mesh.get_aabb()
				acc = box if not has else acc.merge(box)
				has = true
		for c in cur.get_children():
			stack.append(c)
	return acc