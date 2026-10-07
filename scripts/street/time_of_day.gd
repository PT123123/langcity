class_name TimeOfDay
extends Node
## 归属批次 2。依赖：GraphicsTier（仅在设置变更时）。
## 性能预算：零常驻开销 —— 所有插值走 Tween，不在 _process 里逐帧算。
##
## 四个时刻，用 15 秒 Tween 过渡（规格要求，避免跳变）：
##   朝 6:00-8:00   暖橙偏低，长影，薄雾
##   昼 10:00-15:00 冷白偏高，短影
##   夕 17:00-19:00 ★ 默认，最出片：暖橙偏低、长影、天空橙→紫→深蓝
##   夜 20:00-5:00  深蓝紫，点光成主角，自发光全开

signal phase_changed(phase: int)

enum Phase { MORNING, DAY, DUSK, NIGHT }

const TWEEN_TIME := 15.0

## 每个时刻的一整套光影参数。数值来自规格的时段描述 + 日式街景实拍观感。
const PRESETS := {
	Phase.MORNING: {
		"name": "朝", "clock": "6:30",
		"sun_color": Color(1.0, 0.82, 0.66), "sun_energy": 1.10,
		"sun_deg": Vector3(-16, 118, 0),
		"sky_top": Color(0.50, 0.60, 0.72), "sky_horizon": Color(0.93, 0.82, 0.68),
		"ambient": Color(0.70, 0.73, 0.78), "ambient_energy": 0.48,
		"fog": Color(0.90, 0.85, 0.79), "fog_density": 0.011, "fog_energy": 1.15,
		"exposure_bias": 0.10, "bloom_threshold": 0.92,
		"warm_lights": 0.5, "cool_lights": 0.15, "emissive": 0.25,
		# 地形色调统一（粉色调色板压回暖调，见 IslandMaterials.set_terrain_tint）
		"terrain_tint": Color(1.02, 0.98, 0.96), "terrain_tint_amt": 0.28,
		"glow_intensity": 0.18,
	},
	Phase.DAY: {
		"name": "昼", "clock": "12:30",
		"sun_color": Color(1.0, 0.98, 0.95), "sun_energy": 1.45,
		"sun_deg": Vector3(-58, 28, 0),
		"sky_top": Color(0.46, 0.58, 0.72), "sky_horizon": Color(0.80, 0.86, 0.92),
		"ambient": Color(0.76, 0.80, 0.86), "ambient_energy": 0.62,
		"fog": Color(0.88, 0.90, 0.94), "fog_density": 0.0035, "fog_energy": 0.85,
		"exposure_bias": 0.0, "bloom_threshold": 0.95,
		"warm_lights": 0.0, "cool_lights": 0.0, "emissive": 0.0,
		"terrain_tint": Color(0.98, 1.00, 1.02), "terrain_tint_amt": 0.12,
		"glow_intensity": 0.15,
	},
	Phase.DUSK: {
		"name": "夕", "clock": "18:00",
		# 最出片：低角度暖光 + 长影 + 天空橙→紫渐变。
		# 【视觉方向 §3/§6】降饱和、降能量、降曝光 —— 保留氛围但不再过艳过曝。
		"sun_color": Color(1.0, 0.80, 0.62), "sun_energy": 1.35,
		"sun_deg": Vector3(-13, 96, 0),
		"sky_top": Color(0.42, 0.42, 0.56), "sky_horizon": Color(0.92, 0.72, 0.54),
		"ambient": Color(0.86, 0.78, 0.74), "ambient_energy": 0.62,
		"fog": Color(0.90, 0.79, 0.68), "fog_density": 0.006, "fog_energy": 1.05,
		"exposure_bias": 0.15, "bloom_threshold": 0.90,
		"warm_lights": 0.85, "cool_lights": 0.5, "emissive": 0.85,
		"terrain_tint": Color(1.10, 0.94, 0.80), "terrain_tint_amt": 0.52,
		"glow_intensity": 0.22,
	},
	Phase.NIGHT: {
		"name": "夜", "clock": "21:30",
		# 【重要】夜景不能用「低能量 + 负曝光」这套 —— 会压成全黑，什么都看不见。
		# 夜景的正确做法是：月光弱但有方向、ambient 提上来保证轮廓可读、
		# 靠人工点光和自发光做明暗层次。
		"sun_color": Color(0.58, 0.65, 0.85), "sun_energy": 0.45,  # 月光
		"sun_deg": Vector3(-40, 200, 0),
		"sky_top": Color(0.05, 0.06, 0.10), "sky_horizon": Color(0.15, 0.17, 0.24),
		"ambient": Color(0.38, 0.42, 0.55), "ambient_energy": 0.52,
		"fog": Color(0.19, 0.20, 0.27), "fog_density": 0.01, "fog_energy": 0.8,
		"exposure_bias": 0.18, "bloom_threshold": 0.80,
		"warm_lights": 0.9, "cool_lights": 0.6, "emissive": 1.0,
		"terrain_tint": Color(0.78, 0.86, 1.05), "terrain_tint_amt": 0.45,
		"glow_intensity": 0.28,
	},
}

