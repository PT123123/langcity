class_name PlanetBuilder
extends Node3D
## 小星球世界构建器（替代旧 GroundBuilder 的角色）：
##   1. 用 planets_present_full_0..9 十块地形拼出原版星球岛（它们是同一座岛的
##      穿插分层，不是十座岛也不是拼图 —— 直接实例化即对齐，见 menu_island 的教训）；
##   2. 叠 tree-leaves_0..4 高模树冠 + 海面 + 云层 + 岸沫/瀑布 VFX；
##   3. 材质走 IslandMaterials（原版着色逻辑移植：调色板 UV + 离岸距离波浪）；
##   4. 岛心挪到本节点原点（PlanetMath/玩家重力都假设球心 = 原点）；
##   5. 星球地形生成 trimesh 碰撞（StaticBody 层 1|2：玩家走 + 相机弹簧臂挡）。
## 物件摆放不在这一步 —— street.gd 拿 surface() 的射线落点自己摆。
##
## 【为什么不上树】tree-leaves 是原版树冠的高模版，坐标与地形同套世界坐标，
## 直接叠加即可；map.json 里数据驱动的 tree/sakura 继续照常摆（游戏玩法物件）。
##
## 【海面不进碰撞】海只是壳，猫不许下水：street.gd 用 PlanetMath.walk_phi 在
## 水线附近做软墙。这样射线检测摆物件也不会把东西摆到海面上。
##
## 【退化路径】十块任何一块缺失（glb 没转出来）时回退 intro_planet 单体 +
## intro_water/intro_trees —— 与 MenuIsland 的降级顺序一致。

const ART_DIR := "res://assets/art/env/"
const CHUNK_COUNT := 10

var body: StaticBody3D           # 星球地形碰撞（层 1|2）
var math: PlanetMath
var mode := "none"               ## "full" = 十块分层拼岛；"fallback" = intro 单体
var water_radius := 0.0          ## 海面壳半径（世界坐标，到球心）。0 = 没海。
var _water_inst: Node3D
## 【为什么要有它】地形碰撞只含 full_0..9 —— 海底地形也算"地形"，surface()
## 射线会打到海底（平的、坡度全合格），物件就被摆进海里。凡是要落人的
## 地方（物件摆放/传送/整备）都必须先过 water_radius 这道海拔门槛。


## 建星球本体。math 由 street.gd 按 planet.json 的 planet 配置创建好后传入。
func setup(p_math: PlanetMath, cfg: Dictionary) -> void:
	math = p_math
	var terrain_root := Node3D.new()
	terrain_root.name = "Terrain"
	add_child(terrain_root)
	# 树冠/海面/VFX 的挂载点：只参与渲染，不进碰撞（见 _build_full_chunks）。
	var decor_root := Node3D.new()
	decor_root.name = "Decor"
	add_child(decor_root)

	var built := _build_full_chunks(terrain_root, decor_root)
	if not built:
		built = _build_fallback(terrain_root, decor_root)
	if not built:
		push_error("PlanetBuilder: 星球模型全缺失（full_0..9 与 intro_planet 都没有）")
		return

	if bool(cfg.get("clouds", false)):
		_add_decor("planets_present_intro_clouds", IslandMaterials.cloud())

	# 岛心挪到原点：地形/海/云本来就在同一套世界坐标里，一起平移。
	var merged := _mesh_aabb(self)
	if merged.size.length() > 0.0001:
		var c := merged.get_center()
		for child in get_children():
			(child as Node3D).position -= c

	# 整体缩放：planet.json 的 scale 相对 GLB 原生尺寸（原生半径约 34m）。
	# 缩放挂在 builder 根节点上 —— 碰撞收集累乘局部变换会带上它，射线落点是
	# 世界坐标不受影响，PlanetMath.radius 已按同样比例放大。
	var s := float(cfg.get("scale", 1.0))
	if absf(s - 1.0) > 0.001:
		scale = Vector3.ONE * s

	# 海面壳半径（世界坐标）：水面是围岛球壳，球面上任一顶点到球心的距离都等于
	# 半径，取顶点距离中位数（对裙边/泡沫离群点鲁棒）。物件摆放/传送/整备拿它当
	# 海拔门槛 —— 别把楼摆进海里。
	if _water_inst != null:
		water_radius = _water_shell_radius(_water_inst)
		# 可选降水位（planet.json planet 段 "water_drop"，单位=世界米）：
		# 水壳绕球心（世界原点）均匀缩小 drop 米 —— 浅沟/岸架露出来变成可走陆地，
		# 沟壑蓄水变少。water_radius 同步下调，摆件/软墙/小地图全部自动跟随。
		# 注意：岸沫/瀑布 VFX 烘焙在旧水位上，降低后会有 ≤drop 的悬差（低多边形下不显眼）。
		var drop := float(cfg.get("water_drop", 0.0))
		if drop > 0.001 and water_radius > drop + 1.0:
			var k := (water_radius - drop) / water_radius
			var gt := _water_inst.global_transform
			gt.origin *= k                          # 原点也缩 → 精确绕球心收缩，与节点枢轴无关
			gt.basis = gt.basis.scaled(Vector3.ONE * k)
			_water_inst.global_transform = gt
			water_radius -= drop
			# 水面碰撞体是按旧壳形状拷的，重建一次保持视觉/碰撞一致
			var old_wb := get_node_or_null("Decor/WaterBody")
			if old_wb != null:
				old_wb.name = "WaterBody_old"
				old_wb.queue_free()
			_add_player_only_collision(_water_inst, decor_root)

	# 地形碰撞：只对地形块（海/云/树冠/VFX 不挡路）。层 1|2 —— 玩家(掩码3)能踩，
	# 相机弹簧臂(掩码1)也挡，斜坡背面镜头不穿模。
	body = StaticBody3D.new()
	body.name = "PlanetBody"
	body.collision_layer = 3
	body.collision_mask = 0
	add_child(body)
	_collect_collision(terrain_root, Transform3D.IDENTITY, body)


