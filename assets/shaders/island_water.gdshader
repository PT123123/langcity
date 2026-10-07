// 星球海面材质 —— 从原版 art 包 waterMaterial (shaders_port-waterMaterial_*.glsl) 移植。
// 【原版逻辑】基色 = tColors 按 UV 采样（那张是引擎运行时生成的渐变贴图，
// 资产包里没有，这里用 shallow/sea 两色按「离岸距离」重建渐变）；
// COLOR.g = 烘焙的离岸距离（world 单位，0 在岸线）：
//   · 波浪白环：dist ∈ [0.3, 0.7] 的窄带，fract(noise*0.7 + dist*3 + time*0.1) 推进；
//   · 近岸台阶亮带：dist ≈ 0.2 / 1.15 两条青色高光阶。
// 【贴图】tNoise = 原版 water-noises-highq（焦散 Voronoi，波形主驱动）。
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable; // water-noises 焦散
uniform vec3 shallow_color : source_color = vec3(0.624, 0.886, 0.878); // #9fe2e0 近岸
uniform vec3 sea_color : source_color = vec3(0.439, 0.78, 0.749);      // #70c7bf 主海面
uniform float noise_scale = 0.05;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float dist = COLOR.g;
	vec3 n = normalize(w_nrm);
	vec3 an = pow(abs(n), vec3(4.0));
	an /= an.x + an.y + an.z;
	// 焦散噪声三轴混合（海面近似平面，z 轴权重占主导）
	float tn = texture(noise_tex, w_pos.zy * noise_scale).r * an.x
		+ texture(noise_tex, w_pos.xz * noise_scale).r * an.y
		+ texture(noise_tex, w_pos.xy * noise_scale).r * an.z;

	// 基色：近岸浅 → 远海深（原版是运行时渐变贴图，这里按离岸距离重建）
	vec3 color = mix(shallow_color, sea_color, smoothstep(0.0, 2.2, dist));
	// 远海微妙深浅斑驳（焦散网格），避免一大片死平
	color *= 0.93 + 0.12 * smoothstep(0.35, 0.75, tn);

	// 波浪白环：只在离岸 0.3~0.7 的窄带出现，随时间向岸推进
	float waves = fract(tn * 0.7 + dist * 3.0 + TIME * 0.1);
	waves *= 1.0 - step(0.7, dist);
	waves *= step(0.3, dist);
	waves *= tn;
	waves = step(0.3, waves);
	color = mix(color, vec3(1.0), waves * 0.85);

	// 近岸两级台阶亮带（原版 smoothstep 阶梯高光）
	color += smoothstep(0.3, 0.0, step(0.2, dist - tn * 1.5)) * vec3(0.2, 0.8, 1.0) * 0.035;
	color += smoothstep(0.3, 0.0, step(1.15, dist - tn * 1.5)) * vec3(0.2, 0.8, 1.0) * 0.01;

	ALBEDO = color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