var phase: int = Phase.DUSK          # ★ 默认黄昏，规格指定
var sun: DirectionalLight3D
var env: Environment
var world_env: WorldEnvironment
## 星球模式：天空固定为宇宙深空，只随时刻微调渐变色相；
## 太阳/灯火/自发光/雾的节奏照旧（夜里星球上的店灯照样亮）。
var space_sky := false
var _sky_mat: ProceduralSkyMaterial
var _fill: DirectionalLight3D
var _warm_lights: Array[OmniLight3D] = []
var _cool_lights: Array[OmniLight3D] = []
var _emissives: Array[MeshInstance3D] = []
var _base_emissive := {}# instance_id -> StandardMaterial3D
var _base_energy := {}     # instance_id -> 原始 emission 强度
var _tween: Tween
## 批次 1 的调色 shader（Vignette / 色差 / 颗粒），由 street.gd 注入
var grade_mat: ShaderMaterial
var _last_warm_k := 0.85
var _last_cool_k := 0.5
var _last_emissive_k := 0.8

## 宇宙星空的渐变色（space_sky=true 时取代 PRESETS 里的地球天空色）。
## 保留每个时刻一点色相差异：朝/夕有淡淡的曙暮光带，昼/夜接近纯深空。
## fog_density 是「星球大气」：小星球的远处地形要淡入天空色，否则背光面
## 悬在天上像一排浮岛 —— 这是小星球观感的标准解法（马里奥银河同理）。
const SPACE_SKY := {
	Phase.MORNING: {
		"sky_top": Color(0.03, 0.04, 0.09), "sky_horizon": Color(0.16, 0.15, 0.22),
		"ground_bottom_color": Color(0.02, 0.02, 0.05), "ground_horizon_color": Color(0.10, 0.10, 0.16),
		"fog_density": 0.028,
	},
	Phase.DAY: {
		"sky_top": Color(0.07, 0.13, 0.19), "sky_horizon": Color(0.30, 0.52, 0.55),
		"ground_bottom_color": Color(0.05, 0.10, 0.13), "ground_horizon_color": Color(0.22, 0.40, 0.44),
		"fog_density": 0.014,
	},
	Phase.DUSK: {
		# 【视觉实测后重调】原来这里是暗紫 (0.04,0.03,0.09)/(0.22,0.15,0.26)，
		# 取色实测渲染出来是 #2d5962 —— 一片**青绿**，和暖色地面彻底割裂。
		# 原因链条：mobile renderer 下暗紫 sky 会被 ambient(青灰 0.78/0.74/0.76
		# 的补光) + 雾二次提亮，绿蓝通道被抬到 0.41/0.44，红色反而略降。
		# 与其继续和渲染管线搏斗，不如直接给一个「本来就该是暖色」的目标值 ——
		# 黄昏天必须是暖的，这是日式街景的基本物理直觉。
		"sky_top": Color(0.16, 0.12, 0.30),      # 顶部深紫（夜色初临）
		"sky_horizon": Color(0.72, 0.42, 0.30),   # 地平线暖橙（夕照）
		"ground_bottom_color": Color(0.10, 0.07, 0.09),
		"ground_horizon_color": Color(0.42, 0.26, 0.20),
		"fog_density": 0.032,
	},
	Phase.NIGHT: {
		"sky_top": Color(0.012, 0.015, 0.035), "sky_horizon": Color(0.05, 0.06, 0.11),
		"ground_bottom_color": Color(0.01, 0.01, 0.025), "ground_horizon_color": Color(0.035, 0.04, 0.08),
		"fog_density": 0.045,
	},
}