## 从外面沿 -dir 打到星球表面，取落点与法线（物件/出生点全走这里，不假设完美球面）。
## 必须在星球已入树后调用。fallback：标称球面。
##
## 【hit 字段为什么必须返回】落空时静默返回标称球面是最阴的 bug 源：调用方
## 分不出「这里是标称球面」和「这里真的是这个半径」，物件就挂在天上。
## 实测 245 个物件能全部落在这个兜底上（见 docs/MAP_FLOATING_FIX.md）。
## 摆件/出生点都据此判 ok，不合格就走各自的补救（见 street.gd 的处理）。
func surface(dir: Vector3) -> Dictionary:
	var d := dir.normalized()
	var far := math.radius * 3.0 + 30.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(d * far, d * 0.5, 2)
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return {"pos": hit["position"], "normal": hit["normal"].normalized(), "hit": true}
	return {"pos": d * math.radius, "normal": d, "hit": false}


# ---------------------------------------------------------------- 组装

## 十块穿插分层拼岛。缺任何一块就放弃整套（分层缺一块会露洞，比退化方案糟）。
## 【terrain vs decor】只有 full_0..9 地形块进碰撞。树冠/海面/VFX 必须挂 decor：
## 它们叠在地形上方，进了碰撞会让 surface() 射线打到树冠顶（物件全摆上树梢/海面，
## 悬空），玩家也会撞上一圈隐形叶墙 —— 「某些方向阻力特别大」的元凶。
func _build_full_chunks(root: Node3D, decor: Node3D) -> bool:
	var insts: Array[Node3D] = []
	for i in CHUNK_COUNT:
		var inst := _instantiate("planets_present_full_%d" % i, IslandMaterials.terrain())
		if inst == null:
			for done: Node3D in insts:
				done.queue_free()
			push_warning("PlanetBuilder: 缺 full_%d，回退 intro_planet 方案" % i)
			return false
		insts.append(inst)
		root.add_child(inst)
	# 高模树冠直接叠加（与地形同一套烘焙坐标）
	for i in 5:
		var leaves := _instantiate("planets_present_tree-leaves_%d" % i, IslandMaterials.leaves())
		if leaves != null:
			decor.add_child(leaves)
	# 海面：渲染进 decor；碰撞单独建【只含层 1】的水壳 —— 玩家(掩码 3)踩得住
	# 不会沉到海底，但 surface() 射线(掩码 2)和摆件全部无视它（否则物件摆上水面）。
	var water := _instantiate("planets_present_water", IslandMaterials.water())
	if water != null:
		decor.add_child(water)
		_water_inst = water
		_add_player_only_collision(water, decor)
	# 岸沫/瀑布 VFX（原版烘焙在岸线/瀑布口，直接实例化即对齐）
	for vfx in ["planets_present_beachfoam_vfx", "planets_present_waterfall_vfx",
			"planets_present_waterfall_inlet_vfx", "planets_present_waterfallsplash_vfx"]:
		var fx := _instantiate(vfx, IslandMaterials.flat(true))
		if fx != null:
			decor.add_child(fx)
	# 【不上 intro_galaxies】星系迷你岛群的烘焙坐标与这座岛不同心（实测贴脸散在
	# 岛边像悬浮碎片）；背景星点由 street.gd 的程序星空承担。
	mode = "full"
	return true


