// 星球树冠材质 —— 原版 tree-leaves 模型的 leavescolor 是调色索引（小整数
// 0/1/2，convert.mjs 写进 COLOR.r）。原版映射表在网页层、已随包丢失；
// 按原版截图的树冠三档绿就近取调色板同族色。COLOR.g = 树簇 batchId，
// 用于给不同树簇做微小的明度错落，避免整棵树一个颜色。
// 【贴图】tree-leaves.ktx2 解码出的树冠剪纸 mask：黑 = 叶片区域，白 = 镂空。
// 解码出的 PNG 无 alpha，用 1-r 当 alpha，discard 掉白区 —— 叶簇边缘才有
// 原版那种手撕纸的碎叶轮廓。
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D leaf_mask : source_color, filter_linear_mipmap, repeat_enable; // tree-leaves 剪纸 mask
uniform vec3 leaf0 : source_color = vec3(0.588, 0.922, 0.294); // #96eb4b 亮绿
uniform vec3 leaf1 : source_color = vec3(0.435, 0.698, 0.616); // #6fb29d 青绿
uniform vec3 leaf2 : source_color = vec3(0.38, 0.62, 0.451);   // #619e73 深绿

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 剪纸镂空：mask 黑（r≈0）= 叶片；白 = 空洞。软边抗锯齿
	float hole = texture(leaf_mask, UV).r;
	float alpha = 1.0 - smoothstep(0.45, 0.9, hole);
	if (alpha < 0.02) {
		discard;
	}
	float idx = COLOR.r;
	vec3 color = leaf0;
	if (idx > 1.5) {
		color = leaf2;
	} else if (idx > 0.5) {
		color = leaf1;
	}
	// 树簇间明度错落 + 顶点级微噪声（原版靠 rand 属性抖动叶子颜色）
	float jitter = fract(sin(COLOR.g * 12.9898 + w_pos.x * 3.7 + w_pos.y * 7.3) * 43758.5453);
	color *= 0.92 + 0.13 * jitter;
	ALBEDO = color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ALPHA = alpha;
}