## sky 用 gradient 而非 panorama —— 渐变才能表现「橙→紫→深蓝」的黄昏
func setup(p_sun: DirectionalLight3D, p_env: Environment, p_world: WorldEnvironment,
		p_fill: DirectionalLight3D) -> void:
	sun = p_sun
	env = p_env
	world_env = p_world
	_fill = p_fill
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = PRESETS[Phase.DUSK]["sky_top"]
	_sky_mat.sky_horizon_color = PRESETS[Phase.DUSK]["sky_horizon"]
	_sky_mat.ground_bottom_color = Color(0.14, 0.13, 0.12)
	_sky_mat.ground_horizon_color = Color(0.3, 0.26, 0.24)
	_sky_mat.sun_angle_max = 24.0
	_sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	if space_sky:
		# 星球：初始就落到宇宙深空配色（否则首帧闪一下地球黄昏天）
		_apply_space_sky(Phase.DUSK, 1.0)
	# 【Messenger 视觉】色调映射交给 GraphicsTier.apply() 统一设 LINEAR。
	# 原来这里硬写 ACES，会覆盖 GraphicsTier 的设置 —— 两条路径必须一致，
	# 否则室内/室外切场景时会闪一下色调映射不同的观感。
	# 留这一行只作为兜底默认值。
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	# 【关键】必须用 SKY 而不是 COLOR。
	# COLOR = 只取一个纯色当环境光 -> 天空的橙紫渐变完全不参与照明，
	#         阴影区死黑，而且所有材质受光一致 -> 画面平、像贴纸。
	# SKY   = 用天空贴图算环境光（bounced light），阴面会被天空的冷/暖色自然补亮，
	#         这是黄昏/夜景能有层次的物理基础。
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# 0.5 = 一半来自预设 ambient 色，一半来自天空。
	# 纯 SKY(1.0) 太蓝，纯 COLOR(0) 太平，0.5 是夜景最稳的平衡点。
	env.ambient_light_sky_contribution = 0.5
	_apply_preset(phase, 0.0)


## 注册街道上的暖色点光（灯笼/灯箱/窗户）
func register_warm(l: OmniLight3D) -> void:
	_warm_lights.append(l)
	_apply_one_light(l, 0.0)


## 注册冷色点光（招牌/贩卖机）
func register_cool(l: OmniLight3D) -> void:
	_cool_lights.append(l)
	_apply_one_light(l, 0.0)


## 注册夜晚会亮起来的自发光物体。
## 【关键】不能只靠显式 register —— 场景里有大量材质是通过 Interactable.mat_photo /
## glass_mat 等工厂创建的，只有走 register 才会被记录。
## 所以补一层「全表扫描」：把所有 emission_enabled 且基准强度>0 的材质都纳入调制。
func register_emissive(mi: MeshInstance3D) -> void:
	_emissives.append(mi)
	if mi.material_override == null:
		return
	var m := mi.material_override as StandardMaterial3D
	if m == null:
		return
	var k := m.get_instance_id()
	_base_emissive[k] = m
	_base_energy[k] = m.emission_energy_multiplier


## 扫描场景里所有开启了自发光且基准强度 > 0 的 MeshInstance3D。
## 在场景搭完之后调一次即可，不用逐个物体注册。
func scan_emissives(root: Node) -> void:
	for n in _walk_all(root):
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var m := mi.material_override as StandardMaterial3D
			if m != null and m.emission_enabled and m.emission_energy_multiplier > 0.01:
				var k := m.get_instance_id()
				if not _base_emissive.has(k):
					_base_emissive[k] = m
					_base_energy[k] = m.emission_energy_multiplier


func _walk_all(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk_all(c))
	return out


