class_name TexAudit
extends RefCounted
## 贴图覆盖率审计：回答「哪些模型还是纯色裸模」。
##
## 【为什么需要这个工具】项目里「有没有贴图」有三套互不相通的来源
## （assets/tex 的照片贴图、Kenney 的 colormap、星球包的调色板+噪声），
## 靠读代码判断「哪个物件挂了图」必然漏判 —— 必须遍历**真实运行中的场景**，
## 逐个材质问「你挂了纹理吗」。这也是唯一能回答用户那句
## 「确保几乎所有模型都有贴图，不要纯的裸的」的验收方式。
##
## 判定规则（材质级）：
##   StandardMaterial3D  → albedo_texture / detail_albedo / normal_texture 任一非空即算有图
##   ShaderMaterial      → 按 shader 路径查它自己的纹理开关（toon 的 use_albedo_tex、
##                          foliage 的 use_leaf_tex、island_flat 的 use_uv…）
##   其他 / null         → 算裸（null 材质在引擎里就是默认白）
##
## 产物：out/tex_probe.txt（分组覆盖率 + 裸材质清单）+ 控制台摘要
## 用法：godot --headless --path . --quit-after 3000 res://scenes/street.tscn -- --shot-action=probe_tex


## 材质是否挂了纹理。true = 有图，false = 需要细看（可能是玻璃/自发光的有意留白）。
static func has_tex(m: Material) -> bool:
	if m == null:
		return false
	if m is ShaderMaterial:
		return _shader_has_tex(m as ShaderMaterial)
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		return b.albedo_texture != null or b.normal_texture != null \
			or b.detail_albedo != null
	return false


## 有意不贴图的材质：玻璃（贴了立刻变浑）、自发光/UNSHADED 灯箱与霓虹
## （贴图会被自发光盖住，纯属浪费采样）、背景星空。
## 【为什么要单列】把它们算进「裸模」会让验收数字失真 —— 强行给光源糊一张
## 砖纹贴图，画面只会变脏，不会变好。所以覆盖率只统计「本该有表面纹理」的件。
static func is_intentional_bare(m: Material) -> bool:
	if m == null:
		return true
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
		if b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			return true
		if b.emission_enabled:
			return true
		return false
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		var sh := sm.shader
		if sh != null and sh.resource_path.ends_with("water.gdshader"):
			return false
	return false


## ShaderMaterial 没有「列出全部参数」的 API，只能按已知的纹理开关逐个问。
## 新增 shader 时**必须**在这里登记，否则会被误判成裸模。
static func _shader_has_tex(m: ShaderMaterial) -> bool:
	var sh := m.shader
	if sh == null:
		return false
	var path := sh.resource_path
	# 星球包：terrain / water / leaves / cloud 四个 shader 各自硬绑了噪声或遮罩贴图
	if path.ends_with("island_terrain.gdshader") or path.ends_with("island_water.gdshader") \
			or path.ends_with("island_leaves.gdshader") or path.ends_with("island_cloud.gdshader"):
		return true
	# island_flat：use_uv=true 时采样调色板，false 时退化成纯色平涂（那就是裸模）
	if path.ends_with("island_flat.gdshader"):
		return bool(m.get_shader_parameter("use_uv"))
	if path.ends_with("toon.gdshader"):
		return bool(m.get_shader_parameter("use_albedo_tex")) \
			or bool(m.get_shader_parameter("use_detail_tex")) \
			or bool(m.get_shader_parameter("use_normal_tex")) \
			or bool(m.get_shader_parameter("use_rough_tex"))
	if path.ends_with("foliage.gdshader"):
		return bool(m.get_shader_parameter("use_leaf_tex"))
	# 兜底：任一常见纹理参数名有值就算有图（避免新 shader 被判裸）
	for k in ["albedo_tex", "noise_tex", "leaf_mask", "detail_tex", "base_tex"]:
		var v: Variant = m.get_shader_parameter(k)
		if v is Texture2D:
			return true
	return false


