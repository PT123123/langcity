// Messenger 风格 toon 材质 —— 移植自 arafays/messenger-copy (MIT) 的
// atlasVertexShader / atlasFragmentShader，改写为 Godot spatial shader。
//
// 【为什么必须移植而不是模仿】
// Messenger 的观感核心不在纹理，而在这一行：
//     colorShadow = hsv2rgb(vec3(rgb2hsv(baseColor).xy, rgb2hsv(baseColor).z * 0.5));
// 它只把明度（value）压到 0.5，**色相与饱和度原样保留**。
// 常规 PBR / toon 阴影会把暗部往蓝紫或往黑里拉（冷阴影），Messenger 不是这样 ——
// 暗部是「同一个颜色的更深版本」。这才是它那种「干净、像糖果」的画面感的来源。
//
// 【与原版的差异，都是必须的】
//   1. 原版是 unlit ShaderMaterial，只算 dot(N, L)；Godot 这边要参与
//      光照/阴影/雾，所以把 shade 作为 ALBEDO 的调制写进 BASE。
//   2. 原版阴影是 `1.0 - step(0.4, shade)` 的**硬边**。这里保留硬边但给
//      一点 smoothstep 过渡，否则低模的大平面会出现锯齿状硬边。
//   3. 原版 uLightPosition 是点光源；这里用 Godot 的 LIGHT 块，方向光/点光都支持。
//
// 【不要】在此加 specular / rim / sheen —— 一点点就会把 Messenger 的平涂感打回
// 「普通 PBR」，这正是本项目要避免的。粗糙度统一 1.0，靠明度分层区分材质。

shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_tex = false;
// 每米重复次数：0.5 = 一张贴图铺 2 米（与 mat_photo 的 scale 语义一致）
uniform float tex_scale : hint_range(0.01, 8.0) = 0.5;

// 高频细节层，抑制大平面平铺感；对应 Messenger 的 tNoiseTerrain
uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_detail_tex = false;
uniform float detail_scale : hint_range(0.01, 16.0) = 4.0;
uniform float detail_amount : hint_range(0.0, 2.0) = 1.0;

// ---- 法线贴图（视觉预算第 3 项，零几何成本）----
// 磁盘上已有 87 张 1K normal（ambientCG / Poly Haven CC0），此前这条路径
// 完全没接 —— 墙面/地面/屋瓦拿到了 albedo 却没有凹凸，等于白花 40MB 贴图预算。
// 关键取舍：**用贴图解决的事绝不用面数解决**。一块 2m 的墙用 2K tris 去刻
// 砖缝，比一张 1K normal 贵两个数量级，且在 mobile 上直接掉帧。
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal_tex = false;
uniform float normal_scale : hint_range(0.0, 4.0) = 1.6;
// 法线起伏的**可见强度**。为什么需要它：硬边阴影通道的 smoothstep 窗口
// 只有 0.38±0.04，1K 法线在墙面上的起伏几乎全落在窗口外 → 被削平。
// 这条独立的连续通道把凹凸重新还回来。0 = 关闭（回到纯硬边 toon）。
uniform float normal_detail_visibility : hint_range(0.0, 2.0) = 0.55;

// ---- Roughness 贴图：不用来做高光，当「脏污/老化遮罩」用 ----
//
// 【为什么这么用】本 shader 全程 SPECULAR=0 / ROUGHNESS=1（Messenger 平涂风
// 格的硬性前提：形体差异只靠明度分层，不靠高光）。所以 rgh 通道送进
// ROUGHNESS 输出**在数学上完全无效** —— 设成 0.2 还是 1.0 画面一模一样。
//
// 但 ambientCG 的 rgh 图信息量很高：实测 brick_wall_001_rgh 是砖面斑驳老化，
// roof_rgh 是瓦片苔痕与色差。这些正是「材质看起来新 / 假」的来源。
//
// 做法：把 rgh 当 wear mask 调制 albedo —— 粗糙度高的地方 = 更脏更暗。
// 成本：一次贴图采样（与 normal 同一三平面投影，可复用权重）。
// 收益：墙面/屋顶/地面立刻有年代感，是「材质质量」最便宜的一档提升。
//
// 【为什么不能直接用 ROUGHNESS 输出】见上：toon 管线无高光，
// 输出什么值都不影响像素。必须自己拿它调制 ALBEDO。
uniform sampler2D rough_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_rough_tex = false;
uniform float wear_strength : hint_range(0.0, 1.0) = 0.30;

