class_name GraphicsTier
extends RefCounted
## 归属批次 1。依赖：无（纯静态工具 + 一个 Environment 应用函数）。
## 性能预算：零开销（仅在启动与设置变更时调用）。
##
## 画质三档。按规格表实现，供 `street.gd` 的 _setup_environment() 与
## `game_state.apply_graphics_tier()` 调用。
##
## 设计要点：
##   · Mobile 渲染器无 SRP Batcher，靠合批省 draw call，所以档位主要砍
##     后处理与阴影，而不是砍几何体。
##   · 绝不用「降分辨率」保帧率 —— FSRCAS 锐化是免费的画质。

enum Tier { LOW = 0, MEDIUM = 1, HIGH = 2 }

const TIER_NAME := {
	Tier.LOW: "低（省电 / 旧机）",
	Tier.MEDIUM: "中（推荐）",
	Tier.HIGH: "高（旗舰 / 桌面）",
}

## 暗角颜色：深棕而非纯黑（规格要求）
const VIGNETTE_COLOR := Color(0.06, 0.05, 0.04)


## 机型嗅探：按内存与设备名猜一个起始档。桌面一律高。
##
## 【Godot 4.4 注意】没有 `OS.get_video_adapter_memory()`（4.x 已移除该静态方法，
## 反射确认只有 get_video_adapter_driver_info / get_memory_info / get_static_memory_usage）。
## 改用 `OS.get_static_memory_peak_usage()` 近似系统内存，配合设备名 SoC 判断。
static func detect() -> Tier:
	if OS.has_feature("editor"):
		return Tier.HIGH
	# 桌面 / 主机
	if not OS.has_feature("mobile"):
		return Tier.HIGH
	var dev := RenderingServer.get_video_adapter_name().to_lower()
	# SoC 名字判断比内存可靠（Android 拿不到 GPU 显存）
	for good in ["sd 8", "dimensity 9", "dimensity 8", "snapdragon 8", "apple m", "adreno 7"]:
		if dev.contains(good):
			return Tier.HIGH
	for mid in ["sd 7", "sd 6", "dimensity 7", "dimensity 6", "snapdragon 7", "adreno 6"]:
		if dev.contains(mid):
			return Tier.MEDIUM
	# 系统内存兜底：>8GB 视为中档以上
	var mem_mb := int(OS.get_static_memory_peak_usage() / (1024 * 1024))
	if mem_mb > 8192:
		return Tier.MEDIUM
	return Tier.LOW


## 把档位应用到 Environment。street.gd 建好 env 后调用。
##
## 【Godot 4.4 的重要差异】规格里写的 `env.vignette_*` / `env.chromatic_*` /
## `env.auto_exposure_*` 在 Godot 4.4 的 Environment 上**根本不存在**。
## 4.3+ 把后处理拆出去了：
##   · ColorLUT  → `env.adjustment_color_correction`（挂 LUT 贴图的 Texture）
##   · Vignette / Chromatic Aberration → 需自建全屏 CanvasLayer + shader
##     （CompositorEffect 能做但要走 RenderDevice，移动端兼容风险高，不采纳）
##   · Auto Exposure → Environment 无此功能，改用 tonemap_exposure 手动插值
##   · 正确属性名是 `tonemap_white`（不是 tonemap_exposure_white）
static func apply(env: Environment, sun: DirectionalLight3D, tier: Tier) -> void:
	# ---- 分档公共项 ----
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.12
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES   # 规格要求

	match tier:
		Tier.HIGH:
			# Bloom: High
			env.glow_enabled = true
			env.glow_intensity = 0.55
			env.glow_strength = 1.0
			env.glow_bloom = 0.04
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 0.85
			env.glow_hdr_scale = 2.0
			# SSAO: Medium —— 屋檐下/电柱根/贩卖机底的接触阴影是廉价感重灾区
			env.ssao_enabled = true
			env.ssao_radius = 0.5
			env.ssao_intensity = 1.6
			env.ssao_power = 1.2
			env.ssao_detail = 0.6
			# Volumetric fog
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.008
			env.volumetric_fog_albedo = Color(0.72, 0.7, 0.66)
			env.volumetric_fog_emission = Color(0.04, 0.04, 0.05)
			env.volumetric_fog_emission_energy = 0.25
			env.volumetric_fog_gi_inject = 0.4
			env.volumetric_fog_anisotropy = 0.6
			_sun_shadow(sun, 4, 70.0)
		Tier.MEDIUM:
			env.glow_enabled = true
			env.glow_intensity = 0.5
			env.glow_strength = 1.0
			env.glow_bloom = 0.04
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 0.85
			env.glow_hdr_scale = 2.0
			# 中档也保留 SSAO：省这点开销换「不像 demo」的观感很划算
			env.ssao_enabled = true
			env.ssao_radius = 0.4
			env.ssao_intensity = 1.2
			env.ssao_power = 1.0
			env.ssao_detail = 0.3
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.005
			env.volumetric_fog_albedo = Color(0.72, 0.7, 0.66)
			env.volumetric_fog_emission = Color(0.04, 0.04, 0.05)
			env.volumetric_fog_emission_energy = 0.2
			env.volumetric_fog_gi_inject = 0.0
			env.volumetric_fog_anisotropy = 0.5
			_sun_shadow(sun, 2, 60.0)
		Tier.LOW:
			# Bloom: Low
			env.glow_enabled = true
			env.glow_intensity = 0.42
			env.glow_strength = 1.0
			env.glow_bloom = 0.02
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
			env.glow_hdr_threshold = 0.9
			env.glow_hdr_scale = 2.0
			# SSAO / 体积雾全关（低端机用雾 + 明度分层替代）
			env.ssao_enabled = false
			env.volumetric_fog_enabled = false
			_sun_shadow(sun, 1, 45.0)

	# 规格红线：移动端禁止 SSR（掉 15~25fps）
	env.ssr_enabled = false
	env.tonemap_white = 6.0


static func _sun_shadow(sun: DirectionalLight3D, splits: int, dist: float) -> void:
	sun.shadow_enabled = true
	# 【Godot 4.4】只有 SHADOW_PARALLEL_2_SPLITS / _4_SPLITS 两档，
	# 没有 1 级联（规格表写的「1 级联」在引擎里不存在）。
	# 低端机用 2 级联 + 缩短 shadow_max_distance 来省成本，效果等价于单级联。
	sun.directional_shadow_mode = (
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if splits >= 4
		else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	sun.directional_shadow_max_distance = dist
	# 减少 shadow acne，同时避免 peter-panning（阴影脱离物体底部）
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 1.3
	sun.light_specular = 0.5


## 点光预算：规格规定中档 3 个 / 高档 6 个 / 低档 1 个
static func omni_budget(tier: Tier) -> int:
	match tier:
		Tier.HIGH: return 6
		Tier.MEDIUM: return 3
		_: return 1


## 降级顺序（performance_budget 规格：连续掉帧时按此顺序关）
const DEGRADE_ORDER := [
	"volumetric_fog", "ssao", "glow", "particles", "shadow",
]
