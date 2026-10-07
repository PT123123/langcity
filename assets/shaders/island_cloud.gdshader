// 星球云层材质 —— 从原版 art 包 cloudMaterial (shaders_port-cloudMaterial_*.glsl) 移植。
// 原版云 = 平色 + 定向光硬阴影色（引擎承担）+ 顶点抖动：
//   pos += sin(noise*180 + floor(time*6)*0.25) * normalize(pos) * 0.5
// 「floor(time*6)」让抖动每 1/6 秒跳一格 —— 剪纸定格动画的手感，必须保留。
// 【贴图】抖动相位用原版 clouds_noise_512。
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable; // clouds_noise
uniform vec3 cloud_color : source_color = vec3(0.949, 0.941, 0.918); // #f2f0ea
uniform float wobble_amp = 0.5;
uniform float noise_scale = 0.07;

void vertex() {
	float tn = texture(noise_tex, VERTEX.xy * noise_scale).r;
	float step_t = floor(TIME * 6.0) * 0.25;
	VERTEX += normalize(VERTEX) * sin(tn * 180.0 + step_t) * wobble_amp;
}

void fragment() {
	ALBEDO = cloud_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