func set_phase(p: int, instant := false) -> void:
	phase = p
	if instant:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_apply_preset(p, 1.0)
	else:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.set_parallel(true)
		_tween.tween_method(_apply_preset.bind(p), 0.0, 1.0, TWEEN_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	phase_changed.emit(p)


func cycle() -> void:
	set_phase(((phase + 1) % 4) as int)


## 插值应用。t=0 全旧值，t=1 全新值。
func _apply_preset(target: int, t: float) -> void:
	var a: Dictionary = _current_snapshot()
	var b: Dictionary = PRESETS[target]
	var k := clampf(t, 0.0, 1.0)

	# 太阳
	sun.light_color = _lerp_c(a["sun_color"], b["sun_color"], k)
	sun.light_energy = lerpf(a["sun_energy"], b["sun_energy"], k)
	# 角度走最短路径
	sun.rotation_degrees = _lerp_v(a["sun_deg"], b["sun_deg"], k)
	if _fill != null:
		# 补光在夜里转为「城市光」——冷蓝偏品红，模拟地面反射的招牌光
		_fill.light_energy = lerpf(0.22, 0.34, k) * (1.0 - float(b["ambient_energy"]) * 0.4)
		_fill.light_color = _lerp_c(a["sun_color"], b["sun_color"], k).lerp(Color(0.85, 0.75, 1.0), 0.5)

	# 天空：星球模式用宇宙深空配色，地球模式按预设插值
	if space_sky:
		_apply_space_sky(target, k)
	else:
		_sky_mat.sky_top_color = _lerp_c(a["sky_top"], b["sky_top"], k)
		_sky_mat.sky_horizon_color = _lerp_c(a["sky_horizon"], b["sky_horizon"], k)

	# 环境光
	env.ambient_light_color = _lerp_c(a["ambient"], b["ambient"], k)
	env.ambient_light_energy = lerpf(a["ambient_energy"], b["ambient_energy"], k)

	# 地形色调统一：原版调色板是粉色的，不改它；但要压进当前时刻的色温里，
	# 否则地面在暖色夕照下是一大片刺眼的冷粉（详见 IslandMaterials.set_terrain_tint）。
	# 星球以外（室内）没有地形材质，set_terrain_tint 内部对缺失 key 直接返回。
	_island_tint(a, b, k)

	# 雾
	env.fog_light_color = _lerp_c(a["fog"], b["fog"], k)
	env.fog_density = lerpf(a["fog_density"], b["fog_density"], k)
	env.fog_light_energy = lerpf(a["fog_energy"], b["fog_energy"], k)
	if space_sky:
		# 星球大气：雾要「把星球背面融进天空」但**不能把暖色夕照洗掉**。
		#
		# 【这里原来 lerp(sc, 0.85) 是画面最大的问题】深空的 sky_horizon
		# （DUSK 是 0.22/0.15/0.26 的暗紫）权重压到 85% 后，等于用暗紫
		# 重染了整颗星球的雾 —— 实测下来暖色夕阳完全不见，全画面泛青蓝，
		# 建筑像蒙了层塑料膜。根因是「氛围色」压过了「光照色」。
		#
		# 现在反过来：暖色雾为主（.28），深空色只作为远端的冷调收边（保留 72%）。
		# 想要「浮岛融进星空」的空气感，靠 fog_density 而不是靠把雾染成深空色 ——
		# 密度负责纵深，颜色负责色温，两者不该混为一谈。
		# 【再调】SPACE_SKY[DUSK].sky_horizon 已改成暖橙 (0.72,0.42,0.30)，
		# 所以这里 lerp 0.18 即可 —— 保留一点点即可，暖色必须占主导。
		var sc: Dictionary = SPACE_SKY[target]
		env.fog_light_color = (env.fog_light_color as Color).lerp(sc["sky_horizon"], 0.18)
		# 密度整体降一档：0.032 在半径 51 的星球上意味着「半颗星球都是雾」，
		# 近处的建筑细节全被吃掉。降到 0.016~0.022 才留得住街景。
		#
		# 【DUSK 实测再调 —— 第三次】SPACE_SKY[DUSK].sky_horizon 换成暖橙后，
		# 雾的暖调变得非常强。雾是**加性**的，而半径 51 的星球上
		# 0.032×0.42=0.0134 的密度仍然足以把近处建筑洗成一片粉白 ——
		# 天空好看但街景全糊，等于白改。
		# 关键认识：星球是个**小半径球体**，相机离物体只有十几米，
		# 而雾按「到原点的距离」算 —— 这里的雾不是远景大气而是「贴在脸上的一层纱」。
		# 所以密度必须低一个数量级。0.32 系数（≈0.010）才保住近处细节。
		var fd := float(sc["fog_density"])
		if target == Phase.DUSK:
			fd *= 0.32
		else:
			fd *= 0.68
		env.fog_density = fd
		# fog_light_energy 也压低：暖橙 sky_horizon 亮度远高于原暗紫，
		# 同样 density 下等效多罩了一层亮纱。
		env.fog_light_energy = 0.62

	# 后处理联动（规格：曝光偏置 / Bloom 阈值随时刻变）
	# 【注意】Environment 没有 `adjustment_exposure`（4.4 实测），也没有 AutoExposure。
	# 用 tonemap_exposure 手动插值来模拟「曝光偏置」。
	env.tonemap_exposure = lerpf(a["exposure_bias"], b["exposure_bias"], k) + 1.0
	env.glow_hdr_threshold = lerpf(a["bloom_threshold"], b["bloom_threshold"], k)
	env.glow_intensity = lerpf(a["glow_intensity"], b["glow_intensity"], k)
	# 体积雾的 albedo 也跟色调走
	if env.volumetric_fog_enabled:
		# 【原来用 .lightened(0.1)】lightened() 是往纯白推，体积雾又是加性的 ——
		# 这一行等价于每秒往画面里持续加一层灰白，直接把暖色夕照洗成「蒙纱灰」。
		# 改为原色（最多提亮 4%）保留色温：雾要「是暖色的空气」，不是「一层灰」。
		env.volumetric_fog_albedo = _lerp_c(a["fog"], b["fog"], k).lightened(0.04)

	# 人工光强度
	_last_warm_k = lerpf(a["warm_lights"], b["warm_lights"], k)
	_last_cool_k = lerpf(a["cool_lights"], b["cool_lights"], k)
	_last_emissive_k = lerpf(a["emissive"], b["emissive"], k)
	for l in _warm_lights:
		_apply_one_light(l, _last_warm_k)
	for l in _cool_lights:
		_apply_one_light(l, _last_cool_k)
	# 自发光：直接按材质表调制（比按 MeshInstance 稳，材质被多处共享时不会漏）
	var ek := lerpf(a["emissive"], b["emissive"], k)
	_last_emissive_k = ek
	for key in _base_emissive:
		var mat: Variant = _base_emissive[key]
		if mat == null:
			continue
		var mm := mat as StandardMaterial3D
		if mm == null or not is_instance_valid(mm):
			continue
		mm.emission_energy_multiplier = _base_energy.get(key, mm.emission_energy_multiplier) * ek
	# Vignette 强度跟着时刻走：夜里略强一点（聚焦感），但整体保持「几乎看不见」。
	# glow_intensity 新范围约 0.15~0.28，按此归一化到 0~1。
	if grade_mat != null:
		var gk := clampf((float(b["glow_intensity"]) - 0.14) / 0.14, 0.0, 1.0)
		grade_mat.set_shader_parameter("vignette_strength", lerpf(0.14, 0.22, gk))


## 把当前时刻的地形色温写进共享地形材质。
## 单独抽成函数而不是内联在 _apply_preset 里，是为了在 preset 字典里
## terrain_tint 缺失时（旧存档/将来删掉某个时刻）能安全降级而不是崩。
func _island_tint(a: Dictionary, b: Dictionary, k: float) -> void:
	if not a.has("terrain_tint") or not b.has("terrain_tint"):
		return
	# 逐通道插值而不是 lerp(两个 Color)：Color 的 lerp 在 sRGB 空间做，
	# 而这里只是想「朝暖调偏一点」，逐通道线性插值更可控。
	var ta: Color = a["terrain_tint"]
	var tb: Color = b["terrain_tint"]
	var tint := Color(
		lerpf(ta.r, tb.r, k), lerpf(ta.g, tb.g, k), lerpf(ta.b, tb.b, k), 1.0)
	var amt := lerpf(float(a["terrain_tint_amt"]), float(b["terrain_tint_amt"]), k)
	IslandMaterials.set_terrain_tint(tint, amt)


## 把当前时刻的地形色温重新写进共享地形材质。
##
## 【为什么需要单独暴露这个方法】_apply_preset() 里的 _island_tint() 在
## **_build_planet() 之前**就执行了（street._ready 里 _setup_environment()
## 在 _build_planet() 之前），那时地形材质还没被创建 ——
## IslandMaterials.set_terrain_tint() 见缓存里没有 "terrain" 就安全返回，
## 于是色温静默不生效（实测画面 Δ0）。
## 星球建完后由 street.gd 调本方法补一次。材质是共享单例，只改两个 uniform。
##
## 【为什么不直接重跑 _apply_preset】_apply_preset(a, b, k) 需要插值上下文
## （前后两个时刻 + 进度 k），而过渡 tween 正在跑，重复调用会让
## 太阳/雾/自发光全部跳变。这里只动地形色温，不碰任何其他通道。
func reapply_terrain_tint() -> void:
	# 【实测踩坑】原来这里写的是 `if phase < 0 or phase >= PRESETS.size(): return`，
	# 看似合理，实际导致**永远静默返回**：
	#   · PRESETS 是 Dictionary，phase 是枚举 int，两者比较本身没问题；
	#   · 但真正的原因是「此刻 phase 还没被 set_phase 改成 DUSK」——
	#     _ready 里 _setup_environment() 先跑（把 phase 设为存档里的 DAY=1 并
	#     调了一次 _island_tint），之后 viewshot/我的 --view-phase=2 才切 DUSK，
	#     而切时刻走的是 15 秒插值 tween，终点帧才写 DUSK 的色温。
	#   · 于是我补的那次调用带着旧的 phase 值，等于把 DAY 又写了一遍。
	# 结论：这里不该猜 phase，该做的是「把当前时刻的色温原样再写一次」，
	# 所以直接用 PRESETS[phase] 本身做 a/b 两端（k=0），无守卫。
	if not PRESETS.has(phase):
		return
	var cur: Dictionary = PRESETS[phase]
	_island_tint(cur, cur, 0.0)


## 宇宙深空配色直接落到材质上（四个时刻之间只动太阳/灯火；渐变色差异微妙，
## 直接设目标值即可，跳变不可感知）
func _apply_space_sky(target: int, _t: float) -> void:
	var c: Dictionary = SPACE_SKY[target]
	_sky_mat.sky_top_color = c["sky_top"]
	_sky_mat.sky_horizon_color = c["sky_horizon"]
	_sky_mat.ground_bottom_color = c["ground_bottom_color"]
	_sky_mat.ground_horizon_color = c["ground_horizon_color"]


func _apply_one_light(l: OmniLight3D, k: float) -> void:
	if not is_instance_valid(l):
		return
	var is_warm := _warm_lights.has(l)
	if is_warm:
		l.light_energy = 2.6 * k
		l.light_color = Color(1.0, 0.80, 0.52)
		l.omni_range = 6.5
		l.omni_attenuation = 1.4
	else:
		l.light_energy = 2.0 * k
		l.light_color = _cool_color_of(l)
		l.omni_range = 4.5
		l.omni_attenuation = 1.8


func _cool_color_of(l: OmniLight3D) -> Color:
	# 冷光按招牌色走：贩卖机偏青白，信号灯偏品红（都已去饱和）
	if l.get_meta("cool_tint", false):
		return Color(0.82, 0.90, 0.95)
	return Color(0.85, 0.92, 1.0)


## 记录当前状态作为插值起点（避免 Tween 途中再次切换时跳变）
func _current_snapshot() -> Dictionary:
	return {
		"sun_color": sun.light_color if sun else Color.WHITE,
		"sun_energy": sun.light_energy if sun else 1.0,
		"sun_deg": sun.rotation_degrees if sun else Vector3.ZERO,
		"sky_top": _sky_mat.sky_top_color if _sky_mat else Color.BLUE,
		"sky_horizon": _sky_mat.sky_horizon_color if _sky_mat else Color.CYAN,
		"ambient": env.ambient_light_color,
		"ambient_energy": env.ambient_light_energy,
		"fog": env.fog_light_color,
		"fog_density": env.fog_density,
		"fog_energy": env.fog_light_energy,
		"exposure_bias": env.tonemap_exposure - 1.0,
		"bloom_threshold": env.glow_hdr_threshold,
		"glow_intensity": env.glow_intensity,
		"warm_lights": _last_warm_k,
		"cool_lights": _last_cool_k,
		"emissive": _last_emissive_k,
	}


func _lerp_c(a: Color, b: Color, t: float) -> Color:
	return Color(lerpf(a.r, b.r, t), lerpf(a.g, b.g, t), lerpf(a.b, b.b, t), 1.0)


func _lerp_v(a: Vector3, b: Vector3, t: float) -> Vector3:
	return Vector3(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t), lerpf(a.z, b.z, t))


func phase_name(p := -1) -> String:
	if p < 0:
		p = phase
	return String(PRESETS[p]["name"])


func phase_clock(p := -1) -> String:
	if p < 0:
		p = phase
	return String(PRESETS[p]["clock"])
