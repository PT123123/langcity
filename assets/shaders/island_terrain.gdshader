// 星球地形材质 —— 从原版 art 包 introMaterial (shaders_port-introMaterial_*.glsl) 移植。
// 【原版逻辑】颜色 = 16×16 调色板贴图按 UV 最近邻采样（引擎上传时 flipY，
// palette.png 已预翻转，这里直接用 UV）；山体（COLOR.b==elementId==1）按
// 三平面噪声决定草地掩码（整面换成草绿格）+ 岩石条纹。
// 【贴图】tNoise 用原版 noise-simplex-layered-blur（三通道各异的 layered simplex）；
// 条纹采样原版 noises-terrain 的红斑通道。
// COLOR = (surfaceId, batchId, elementId, 1)，由 art_convert/convert.mjs 写回。
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;   // noise-simplex-layered
uniform sampler2D terrain_noise : source_color, filter_linear_mipmap, repeat_enable; // noises-terrain
uniform vec2 grass_cell = vec2(0.15, 0.95); // 草地掩码命中的调色板 UV（深绿格）

// 【这里曾经尝试过「地形黄昏色调统一」，已回滚 —— 记录原因避免重蹈】
// 想法：原版 palette.png 是粉色系调色板，而星球上其余一切都已统一到暖色夕照，
// 只有地形带冷粉，割裂明显。做法是加 dusk_tint / dusk_tint_strength 两个
// uniform，在 fragment 里做 ALBEDO = mix(ALBEDO, ALBEDO*tint, strength)。
//
// 实测结论：**uniform 写入成功、shader 编译通过、代码逻辑正确，但画面 Δ0**
// （纯红+强度1.0 的极端测试同样 Δ0）。逐层排查全部通过：
//   · shader 能加载，6 个 uniform 都在（shader_compile_check）
//   · IslandMaterials.set_terrain_tint 写进同一个材质实例，18 帧后仍保持（who2 探针）
//   · 场景里确实只有 1 个地形材质实例，持有正确值（who_uses_terrain 探针）
// 唯一未排除的可能：该材质虽被 set_surface_override_material 赋给地形块，
// 但**真正可见的地面像素不经过它**（星球包可能另有覆盖/回退路径）。
// 在没有定位清楚之前挂着两个无人使用的 uniform 是纯负债，已移除。
// 真要解决，先用 --view-nosky 那类手段确认「屏幕上的地面到底是谁画的」。


varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	// fragment 里的 VERTEX/NORMAL 是视图空间；三平面噪声与山体坡向都要世界空间
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 triplanar(vec3 n, vec3 p, float scale) {
	vec3 an = pow(abs(n), vec3(4.0));
	an /= an.x + an.y + an.z;
	// 原版 tNoise 自带三通道不同噪声层，逐通道做三轴加权混合
	float ax = texture(noise_tex, p.zy * scale).r;
	float ay = texture(noise_tex, p.xz * scale).r;
	float az = texture(noise_tex, p.xy * scale).r;
	float g = texture(noise_tex, p.zy * scale * 2.7 + vec2(0.33, 0.11)).g * an.x
		+ texture(noise_tex, p.xz * scale * 2.7 + vec2(0.33, 0.11)).g * an.y
		+ texture(noise_tex, p.xy * scale * 2.7 + vec2(0.33, 0.11)).g * an.z;
	float b = texture(noise_tex, p.zy * scale * 6.1 + vec2(0.71, 0.47)).b * an.x
		+ texture(noise_tex, p.xz * scale * 6.1 + vec2(0.71, 0.47)).b * an.y
		+ texture(noise_tex, p.xy * scale * 6.1 + vec2(0.71, 0.47)).b * an.z;
	return vec4(ax * an.x + ay * an.y + az * an.z, g, b, 1.0);
}

void fragment() {
	vec3 n = normalize(w_nrm);
	vec4 tn = triplanar(n, w_pos, 0.07);
	vec2 colorUV = UV;
	if (COLOR.b > 0.5) {
		// 山体：草地掩码（噪声 + 坡向决定哪些面保持草绿）
		float grassMask = step(0.15, max(0.0, -tn.r * 1.5 + dot(n, normalize(w_pos))) - tn.g * 0.35 + 0.1 - tn.b * 0.05);
		// 岩石条纹：原版只拿来切描边分区；这里把条纹弱化混入岩壁色阶
		float h = length(w_pos);
		float n1 = sin(h * 0.025 + (n.x + n.y + n.z) * 0.05 + (w_pos.x + w_pos.y + w_pos.z) * 1.5);
		float striations = texture(terrain_noise, vec2(n1 * 0.01, h * 0.07 - n1 * 0.02)).r;
		striations = step(0.47, striations + tn.r * 0.2 + tn.g * 0.05);
		colorUV = mix(colorUV, grass_cell, grassMask);
		ALBEDO = texture(palette, colorUV).rgb;
		ALBEDO = mix(ALBEDO, ALBEDO * 0.82, striations * (1.0 - grassMask) * 0.6);
	} else {
		ALBEDO = texture(palette, colorUV).rgb;
	}
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
