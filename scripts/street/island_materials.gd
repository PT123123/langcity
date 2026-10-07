class_name IslandMaterials
extends RefCounted
## 星球族材质工厂：把原版 art 包的着色逻辑（introMaterial / waterMaterial /
## cloudMaterial 的移植版）包成共享 ShaderMaterial。全部星球件共用这几份
## 材质实例 —— Godot 按 shader+参数批处理，470k 顶点地形也只有 4 个 draw 分支。
##
## 【顶点色语义】convert.mjs 给 planets_* 家族写回的 COLOR_0：
##   地形   (surfaceId, batchId, elementId)   —— 山体标记 = elementId == 1
##   水面   (dist, dist, 0)                   —— g = 烘焙离岸距离（world 单位）
##   树叶   (leavescolor, batchId, 0)         —— r = 调色索引，g = 树簇号
##
## 【贴图】全部来自原版 ktx2（tools/art_convert/ktx2png.mjs 解码成 PNG）：
##   noise-simplex-layered-blur  地形三平面 tNoise（三通道异频 layered simplex）
##   noises-terrain              山体岩石条纹
##   water-noises-highq          海面焦散/波浪
##   tree-leaves                 树冠剪纸 mask
##   clouds_noise_512            云顶点抖动相位
## 详见 assets/shaders/island_*.gdshader 顶部说明。

const TERRAIN_SHADER := preload("res://assets/shaders/island_terrain.gdshader")
const WATER_SHADER := preload("res://assets/shaders/island_water.gdshader")
const LEAVES_SHADER := preload("res://assets/shaders/island_leaves.gdshader")
const CLOUD_SHADER := preload("res://assets/shaders/island_cloud.gdshader")
const FLAT_SHADER := preload("res://assets/shaders/island_flat.gdshader")
const PALETTE_TEX := preload("res://assets/art/env/palette.png")
const NOISE_LAYERS := preload("res://assets/tex/art/assets_images_noise-simplex-layered-blur-highq.png")
const NOISE_TERRAIN := preload("res://assets/tex/art/assets_images_noises-terrain.png")
const NOISE_WATER := preload("res://assets/tex/art/assets_images_water-noises-highq.png")
const NOISE_CLOUD := preload("res://assets/tex/art/assets_images_clouds_noise_512.png")
const LEAF_MASK := preload("res://assets/tex/art/assets_images_tree-leaves.png")

static var _cache := {}


static func terrain() -> ShaderMaterial:
	var m := _material("terrain", TERRAIN_SHADER)
	m.set_shader_parameter("palette", PALETTE_TEX)
	m.set_shader_parameter("noise_tex", NOISE_LAYERS)
	m.set_shader_parameter("terrain_noise", NOISE_TERRAIN)
	return m


static func water() -> ShaderMaterial:
	var m := _material("water", WATER_SHADER)
	m.set_shader_parameter("noise_tex", NOISE_WATER)
	return m


static func leaves() -> ShaderMaterial:
	var m := _material("leaves", LEAVES_SHADER)
	m.set_shader_parameter("leaf_mask", LEAF_MASK)
	return m


static func cloud() -> ShaderMaterial:
	var m := _material("cloud", CLOUD_SHADER)
	m.set_shader_parameter("noise_tex", NOISE_CLOUD)
	return m


## use_uv=false 时退化为纯色平涂（没有 UV 的小件）
static func flat(use_uv: bool, color := Color.WHITE) -> ShaderMaterial:
	var key := "flat_%s_%s" % [use_uv, color.to_html()]
	if not _cache.has(key):
		var m := _material(key, FLAT_SHADER)
		m.set_shader_parameter("use_uv", use_uv)
		m.set_shader_parameter("flat_color", color)
		if use_uv:
			m.set_shader_parameter("palette", PALETTE_TEX)
		_cache[key] = m
	return _cache[key]


static func _material(key: String, shader: Shader) -> ShaderMaterial:
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = shader
		_cache[key] = m
	return _cache[key]


## 按时刻给地形压一层色调统一。
##
## 【为什么需要】原版 palette.png 是**粉色系**调色板，改它就毁了原作观感；
## 但星球上其余一切（建筑/地面/人物/天空）都已统一到暖色夕照里，
## 只有地形还带着冷粉 —— 实测地面是一大片刺眼的亮粉色低模色块。
##
## 为什么能直接改 `_cache["terrain"]`：地形材质是**全星球共享单例**
## （planet_builder 里 10 个 full_0..9 + intro_planet 都用 terrain()），
## 所以设一次即全星球生效，零 draw call 零遍历。着色器侧是
## `mix(ALBEDO, ALBEDO*tint, strength)`，strength=0 时完全退回原版。
static func set_terrain_tint(tint: Color, strength: float) -> void:
	if not _cache.has("terrain"):
		return
	var m := _cache["terrain"] as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter("dusk_tint", tint)
	m.set_shader_parameter("dusk_tint_strength", clampf(strength, 0.0, 1.0))