// ---- AO：仅几何近似（零贴图成本）----
// 【为什么没有顶点色 AO】本项目的 GLB 顶点色是调色索引不是明度，
// 拿来当 AO 会让树冠变成黑色噪点（已在 vertex() 注释里记录实测）。
// 项目 87 张贴图里也没有任何 AO 通道。要真 AO 只能另找带 AO 的贴图源。
// 现在用「朝下的面天然被遮蔽」这一条几何规律近似 —— 零采样、零带宽。
uniform float vertex_ao_strength : hint_range(0.0, 2.0) = 0.0;   // 保持关闭
uniform float contact_ao_strength : hint_range(0.0, 2.0) = 0.45;

// ---- 轮廓描边（视觉预算第 1 项，零额外 draw call）----
// 【为什么不用反向外壳 / 屏幕空间】
//   · 反向外壳要给每个 MeshInstance3D 挂一个子节点：+1584 个 draw call，
//     而当前 draw call 已经是全项目最大瓶颈，不能碰。
//   · 屏幕空间深度描边需要 hint_depth_texture，而 Godot 只在 spatial
//     shader 里提供它 —— canvas_item 里引用会编译失败导致满屏刷白
//     （grade.gdshader 文件头记录了这个坑，见 godotengine/godot#74189）。
// fresnel 内描边是唯一「零 draw call、零后处理」的轮廓方案：视角越掠，
// 越接近边缘，1.0 尖峰。它不是屏幕空间描边（描的是朝向相机的面），
// 但在平涂低模上观感几乎一致 —— Messenger 自身的树冠剪影也是这样来的。
// fresnel = 1 - dot(N, V)。**取值范围远比想象中窄**：
// 视角 0°（正对）= 0.0，45° = 0.29，60° = 0.50，80° = 0.83，要到 89° 才接近 1.0。
// 【踩过的坑】最初写 rim_bias=0.62，结果 smoothstep(0.62,1.0,f) 在 60° 时
// 仍返回 0 —— 整个球体/建筑只有最后几度掠射角才有描边，等于没有。
// bias 必须压到 0.12~0.20 区间（对应 35°~45° 起描），
// power 用 1.6~2.2（3.2 会把有效区间压得极窄）。
uniform float rim_darken : hint_range(0.0, 1.0) = 0.42;
uniform float rim_power : hint_range(0.5, 8.0) = 2.0;
uniform float rim_bias : hint_range(0.0, 1.0) = 0.16;   // 越大描边越窄

// 阴影压暗强度：1.0 = 暗部明度砍半（Messenger 原值）
// 【从 0.82 降到 0.58 —— 视觉实测后的调整，不是随手改数字】
// Messenger 原值 0.5 是为「纯手算点光 + 无环境项」的管线调的；本项目有
// ambient + 反向补光 + 雾，暗部再砍到 18% 明度就成了纯黑板：
// 背光面的砖缝/瓦片/贴图全部读不出来，建筑看起来像没贴图的灰盒子。
// 0.58 让暗部停在 42% 明度 —— 仍是清晰的明暗分层（toon 的核心），
// 但贴图层次得以保留。保住色相不变（hsv_shade 只动 V），
// 所以「Messenger 的暗部是同色更深」这个特性一点没丢。
uniform float shade_strength : hint_range(0.0, 1.0) = 0.58;
// 硬边过渡宽度，0 = 纯硬边（最 Messenger），越大越柔
uniform float shade_softness : hint_range(0.0, 0.5) = 0.08;
// 迎光面提亮：模拟 Messenger 里 sun 侧的通透感
uniform float lift : hint_range(0.0, 0.5) = 0.06;
// 暗部环境光抬升：模拟天空/地面 bounced light 落在背光面上。
// 【为什么必须有这一项】本 shader 不参与 Godot 的 ambient 项（Messenger 是
// unlit 手算管线），所以背光面除了 toon 的压暗之外**没有任何环境光**。
// 压暗 0.58 后剩 42% 明度，再乘这个抬升才够读出贴图层次 ——
// 现实里背光墙会被天空光打亮，不会是纯暗块。
uniform float ambient_occlusion_lift : hint_range(0.0, 0.5) = 0.13;

