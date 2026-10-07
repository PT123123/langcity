class_name ToonKit
extends RefCounted
## Messenger 风格 toon 材质体系的入口。
## 依赖：res://assets/shaders/{toon,foliage,water}.gdshader
## 性能预算：零常驻开销 —— 只在材质创建时跑一次，之后交给 Godot 批处理。
##
## 【这是什么】
## 一层薄壳：把 Messenger 的 toon 材质体系（见 toon.gdshader 顶部说明）
## 套到 LangCity 既有的 StandardMaterial3D 语义上。
##
## 【为什么不直接全换成 ShaderMaterial】
## LangCity 有大量逻辑依赖 StandardMaterial3D 的具体行为：
##   · TimeOfDay.scan_emissives() 按 emission_energy_multiplier 点亮夜景
##   · TimeOfDay._apply_preset() 每帧/每 Tween 改材质参数
##   · ModelUtil.attach_colormap() 给 Kenney 模型补外置 colormap 贴图
##   · GraphicsTier / InteriorLighting 只碰 Environment 和灯光
## 全换 ShaderMaterial 要把这些重写一遍，收益远小于风险。
## 所以：**保留 StandardMaterial3D 的管线行为，只把「材质长什么样」换成 Messenger 的。**
##
## 【三档策略 —— 这是本方案性能与观感的平衡点】
## Messenger 的低模本来就是纯色 + 顶点色，纹理极少。所以：
##   · 纯色物件（mat / tex_mat / ModelUtil 染色的 GLB）
##     → StandardMaterial3D + 关高光 + 关金属 + roughness 1.0（= ToonKit.toon）
##     观感等价于 Messenger，成本与原来完全一样。**这是覆盖 90% 物件的路径。**
##   · 带贴图的大面（mat_photo：墙面、地面）
##     → 真 ShaderMaterial（toon.gdshader），需要逐像素硬边阴影 + 三平面。
##   · 自发光 / 玻璃
##     → 保持 unshaded（Messenger 里它们本来就不参与光照）。
##
## 【关键：为什么"关高光"这么重要】
## StandardMaterial3D 默认 metallic_specular=0.5，在暖色夕照下每个物体
## 都会有一块白色高光。Messenger 的画面里**没有高光**——所有形体差异
## 只靠明度分层。把 specular 关掉是这次改造观感提升最大的一步。

const TOON_SHADER := preload("res://assets/shaders/toon.gdshader")
const FOLIAGE_SHADER := preload("res://assets/shaders/foliage.gdshader")
const WATER_SHADER := preload("res://assets/shaders/water.gdshader")

## 全局开关：任何时候都能一键退回原来的 PBR 观感，方便对比。
## 不做成设置项是因为它会牵动材质缓存的 key，属于开发期开关。
static var enabled := true


## 把一个 StandardMaterial3D 调成 Messenger 式的平涂表面。
## 就地修改并返回，方便在已有工厂里一行接入。
static func apply(m: BaseMaterial3D) -> void:
	if not enabled or m == null:
		return
	m.roughness = 1.0
	m.metallic = 0.0
	m.metallic_specular = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# Burley 比 Lambert 稍软：配合 roughness=1 出的是 Messenger 那种
	# 「平涂但有一丝过渡」的过渡，纯 Lambert + 硬边会退回 90 年代贴图游戏感。
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	# 法线贴图会让低模表面出现高频噪点，与平涂观感冲突
	m.normal_enabled = false
	# detail 层同理：高频细节在小尺寸物件上会变成脏点
	m.detail_enabled = false


