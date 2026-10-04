// 归属批次 1。Vignette + 轻微 Chromatic Aberration。
//
// 为什么不用 Environment：Godot 4.3+ 把后处理从 Environment 拆走了，
// Environment 上没有 vignette_* / chromatic_* 属性（4.4 实测确认）。
// CompositorEffect 能做，但要碰 RenderDevice，移动端兼容风险高。
// 全屏 CanvasLayer + shader 是最稳的零依赖做法。
//
// 规格要求：Vignette strength 0.18 / color 深棕非纯黑；色差 strength 0.08 仅边缘。

// 【关键】必须用 hint_screen_texture 显式声明屏幕采样，
// 否则 canvas_item 模式下的 TEXTURE 是 ColorRect 自己的空白纹理 → 全屏被刷白。
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.42;
uniform vec4 vignette_color : source_color = vec4(0.06, 0.05, 0.04, 1.0);
uniform float vignette_softness : hint_range(0.0, 2.0) = 0.9;
uniform float vignette_shape : hint_range(0.0, 1.0) = 0.6;
uniform float chromatic : hint_range(0.0, 2.0) = 0.08;
uniform float grain : hint_range(0.0, 1.0) = 0.02;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = distance(uv, vec2(0.5));

	// ---- Chromatic Aberration：只在画面边缘可见，中心完全干净 ----
	vec3 col;
	if (chromatic > 0.001) {
		float edge = smoothstep(0.28, 0.72, d);
		vec2 dir = (uv - vec2(0.5)) * chromatic * edge * 0.012;
		col.r = texture(screen_tex, uv + dir).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - dir).b;
	} else {
		col = texture(screen_tex, uv).rgb;
	}

	// ---- Vignette：深棕而非纯黑，避免边缘发死 ----
	float v = smoothstep(0.82, vignette_softness * 0.42, d * vignette_shape * 1.35);
	v = pow(clamp(v, 0.0, 1.0), 1.35);
	col = mix(col, col * vignette_color.rgb * 2.2, v * vignette_strength);

	// ---- 胶片颗粒：极轻，抵消 ACES 后的数字感 ----
	if (grain > 0.001) {
		float n = rand(uv * vec2(1920.0, 1080.0) + vec2(TIME * 37.0, 0.0));
		col += (n - 0.5) * grain;
	}

	// 保持原 alpha（通常为 1），只改 RGB
	COLOR = vec4(col, COLOR.a);
}