## 人类可读的材质标签：文件名优先，其次材质自身名字，最后类型名。
static func mat_label(m: Material) -> String:
	if m == null:
		return "null"
	if m is ShaderMaterial:
		var sh: Shader = (m as ShaderMaterial).shader
		if sh != null and sh.resource_path != "":
			return sh.resource_path.get_file().get_basename()
	if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture != null:
		var t: Texture2D = (m as BaseMaterial3D).albedo_texture
		return "photo:" + t.resource_path.get_file().get_basename()
	return m.get_class() + ":" + (m.resource_name if m.resource_name != "" else "-")


## 一次统计：一组节点里有多少可见面、多少裸面、裸面都是什么材质。
static func stat_node(root: Node) -> Dictionary:
	var total := 0
	var bare := 0
	var skip := 0
	var bare_mats := {}
	var labels := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D and not (n as GeometryInstance3D).is_visible_in_tree():
			pass   # 不可见的不算「玩家看到的裸模」
		elif n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree():
				for i in mi.mesh.get_surface_count():
					# 【三处取材质，顺序不能反】手搭几何体走 material_override
					# （box/cyl/sph 都往这儿塞），GLB 走 surface 材质，
					# surface_override 优先级最高。只读 surface 材质的话，
					# 满场 material_override 会被误判成「null 材质 = 裸模」。
					var m: Material = mi.get_surface_override_material(i)
					if m == null:
						m = mi.material_override
					if m == null and i < mi.mesh.get_surface_count():
						m = mi.mesh.surface_get_material(i)
					total += 1
					var lb := mat_label(m)
					labels[lb] = int(labels.get(lb, 0)) + 1
					if not has_tex(m):
						if is_intentional_bare(m):
							skip += 1
						else:
							bare += 1
							bare_mats[lb] = int(bare_mats.get(lb, 0)) + 1
		elif n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			if mmi.multimesh != null and mmi.is_visible_in_tree():
				# 【MultiMeshInstance3D 没有 material 属性】它的渲染材质来自
				# multimesh.mesh 的 surface 材质，或整个网格共用的 material_override
				# （散落装饰正是后者）。两个都要看，否则会把 140 件装饰全判成裸模。
				var src_mesh := mmi.multimesh.mesh
				if src_mesh != null:
					for i in src_mesh.get_surface_count():
						var m: Material = mmi.material_override
						if m == null:
							m = src_mesh.surface_get_material(i)
						total += 1
						var lb := mat_label(m)
						labels[lb] = int(labels.get(lb, 0)) + 1
						if not has_tex(m):
							if is_intentional_bare(m):
								skip += 1
							else:
								bare += 1
								bare_mats[lb] = int(bare_mats.get(lb, 0)) + 1
		for c in n.get_children():
			stack.append(c)
	return {"total": total, "bare": bare, "skip": skip, "bare_mats": bare_mats, "labels": labels}


## 分组标签：Interactable 用 kind，其余按最近的有名容器分组。
static func group_of(n: Node) -> String:
	var p: Node = n.get_parent()
	while p != null:
		if p is Interactable:
			return "kind:" + (p as Interactable).kind
		p = p.get_parent()
	return ""


static func _fmt_counter(d: Dictionary, limit := 4) -> String:
	var keys: Array = d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	var parts: Array[String] = []
	for i in mini(limit, keys.size()):
		parts.append("%s×%d" % [keys[i], d[keys[i]]])
	if keys.size() > limit:
		parts.append("…+%d 种" % (keys.size() - limit))
	return ", ".join(parts)