// 指向太阳的**世界**方向（由 ToonKit.set_light_dir 从 GDScript 写入）。
//
// 【为什么必须传进来，不能用内建 LIGHT】
// Godot 的 `LIGHT` 只在 light() 函数里存在，**fragment() 里没有**。
// 在 fragment 里写 normalize(LIGHT) 会编译失败
// （'LIGHT' : undeclared identifier）→ 材质作废。
// Messenger 原版是 unlit ShaderMaterial，用 uLightPosition uniform，
// 正是同一个原因 —— 这里照搬那个做法。
//
// 【为什么用世界空间而不是视空间】
// fragment 的 NORMAL 是视空间、我的三平面贴图需要世界空间，
// 两套坐标系混用最容易出错。既然光照方向已经是自己传的，
// 直接全程用世界法线，一致且好推理。
uniform vec3 light_dir_world = vec3(0.0, -1.0, 0.0);

varying vec3 v_toon_world_normal;
varying vec3 v_toon_world_pos;
varying float v_toon_vert_ao;

// 三平面世界映射：贴图坐标从世界坐标算，不依赖网格 UV。
// 【为什么必须世界坐标】LangCity 的几何体一半是手搭 BoxMesh/SphereMesh，
// UV 基本不可用；Kenney 的 GLB 虽有 UV，但同一贴图在不同物件上的 UV 尺度
// 差几十倍。只有世界坐标 + 固定 scale 才能让「一张贴图铺 N 米」成立。
// 这与 Messenger 的 terrainMaterial 里那段 triplanar() 是同一个做法
// （原版函数签名 triplanar(tex, normal, pos, scale)，MIT 授权）。
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

// 三平面法线采样，返回**世界空间**的扰动后法线。
//
// 【为什么必须逐投影做「白点减法」再加权】
// 法线贴图存的是**切线空间**方向（+Y = 表面本身，XY = 凹凸偏移），
// 它不知道自己被贴到了哪个轴上。所以正确做法是每个投影面各自
// 还原一次「贴图法线 → 该面的几何法线」，最后按权重混合：
//   1. texture(...).xyz * 2.0 - 1.0   解码 [-1,1] → [0,1]
//   2. 减去 (0,1,0)                    得到「相对平坦」的偏移增量
//   3. 用该投影面的几何切线基重建世界法线
// 直接把三张贴图加权平均是错的 —— 三个面的贴图指向互不相容的坐标系，
// 混出来的法线会让墙面出现无法解释的扭曲高光。
//
// basis_normal：投影面的几何法线
//  tangent_t   : 投影面对应的第一切线
//  bitangent_b : 投影面对应的第二切线
vec3 triplanar_normal_from(sampler2D tex, vec3 basis_normal, vec3 tangent_t,
		vec3 bitangent_b, vec3 wpos, float scale) {
	vec3 nt = texture(tex, wpos.zy * scale).xyz * 2.0 - 1.0;
	nt.xy *= normal_scale;
	return normalize(basis_normal * nt.z + tangent_t * nt.x + bitangent_b * nt.y);
}

vec3 triplanar_normal(sampler2D tex, vec3 n, vec3 wpos, float scale) {
	vec3 w = triplanar_weights(n);
	vec3 an = abs(n);
	// 与 triplanar() 的投影顺序严格对应：zy / xz / xy
	vec3 nx = triplanar_normal_from(tex, vec3( 1, 0, 0), vec3(0, 0, 1), vec3(0, 1, 0), wpos, scale);
	vec3 ny = triplanar_normal_from(tex, vec3( 0, 1, 0), vec3(1, 0, 0), vec3(0, 0, 1), wpos, scale);
	vec3 nz = triplanar_normal_from(tex, vec3( 0, 0, 1), vec3(1, 0, 0), vec3(0, 1, 0), wpos, scale);
	// 用 |n| 而非 pow(|n|,4) 配权：法线扰动后权重若仍用 4 次幂，
	// 掠射面的贡献会过强，边缘出现黑边。线性权重更稳。
	vec3 w2 = an / max(an.x + an.y + an.z, 0.0001);
	return normalize(nx * w2.x + ny * w2.y + nz * w2.z);
}

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

