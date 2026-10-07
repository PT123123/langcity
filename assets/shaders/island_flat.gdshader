// 星球小件平涂 —— 原版对 VFX/电缆/按钮等小件用 uColor 或调色板 UV 平涂。
// 有 UV 的（瀑布/白沫/烟）按调色板取样；没有的按 uniform 色。
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform bool use_uv = true;
uniform vec3 flat_color : source_color = vec3(1.0);

void fragment() {
	if (use_uv) {
		ALBEDO = texture(palette, UV).rgb;
	} else {
		ALBEDO = flat_color;
	}
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
