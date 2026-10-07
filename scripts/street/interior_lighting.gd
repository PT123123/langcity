extends RefCounted
class_name InteriorLighting
## 室内光照（Mobile 渲染器）：不建天空、不烘焙 LightmapGI。
## 用「暖灰底色环境光 + 一盏垂直平行补光 + ≤3 盏不投影暖色点光」撑起可读的画面，
## 保证室内不黑、又不会比室外更耗性能。
##
## 与 street.gd 的关系：城市走 GraphicsTier.apply（黄昏外景），
## 室内（place.kind == "interior"）走本文件的 apply()。


static func apply(env: Environment, sun: DirectionalLight3D, tier: int) -> void:
	if env == null:
		return
	# 底色：暖灰（不是纯黑），阴影处理论上由 ambient 兜底
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.085, 0.082, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.56, 0.52)
	# 低档再加一点，避免小屏/低端机上室内糊成一片黑
	env.ambient_light_energy = 0.9 if tier == GraphicsTier.Tier.LOW else 0.8
	# 【Messenger 视觉】色调映射与室外统一为 LINEAR + 白色点 1.0。
	# 原来这里是 ACES，室内外用两套曲线 —— 进出室内时整个画面的
	# 色彩关系会变一次，是很明显的「切换了另一张贴图」的违和感。
	# Messenger 的室内外是同一套材质逻辑，必须一致。
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_white = 1.0
	env.tonemap_exposure = 1.0
	# 饱和/对比统一由 grade.gdshader 负责，与室外同一条路径
	env.adjustment_enabled = false

	# 室内没有天空盒，这些项显式关掉（沿用 GraphicsTier 的低档策略）
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.ssr_enabled = false
	env.ssao_enabled = false
	env.glow_enabled = tier != GraphicsTier.Tier.LOW
	if env.glow_enabled:
		# Bloom 极少（视觉方向 §15），与室外 GraphicsTier 保持一致
		env.glow_intensity = 0.20
		env.glow_bloom = 0.015
		env.glow_hdr_threshold = 0.95
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.04

	# 保留一盏平行光当「顶部补光」：方向朝下、不投影，
	# 这样 GraphicsTier 的分档接口（需要非空 sun）与后续 apply_tier 都能沿用。
	if sun != null:
		sun.rotation_degrees = Vector3(-90, 0, 0)
		sun.light_color = Color(1.0, 0.97, 0.92)
		sun.light_energy = 0.45 if tier == GraphicsTier.Tier.LOW else 0.55
		sun.light_specular = 0.1
		sun.shadow_enabled = false