## 退化：intro_planet 单体（菜单同款低模岛）+ intro 水/树（水/树不进碰撞，理由同上）。
func _build_fallback(root: Node3D, decor: Node3D) -> bool:
	var planet := _instantiate("planets_present_intro_planet", IslandMaterials.terrain())
	if planet == null:
		return false
	root.add_child(planet)
	var water := _instantiate("planets_present_intro_water", IslandMaterials.water())
	if water != null:
		decor.add_child(water)
		_water_inst = water
		_add_player_only_collision(water, decor)
	var trees := _instantiate("planets_present_intro_trees", IslandMaterials.terrain())
	if trees != null:
		decor.add_child(trees)
	mode = "fallback"
	return true


func _add_decor(stem: String, mat: Material) -> void:
	var inst := _instantiate(stem, mat)
	if inst != null:
		add_child(inst)


func _instantiate(stem: String, mat: Material) -> Node3D:
	var path := ART_DIR + stem + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	_override_materials(inst, mat)
	return inst


func _override_materials(root: Node, mat: Material) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					mi.set_surface_override_material(i, mat)
		for c in n.get_children():
			stack.append(c)


# ---------------------------------------------------------------- 碰撞收集

## 递归收集 root 子树里所有网格的 trimesh 碰撞。xf 是相对 target 所在父空间的
## 累计变换（用局部变换累乘，不依赖是否已在场景树里）。
func _collect_collision(root: Node, xf: Transform3D, target: StaticBody3D) -> void:
	var next_xf := xf
	if root is Node3D:
		var n3 := root as Node3D
		next_xf = xf * n3.transform
		if root is MeshInstance3D:
			var mi := root as MeshInstance3D
			if mi.mesh != null:
				var cs := CollisionShape3D.new()
				cs.shape = mi.mesh.create_trimesh_shape()
				cs.transform = next_xf
				target.add_child(cs)
	for c in root.get_children():
		_collect_collision(c, next_xf, target)


## 水面专用：碰撞体只含层 1 —— 玩家(掩码3)踩得住水不沉底、相机臂(掩码1)挡住
## 不穿水面；surface() 射线(掩码2)与所有摆件逻辑无视它。inst 与新建的 body
## 挂在同一个 parent 下，形状变换在 parent 空间累计。
func _add_player_only_collision(inst: Node3D, parent: Node3D) -> void:
	var wb := StaticBody3D.new()
	wb.name = "WaterBody"
	wb.collision_layer = 1
	wb.collision_mask = 0
	parent.add_child(wb)
	_collect_collision(inst, Transform3D.IDENTITY, wb)


## 水面壳半径：采样水面网格顶点到球心（原点）的距离取中位数。
## 注意水面壳常是球冠而非全球，AABB 量不出球面半径 —— 顶点距离才是直接量。
static func _water_shell_radius(n: Node) -> float:
	var dists: PackedFloat64Array = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null:
				var xf := mi.global_transform
				for v in mi.mesh.get_faces():
					dists.append((xf * v).length())
		for c in cur.get_children():
			stack.append(c)
	if dists.is_empty():
		return 0.0
	dists.sort()
	return dists[dists.size() / 2]


## 递归合并子树里所有网格的世界坐标包围盒（要求已在场景树内）。
static func _world_aabb(n: Node) -> AABB:
	var acc := AABB()
	var has := false
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree():
				var box: AABB = mi.global_transform * mi.mesh.get_aabb()
				acc = box if not has else acc.merge(box)
				has = true
		for c in cur.get_children():
			stack.append(c)
	return acc


## 递归合并子树里所有可见网格的包围盒（节点空间）。
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
