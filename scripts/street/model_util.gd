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
## 选型标准：CC0 / CC-BY、单文件自带 buffer（无外部 .bin/.png）。
## 【「GLB 不含贴图」不是缺点，是本项目的补图入口】Kenney 两族模型都不自带
## 像素贴图：colormap 族靠外置图集、 Furniture/Nature 族只有 baseColorFactor。
## attach_textures() 负责把它们**全部**补上贴图（见该函数的两条路说明）——
## 验收用 `--shot-action=probe_tex`（out/tex_probe.txt 逐材质统计覆盖率）。


## 场景里有几十棵树/家具，重复 load() 同一个 GLB 会白白重复解析。
static var _scene_cache := {}
static var _mat_cache := {}


## 载入模型场景。rel 支持 "res://" 开头的绝对路径（美术包资产在 assets/art/ 下），
## 其余按 res://assets/models/ 相对解析。路径不存在返回 null（调用方负责兜底）。
##【贴图不在这里补】City Kit 的 colormap 是外置贴图（GLB 本身不含图），
## 导入后材质是纯白。补贴图的动作放在 spawn() 里对实例节点做——
## PackedScene 不是 Node，没法直接遍历。
static func scene(rel: String) -> PackedScene:
	if _scene_cache.has(rel):
		return _scene_cache[rel] as PackedScene
	var path := rel if rel.begins_with("res://") else "res://assets/models/" + rel
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path)
	_scene_cache[rel] = ps
	return ps


## 遍历节点树，给缺贴图的材质补上贴图 —— **全量覆盖，不留纯色裸模**。
##
## 【为什么必须分两条路】Kenney 资产在这个项目里是两族，贴法完全相反：
##   A. colormap 族（city-kit-* / holiday-kit）：材质名就叫 "colormap"，颜色 100% 来自
##      外置图集，GLB 里的 UV 直接指向图集里的色块。贴错图集 = 颜色全错（车变紫、
##      路牌变棕）。**必须用模型自己的图集，且保留原 UV**（不能三平面）。
##   B. 表面族（Furniture / Nature / 家电）：材质只有 baseColorFactor，一个像素贴图都没有
##      —— 床、椅子、沙发、洗衣机、树丛全是纯色块。**必须按材质名配表面贴图，
##      并用三平面世界映射**（这些 GLB 的 UV 基本不可信，当成随手填的）。
## 靠「文件名白名单」判断是哪族曾经漏了一大片（新增模型默认走错路 → 白模）。
## 现在改成**看材质名**：colormap 族自带线索，表面族一律进 B 路。
static func attach_textures(root: Node, rel: String) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh is ArrayMesh:
				var mesh := mi.mesh as ArrayMesh
				for i in mesh.get_surface_count():
					var m := mesh.surface_get_material(i)
					if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture == null:
						mesh.surface_set_material(i, _textured(m as BaseMaterial3D, rel))
		for c in n.get_children():
			stack.append(c)


## 兼容旧调用名（语义已扩成「补全贴图」，不再只管 colormap）。
static func attach_colormap(root: Node, rel: String) -> void:
	attach_textures(root, rel)


## 单个材质补图。colormap 族 → 套图集（留 UV）；其余 → 按材质名配表面贴图（三平面）。
static func _textured(src: BaseMaterial3D, rel: String) -> Material:
	if _is_colormap(src):
		var atlas := _tex(_atlas_path(rel))
		if atlas != null:
			return _with_tex(src, atlas, false)
		# 图集缺失也不能退回纯白：落到表面族逻辑，至少有个表面细节
		var fallback := _tex(_surface_path(src.resource_name, "colormap"))
		if fallback == null:
			fallback = _tex("res://assets/tex/plaster_col.jpg")
		if fallback == null:
			return src
		return _with_tex(src, fallback, true)
	var p := _surface_path(src.resource_name, rel)
	if p.is_empty():
		return src
	return _with_tex(src, _tex(p), true)


static func _is_colormap(m: BaseMaterial3D) -> bool:
	return m.resource_name.to_lower().contains("colormap")


