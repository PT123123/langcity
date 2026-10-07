// 全屏后处理层 —— 移植自 arafays/messenger-copy (MIT) 的 postProcessing.glsl.ts。
//
// 【Messenger 的画面为什么「有轮廓」】
// 原版在 postProcessing.glsl 里拿深度纹理做 4 邻域差分，深度突变的像素
// 就是物体边界，涂成深色 —— 于是每个低模物体都有一圈轮廓线。
//
// 【描边为什么暂时不在这里做 —— 引擎限制，不是偷懒】
// Godot 的 `hint_depth_texture` **只支持 spatial shader**。
// 在 canvas_item 里用会生成
//     texture(sampler2D(depth_buffer, ...), ...)
// 而 depth_buffer 在 2D 管线里不存在 → 编译失败：
//     'depth_buffer' : undeclared identifier
// shader 一旦编译失败，ColorRect 就退回默认 modulate（纯白）→ 全屏刷白。
// （godotengine/godot#74189 记录的正是这个现象。）
//
// 而 canvas_item 拿不到深度、spatial 拿不到颜色缓冲 —— 这正是取舍点。
// 真正能做屏幕空间深度描边的路径只有两条，都比现在重：
//   1. CompositorEffect + RenderDevice（正解，但移动端兼容风险高，
//      graphics_tier.gd 早就明确「不采纳」）
//   2. 反向外壳描边（inverted hull）：给网格套一层沿法线外扩、
//      只画背面的副本，纯几何、零后处理、移动端友好 ——
//      代价是要给每个 MeshInstance3D 挂一个子节点
// 两者都需要单独一轮实现与实测。等这层分级跑通后再单独做。
//
// 【色彩分级：LUT 的解析式替代】
// Messenger 有 lut.ktx2（8×8×8 strip LUT）在片元最后做一次色彩映射，
// 这是它「颜色统一但不脏」的来源。那张 LUT 属 abeto 所有，不能用，
// 所以用解析式分级替代：暗部柔提亮、压一点饱和、往青橙轴上偏。
// 效果接近，但不是逐像素查表 —— 有意的替代方案。
//
// 【仍保留原有的暗角】
// 视觉方向 §15 要求暗角存在且克制，保留。

shader_type canvas_item;
render_mode unshaded, blend_mix;

// 【关键】必须用 hint_screen_texture 显式声明屏幕采样，
// 否则 canvas_item 模式下的 TEXTURE 是 ColorRect 自己的空白纹理 → 全屏被刷白。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

uniform vec4 vignette_color : source_color = vec4(0.10, 0.09, 0.08, 1.0);
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.20;
uniform float vignette_softness : hint_range(0.0, 2.0) = 0.9;
uniform float vignette_shape : hint_range(0.0, 1.0) = 0.6;

// ---- 色彩分级（LUT 的解析式替代）----
uniform float grade_lift : hint_range(0.0, 0.2) = 0.02;      // 暗部提亮，防死黑
uniform float grade_saturation : hint_range(0.0, 2.0) = 1.06;
uniform float grade_contrast : hint_range(0.5, 1.5) = 1.04;
// 冷暗暖亮：Messenger 的黄昏全景就是这个倾向。极轻，0 = 不做。
uniform float grade_split_tint : hint_range(0.0, 0.5) = 0.06;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_tex, uv).rgb;

	// ---- 色彩分级 ----
	// 1) 暗部柔和提亮：按亮度平滑衰减，线性乘会把黑位抬成灰雾
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col += grade_lift * (1.0 - smoothstep(0.0, 0.6, lum));
	// 2) 饱和度
	col = mix(vec3(lum), col, grade_saturation);
	// 3) 对比度（围绕中灰 0.5）
	col = (col - 0.5) * grade_contrast + 0.5;
	// 4) 冷暗暖亮：暗部压一点青，亮部提一点暖
	col += vec3(-0.4, 0.0, 0.9) * grade_split_tint * (1.0 - smoothstep(0.0, 0.5, lum));
	col += vec3(1.0, 0.45, -0.3) * grade_split_tint * smoothstep(0.45, 1.0, lum);

	// ---- Vignette：深棕而非纯黑，避免边缘发死 ----
	float d = distance(uv, vec2(0.5));
	float v = smoothstep(0.82, vignette_softness * 0.42, d * vignette_shape * 1.35);
	v = pow(clamp(v, 0.0, 1.0), 1.35);
	col = mix(col, col * vignette_color.rgb * 2.2, v * vignette_strength);

	// 保持原 alpha（通常为 1），只改 RGB
	COLOR = vec4(col, COLOR.a);
}