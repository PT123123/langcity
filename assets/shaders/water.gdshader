// 水面 shader —— 移植自 arafays/messenger-copy (MIT) 的
// messengerMaterials.glsl.ts 里的 waterVertexShader / waterFragmentShader。
//
// 【原版在做什么】
// Messenger 的水没有反射、没有折射、没有法线贴图动画。它做的是：
//   1. 噪声推着一条**白色浪花带**在水面世界坐标上滚动（uTime 驱动）
//   2. 浪花带用 fract() + step() 切成硬边的色块 —— 这是 Messenger 的招牌：
//      水面是「几层平涂的色带」，不是写实的水
//   3. 靠近水边（vDistance 约 0.3~0.7）才出现浪花，中心没有
//   4. 一条青色的岸边辉光
//
// 【移植到 Godot 的差异】
//   · 原版 vDistance = length(position)，即到**水网格中心**的距离，
//     这是因为 Messenger 的水是一个球面（星球表面的海洋）。
//     LangCity 的水洼是地面上的小平面，没有「球心」概念，
//     所以改成用**边缘距离**：由 vertex 计算到该水面边界的 UV 距离。
//   · 原版是 unlit；这里保留 Godot 光照，让水洼能落进场景的阴影里。
//
// 【不要】加反射/折射/泡沫模拟。水洼是路面的一层薄水膜，越平涂越像 Messenger。

shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled, depth_draw_opaque;

uniform vec4 base_tint : source_color = vec4(0.45, 0.62, 0.72, 0.55);
uniform sampler2D noise_tex : hint_default_white, filter_linear, repeat_enable;
uniform float noise_scale : hint_range(0.01, 4.0) = 0.07;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.05;

// 浪花带：强度、宽度、出现的边界范围
uniform float foam_strength : hint_range(0.0, 1.0) = 0.35;
uniform float foam_ink : hint_range(0.0, 2.0) = 0.7;
// 岸边辉光
uniform vec3 shore_glow : source_color = vec3(0.2, 0.8, 1.0);
uniform float shore_width : hint_range(0.0, 1.0) = 0.2;

// 指向太阳的**世界**方向（由 ToonKit.set_light_dir 写入）。
// 【为什么不用内建 LIGHT】Godot 的 LIGHT 只在 light() 函数里存在，
// fragment() 里没有 —— 在 fragment 写 normalize(LIGHT) 会编译失败。
// Messenger 原版用 uLightPosition uniform 是同一个原因。
uniform vec3 light_dir_world = vec3(0.0, -1.0, 0.0);

varying float v_edge;
varying vec3 v_world;
varying vec3 v_water_world_normal;

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
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 到 UV 边界的距离：0 在中心，1 在四角。用于「只在岸边出现浪花」。
	vec2 d = abs(UV - vec2(0.5)) * 2.0;
	v_edge = max(d.x, d.y);
}

void fragment() {
	vec3 albedo = base_tint.rgb;

	// 原版：noiseUv = worldPos.xz * 0.07 + uTime * 0.05
	vec2 nuv = v_world.xz * noise_scale + vec2(TIME * flow_speed);
	float noise = texture(noise_tex, nuv).r;

	// 原版的浪花带公式（保留 fract/step 的硬边平涂质感）
	float bands = fract(noise * 0.7 + v_edge * 3.0 + TIME * 0.1);
	bands *= 1.0 - step(0.7, v_edge);     // 中心不出现
	bands *= step(0.3, v_edge);          // 只在靠边处出现
	bands = step(0.3, bands * noise);
	albedo = mix(albedo, vec3(1.0), bands * foam_strength);

	// 岸边辉光：原版 `color += smoothstep(0.3, 0, step(0.2, edge - noise*1.5)) * cyan * 0.04`
	float shore = smoothstep(shore_width, 0.0, v_edge) * smoothstep(0.2, 0.6, noise);
	albedo += shore_glow * shore * 0.12;

	// 与 toon.gdshader 同源的 HSV 硬边阴影。
	// 【坐标系】光照方向是自传的世界向量，所以法线也必须取世界空间
	// （fragment 的 NORMAL 是视空间，两者混用会得到错误的明暗）。
	vec3 n = normalize(v_water_world_normal);
	float shade = max(dot(n, -light_dir_world), 0.0);
	vec3 hsv = rgb2hsv(albedo);
	hsv.z = mix(hsv.z, hsv.z * 0.62, 1.0 - smoothstep(0.2, 0.55, shade));
	albedo = hsv2rgb(hsv);

	ALBEDO = albedo;
	ALPHA = base_tint.a;
	ROUGHNESS = 0.15;
	SPECULAR = 0.3;
	METALLIC = 0.0;
	RIM = 0.0;
}