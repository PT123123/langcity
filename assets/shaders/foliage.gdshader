// 植被 shader —— 移植自 arafays/messenger-copy (MIT) 的
// shaders/treeLeaves.glsl.ts，改为 Godot spatial shader。
//
// 【原版在做什么】
// Messenger 的树叶不是一张 alpha 贴图贴满整个树冠，而是：
//   · tree-leaves_0..4.drc  —— 几片「叶子簇」的低模几何（几何本身有形状）
//   · tree-leaves.ktx2       —— 一个叶形 alpha 卡
//   · treeLeaves.glsl        —— 让这些叶片在风里摆动 + 边缘透光
// 原版核心（节选）：
//     position.xz += sin(uTime * windSpeed + phase) * windStrength
//     ALPHA / discard 用叶形贴图切出锯齿状的叶缘
//
// 【这个 shader 在 LangCity 做什么】
// LangCity 的树冠是 Kenney 的 GLB（实心低模球/锥），没有叶片几何。
// 所以这里不复制几何，而是把**原版最关键的两件事**搬到实心树冠上：
//   1. 顶风摆动：顶点按高度加权做低频位移，幅度极小（几厘米），
//      只在树冠的轮廓上能看出来 —— 这是「树是活的」的全部信息量。
//   2. 叶片透光：背光面沿视线方向的透亮（Messenger 里的 rim/SSS 替代）。
//      幅度必须小，否则整棵树会发光。
//
// 【不要】加高光/金属/法线贴图。Messenger 的树叶没有这些。

shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform vec4 base_tint : source_color = vec4(0.42, 0.62, 0.36, 1.0);
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_leaf_tex = false;
// 叶理贴图的世界重复次数（每米）。和 toon.gdshader 的 tex_scale 同一语义。
uniform float leaf_scale : hint_range(0.01, 8.0) = 2.2;

// 冠顶权重：0 = 树干不动，1 = 树冠顶端摆幅最大
// 【为什么这么小】VERTEX 是**局部**空间位移，而 Kenney 的树在
// ModelUtil.normalize() 里被整体放大 2.3~3.4 倍（街道树要 3.4~4.6m 高）。
// 局部位移 0.05 到世界空间就是 0.05*3.4 ≈ 0.17m —— 一棵 4m 的树摆 17cm
// 已经很显眼了。默认 0.035 是按放大 3 倍反推的。
uniform float sway_amount : hint_range(0.0, 0.5) = 0.035;
uniform float sway_speed : hint_range(0.0, 4.0) = 0.9;
// 每棵树相位错开：同一片树林不会整齐划一地摆
uniform float sway_phase = 0.0;

// 背光透亮。Messenger 的叶片是薄片，光能穿过去
uniform float translucency : hint_range(0.0, 1.0) = 0.22;
uniform float trunk_height : hint_range(0.5, 12.0) = 3.0;

// 指向太阳的**世界**方向（由 ToonKit.set_light_dir 写入）。
// 【为什么不用内建 LIGHT / VIEW】这两个都只在 light() 函数里存在，
// fragment() 里没有 —— 在 fragment 写 normalize(LIGHT) 会编译失败。
// Messenger 原版用 uLightPosition uniform 是同一个原因。
// 视线方向改用 fragment 合法内建的 CAMERA_POSITION_WORLD 自己算。
uniform vec3 light_dir_world = vec3(0.0, -1.0, 0.0);

varying vec3 v_foliage_world_normal;
varying vec3 v_foliage_world_pos;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(p.r, c.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void vertex() {
	// 摆动权重 = 离地高度归一化。树干（贴近地面）几乎不动，树冠顶端摆最大。
	// 用世界高度而非局部高度，这样缩放过的模型也有一致的手感。
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_foliage_world_pos = wpos;
	v_foliage_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float h = clamp(wpos.y / trunk_height, 0.0, 1.0);
	float w = h * h;

	float t = TIME * sway_speed + sway_phase;
	// 两个不同频率的正弦叠加，避免看出周期（原版也是这么做的）
	float ox = sin(t) * 0.6 + sin(t * 2.37 + 1.1) * 0.4;
	float oz = sin(t * 0.83 + 2.0) * 0.6 + sin(t * 1.91 + 0.4) * 0.4;

	VERTEX.x += ox * sway_amount * w;
	VERTEX.z += oz * sway_amount * w;
}

// 叶理贴图用**世界坐标三平面**采样，不用网格 UV。
// 【为什么】树冠/草/花都是 Kenney 的实心低模（球/锥），UV 只覆盖每个面 0~1，
// 拿 UV 采样等于「每个面贴一张图」—— 树冠会长出一张张方形贴纸。
// 世界三平面与 toon.gdshader 保持同一套做法，画面上贴图密度才一致。
vec3 triplanar_weights(vec3 n) {
	vec3 b = pow(abs(n), vec3(4.0));
	return b / max(b.x + b.y + b.z, 0.0001);
}

vec4 triplanar(sampler2D tex, vec3 n, vec3 wpos, float scale) {
	vec3 w = triplanar_weights(n);
	vec4 x = texture(tex, wpos.zy * scale);
	vec4 y = texture(tex, wpos.xz * scale);
	vec4 z = texture(tex, wpos.xy * scale);
	return x * w.x + y * w.y + z * w.z;
}

void fragment() {
	vec3 n = normalize(v_foliage_world_normal);
	vec3 l = -light_dir_world;
	vec4 base = base_tint;
	if (use_leaf_tex) {
		base *= triplanar(leaf_tex, n, v_foliage_world_pos, leaf_scale);
	}
	vec3 albedo = base.rgb;

	// 半球环境：朝上的面接天光
	float sky = clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 hsv = rgb2hsv(albedo);
	hsv.z = mix(hsv.z, hsv.z * 0.62, (1.0 - sky) * 0.7);
	albedo = hsv2rgb(hsv);

	// 硬边阴影（与 toon.gdshader 同一阈值，全场景观感才统一）
	float shade = max(dot(n, l), 0.0);
	float shadow = 1.0 - smoothstep(0.33, 0.46, shade);
	hsv = rgb2hsv(albedo);
	hsv.z = mix(hsv.z, hsv.z * 0.5, shadow * 0.85);
	albedo = hsv2rgb(hsv);

	// 背光透光：视线与光向大致相反时最亮 —— 模拟光穿过叶片。
	// 视线用 CAMERA_POSITION_WORLD（fragment 合法内建）自己算：
	// 相机 → 片元 的世界方向。
	vec3 view_dir = normalize(v_foliage_world_pos - CAMERA_POSITION_WORLD);
	float back = clamp(dot(view_dir, l), 0.0, 1.0);
	albedo += base.rgb * translucency * pow(back, 2.0) * (0.4 + 0.6 * sky);

	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	RIM = 0.0;
}