## 深拷贝材质并挂上贴图（材质是共享资源，直接改会影响所有同材质物件）。
## triplanar=true 时用世界三平面映射 —— 表面族必须走这条，它们的 UV 不可信。
static func _with_tex(src: BaseMaterial3D, tex: Texture2D, triplanar := false) -> Material:
	var key := "mt_%d_%d_%s" % [src.get_rid().get_id(), tex.get_rid().get_id(), str(triplanar)]
	if _mat_cache.has(key):
		return _mat_cache[key] as Material
	var out := src.duplicate() as BaseMaterial3D
	out.albedo_texture = tex
	if triplanar:
		out.uv1_triplanar = true
		out.uv1_world_triplanar = true
		out.uv1_scale = Vector3.ONE * SURFACE_TEX_SCALE
	# 平涂观感与贴图共存：关高光、留凹凸采样
	ToonKit.apply(out)
	_mat_cache[key] = out
	return out


static func _tex(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# ---------------------------------------------------------------- 贴图选表

## colormap 族模型 → 图集。
## 【车辆/食物原来没进这张表】新增时按「这套模型属于哪个 kit」填，别靠试：
## 填错的表现是模型整体偏色（例如出租车不是黄色、路牌不是白红）。
const COLORMAP_KIT := {
	# ---- city-kit-roads：路面交通一族 ----
	"dumpster": "city-kit-roads", "construction_cone": "city-kit-roads",
	"construction_barrier": "city-kit-roads", "construction_fence": "city-kit-roads",
	"roadsign_street": "city-kit-roads", "roadsign_stop": "city-kit-roads",
	"roadsign_warning": "city-kit-roads", "light_curved": "city-kit-roads",
	"light_curved_double": "city-kit-roads", "light_square": "city-kit-roads",
	"elec_pole": "city-kit-roads", "elec_pole_wide": "city-kit-roads",
	"elec_wires": "city-kit-roads", "traffic_light": "city-kit-roads",
	"traffic_light_hanging": "city-kit-roads", "bridge_pillar": "city-kit-roads",
	# 车辆：与 traffic_light/路牌同族（道路上的移动物），都取 roads 图集
	"sedan": "city-kit-roads", "sedan-sports": "city-kit-roads", "suv": "city-kit-roads",
	"taxi": "city-kit-roads", "truck": "city-kit-roads", "van": "city-kit-roads",
	"hatchback-sports": "city-kit-roads",
	# ---- city-kit-suburban：民居院落一族 ----
	"planter": "city-kit-suburban", "fence_low": "city-kit-suburban",
	"fence_1x4": "city-kit-suburban", "fence_2x2": "city-kit-suburban",
	# ---- city-kit-commercial：店面一族（食物道具归这里）----
	"awning": "city-kit-commercial", "parasol_a": "city-kit-commercial",
	"bowl-broth": "city-kit-commercial", "can-open": "city-kit-commercial",
	"rice-ball": "city-kit-commercial",
	# ---- city-kit-industrial：工地/水塔 ----
	"container_a": "city-kit-industrial", "container_b": "city-kit-industrial",
	"water_tower": "city-kit-industrial", "chimney": "city-kit-industrial",
	# ---- holiday-kit：雪景/岩石/装饰 ----
	"bench": "holiday-kit", "bench_short": "holiday-kit",
	"rocks_small": "holiday-kit", "rocks_medium": "holiday-kit",
	"rocks_large": "holiday-kit", "wreath": "holiday-kit",
	"snow_pile": "holiday-kit", "tree_holiday": "holiday-kit",
}

## 未知 colormap 模型的兜底图集。commercial 覆盖面最广（店面杂物最多），
## 比留空白好 —— 白模在画面里是「没做完」，偏色只是「色卡错了」。
const COLORMAP_FALLBACK := "city-kit-commercial"

static func _atlas_path(rel: String) -> String:
	var kit: String = COLORMAP_KIT.get(rel.get_file().get_basename(), COLORMAP_FALLBACK)
	return "res://assets/models/kenney/textures/%s_colormap.png" % kit


## 表面族材质名 → assets/tex 里的贴图 kind。
## 【匹配顺序按 key 长度倒序】"woodbark" 必须先于 "wood"、"leafsdark" 先于 "leafs"，
## 否则树皮的粗糙纹会被当普通木纹。**新增材质名时注意这个前缀包含关系。**
const SURFACE_TEX := {
	"woodbarkdark": "bark", "woodbark": "bark", "bark": "bark",
	"woodinner": "floor_old_wood", "wooddark": "dark_planks", "wood": "wood",
	"carpetdarker": "leather", "carpetwhite": "fabric_alt", "carpet": "fabric",
	"leafsdark": "grass", "leafsgreen": "grass", "plant": "grass", "grass": "grass",
	"metalmedium": "metal", "metallight": "metal_shutter", "metaldark": "metal_rust",
	"metal": "metal",
	"leather": "leather", "fabric": "fabric",
	"lamp": "plaster", "colorred": "plaster_paint", "colorpurple": "plaster_paint",
	"coloryellow": "plaster_paint", "_defaultmat": "plaster",
	"glass": "",     # 玻璃有意保持纯色（半透 + 高反射，贴图只会变脏）
}

## 表面族贴图的世界重复次数（每米）。0.9 ≈ 一张贴图铺 1.1m ——
## 家具尺度下颗粒刚好看得见，又不至于把大面铺成花纹墙纸。
const SURFACE_TEX_SCALE := 0.9

## 兜底「微细节」噪声：给语义不明的材质（角色 m0 / 动物 Main / …）用。
## 要的是「不是死平的纯色块」，不是「能认出是什么材料」—— 低对比灰噪声正好。
const GRAIN_TEX := "res://assets/tex/art/assets_images_noise-simplex-layered-blur-highq.png"

## 材质名 → 贴图路径。返回空串 = 有意留白（玻璃等）。
static func _surface_path(mat_name: String, fallback_name: String) -> String:
	var n := mat_name.to_lower()
	if n == "":
		n = fallback_name.to_lower()
	var keys: Array = SURFACE_TEX.keys()
	keys.sort_custom(func(a, b): return String(a).length() > String(b).length())
	for k: String in keys:
		if n.contains(k):
			var kind: String = SURFACE_TEX[k]
			if kind.is_empty():
				return ""
			var p := "res://assets/tex/%s_col.jpg" % kind
			return p if ResourceLoader.exists(p) else ""
	# 【认不出来的材质也不留白，但不能给它糊墙漆】
	# 角色/动物的材质名是 m0 / Main / Material.006 这类无语义的名字，而这些模型
	# 恰恰是最不能被贴上砖纹的（脸、爪子、毛）。给一张低对比噪声当「微细节」：
	# 表面不再是一块死平的纯色，但看不出是什么图案。
	return GRAIN_TEX


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
	attach_textures(inst, rel)
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
##
## 【Messenger 视觉】这里做两件事：
##   1. 继承源材质的 albedo_texture（原有行为，必须在 ToonKit.apply 之前拷）
##   2. 抹平反射参数 —— Messenger 的模型没有任何高光，全靠明度分层。
##      Kenney 的模型是「顶点色 + 纯色材质」，本来就没有 PBR 依赖，
##      所以关掉 specular 对它们是纯增益，不会有副作用。
static func tint_mat(src_name: String, col: Color, src: Material = null) -> StandardMaterial3D:
	var key := "mtint_%s_%s_%s" % [src_name, col.to_html(), str(src.get_rid().get_id()) if src != null else "-"]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.resource_name = src_name
	m.albedo_color = col
	if src is BaseMaterial3D:
		var sm := src as BaseMaterial3D
		if sm.albedo_texture != null:
			m.albedo_texture = sm.albedo_texture
		# 【三平面必须一起搬】表面族贴图是靠世界三平面贴上去的（GLB 的 UV 不可信）。
		# 只搬 albedo_texture 而不搬 uv1_triplanar，染色之后贴图会退回模型 UV ——
		# 表现是「明明上了贴图却看不出/花成一片」。这里是把源的贴图设置整套复制过来。
		m.uv1_triplanar = sm.uv1_triplanar
		m.uv1_world_triplanar = sm.uv1_world_triplanar
		m.uv1_scale = sm.uv1_scale
	# 贴图拷完之后再抹平反射：Messenger 的画面里没有高光，
	# 所有形体差异只靠明度分层。这是本次改造观感提升最大的一步。
	ToonKit.apply(m)
	_mat_cache[key] = m
	return m


## 染色专用材质：纯色 + 高粗糙。
## 【Messenger 视觉】同 tint_mat：关掉高光，植物别加 sheen/rim
## —— 夕照下一加就整片发光，比不加更假。
static func flat_mat(src_name: String, col: Color) -> StandardMaterial3D:
	var key := "mtint_%s_%s" % [src_name, col.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.resource_name = src_name
	m.albedo_color = col
	ToonKit.apply(m)
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
