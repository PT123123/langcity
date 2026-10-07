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
##
## 【Messenger 视觉改造，本批次的四处变更】
##   1. 色调映射 ACES → LINEAR（去掉 tonemap_white=5）
##   2. adjustment_enabled → false，饱和/对比交给 grade.gdshader
##   3. 材质侧全部关高光（见 ToonKit.apply）
##   4. grade.gdshader 增加深度描边 + 解析式色彩分级（Messenger LUT 的替代）
## 其余分档参数（阴影级联 / SSAO / 体积雾 / glow）保持原样 ——
## 性能预算的结论与视觉方向无关，不该被这次改造牵动。
static func apply(env: Environment, sun: DirectionalLight3D, tier: Tier) -> void:
	# ---- 分档公共项 ----
	# 【Messenger 视觉】色调映射：ACES → LINEAR。
	# ACES 是「电影感」曲线，会把高光滚降、给暗部加冷调对比 ——
	# 这正是 Messenger 刻意不要的东西。它的画面是平涂的：同样的颜色
	# 在亮面和暗面保持同一个色相，只有明度不同。ACES 一上手，
	# 所有饱和色立刻被压成灰褐，Messenger 的糖果感全无。
	# LINEAR + tonemap_white 1.0 = 颜色进什么样出什么样。
	# 【代价】高光会硬截断。但由于本项目已把 specular 全关（ToonKit.apply），
	# 画面里几乎没有强高光可以截 —— 代价实际为零。
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_white = 1.0
	# 饱和/对比交给 grade.gdshader 的解析式分级（Messenger LUT 的替代），
	# Environment 的 adjustment 在 LINEAR 下会与后处理叠加两次，容易过冲。
	env.adjustment_enabled = false
	env.fog_enabled = true
	env.fog_sky_affect = 0.0

	match tier:
		Tier.HIGH:
			# Bloom: 极少（视觉方向 §15 —— 后处理不能成为风格本身）
			env.glow_enabled = true
			env.glow_intensity = 0.22
			env.glow_strength = 1.0
			env.glow_bloom = 0.015
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 0.95
			env.glow_hdr_scale = 2.0
			# SSAO: 克制（§6 —— 只做接触阴影，不要黑色脏边）
			env.ssao_enabled = true
			env.ssao_radius = 0.45
			env.ssao_intensity = 1.05
			env.ssao_power = 1.0
			env.ssao_detail = 0.4
			# Volumetric fog
			# 【albedo 之前是中性灰 0.70/0.69/0.67 —— 画面「蒙灰纱」的元凶】
			# 体积雾是**加性**的：albedo 有多亮，雾就把画面提亮多少。中性灰
			# 在暖色夕照下必然读成「发灰的蓝蒙纱」，把所有暖色压掉。
			# 改成暖米色 + 降密度后，雾才真正服务于「空气感」而不是「脏灰」。
			# 体积雾 albedo 会被 time_of_day 每帧按当前 fog 色覆写（见其
			# `_apply_preset` 的 volumetric_fog_albedo 行），这里设的是首帧初值与回退值。
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.0026
			env.volumetric_fog_albedo = Color(0.86, 0.74, 0.60)
			env.volumetric_fog_emission = Color(0.05, 0.035, 0.025)
			env.volumetric_fog_emission_energy = 0.18
			env.volumetric_fog_gi_inject = 0.0
			env.volumetric_fog_anisotropy = 0.6
			_sun_shadow(sun, 4, 70.0)
		Tier.MEDIUM:
			env.glow_enabled = true
			env.glow_intensity = 0.20
			env.glow_strength = 1.0
			env.glow_bloom = 0.015
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 0.95
			env.glow_hdr_scale = 2.0
			# 中档也保留 SSAO：省这点开销换「不像 demo」的观感很划算（但同样收敛）
			env.ssao_enabled = true
			env.ssao_radius = 0.4
			env.ssao_intensity = 0.85
			env.ssao_power = 0.9
			env.ssao_detail = 0.25
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.0030
			env.volumetric_fog_albedo = Color(0.86, 0.74, 0.60)
			env.volumetric_fog_emission = Color(0.05, 0.035, 0.025)
			env.volumetric_fog_emission_energy = 0.15
			env.volumetric_fog_gi_inject = 0.0
			env.volumetric_fog_anisotropy = 0.5
			_sun_shadow(sun, 2, 60.0)
		Tier.LOW:
			# Bloom: Low
			env.glow_enabled = true
			env.glow_intensity = 0.18
			env.glow_strength = 1.0
			env.glow_bloom = 0.01
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 0.96
			env.glow_hdr_scale = 2.0
			# SSAO / 体积雾全关（低端机用雾 + 明度分层替代）
			env.ssao_enabled = false
			env.volumetric_fog_enabled = false
			_sun_shadow(sun, 1, 45.0)

	# 规格红线：移动端禁止 SSR（掉 15~25fps）
	env.ssr_enabled = false
	# 【Messenger 视觉】tonemap_white / tonemap_mode 已在分档公共项里设为
	# LINEAR + 1.0。这里原来还有一句 `tonemap_white = 5.0`（ACES 用的），
	# 会把线性色调映射的白色点推到 5，等于取消映射、让画面直接过曝，
	# 已随 LINEAR 改造一并移除。


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
	sun.shadow_blur = 1.5
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
