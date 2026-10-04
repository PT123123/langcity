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
		"sun_color": Color(1.0, 0.76, 0.54), "sun_energy": 1.25,
		"sun_deg": Vector3(-16, 118, 0),
		"sky_top": Color(0.42, 0.56, 0.78), "sky_horizon": Color(0.96, 0.78, 0.58),
		"ambient": Color(0.66, 0.7, 0.8), "ambient_energy": 0.45,
		"fog": Color(0.92, 0.82, 0.74), "fog_density": 0.011, "fog_energy": 1.15,
		"exposure_bias": 0.2, "bloom_threshold": 0.82,
		"warm_lights": 0.5, "cool_lights": 0.15, "emissive": 0.25,
		"glow_intensity": 0.42,
	},
	Phase.DAY: {
		"name": "昼", "clock": "12:30",
		"sun_color": Color(1.0, 0.97, 0.92), "sun_energy": 1.35,
		"sun_deg": Vector3(-58, 28, 0),
		"sky_top": Color(0.32, 0.52, 0.86), "sky_horizon": Color(0.76, 0.86, 0.96),
		"ambient": Color(0.74, 0.8, 0.9), "ambient_energy": 0.48,
		"fog": Color(0.88, 0.9, 0.94), "fog_density": 0.0035, "fog_energy": 0.85,
		"exposure_bias": 0.0, "bloom_threshold": 0.9,
		"warm_lights": 0.0, "cool_lights": 0.0, "emissive": 0.0,
		"glow_intensity": 0.3,
	},
	Phase.DUSK: {
		"name": "夕", "clock": "18:00",
		# 最出片：低角度暖橙光 + 长影 + 天空橙紫渐变
		# 【曝光】夕照本来光就弱（太阳高度角 -13°），曝光要「补」而不是「压」。
		# 之前给 -0.25 把整条街压成暗调，贴图细节全丢；现在给 +0.32 补回来。
		"sun_color": Color(1.0, 0.72, 0.45), "sun_energy": 1.7,
		"sun_deg": Vector3(-13, 96, 0),
		"sky_top": Color(0.32, 0.32, 0.58), "sky_horizon": Color(0.99, 0.64, 0.36),
		"ambient": Color(0.78, 0.7, 0.76), "ambient_energy": 0.72,
		"fog": Color(0.94, 0.74, 0.56), "fog_density": 0.006, "fog_energy": 1.05,
		"exposure_bias": 0.32, "bloom_threshold": 0.72,
		"warm_lights": 0.85, "cool_lights": 0.5, "emissive": 0.85,
		"glow_intensity": 0.55,
	},
	Phase.NIGHT: {
		"name": "夜", "clock": "21:30",
		# 【重要】夜景不能用「低能量 + 负曝光」这套 —— 会压成全黑，什么都看不见。
		# 夜景的正确做法是：月光弱但有方向、ambient 提上来保证轮廓可读、
		# 靠人工点光和自发光做明暗层次。
		"sun_color": Color(0.5, 0.6, 0.95), "sun_energy": 0.45,  # 月光
		"sun_deg": Vector3(-40, 200, 0),
		"sky_top": Color(0.03, 0.04, 0.1), "sky_horizon": Color(0.12, 0.14, 0.28),
		"ambient": Color(0.34, 0.4, 0.66), "ambient_energy": 0.5,
		"fog": Color(0.16, 0.18, 0.32), "fog_density": 0.01, "fog_energy": 0.8,
		"exposure_bias": 0.3, "bloom_threshold": 0.5,  # 夜景要强溢光
		"warm_lights": 1.0, "cool_lights": 0.9, "emissive": 1.0,
		"glow_intensity": 0.85,
	},
}

var phase: int = Phase.DUSK          # ★ 默认黄昏，规格指定
var sun: DirectionalLight3D
var env: Environment
var world_env: WorldEnvironment
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
	env.tonemap_mode = Environment.TONE_MAPPER_ACES   # 规格要求 ACES
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

	# 天空
	_sky_mat.sky_top_color = _lerp_c(a["sky_top"], b["sky_top"], k)
	_sky_mat.sky_horizon_color = _lerp_c(a["sky_horizon"], b["sky_horizon"], k)

	# 环境光
	env.ambient_light_color = _lerp_c(a["ambient"], b["ambient"], k)
	env.ambient_light_energy = lerpf(a["ambient_energy"], b["ambient_energy"], k)

	# 雾
	env.fog_light_color = _lerp_c(a["fog"], b["fog"], k)
	env.fog_density = lerpf(a["fog_density"], b["fog_density"], k)
	env.fog_light_energy = lerpf(a["fog_energy"], b["fog_energy"], k)

	# 后处理联动（规格：曝光偏置 / Bloom 阈值随时刻变）
	# 【注意】Environment 没有 `adjustment_exposure`（4.4 实测），也没有 AutoExposure。
	# 用 tonemap_exposure 手动插值来模拟「曝光偏置」。
	env.tonemap_exposure = lerpf(a["exposure_bias"], b["exposure_bias"], k) + 1.0
	env.glow_hdr_threshold = lerpf(a["bloom_threshold"], b["bloom_threshold"], k)
	env.glow_intensity = lerpf(a["glow_intensity"], b["glow_intensity"], k)
	# 体积雾的 albedo 也跟色调走
	if env.volumetric_fog_enabled:
		env.volumetric_fog_albedo = _lerp_c(a["fog"], b["fog"], k).lightened(0.1)

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
	# Vignette 强度也跟着时刻走：夜里压得更狠（聚焦感）
	if grade_mat != null:
		grade_mat.set_shader_parameter("vignette_strength",
			lerpf(0.24, 0.42, clampf(float(b["glow_intensity"]) - 0.3, 0.0, 1.0)))


func _apply_one_light(l: OmniLight3D, k: float) -> void:
	if not is_instance_valid(l):
		return
	var is_warm := _warm_lights.has(l)
	if is_warm:
		l.light_energy = 2.6 * k
		l.light_color = Color(1.0, 0.75, 0.35)
		l.omni_range = 6.5
		l.omni_attenuation = 1.4
	else:
		l.light_energy = 2.0 * k
		l.light_color = _cool_color_of(l)
		l.omni_range = 4.5
		l.omni_attenuation = 1.8


func _cool_color_of(l: OmniLight3D) -> Color:
	# 冷光按招牌色走：贩卖机偏青白，信号灯偏品红
	if l.get_meta("cool_tint", false):
		return Color(0.72, 0.95, 1.0)
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
