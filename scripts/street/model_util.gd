class_name ModelUtil
extends RefCounted
## 外部 3D 模型（GLB / glTF）的公共工具：加载缓存、尺寸归一化、按材质染色、动画查找。
##
## 【为什么需要这一层】资源库里的模型不能直接 add_child 就用，三个坑：
##   1. 原点位置五花八门 —— Kenney 的模型原点在角上/底面中心，Quaternius 的在脚底。
##      直接摆会「一半沉进地里、一半飘在半空」。normalize() 统一成「脚贴地、XZ 居中」。
##   2. 尺寸千差万别 —— 同一个包里柴犬 2.6m 高、狐狸 1.2m 高。
##      normalize() 顺手按目标高度缩放，接进玩法数值（猫能跳 0.66m）才不用重调碰撞体。
##   3. 一个 mesh 可能有多个 surface（树冠/树干是两个 surface）——
##      染色必须逐 surface 换，material_override 会把两片一起盖掉。
##
## 选型标准：CC0 / CC-BY、单文件自带 buffer（无外部 .bin/.png）、纯色材质无贴图。


## 场景里有几十棵树/家具，重复 load() 同一个 GLB 会白白重复解析。
static var _scene_cache := {}
static var _mat_cache := {}


## 载入 res://assets/models/ 下的模型场景。路径不存在返回 null（调用方负责兜底）。
##【贴图不在这里补】City Kit 的 colormap 是外置贴图（GLB 本身不含图），
## 导入后材质是纯白。补贴图的动作放在 spawn() 里对实例节点做——
## PackedScene 不是 Node，没法直接遍历。
static func scene(rel: String) -> PackedScene:
	if _scene_cache.has(rel):
		return _scene_cache[rel] as PackedScene
	var path := "res://assets/models/" + rel
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path)
	_scene_cache[rel] = ps
	return ps


## 遍历节点树，给缺贴图的 colormap 材质补上外置贴图。
static func attach_colormap(root: Node, rel: String) -> void:
	var tex_path := _colormap_for(rel)
	if tex_path.is_empty():
		return
	var tex: Texture2D = load(tex_path) as Texture2D
	if tex == null:
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh is ArrayMesh:
			var mi := n as MeshInstance3D
			var mesh := mi.mesh as ArrayMesh
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i)
				if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture == null:
					mesh.surface_set_material(i, _with_tex(m as BaseMaterial3D, tex))
		for c in n.get_children():
			stack.append(c)


## 深拷贝材质并挂上贴图（材质是共享资源，直接改会影响所有同材质物件）。
static func _with_tex(src: BaseMaterial3D, tex: Texture2D) -> Material:
	var key := src.get_rid().get_id()
	if _mat_cache.has(key):
		return _mat_cache[key] as Material
	var out := src.duplicate() as BaseMaterial3D
	out.albedo_texture = tex
	_mat_cache[key] = out
	return out


## 由模型所在套件推出贴图路径。city/holiday 套件的贴图命名规律一致。
static func _colormap_for(rel: String) -> String:
	var suites := {
		"dumpster": "city-kit-roads", "construction_cone": "city-kit-roads",
		"construction_barrier": "city-kit-roads", "construction_fence": "city-kit-roads",
		"roadsign_street": "city-kit-roads", "roadsign_stop": "city-kit-roads",
		"roadsign_warning": "city-kit-roads", "light_curved": "city-kit-roads",
		"light_curved_double": "city-kit-roads", "light_square": "city-kit-roads",
		"elec_pole": "city-kit-roads", "elec_pole_wide": "city-kit-roads",
		"elec_wires": "city-kit-roads", "traffic_light": "city-kit-roads",
		"traffic_light_hanging": "city-kit-roads", "bridge_pillar": "city-kit-roads",
		"planter": "city-kit-suburban", "fence_low": "city-kit-suburban",
		"fence_1x4": "city-kit-suburban", "fence_2x2": "city-kit-suburban",
		"awning": "city-kit-commercial", "parasol_a": "city-kit-commercial",
		"container_a": "city-kit-industrial", "container_b": "city-kit-industrial",
		"water_tower": "city-kit-industrial", "chimney": "city-kit-industrial",
		"bench": "holiday-kit", "bench_short": "holiday-kit",
		"rocks_small": "holiday-kit", "rocks_medium": "holiday-kit",
		"rocks_large": "holiday-kit", "wreath": "holiday-kit",
		"snow_pile": "holiday-kit", "tree_holiday": "holiday-kit",
	}
	var stem := rel.get_file().get_basename()
	if not suites.has(stem):
		return ""
	var p := "res://assets/models/kenney/textures/%s_colormap.png" % suites[stem]
	return p if ResourceLoader.exists(p) else ""


## 实例化并摆位。tints 见 tint()。target_h > 0 时先归一化到该高度。
static func spawn(parent: Node, rel: String, pos := Vector3.ZERO, target_h := 0.0,
		ry := 0.0, tints := {}) -> Node3D:
	var ps := scene(rel)
	if ps == null:
		return null
	var inst := ps.instantiate()
	if inst == null:
		return null
	# 必须在归一化/染色之前贴贴图：染色是拿 albedo_color 去乘贴图，
	# 贴图没绑上时乘出来还是一片白。
	attach_colormap(inst, rel)
	parent.add_child(inst)
	inst.position = pos
	inst.rotation = Vector3(0, ry, 0)
	if target_h > 0.0:
		normalize(inst, target_h)
	if not tints.is_empty():
		tint(inst, tints)
	return inst