## 主流程。host 是 street（用来 add_child 临时实例）。
static func run_all(host: Node) -> void:
	var out: Array[String] = []
	var grand_total := 0
	var grand_bare := 0
	var grand_skip := 0

	# ---- 1. 真实运行中的世界 ----
	out.append("=== 1. 运行中的世界（真实场景树）===")
	var by_group := {}
	var g_total := 0
	var g_bare := 0
	var g_skip := 0
	var g_bare_mats := {}
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var g := group_of(n)
		if g == "":
			# 非 Interactable：按顶层子节点名分组
			var t := n
			while t.get_parent() != null and t.get_parent() != host:
				t = t.get_parent()
			g = "world:" + str(t.name)
		if not by_group.has(g):
			by_group[g] = {"total": 0, "bare": 0, "skip": 0, "mats": {}}
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			var s := stat_node(n)
			var rec: Dictionary = by_group[g]
			rec["total"] = int(rec["total"]) + int(s["total"])
			rec["bare"] = int(rec["bare"]) + int(s["bare"])
			rec["skip"] = int(rec["skip"]) + int(s["skip"])
			var mats: Dictionary = rec["mats"]
			for k: String in s["bare_mats"]:
				mats[k] = int(mats.get(k, 0)) + int(s["bare_mats"][k])
		for c in n.get_children():
			stack.append(c)
	for g: String in by_group:
		var rec2: Dictionary = by_group[g]
		g_total += int(rec2["total"])
		g_bare += int(rec2["bare"])
		g_skip += int(rec2["skip"])
		for k: String in rec2["mats"]:
			g_bare_mats[k] = int(g_bare_mats.get(k, 0)) + int(rec2["mats"][k])
		out.append("  %-28s 面=%-5d 裸=%-5d %s" % [g, rec2["total"], rec2["bare"],
			_fmt_counter(rec2["mats"]) if int(rec2["bare"]) > 0 else ""])
	grand_total += g_total
	grand_bare += g_bare
	grand_skip += g_skip

	# ---- 2. 全部 META kind 逐个实例化 ----
	out.append("")
	out.append("=== 2. 全部物件 kind（Interactable.META 逐个建）===")
	for kind: String in Interactable.META:
		var it := Interactable.make({"kind": kind, "x": 12, "y": 34})
		host.add_child(it)
		await host.get_tree().process_frame
		var s := stat_node(it)
		grand_total += int(s["total"])
		grand_bare += int(s["bare"])
		grand_skip += int(s["skip"])
		for k: String in s["bare_mats"]:
			g_bare_mats[k] = int(g_bare_mats.get(k, 0)) + int(s["bare_mats"][k])
		out.append("  %-16s 面=%-4d 裸=%-4d %s" % [kind, s["total"], s["bare"],
			_fmt_counter(s["bare_mats"]) if int(s["bare"]) > 0 else "OK"])
		it.queue_free()
	await host.get_tree().process_frame

	# ---- 3. 全部外部模型（GLB/gltf） ----
	out.append("")
	out.append("=== 3. 外部模型（assets/models 全量 spawn）===")
	for rel in _list_models():
		var inst := ModelUtil.spawn(host, rel, Vector3(500, 0, 500), 0.0)
		if inst == null:
			out.append("  %-28s 载入失败" % rel)
			continue
		await host.get_tree().process_frame
		var s := stat_node(inst)
		grand_total += int(s["total"])
		grand_bare += int(s["bare"])
		grand_skip += int(s["skip"])
		for k: String in s["bare_mats"]:
			g_bare_mats[k] = int(g_bare_mats.get(k, 0)) + int(s["bare_mats"][k])
		var tag := "OK" if int(s["bare"]) == 0 else "裸 %d/%d" % [s["bare"], s["total"]]
		out.append("  %-28s 面=%-4d %-12s %s" % [rel, s["total"], tag,
			_fmt_counter(s["bare_mats"]) if int(s["bare"]) > 0 else ""])
		inst.queue_free()
		await host.get_tree().process_frame

	# ---- 4. 室内模板 ----
	out.append("")
	out.append("=== 4. 室内模板（data/interiors.json 全量）===")
	for tid: String in _interior_ids():
		var b := InteriorBuilder.new()
		host.add_child(b)
		b.setup(tid, "probe")
		await host.get_tree().process_frame
		var s := stat_node(b)
		grand_total += int(s["total"])
		grand_bare += int(s["bare"])
		grand_skip += int(s["skip"])
		for k: String in s["bare_mats"]:
			g_bare_mats[k] = int(g_bare_mats.get(k, 0)) + int(s["bare_mats"][k])
		out.append("  %-16s 面=%-4d 裸=%-4d %s" % [tid, s["total"], s["bare"],
			_fmt_counter(s["bare_mats"]) if int(s["bare"]) > 0 else "OK"])
		b.queue_free()
		await host.get_tree().process_frame

	out.append("")
	out.append("=== 汇总 ===")
	var judged := maxi(grand_total - grand_skip, 1)
	out.append("  可见面总数 = %d" % grand_total)
	out.append("  应有表面纹理的面 = %d（已扣除玻璃/自发光等有意无图 %d 面）" % [judged, grand_skip])
	out.append("  覆盖率 = %.1f%%（裸面 %d）"
		% [100.0 * float(judged - grand_bare) / float(judged), grand_bare])
	out.append("  裸材质排行：%s" % _fmt_counter(g_bare_mats, 12))

	DirAccess.make_dir_recursive_absolute("res://out")
	var f := FileAccess.open("res://out/tex_probe.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(out) + "\n")
		f.close()
	print("[tex_probe] ", "\n".join(out))


## 性能对照：跑 180 帧后打印 FPS / draw call / 三角面 / 材质数。
## 用途：给「全场景上贴图」这个改动一个客观数字，而不是靠感觉说没掉帧。
## 【为什么单独一个入口】run_all() 会把上百个模型实例进场景，测出来的数没意义。
## 性能对照：跳过前 120 帧预热，再对 180 帧取平均。
## 【为什么要取平均】单帧读数在这台机器上抖动极大（同一场景两次读到 27 / 111），
## 拿单点数字下结论会得到完全相反的两次结论。预热期还包含贴图上传与着色器编译。
static func perf(host: Node) -> void:
	for i in 120:
		await host.get_tree().process_frame
	var samples: Array[float] = []
	var draws := 0
	var tris := 0
	for i in 180:
		await host.get_tree().process_frame
		samples.append(Performance.get_monitor(Performance.TIME_FPS))
		draws += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		tris += int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var sum := 0.0
	var lo := 9999.0
	var hi := 0.0
	for s: float in samples:
		sum += s
		lo = minf(lo, s)
		hi = maxf(hi, s)
	var avg := sum / maxf(float(samples.size()), 1.0)
	var line := "[perf] FPS 平均=%.1f 区间=[%.0f..%.0f] draw_calls=%d primitives=%d" % [
		avg, lo, hi, draws / maxi(samples.size(), 1), tris / maxi(samples.size(), 1)]
	print(line)
	var f := FileAccess.open("res://out/perf.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(line + "\n")
		f.close()
static func _list_models() -> Array[String]:
	var out: Array[String] = []
	_walk_models("res://assets/models", out)
	out.sort()
	return out


static func _walk_models(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		var low := f.to_lower()
		if low.ends_with(".glb") or low.ends_with(".gltf"):
			# 保持完整 res:// 路径。ModelUtil.scene() 对不以 res:// 开头的相对路径
			# 会去 res://assets/models/ 下找 —— 剥掉前缀会全部「载入失败」，
			# 探针就会静默地把 80 多个模型全判成没检查。
			out.append(dir_path + "/" + f)
	for sub in d.get_directories():
		_walk_models(dir_path + "/" + sub, out)


static func _interior_ids() -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open("res://data/interiors.json", FileAccess.READ)
	if f == null:
		return out
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		var tpl: Variant = (parsed as Dictionary).get("templates", {})
		if tpl is Dictionary:
			for k: String in (tpl as Dictionary):
				out.append(k)
	return out