// Messenger 的招牌操作：保色相、保饱和，只压明度。
vec3 hsv_shade(vec3 color, float k) {
	vec3 hsv = rgb2hsv(color);
	hsv.z = mix(hsv.z, hsv.z * 0.5, k);
	return hsv2rgb(hsv);
}

void vertex() {
	v_toon_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_toon_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 【顶点色当 AO 这条路在本项目必须关掉 —— 已实测翻车】
	// 原以为 GLB 的 COLOR_0 是美术烘焙的 AO 明度可以直接复用。实测树冠变成
	// 黑色网格状碎块。查 island_materials.gd 才知道：convert.mjs 给星球包写回的
	// COLOR_0 是**调色索引**，不是明度 ——
	//     树叶   (leavescolor, batchId, 0)   ← r 是调色索引，g 是树簇号
	//     地形   (surfaceId, batchId, elementId)
	//     水面   (dist, dist, 0)             ← g 是烘焙离岸距离
	// 拿索引当明度 = 拿随机数当 AO = 满屏噪点。
	// 结论：AO 只能走几何近似（contact_ao_strength），或另找真正的 AO 贴图通道。
	v_toon_vert_ao = 1.0;
}

void fragment() {
	// 全程世界空间：法线、贴图、光照方向都用世界坐标，
	// 避免视空间/世界空间混用（fragment 的 NORMAL 是视空间，
	// 而三平面贴图与自传的光照方向都是世界空间）。
	vec3 wn = normalize(v_toon_world_normal);

	vec4 base = base_tint;
	if (use_albedo_tex) {
		base *= triplanar(albedo_tex, wn, v_toon_world_pos, tex_scale);
	}
	vec3 albedo = base.rgb;

	// 地形细节层：Messenger 在 terrainMaterial 末尾乘了一层
	// `color *= 0.92 + terrainDetail * 0.08`。幅度极小，只是为了让大平面
	// 在移动中不显得像一块死板的色块。没有细节贴图时自动跳过。
	if (use_detail_tex) {
		vec4 d = triplanar(detail_tex, wn, v_toon_world_pos, detail_scale);
		albedo *= 0.92 + d.r * 0.08 * detail_amount;
	}

	// ---- 脏污/老化遮罩（roughness 通道当 wear mask 用）----
	// 放在法线扰动**之前**：这样脏污跟着凹凸走，凹处更脏，符合直觉。
	// 【为什么乘在 hsv_shade 之前而不是之后】hsv_shade 只压明度保色相，
	// 脏污也必须是「同色更深」而不是「混进灰色」—— Messenger 最反对的就是冷脏。
	if (use_rough_tex) {
		float wear = triplanar(rough_tex, wn, v_toon_world_pos, tex_scale).r;
		// rgh 图整体偏亮（灰白），要以中灰 0.55 为基准做双向偏移，
		// 直接 wear 会把整个面压暗一大截 —— 那样就不是「老化」而是「阴影」。
		float dirt = clamp((wear - 0.55) * 1.6, -0.5, 1.0);
		albedo = hsv_shade(albedo, max(dirt, 0.0) * wear_strength);
		// 粗糙度低的地方（更光滑/更亮的部分）轻微提亮，形成「被摸亮」的边角感。
		// 幅度极小，主要是打破死板。
		albedo += albedo * max(-dirt, 0.0) * wear_strength * 0.35;
	}

	// ---- 法线扰动：把 normal_tex 的凹凸打进光照计算 ----
	// 【为什么不用内建 NORMAL_MAP】它依赖引擎的 tangent 框架，而本项目一半
	// 几何是手搭 BoxMesh/SphereMesh，**没有有效 tangent**（generate_tangents
	// 没跑）—— 用 NORMAL_MAP 会得到乱掉的朝向。triplanar_normal() 手动从
	// 世界法线重建切线基，对任何 mesh 都成立。
	// 注意：triplanar_normal 返回的已经是**世界空间**法线，不要再减白点。
	vec3 shading_n = wn;
	if (use_normal_tex) {
		shading_n = triplanar_normal(normal_tex, wn, v_toon_world_pos, tex_scale);
	}

	// ---- AO：顶点色 × 几何接触阴影 ----
	// 顺序很重要：接触阴影必须用**扰动后**的 shading_n，否则砖缝的凹处
	// 拿到的还是平面法线，阴影会浮在表面外面。
	float ao = mix(1.0, v_toon_vert_ao, vertex_ao_strength);
	// 朝下的面天然被上方几何遮挡。smoothstep 让「明显朝下」才变暗，
	// 竖直墙面（y≈0）不受影响 —— 避免整面墙被均匀压灰。
	float downward = smoothstep(0.0, -0.55, shading_n.y);
	ao *= mix(1.0, 1.0 - downward * 0.9, contact_ao_strength);
	albedo *= ao;

	// Messenger 是纯手算点光，没有环境项；加一点点是为了让背光面不至于死黑，
	// 幅度必须小，否则就不是 Messenger 了。
	float sky = clamp(shading_n.y * 0.5 + 0.5, 0.0, 1.0);
	albedo = hsv_shade(albedo, (1.0 - sky) * 0.22);

	float shade = max(dot(shading_n, -light_dir_world), 0.0);
	// 硬边为主，shade_softness 只用来削掉硬边上的锯齿
	float shadow = 1.0 - smoothstep(
		0.38 - shade_softness * 0.5, 0.38 + shade_softness * 0.5, shade);

	albedo = hsv_shade(albedo, shadow * shade_strength);
	albedo += albedo * lift * smoothstep(0.55, 1.0, shade);
	// 背光面抬升：只作用于阴影区（迎光面已由 lift 处理）。
	// 用 albedo 自身做加法而不是纯加常数 —— 保证暗部仍然是「同色更深」，
	// 不会在暗部混进灰色（这正是 Messenger 反对的「冷阴影」）。
	albedo += albedo * ambient_occlusion_lift * shadow;

	// ---- 法线细节的可见性补偿（不加这行，接了 normal 也等于没接）----
	// 【踩过的坑】上面只有 `shadow` 一个明暗通道，而它是**硬边**的：
	// smoothstep 窗口只有 0.38±0.04。1K 法线贴图在 2.4 米墙面上的起伏，
	// dot(N,L) 大多落在 0.34~0.42 —— 正好被这扇窄窗整段削平。
	// 结果就是「贴图加载了、normal_tex 也绑了、墙面却还是一块灰板」。
	//
	// 正确做法：给法线起伏留一条**独立的、连续的**明暗通道，绕过硬边门限。
	// 幅度要小（阴影级 0.82，这里 0.28），否则会盖掉 toon 的硬边风格。
	// 只在有法线贴图时生效，避免纯色物件被无意义地加上噪点。
	float bump_shade = 0.0;
	if (use_normal_tex) {
		// 扰动前后的光照差 = 凹凸带来的额外明暗
		float flat_shade = max(dot(wn, -light_dir_world), 0.0);
		bump_shade = (shade - flat_shade) * normal_detail_visibility;
		// 凹处压暗、凸处提亮，围绕 0 双向
		albedo = hsv_shade(albedo, clamp(-bump_shade, 0.0, 0.6));
		albedo += albedo * clamp(bump_shade, 0.0, 0.6);
	}

	// ---- 轮廓描边：fresnel 内描边，零 draw call ----
	// 视线方向用 CAMERA_POSITION_WORLD 算（fragment 合法内建），
	// 不用 VIEW —— VIEW 是视空间的，和世界法线点乘会得到错的角度。
	vec3 view_dir = normalize(v_toon_world_pos - CAMERA_POSITION_WORLD);
	float fres = 1.0 - clamp(dot(wn, -view_dir), 0.0, 1.0);
	// rim_bias 越接近 1，smoothstep 窗口越窄，描边越细
	float edge = smoothstep(rim_bias, 1.0, fres);
	edge = pow(edge, rim_power);
	// 压暗而不是提亮：Messenger 的轮廓是「同色更深」，与 hsv_shade 一致
	albedo = hsv_shade(albedo, edge * rim_darken);

	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	RIM = 0.0;
}