## 归一化：脚贴 y=0、XZ 居中；target_h > 0 时再缩放到这个高度（米）。
static func normalize(root: Node3D, target_h := 0.0) -> void:
	var r: Variant = _collect(root)
	if r == null:
		return
	var aabb := r as AABB
	if aabb.size.y <= 0.0001:
		return
	var s := 1.0
	if target_h > 0.0:
		s = target_h / aabb.size.y
	var mid := aabb.get_center()
	# 【XZ 偏移必须先按 root 自身的 Y 旋转转到父空间】
	# AABB 是 root 局部空间的量，而 root.position 是父空间的。spawn() 先设了
	# rotation.y 再进来，偏移不做同角度旋转的话，旋转过的模型（床/桌/沙发/
	# 洗衣机…这批 Kenney 模型原点在角上）会整体错位 0.3~2m，跟周边物件穿插。
	var off_xz := Basis(Vector3.UP, root.rotation.y) * (Vector3(mid.x, 0, mid.z) * s)
	root.position += Vector3(-off_xz.x, -aabb.position.y * s, -off_xz.z)
	if s != 1.0:
		root.scale = root.scale * s


## 递归收集包围盒，返回合并后的 AABB（没有可见网格时返回 null）。
## 蒙皮网格必须额外乘骨架变换，否则拿到的是绑定姿态的错包围盒。
## 不用 `is SkinnedMeshInstance3D` —— 这个类名在部分脚本上下文解析不到，改用方法探测。
static func _collect(n: Node) -> Variant:
	var acc: Variant = null
	if n.has_method("get_skeleton") and (n is VisualInstance3D) and (n is MeshInstance3D):
		var smi := n as MeshInstance3D
		if smi.mesh != null:
			acc = smi.transform * smi.mesh.get_aabb() * n.call("get_skeleton")
	elif n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			acc = mi.transform * mi.mesh.get_aabb()
	for c in n.get_children():
		var sub: Variant = _collect(c)
		if sub != null:
			acc = sub if acc == null else (acc as AABB).merge(sub as AABB)
	return acc


## 按材质名子串染色。tints = {"leafs": Color(...), "*": Color(...)}
## "*" 表示全部材质一起染。
static func tint(root: Node, tints: Dictionary) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			_tint_mesh(child as MeshInstance3D, tints)
		tint(child, tints)


static func _tint_mesh(mi: MeshInstance3D, tints: Dictionary) -> void:
	var mesh := mi.mesh
	if mesh == null or not (mesh is ArrayMesh):
		return
	var src := mesh as ArrayMesh
	var copy: ArrayMesh = null
	for i in src.get_surface_count():
		var mat := src.surface_get_material(i)
		var mname := mat.resource_name if mat != null else ""
		if mname == "":
			mname = src.surface_get_name(i)
		var col := Color(0, 0, 0, 0)
		var hit := false
		for k: String in tints:
			if k == "*" or mname.to_lower().contains(k.to_lower()):
				col = tints[k]
				hit = true
				break
		if not hit:
			continue
		if copy == null:
			copy = src.duplicate() as ArrayMesh
		copy.surface_set_material(i, tint_mat(mname, col, mat))
	if copy != null:
		mi.mesh = copy


## 染色材质：albedo_color 是**乘**贴图的，所以「保留原贴图 + 乘一个色」就能改车漆色。
## 原来直接 new 一个纯色材质会把贴图丢掉（车就变成一块塑料）。
## 反射参数一律继承源材质 —— 之前一律用 0.55/0.1（车的参数），
## 结果木家具变得又亮又滑，在夕照下整块发白。
static func tint_mat(src_name: String, col: Color, src: Material = null) -> StandardMaterial3D:
	var key := "mtint_%s_%s_%s" % [src_name, col.to_html(), str(src.get_rid().get_id()) if src != null else "-"]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.resource_name = src_name
	m.albedo_color = col
	m.roughness = 0.9
	m.metallic = 0.0
	m.metallic_specular = 0.15
	if src is BaseMaterial3D:
		var sm := src as BaseMaterial3D
		m.roughness = sm.roughness
		m.metallic = sm.metallic
		m.metallic_specular = sm.metallic_specular
		if sm.albedo_texture != null:
			m.albedo_texture = sm.albedo_texture
	_mat_cache[key] = m
	return m


## 染色专用材质：纯色 + 高粗糙。
## 植物别加 sheen/rim —— 夕照下一加就整片发光，比不加更假。
static func flat_mat(src_name: String, col: Color) -> StandardMaterial3D:
	var key := "mtint_%s_%s" % [src_name, col.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.resource_name = src_name
	m.albedo_color = col
	m.roughness = 0.94
	m.metallic = 0.0
	m.metallic_specular = 0.1
	_mat_cache[key] = m
	return m

## 递归找 AnimationPlayer，并挑第一个名字含 keys 之一的动画播上。
## 返回 null 表示模型没有动画（静态模型也能用，只是不会动）。
static func find_anim(root: Node, keys: Array) -> AnimationPlayer:
	for child in root.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var sub := find_anim(child, keys)
		if sub != null:
			return sub
	return null


## 在 AnimationPlayer 里挑一个动画名（模糊匹配 keys），挑不到返回 ""。
static func pick_anim(ap: AnimationPlayer, keys: Array) -> String:
	if ap == null:
		return ""
	for k: String in keys:
		for a in ap.get_animation_list():
			if String(a).to_lower().contains(k.to_lower()):
				return String(a)
	return ""