## 纯色 toon 材质。
static func toon(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	apply(m)
	return m


## 带贴图的 toon 材质（建筑墙面、地面等大面）。
## tex_scale 语义与 Interactable.mat_photo 的 scale 一致：每米重复次数。
##
## 【normal 贴图是这一层最大的性价比点】传入 normal 后，墙面/地面/屋瓦立刻
## 获得真实的凹凸与自遮蔽感 —— 而代价只是**一次贴图采样**，不增加任何三角面。
## 反过来用几何刻砖缝需要 2K tris/m²，在 mobile 上是数量级的开销差。
##
## 【roughness 贴图不送进 ROUGHNESS，而是当 wear mask】toon 管线无高光
## （SPECULAR=0 / ROUGHNESS=1 是 Messenger 平涂的前提），rgh 送进 ROUGHNESS
## 数学上完全无效。但 rgh 图里的斑驳/苔痕正是「材质显新显假」的来源，
## 拿来调制 albedo 明度就有明确收益（详见 toon.gdshader 注释）。
static func toon_tex(albedo: Texture2D, tint: Color, tex_scale: float,
		detail: Texture2D = null, detail_scale := 4.0, detail_amount := 1.0,
		normal: Texture2D = null, normal_amount := 1.6,
		rough: Texture2D = null, wear := 0.30) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("base_tint", tint)
	m.set_shader_parameter("use_albedo_tex", albedo != null)
	if albedo != null:
		m.set_shader_parameter("albedo_tex", albedo)
	m.set_shader_parameter("tex_scale", tex_scale)
	m.set_shader_parameter("use_detail_tex", detail != null)
	if detail != null:
		m.set_shader_parameter("detail_tex", detail)
	m.set_shader_parameter("detail_scale", detail_scale)
	m.set_shader_parameter("detail_amount", detail_amount)
	# 只有 normal 与 albedo 同 scale 才对得上凹凸（不同 scale 会让法线方向错乱）
	m.set_shader_parameter("use_normal_tex", normal != null)
	if normal != null:
		m.set_shader_parameter("normal_tex", normal)
		m.set_shader_parameter("normal_scale", normal_amount)
	m.set_shader_parameter("use_rough_tex", rough != null)
	if rough != null:
		m.set_shader_parameter("rough_tex", rough)
		m.set_shader_parameter("wear_strength", wear)
	return m


## 顶点色着色的表面材质：albedo = 顶点色 × 表面贴图（三平面世界映射）。
## 给 MultiMesh 散落装饰用 —— 它们的逐件颜色变化走 MultiMesh 的顶点色，
## 所以**不能**换成 toon.gdshader（那个 shader 不读 COLOR），只能在
## StandardMaterial3D 上把「顶点色 + 三平面贴图」两件事一起打开。
static func vertex_tinted(tex: Texture2D, scale := 2.5) -> StandardMaterial3D:
	var key := "vtex_%s_%f" % [str(tex.resource_path.get_file()) if tex != null else "-", scale]
	if _vtex_cache.has(key):
		return _vtex_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
	apply(m)
	_vtex_cache[key] = m
	return m


static var _vtex_cache := {}

## 叶理贴图（树冠/草/花的表面细节）。用 assets/tex 的草地扫描图三平面贴上 ——
## 它是唯一「从远处看就是叶丛」的低成本贴图。星球包那两张 tree-leaves 是
## alpha 遮罩（白底黑叶形），当 albedo 乘上去会让树冠变成一块块黑斑，不能用。
const LEAF_TEX := preload("res://assets/tex/grass_col.jpg")

## 植被材质（树冠 / 灌木 / 草）。
## sway_phase 由调用方按位置哈希给出，让整排树不会整齐划一地摆。
## 【use_leaf_tex 现在是真的开着】以前恒为 false，等于整棵树冠是一块死平的纯色
## ——「几乎所有模型都要有贴图」这条要求下它是最大的裸模来源之一。
static func foliage(tint: Color, phase := 0.0, trunk_height := 3.0,
		leaf_scale := 2.2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("base_tint", tint)
	m.set_shader_parameter("use_leaf_tex", true)
	m.set_shader_parameter("leaf_tex", LEAF_TEX)
	m.set_shader_parameter("leaf_scale", leaf_scale)
	m.set_shader_parameter("sway_phase", phase)
	m.set_shader_parameter("trunk_height", trunk_height)
	return m


## 水面材质（水洼）。noise 传 None 时用引擎默认白噪声，也能跑 ——
## 但引擎白噪声在平面上是一层均匀噪点，看着像屏幕脏了；传一张真实水面噪声
## 才有「水在晃」的感觉。星球包的水面噪声可以直接复用（同一套 ktx2 解码图）。
const WATER_NOISE := preload("res://assets/tex/art/assets_images_water-noises-highq.png")

## 水面材质（水洼）。noise 传 None 时用引擎默认白噪声，也能跑。
static func water(tint: Color, noise: Texture2D = WATER_NOISE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("base_tint", tint)
	if noise != null:
		m.set_shader_parameter("noise_tex", noise)
	return m