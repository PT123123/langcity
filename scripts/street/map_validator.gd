class_name MapValidator
extends RefCounted
## 地图合法性校验器：给 planet.json 的每个物件打「落点分 + 处置建议」，并检查整个
## 可走区域是否被物件割裂。回答的是「这栋楼能不能放这儿」，不是「这栋楼好不好看」。
##
## 【和 curate_planet 的分工】
##   curate_planet 是「修」—— 找到坏落点就螺旋搬迁并写回 planet.json（会改数据）。
##   MapValidator 是「查」—— 只读评估、打分、出报告，绝不改数据。先查再决定修不修。
##   两者的落点质量判据同源（射线命中/坡度/孤峰/占地平整/海面海拔），本类把
##   「合格与否」升级成「Score + ACCEPT/MOVE/ROTATE/REJECT」，并新增两项 curate 没有的：
##     1. 真实 AABB 互叠（curate 只用中心弧距粗筛，会漏掉「长条建筑斜着压过来」）；
##     2. NavMesh 连通性（curate 完全不查 —— 它不知道楼把路堵死了）。
##
## 【为什么用运行时烘焙的真 NavMesh，而不是射线网格】实测地形上烘焙只要
## parse≈90ms / bake≈270ms（2864 多边形），代价可接受；而且 NavMesh 的
## agent_radius/max_climb 会把「猫能钻过去的缝」和「钻不过去的墙」按真实体量
## 判出来，这是射线网格拼不出的。见 _bake()。
##
## 【路线冲突怎么查】星球道路是烘焙进地形 GLB 的，planet.json 里没有道路数据，
## 所以不能直接做「建筑 footprint ∩ 道路掩码」。本类改用功能等价判据：
##   烘焙两遍 NavMesh —— 只含地形 vs 含地形+建筑代理盒；
##   若某处「原本可达」在加了建筑后变成「不可达/孤岛」，就是建筑堵的路。
## 这正是文档第 5 节的做法，且不依赖任何道路数据。
##
## 产物：由调用方（_tools/map_validate.gd）写 out/map_validate.txt + 撒标记球。
## 用法：Godot_v4.4.1-stable_win64_console.exe --path . res://_tools/map_validate.tscn

## 占地悬空判定：脚下地面比基座低过这么多米 = 悬空（猫能从底下钻过去）。
## 【为什么不能只打中心一点】中心射线永远贴在台上，量不出「地皮塌在旁边」——
## 这正是「楼悬在天上、能从底下走」的根因。必须按物件真实矩形四角取样。
const FOOT_FLOAT_TOL := 0.5
## 占地半埋判定：脚下地面比基座高过这么多米 = 陷进坡里
const FOOT_SINK_TOL := 1.0
## 孤峰探测：四周采样半径（米）与「明显更低」的判定落差（米）
const SPIKE_DIST := 2.5
const SPIKE_DROP := 2.5
## 坡度阈值（法线·径向）：大件要平（楼不能站坡上），小道具可以斜
const DOT_MIN_BIG := 0.86
const DOT_MIN_PROP := 0.72
## 海拔门槛余量（米）：落点必须在 water_radius + 这个值之上，否则算「摆进海里」
const WATER_MARGIN := 0.35
## 互叠容差（米）：小于此不算重叠（低多边 diorama 本就允许墙角轻微咬合）
const OBB_TOL := 0.25
## 打分阈值
const ACCEPT_MIN := 85.0
const MOVE_MIN := 55.0
## 「大件」判定：footprint 半长边 ≥ 此值（米）即为建筑/车辆级，参与互叠与 NavMesh 代理
const BIG_HALF := 1.0

## NavMesh 烘焙参数（按猫的体量：半径 0.15 / 高 0.36，留一点余量）
## 【坡度必须跟玩法一致】Player.floor_max_angle = 60°，烘焙也设 60° —— 设 45°
## 会把 45~60° 的坡面切成不可走，本来连续的小镇被切成一堆孤立平台（实测
## 45° 时基线碎成 261 个连通域，主域只剩 1801㎡）。
const NAV_CELL := 0.5
const NAV_CELL_H := 0.25
## 【必须是 NAV_CELL 的整数倍】否则 Godot 把 agent_radius 向上取整到 1 体素并
## 打印「loses precision」警告（0.4→0.5）。直接取整倍数：意图与实际一致，警告消失。
const NAV_AGENT_R := 0.5
const NAV_AGENT_H := 0.5        # 必须是 NAV_CELL_H 的整数倍（0.5/0.25=2）
const NAV_MAX_CLIMB := 0.5      # 必须是 NAV_CELL_H 的整数倍，否则同上
const NAV_MAX_SLOPE := 60.0
const NAV_MIN_REGION := 2.0
## 只吃地形碰撞这一层：PlanetBody.collision_layer = 3（地形），水面 WaterBody = 1。
## 掩码 2 命中地形、排除水面 —— 否则水壳会被当成可行走面。见 PlanetBuilder。
const NAV_TERRAIN_LAYER := 2


# ================================================================
# 主入口
# ================================================================

## 校验 objects（planet.json 的 objects 数组）。nav_root 是已建好 PlanetBuilder
## 的父节点（用于烘焙 NavMesh）；传 null 则跳过连通性检查。
## 返回 {results, counts, nav, lines}。
static func validate(builder: PlanetBuilder, math: PlanetMath, world_px: Vector2,
		objects: Array, nav_root: Node3D = null, opts: Dictionary = {}) -> Dictionary:
	var do_nav: bool = bool(opts.get("navmesh", true)) and nav_root != null

	var n := objects.size()
	var results: Array[Dictionary] = []
	results.resize(n)

	# ---- 1. 逐物件落点评估 ----
	for i in n:
		var obj: Dictionary = objects[i]
		results[i] = _eval_object(builder, math, world_px, obj, i)

	# ---- 2. 大件 AABB 互叠 ----
	_eval_overlaps(math, world_px, objects, results)

	# ---- 3. 定裁决（打分与判据解耦）----
	finalize(results)

	# ---- 4. NavMesh 连通性 ----
	var nav := {}
	if do_nav:
		nav = _check_navmesh(nav_root, math, world_px, objects, results)

	# ---- 4. 汇总 ----
	var counts := {"ACCEPT": 0, "MOVE": 0, "ROTATE": 0, "REJECT": 0, "SKIP": 0}
	for r: Dictionary in results:
		counts[r["verdict"]] = int(counts.get(r["verdict"], 0)) + 1

	var lines := _format(results, counts, nav, objects)
	return {"results": results, "counts": counts, "nav": nav, "lines": lines}


# ================================================================
# 落点质量（射线判据，与 curate_planet 同源）
# ================================================================

static func _eval_object(builder: PlanetBuilder, math: PlanetMath, world_px: Vector2,
		obj: Dictionary, idx: int) -> Dictionary:
	var kind := String(obj.get("kind", ""))
	var px := Vector2(float(obj.get("x", 0)), float(obj.get("y", 0)))
	var yaw := deg_to_rad(float(obj.get("rot", 0.0)))
	var dir := math.dir_from_px(px, world_px)
	var half := _foot_half(obj)
	var is_big := maxf(half.x, half.y) >= BIG_HALF

	var rec := {
		"i": idx, "kind": kind, "px": px, "dir": dir, "yaw": yaw,
		"half": half, "rects": _foot_rects(obj), "h": _height(obj), "big": is_big,
		"score": 100.0, "verdict": "ACCEPT", "issues": [] as Array[String],
		"pos": dir * math.radius, "normal": dir, "hit": false, "r": 0.0,
		"slope": 1.0, "spike": 0, "foot_bad": 0, "overlaps": [] as Array[Dictionary],
	}

	if _should_skip(obj, kind):
		rec["verdict"] = "SKIP"
		return rec

	var spot := builder.surface(dir)
	var hit: bool = bool(spot.get("hit", false))
	rec["hit"] = hit
	var pos: Vector3 = spot["pos"]
	var nrm: Vector3 = (spot["normal"] as Vector3).normalized()
	rec["pos"] = pos
	rec["normal"] = nrm

	if not hit:
		rec["score"] = 0.0
		(rec["issues"] as Array).append("射线落空（岛外/海面 → 走标称球面兜底 = 悬空）")
		rec["verdict"] = "REJECT"
		return rec

	var r0 := pos.length()
	rec["r"] = r0
	var dot_min: float = DOT_MIN_BIG if is_big else DOT_MIN_PROP
	var slope: float = nrm.dot(pos.normalized())
	rec["slope"] = slope
	# 基座面所在半径：物件可被 y_lift 沿当地法线下沉/抬起（室内屋台），也可能有 plinth
	# 地基把脚下填起来（「楼悬在坡上、底下能钻过去」的正解）。悬空/半埋必须按「实际
	# 支撑面」量，否则填了地基校验器还报悬空。
	var base_r := r0 + float(obj.get("y_lift", 0.0)) - float(obj.get("plinth", 0.0))

	var issues: Array[String] = rec["issues"]
	var pen := 0.0
	var hard := false

	# 海拔：落点在海面之下 = 摆进海里（海底也是地形，射线全合格）。
	# 【必须重罚，不能只置 hard】置 hard 只影响裁决；候选搜索是拿 score 排序的，
	# 海里若还留 100 分，修图时会把物件往海里搬（实测把 car/library/furniture 搬进海）。
	if builder.water_radius > 0.0 and r0 < builder.water_radius + WATER_MARGIN:
		issues.append("落点在海面下 r=%.1f < %.1f" % [r0, builder.water_radius + WATER_MARGIN])
		hard = true
		pen += 100.0

	# 坡度
	if slope < dot_min:
		issues.append("坡太陡 dot=%.2f < %.2f" % [slope, dot_min])
		pen += clampf((dot_min - slope) * 200.0, 0.0, 60.0)

	# 孤峰/树干顶：脚下平但四周陡降
	var n_drop := 0
	for t in 4:
		var nd := _offset_dir(math, pos.normalized(), TAU * float(t) / 4.0, SPIKE_DIST)
		var nh := _ray(builder, nd)
		if nh.is_empty() or (nh["pos"] as Vector3).length() < r0 - SPIKE_DROP:
			n_drop += 1
	rec["spike"] = n_drop
	if n_drop >= 2:
		issues.append("邻域塌陷 %d/4（树干顶/崖边探头）" % n_drop)
		pen += float(n_drop) * 15.0

	# 占地平整：按物件真实矩形（每个子盒的四角 + 中心）取样，量「脚下地面比基座低多少」。
	# 【这是「楼悬在天上」的主检测】低过 FOOT_FLOAT_TOL 就是地皮塌在旁边、猫能从底下钻过。
	# 采样点用物件自身的带 yaw 切平面基展开 —— 只按固定半径转一圈会漏掉矩形长边的外伸角。
	if is_big:
		# basis_at 已经含 yaw（X=物件局部 X，Z=物件局部 Z），子盒坐标直接乘，
		# 不能再手动转一次 yaw（那会转两遍，采样点落到错误方位）。
		var b := math.basis_at(pos.normalized(), yaw)
		var Xo := b.x
		var Zo := b.z
		var max_drop := 0.0
		var max_rise := 0.0
		var bad := 0
		for r: Dictionary in rec["rects"]:
			var rc: Vector2 = r["c"]
			var rh: Vector2 = r["h"]
			var pts: Array = [
				rc + Vector2(-rh.x, -rh.y), rc + Vector2(rh.x, -rh.y),
				rc + Vector2(rh.x, rh.y), rc + Vector2(-rh.x, rh.y), rc,
			]
			for p: Vector2 in pts:
				var nd := (pos + Xo * p.x + Zo * p.y).normalized()
				var nh := _ray(builder, nd)
				if nh.is_empty():
					bad += 1
					max_drop = maxf(max_drop, 99.0)
					continue
				var drop := base_r - (nh["pos"] as Vector3).length()
				if drop > 0.0:
					max_drop = maxf(max_drop, drop)
				else:
					max_rise = maxf(max_rise, -drop)
		rec["max_drop"] = max_drop
		rec["foot_bad"] = bad
		if max_drop > FOOT_FLOAT_TOL:
			issues.append("占地悬空 %.2fm（脚下是空的，能钻过去）" % max_drop)
			pen += clampf(max_drop * 30.0, 0.0, 75.0)
		if max_rise > FOOT_SINK_TOL:
			issues.append("占地半埋 %.2fm（陷进坡里）" % max_rise)
			pen += clampf(max_rise * 15.0, 0.0, 40.0)

	rec["score"] = maxf(0.0, 100.0 - pen)
	rec["_hard"] = hard
	return rec


# ================================================================
# 大件互叠（切平面 OBB / SAT）
# ================================================================

## 两个「占地体」的最大穿透深度（米）；不重叠返回 0。
## a/b 需含：dir / pos / yaw / rects（子盒）/ h（身高）。
## 【竖向上门控】两物件都是「脚贴各自地面、往上长 h」，高差不重叠就撞不到 ——
## 星球上山顶的车站与坡底的车水平投影会叠在一起，没有这道门控会误报互叠。
static func _obb_pair(math: PlanetMath, a: Dictionary, b: Dictionary) -> float:
	var dirA: Vector3 = a["dir"]
	var XA := math.basis_at(dirA, float(a["yaw"])).x
	var ZA := math.basis_at(dirA, float(a["yaw"])).z
	var dirB: Vector3 = b["dir"]
	var XB := math.basis_at(dirB, float(b["yaw"])).x
	var ZB := math.basis_at(dirB, float(b["yaw"])).z
	var d: Vector3 = (b["pos"] as Vector3) - (a["pos"] as Vector3)
	var dv := d.dot(dirA.normalized())
	if dv >= float(a["h"]) or dv <= -float(b["h"]):
		return 0.0
	var cB0 := Vector2(d.dot(XA), d.dot(ZA))
	var angB := atan2(XB.dot(ZA), XB.dot(XA))
	var axx := XB.dot(XA)
	var axz := XB.dot(ZA)
	var azx := ZB.dot(XA)
	var azz := ZB.dot(ZA)
	# 逐子盒取最大穿透：house 的院子围墙是 L 形，当成一个整块会虚报互叠
	var depth := 0.0
	for ra: Dictionary in a["rects"]:
		var ca: Vector2 = ra["c"]
		var ha: Vector2 = ra["h"]
		for rb: Dictionary in b["rects"]:
			var cb: Vector2 = rb["c"]
			var hb: Vector2 = rb["h"]
			var c2 := cB0 + Vector2(axx * cb.x + azx * cb.y, axz * cb.x + azz * cb.y)
			depth = maxf(depth, _obb_overlap(ca, ha, 0.0, c2, hb, angB))
	return depth


static func _eval_overlaps(math: PlanetMath, world_px: Vector2, objects: Array,
		results: Array[Dictionary]) -> void:
	var big: Array[int] = []
	for i in results.size():
		if bool(results[i]["big"]) and results[i]["verdict"] != "SKIP" and bool(results[i]["hit"]):
			big.append(i)
	for ai in big.size():
		var a: Dictionary = results[big[ai]]
		for bi in range(ai + 1, big.size()):
			var b: Dictionary = results[big[bi]]
			var depth := _obb_pair(math, a, b)
			if depth > OBB_TOL:
				var dist := ((b["pos"] as Vector3) - (a["pos"] as Vector3)).length()
				(a["overlaps"] as Array).append({"kind": b["kind"], "i": b["i"], "depth": depth, "dist": dist})
				(b["overlaps"] as Array).append({"kind": a["kind"], "i": a["i"], "depth": depth, "dist": dist})
				(a["issues"] as Array).append("与 %s 互叠 %.2fm(中心距%.1fm)" % [b["kind"], depth, dist])
				(b["issues"] as Array).append("与 %s 互叠 %.2fm(中心距%.1fm)" % [a["kind"], depth, dist])

	# 互叠回写进分数/裁决
	for i in results.size():
		var rec: Dictionary = results[i]
		if rec["verdict"] == "SKIP":
			continue
		var ov: Array = rec["overlaps"]
		if ov.is_empty():
			continue
		var pen := 0.0
		var deep := false
		for o: Dictionary in ov:
			pen += 25.0 + float(o["depth"]) * 8.0
			if float(o["depth"]) > 1.5:
				deep = true
		rec["score"] = maxf(0.0, float(rec["score"]) - pen)
		rec["_hard"] = bool(rec.get("_hard", false)) or deep


# ================================================================
# NavMesh 连通性
# ================================================================

## 烘焙一次地形 NavMesh，再把每个大件的 footprint 从可行走面里「扣掉」，
## 比较扣前/扣后的连通性 —— 主域塌缩 = 建筑把路堵死。
## 【为什么不做第二遍烘焙】用代理盒再烘一遍时，代理盒的顶面本身会被烘成
## 可行走面（实测总可行走面积反增 7211→7368㎡），污染统计。改成在已烘好的
## 地形网格上按 footprint 剔除多边形：精确、无伪面，也更快。
## 返回 {baseline, full, cut, note}
static func _check_navmesh(nav_root: Node3D, math: PlanetMath, world_px: Vector2,
		objects: Array, results: Array[Dictionary]) -> Dictionary:
	var out := {"note": "", "baseline": {}, "full": {}, "cut": [] as Array}
	if not nav_root.is_inside_tree():
		out["note"] = "nav_root 不在场景树里，跳过"
		return out

	var nav := _bake(nav_root)
	if nav == null or nav.get_polygon_count() == 0:
		out["note"] = "地形 NavMesh 烘焙为空/失败，跳过连通性检查"
		return out
	var np := nav.get_polygon_count()
	var adj := _poly_adjacency(nav)

	# 基线：全部多边形连通
	var none := PackedByteArray()
	none.resize(np)   # 全 0 = 无阻挡
	var cb := _poly_components(nav, none, adj)
	out["baseline"] = _comp_stats(nav, cb)

	# 把大件 footprint 覆盖的多边形标为不可走（外扩 agent 半径模拟不可通过的
	# 窄缝），并记下「哪个大件挡的」，好把断开区域直接归责到具体建筑。
	var bigs := _big_obbs(results)
	var blocked := PackedByteArray()
	blocked.resize(np)
	var owner := PackedInt32Array()
	owner.resize(np)
	for i in np:
		var o := _poly_block_owner(nav, i, bigs)
		owner[i] = o
		blocked[i] = 1 if o >= 0 else 0
	var cf := _poly_components(nav, blocked, adj)
	out["full"] = _comp_stats(nav, cf)

	# 新增断开区域：masked 里非主域、面积够大、原本属于基线主域。
	# 归责：区域每个多边形的「被挡邻居」的 owner 就是堵路建筑 —— 比按距离
	# 猜「附近大件」准得多（大区域的质心可能离真正的堵点很远）。
	var base_main: int = cb["main"]
	var mask_main: int = cf["main"]
	var groups := {}
	for i in np:
		if blocked[i] == 1:
			continue
		groups.get_or_add(int(cf["comp_of"][i]), []).append(i)
	var cut: Array = []
	for c in groups:
		if c == mask_main:
			continue
		var area := float((cf["areas"] as Dictionary).get(c, 0.0))
		if area < 20.0:
			continue   # 20㎡ 以下多为坡地/崖边平台，不算「路被堵死」
		var polys: Array = groups[c]
		var was_main := false
		var culprits := {}
		var center := Vector3.ZERO
		for i in polys:
			if int(cb["comp_of"][i]) == base_main:
				was_main = true
			center += _poly_center(nav, i)
			for j in adj[i]:
				var ow := int(owner[j])
				if ow >= 0:
					culprits[ow] = true
		if not was_main:
			continue
		center = (center / maxf(float(polys.size()), 1.0)).normalized()
		var names: Array = []
		for ow in culprits:
			names.append(String((bigs[ow] as Dictionary)["kind"]))
		names.sort()
		cut.append({"area": area, "px": math.px_from_dir(center, world_px), "near": names})
	cut.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["area"]) > float(b["area"]))
	out["cut"] = cut
	return out


## 大件的世界切平面 OBB（位置 + 朝向 + 子盒），供多边形剔除用。
static func _big_obbs(results: Array[Dictionary]) -> Array:
	var out: Array = []
	for rec: Dictionary in results:
		if not bool(rec["big"]) or rec["verdict"] == "SKIP" or not bool(rec["hit"]):
			continue
		var dir: Vector3 = rec["dir"]
		var bi := _basis_at_dir(dir, float(rec["yaw"]))
		out.append({
			"kind": rec["kind"], "pos": rec["pos"], "up": dir.normalized(),
			"X": bi.x, "Z": bi.z, "rects": rec["rects"],
		})
	return out


## ================================================================
# 公开 API：给可视化编辑器做「可达性」判定
# ================================================================

## 烘焙地形 NavMesh 并算好基线连通域（不含建筑阻挡）。返回
## {nav, comp_of, areas, main, main_area}；nav 为 null 表示不可用。
## 【为什么单独暴露】编辑器选中一栋楼时要回答「这里走得到吗、是不是孤岛」，
## 需要复用同一套烘焙/连通域口径，而不是另写一份。一次烘焙 ≈0.4s，按需调用并缓存。
static func analyze_navigation(nav_root: Node3D) -> Dictionary:
	if not nav_root.is_inside_tree():
		return {"nav": null}
	var nav := _bake(nav_root)
	if nav == null or nav.get_polygon_count() == 0:
		return {"nav": null}
	var adj := _poly_adjacency(nav)
	var np := nav.get_polygon_count()
	var none := PackedByteArray()
	none.resize(np)
	var comp := _poly_components(nav, none, adj)
	# 【性能】预存多边形中心：reachable_at 会被自动放置逐候选调用，若每次现算
	# _poly_center（内部 get_vertices 会整份拷顶点）会慢到不可用。这里只算一次。
	var verts := nav.get_vertices()
	var centers := PackedVector3Array()
	centers.resize(np)
	for i in np:
		var poly := nav.get_polygon(i)
		var acc := Vector3.ZERO
		for idx in poly:
			acc += verts[idx]
		centers[i] = acc / maxf(float(poly.size()), 1.0)
	return {"nav": nav, "comp_of": comp["comp_of"], "areas": comp["areas"],
		"main": comp["main"], "main_area": comp["main_area"], "centers": centers}


## 世界点附近 tol_m 内是否有可行走面，以及它是否属于主连通域。返回
## {on_nav, main, dist}：on_nav=附近有可行走面；main=其中含主城区；dist=最近距离（米）。
static func reachable_at(navres: Dictionary, world_pos: Vector3, tol_m: float) -> Dictionary:
	var centers: PackedVector3Array = navres.get("centers", PackedVector3Array())
	if navres.get("nav", null) == null or centers.is_empty():
		return {"on_nav": false, "main": false, "dist": -1.0}
	var comp_of: Array = navres["comp_of"]
	var main := int(navres["main"])
	var up := world_pos.normalized()
	var found := false
	var in_main := false
	var best := 1e9
	var tol2 := tol_m * tol_m
	for i in centers.size():
		var d := centers[i] - world_pos
		if absf(d.dot(up)) > 3.0:
			continue   # 不在同一层
		var flat := d - up * d.dot(up)
		var d2 := flat.length_squared()
		if d2 <= tol2:
			found = true
			best = minf(best, sqrt(d2))
			if int(comp_of[i]) == main:
				in_main = true
	return {"on_nav": found, "main": in_main, "dist": best if found else -1.0}


## 公开：评估单个候选落点（射线/坡度/孤峰/占地平整/海拔）。idx 传 -1 即可。
## 供编辑器「自动放置」逐个候选打分用 —— 与 MapValidator 主判据同源。
static func eval_one(builder: PlanetBuilder, math: PlanetMath, world_px: Vector2,
		obj: Dictionary) -> Dictionary:
	return _eval_object(builder, math, world_px, obj, -1)


## 公开：两个「占地体」的最大穿透深度（米）。a/b 用 placed_of(rec) 构造。
static func overlap_depth(math: PlanetMath, a: Dictionary, b: Dictionary) -> float:
	return _obb_pair(math, a, b)


## 公开：从评估结果抽出互叠判定要用的字段 {dir,pos,yaw,rects,h,kind}。
static func placed_of(rec: Dictionary) -> Dictionary:
	return _placed_of(rec)


## 多边形中心落进哪个大件的 footprint（外扩 NAV_AGENT_R）；都不在则返回 -1。
## 返回「谁挡的」而不是「挡没挡」，是为了能把断开区域直接归责到具体建筑。
static func _poly_block_owner(nav: NavigationMesh, i: int, bigs: Array) -> int:
	var c := _poly_center(nav, i)
	for bi in bigs.size():
		var o: Dictionary = bigs[bi]
		var d: Vector3 = c - (o["pos"] as Vector3)
		if absf(d.dot(o["up"])) > 3.0:
			continue   # 不在同一层（上方/下方）
		var lx := d.dot(o["X"])
		var lz := d.dot(o["Z"])
		for r: Dictionary in o["rects"]:
			var rc: Vector2 = r["c"]
			var rh: Vector2 = r["h"]
			if absf(lx - rc.x) <= rh.x + NAV_AGENT_R and absf(lz - rc.y) <= rh.y + NAV_AGENT_R:
				return bi
	return -1


## dir 处绕法线转 yaw 的切平面基（与 PlanetMath.basis_at 等价，独立实现避免
## 每对象 new 一个 PlanetMath）。X=东、Z=南。
static func _basis_at_dir(dir: Vector3, yaw: float) -> Basis:
	var up := dir.normalized()
	var n := Vector3.UP - up * up.y
	if n.length_squared() < 1e-6:
		n = Vector3.RIGHT - up * up.x
	n = n.normalized()
	var e := n.cross(up).normalized()
	var s := -n
	var b := Basis(e, up, s)
	if yaw != 0.0:
		b = b * Basis(Vector3.UP, yaw)
	return b


static func _make_nav() -> NavigationMesh:
	var nav := NavigationMesh.new()
	# 【必须走碰撞体解析，不能走 MeshInstance】
	# 走 MeshInstance 会把子树里所有可见网格都当几何 —— 树冠（tree-leaves）的顶面
	# 会被烘成一块块「可行走孤岛」，水面壳也会变成可行走面，基线连通域直接碎成
	# 382 块（实测）。改吃 PlanetBody 的地形 trimesh 碰撞后基线收敛到个位数。
	# 顺带避开「runtime 解析 RenderingServer 网格」的 GPU 回读警告。
	# 【属性名坑】NavigationMesh 的烘焙参数都带 geometry_ 前缀，
	# 写 parsed_geometry_type 会赋值失败并让整个函数返回 null（随后连锁报错）。
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.geometry_collision_mask = NAV_TERRAIN_LAYER
	nav.cell_size = NAV_CELL
	nav.cell_height = NAV_CELL_H
	nav.agent_radius = NAV_AGENT_R
	nav.agent_height = NAV_AGENT_H
	nav.agent_max_climb = NAV_MAX_CLIMB
	nav.agent_max_slope = NAV_MAX_SLOPE
	nav.region_min_size = NAV_MIN_REGION
	return nav


static func _bake(root: Node) -> NavigationMesh:
	var nav := _make_nav()
	if nav == null:
		return null
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, src, root)
	NavigationServer3D.bake_from_source_geometry_data(nav, src)
	return nav


# ---------------- 连通域（多边形邻接 flood fill，纯 CPU，无服务器时序依赖） ----------------

## 多边形邻接表（共享边的两个多边形互为邻居）。边按顶点位置量化成 key，
## 烘焙出的网格共享边用同一批顶点索引 → 位置完全相等，量化安全。
static func _poly_adjacency(nav: NavigationMesh) -> Array:
	var np := nav.get_polygon_count()
	var verts := nav.get_vertices()
	var adj: Array = []
	adj.resize(np)
	for i in np:
		adj[i] = [] as Array[int]
	var edge := {}
	for i in np:
		var poly := nav.get_polygon(i)
		var m := poly.size()
		for e in m:
			var a := poly[e]
			var b := poly[(e + 1) % m]
			var key := _edge_key(verts[a], verts[b])
			if edge.has(key):
				var j := int(edge[key])
				(adj[i] as Array).append(j)
				(adj[j] as Array).append(i)
			else:
				edge[key] = i
	return adj


## 多边形连通域（并查集）。blocked[i]==1 的多边形视作不存在，不参与连通，
## 这样同一张地形网格既能算「扣建筑前」也能算「扣建筑后」的连通域。
static func _poly_components(nav: NavigationMesh, blocked: PackedByteArray, adj: Array) -> Dictionary:
	var np := nav.get_polygon_count()
	var parent: Array = []
	parent.resize(np)
	for i in np:
		parent[i] = i
	for i in np:
		if blocked[i] == 1:
			continue
		for j in adj[i]:
			if blocked[j] == 0:
				_uf_union(parent, i, j)
	var comp_of: Array = []
	comp_of.resize(np)
	var areas := {}
	for i in np:
		if blocked[i] == 1:
			comp_of[i] = -1
			continue
		var c := _uf_find(parent, i)
		comp_of[i] = c
		areas[c] = float(areas.get(c, 0.0)) + _poly_area(nav, i)
	var main := -1
	var main_area := -1.0
	for c in areas:
		if float(areas[c]) > main_area:
			main_area = float(areas[c])
			main = c
	return {"comp_of": comp_of, "areas": areas, "main": main, "main_area": main_area}


static func _comp_stats(nav: NavigationMesh, comp: Dictionary) -> Dictionary:
	var areas: Dictionary = comp["areas"]
	var main_area := float(comp["main_area"])
	var islands := 0
	var island_area := 0.0
	var total := 0.0
	var top: Array[float] = []
	for c in areas:
		var a := float(areas[c])
		total += a
		top.append(a)
		if c == comp["main"]:
			continue
		# 孤岛 = 面积小于主连通域的 2%（约 <0.5% 行走面）
		if a < main_area * 0.02:
			islands += 1
			island_area += a
	top.sort()
	top.reverse()
	var top5: PackedFloat32Array = []
	for i in mini(5, top.size()):
		top5.append(top[i])
	return {
		"polys": nav.get_polygon_count(),
		"components": areas.size(),
		"main_area": main_area,
		"islands": islands,
		"island_area": island_area,
		"total_area": total,
		"top5": top5,
	}


static func _poly_center(nav: NavigationMesh, i: int) -> Vector3:
	var verts := nav.get_vertices()
	var poly := nav.get_polygon(i)
	var acc := Vector3.ZERO
	for idx in poly:
		acc += verts[idx]
	return acc / maxf(float(poly.size()), 1.0)


static func _poly_area(nav: NavigationMesh, i: int) -> float:
	var verts := nav.get_vertices()
	var poly := nav.get_polygon(i)
	if poly.size() < 3:
		return 0.0
	var v0 := verts[poly[0]]
	var area := 0.0
	for j in range(1, poly.size() - 1):
		var v1 := verts[poly[j]]
		var v2 := verts[poly[j + 1]]
		area += (v1 - v0).cross(v2 - v0).length() * 0.5
	return area


static func _uf_find(parent: Array, x: int) -> int:
	while int(parent[x]) != x:
		parent[x] = parent[parent[x]]
		x = int(parent[x])
	return x


static func _uf_union(parent: Array, a: int, b: int) -> void:
	var ra := _uf_find(parent, a)
	var rb := _uf_find(parent, b)
	if ra != rb:
		parent[rb] = ra


static func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka := _quant(a)
	var kb := _quant(b)
	return (ka + "|" + kb) if ka <= kb else (kb + "|" + ka)


static func _quant(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x * 100.0), roundi(v.y * 100.0), roundi(v.z * 100.0)]


# ================================================================
# 几何工具
# ================================================================

static func _ray(builder: PlanetBuilder, dir: Vector3) -> Dictionary:
	var d := dir.normalized()
	var far := builder.math.radius * 3.0 + 30.0
	var space := builder.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(d * far, d * 0.5, 2)
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	return {"pos": hit["position"], "normal": (hit["normal"] as Vector3).normalized()}


static func _offset_dir(math: PlanetMath, d: Vector3, ang: float, dist_m: float) -> Vector3:
	var a := dist_m / math.radius
	var t := sin(ang) * math.north_at(d) + cos(ang) * math.east_at(d)
	return (d * cos(a) + t * sin(a)).normalized()


## 物件占地的「子盒」列表（局部 x/z 平面，米）：真实碰撞盒 + 附属实心段（如
## house 的院子围墙）逐个列出，而不是并成一个包围矩形 —— L 形院落并成矩形会
## 虚报互叠（实测把相邻民居错判成 2m+ 重叠）。这是权威口径，不需实例化物件。
static func _foot_rects(obj: Dictionary) -> Array:
	var kind := String(obj.get("kind", ""))
	var meta: Dictionary = Interactable.META.get(kind, {})
	var box: Vector3
	var solid: Variant = meta.get("solid", null)
	if solid is Vector3:
		box = solid
	elif meta.has("click"):
		box = meta["click"]
	else:
		box = Vector3(0.8, 0.8, 0.8)
	var out: Array = [{"c": Vector2.ZERO, "h": Vector2(box.x * 0.5, box.z * 0.5)}]
	for ex: Dictionary in meta.get("extra_solids", []):
		var s: Vector3 = ex.get("s", Vector3.ONE)
		var p: Vector3 = ex.get("p", Vector3.ZERO)
		out.append({"c": Vector2(p.x, p.z), "h": Vector2(s.x * 0.5, s.z * 0.5)})
	return out


## 物件高度（米，取自 META 的实心盒 / 点击盒）。互叠判定要用它做「竖向是否重叠」
## 门控 —— 星球上两物件即使水平投影挨着，只要高差超过各自高度就根本撞不到一起。
static func _height(obj: Dictionary) -> float:
	var kind := String(obj.get("kind", ""))
	var meta: Dictionary = Interactable.META.get(kind, {})
	var solid: Variant = meta.get("solid", null)
	if solid is Vector3:
		return (solid as Vector3).y
	if meta.has("click"):
		return (meta["click"] as Vector3).y
	return 1.0


## 物件占地的整体半长边（米）：子盒并集的包络。用于「大件」判定与占地平整度采样半径。
static func _foot_half(obj: Dictionary) -> Vector2:
	var hx := 0.0
	var hz := 0.0
	for r: Dictionary in _foot_rects(obj):
		var c: Vector2 = r["c"]
		var h: Vector2 = r["h"]
		hx = maxf(hx, absf(c.x) + h.x)
		hz = maxf(hz, absf(c.y) + h.y)
	return Vector2(hx, hz)


static func _should_skip(obj: Dictionary, kind: String) -> bool:
	var meta: Dictionary = Interactable.META.get(kind, {})
	if bool(meta.get("novis", false)):
		return true
	if obj.get("hidden", false) == true:
		return true
	return false


static func _obb_overlap(c1: Vector2, h1: Vector2, r1: float,
		c2: Vector2, h2: Vector2, r2: float) -> float:
	var axes := [
		Vector2(cos(r1), sin(r1)), Vector2(-sin(r1), cos(r1)),
		Vector2(cos(r2), sin(r2)), Vector2(-sin(r2), cos(r2)),
	]
	var best := INF
	for ax in axes:
		var p1 := _proj_rect(c1, h1, r1, ax)
		var p2 := _proj_rect(c2, h2, r2, ax)
		var o := minf(p1.y, p2.y) - maxf(p1.x, p2.x)
		if o <= 0.0:
			return 0.0
		best = minf(best, o)
	return best


static func _proj_rect(c: Vector2, h: Vector2, r: float, ax: Vector2) -> Vector2:
	var u := Vector2(cos(r), sin(r))
	var v := Vector2(-sin(r), cos(r))
	var rad := h.x * absf(ax.dot(u)) + h.y * absf(ax.dot(v))
	var mid := c.dot(ax)
	return Vector2(mid - rad, mid + rad)


# ================================================================
# 裁决
# ================================================================

## 在 _eval_object + _eval_overlaps 之后定裁决。单独一个函数是为了让
## 「打分」与「裁决」解耦 —— 阈值调整不用碰判据代码。
static func finalize(results: Array[Dictionary]) -> void:
	for rec: Dictionary in results:
		if rec["verdict"] == "SKIP":
			continue
		var score := float(rec["score"])
		var hard := bool(rec.get("_hard", false))
		var issues: Array = rec["issues"]
		var only_overlap := not (rec["overlaps"] as Array).is_empty() \
			and int(rec["spike"]) == 0 and int(rec["foot_bad"]) == 0 \
			and float(rec["slope"]) >= (DOT_MIN_BIG if bool(rec["big"]) else DOT_MIN_PROP) \
			and bool(rec["hit"])
		if hard or score < MOVE_MIN:
			rec["verdict"] = "REJECT"
		elif only_overlap and score >= MOVE_MIN:
			rec["verdict"] = "ROTATE"
		elif issues.is_empty() and score >= ACCEPT_MIN:
			rec["verdict"] = "ACCEPT"
		elif score >= ACCEPT_MIN:
			rec["verdict"] = "ACCEPT"
		else:
			rec["verdict"] = "MOVE"


# ================================================================
# 修复：为重叠 / 落点差的大件找合法位置（判据与上面同源，检测=修复不打架）
# ================================================================

const FIX_STEP_M := 1.0        ## 外扩搜索步长（弧距，米）：细一点才能做「就近让位」
## 外扩搜索上限（弧距，米）：只给「互叠」用，就近让位。
const FIX_MAX_M := 6.0
## 自动落地的下沉上限（米）。超过这个深度就不再「埋」（11m 深会把整栋楼埋没），
## 改为尝试搬迁找平地 —— 落地负责浅悬空，搬迁负责深悬空。
const FIX_MAX_SINK := 2.0
const FIX_DIST_PENALTY := 6.0  ## 每米位移罚分：优先原地旋转 / 就近让位
## 是否启用「搬迁 / 转向」修互叠。默认关：实测在这张丘陵图上，任何自动搬迁都会把楼
## 吸到图缘（px_from_dir 钳制 → 一排楼叠在同一点）或把镇子搬空。只保留「就地落地」，
## 那是唯一安全且真正解决「能从楼底钻过去」的手段。
const FIX_ENABLE_MOVE := false
## 只处理穿透深度超过此值的互叠（米）。curate_planet 的注释讲得很清楚：低多边
## diorama 里 ±1m 的墙角咬合看不出来，死磕既无意义又会让整座镇互相挤到散架。
const FIX_MIN_OVERLAP := 1.0
## 只处理占地下方悬空超过此值的物件（米）。0.4m 猫就能钻过去，但满坡的轻微外伸
## （0.5~1m）遍地都是，全治会把镇子搬空；取 1.0 只治「一眼看出来悬在天上」的。
const FIX_MIN_FLOAT := 1.0
## 原地候选朝向：转一下常常就解决重叠，且完全不动布局
const FIX_ROTS := [0.0, PI * 0.5, PI, PI * 1.5]


## 只读规划：返回 {objects（改好的副本）, changes}。不改入参、不写文件。
## 策略：优先原地换朝向 → 不行再逐圈外扩（≤ FIX_MAX_M）；评分复用同一套落点分 +
## 与「已固定大件」的互叠罚分 + 位移惩罚。传了 nav_root 时另加【连通性护栏】：
## 每步候选改完重烘 NavMesh，主可行走区缩水 >2% 就撤销该步。
static func plan_fix(builder: PlanetBuilder, math: PlanetMath, world_px: Vector2,
		objects: Array, nav_root: Node3D = null) -> Dictionary:
	var n := objects.size()
	var objs := _dup_objs(objects)

	var results: Array[Dictionary] = []
	results.resize(n)
	for i in n:
		results[i] = _eval_object(builder, math, world_px, objs[i], i)
	_eval_overlaps(math, world_px, objs, results)
	finalize(results)

	# ---- 预修：补地基（只加 plinth 字段，不动 x/y/rot、不下沉）----
	# 「楼悬在坡上、底下能钻过去」的正解不是下沉（深了会把整栋埋掉）也不是搬迁（会把
	# 镇子搬空），而是**在楼底补一段落到坡面的地基/挡土墙**：既不留缝，也不埋楼，
	# 观感上就是山坡建筑常见的混凝土基座。plinth = 脚下地面比基座低的最大值。
	var changes: Array = []
	for i in n:
		var rg: Dictionary = results[i]
		if rg["verdict"] == "SKIP":
			continue
		var drop := float(rg.get("max_drop", 0.0))
		if drop <= FIX_MIN_FLOAT:
			continue
		if drop <= float(objs[i].get("plinth", 0.0)):
			continue
		var rot_now := int(round(float(objs[i].get("rot", 0.0))))
		objs[i]["plinth"] = drop
		changes.append({"kind": rg["kind"], "from_px": rg["px"], "to_px": rg["px"],
			"from_rot": rot_now, "to_rot": rot_now, "sink": drop,
			"score_before": float(rg["score"]), "score_after": float(rg["score"]),
			"issues": rg["issues"]})
	# 落地后重评（悬空消失，可能换来半埋；互叠也会随之变化）
	if not changes.is_empty():
		for i in n:
			results[i] = _eval_object(builder, math, world_px, objs[i], i)
		_eval_overlaps(math, world_px, objs, results)
		finalize(results)

	if not FIX_ENABLE_MOVE:
		return {"objects": objs, "changes": changes}

	var host_of := _map_hosts(objs)

	# 【只治硬伤】互叠 / 射线落空 / 摆进海里才动。坡度与占地不平交给 curate_planet，
	# 而且那是作者刻意的街区布局 —— 本工具不越权重排（实测：按地形分重排会把整座
	# 城镇散开、NavMesh 反而更碎：主域 1165→571㎡、断裂 7→14 处）。
	# 【带门窗的建筑不能靠转向修】门窗是独立物件、锚在楼的正南面；转楼而不带门窗，
	# 门窗会留在原地错位。这档只转无门窗依附的物件；带门窗的留给人工处理。
	var door_hosts := {}
	for o: Dictionary in objs:
		var kk := String(o.get("kind", ""))
		if kk == "door" or kk == "window":
			var hh := String(o.get("host", ""))
			if hh != "":
				door_hosts[hh] = true

	var todo: Array[int] = []
	for i in n:
		var r: Dictionary = results[i]
		if r["verdict"] == "SKIP" or door_hosts.has(r["kind"]):
			continue
		var ov: Array = r["overlaps"]
		var hard := bool(r.get("_hard", false)) or not bool(r["hit"])
		var maxdep := 0.0
		for o: Dictionary in ov:
			maxdep = maxf(maxdep, float(o["depth"]))
		var floating := float(r.get("max_drop", 0.0)) > FIX_MIN_FLOAT
		if not hard and not floating and maxdep <= FIX_MIN_OVERLAP:
			continue
		todo.append(i)
	todo.sort_custom(func(x: int, y: int) -> bool:
		return float(results[x]["score"]) < float(results[y]["score"]))

	# 【连通性护栏】没有它，纯按「互叠 + 地形」打分会把楼挪到路口上：实测主可行走区
	# 1165→748㎡、被切断区域 7→10 —— 修好了穿模却堵死了路。有它则逐步验、堵路就撤。
	var nav_ok := nav_root != null and nav_root.is_inside_tree()
	var cur_main := 0.0
	if nav_ok:
		cur_main = _nav_main(nav_root, math, world_px, objs, results)
		nav_ok = cur_main > 0.0

	for i in todo:
		var r: Dictionary = results[i]
		# 【障碍 = 所有其他大件】不能只躲「已通过的大件」：那样坏件会挪到另一个坏件
		# 身上（实测 police 被挪到 cafe 头上，中心距 0.7m、互叠反而从 3.5m 涨到 4.0m）。
		var obstacles := _obstacles_except(results, i)
		# 纯悬空（无互叠、无硬伤）只允许原地转向；有互叠才允许就近挪窝
		var hard := bool(r.get("_hard", false)) or not bool(r["hit"])
		var maxdep := 0.0
		for o: Dictionary in r["overlaps"]:
			maxdep = maxf(maxdep, float(o["depth"]))
		# 只有「互叠 / 硬伤 / 深悬空（落地埋不动）」才允许挪窝；其余最多原地转
		var deep := float(r.get("max_drop", 0.0)) > FIX_MAX_SINK
		var max_dist := 0.0
		if hard or maxdep > FIX_MIN_OVERLAP or deep:
			max_dist = FIX_MAX_M
		var best := _find_best(builder, math, world_px, objs[i], r, obstacles, max_dist)
		if best.is_empty():
			continue
		var np: Vector2 = best["px"]
		var old_px: Vector2 = r["px"]
		var old_deg := float(objs[i].get("rot", 0.0))
		var new_deg := fposmod(rad_to_deg(float(best["yaw"])), 360.0)
		var moved := np.distance_to(old_px) > 0.5
		var rotated := absf(new_deg - fposmod(old_deg, 360.0)) > 0.5
		if not moved and not rotated:
			continue
		var snap := _dup_objs(objs)
		_apply_move(objs, i, np, new_deg, host_of, world_px)
		results[i] = _eval_object(builder, math, world_px, objs[i], i)
		if nav_ok:
			var m2 := _nav_main(nav_root, math, world_px, objs, results)
			if m2 < cur_main * 0.98:
				objs = snap              # 撤销：这步会把通路堵死
				results[i] = r
				continue
			cur_main = m2
		changes.append({
			"kind": r["kind"], "from_px": old_px, "to_px": np,
			"from_rot": int(round(old_deg)), "to_rot": int(round(new_deg)),
			"score_before": float(r["score"]), "score_after": float(best["score"]),
			"issues": r["issues"],
		})
	return {"objects": objs, "changes": changes}


## 除 i 之外、所有「大件且落点有效」的占地体（取当前 results 位置）。
static func _obstacles_except(results: Array[Dictionary], i: int) -> Array:
	var out: Array = []
	for k in results.size():
		if k == i:
			continue
		var r: Dictionary = results[k]
		if bool(r["big"]) and r["verdict"] != "SKIP" and bool(r["hit"]):
			out.append(_placed_of(r))
	return out


## 深拷贝 objects（每个条目都是 Dictionary）。
static func _dup_objs(objs: Array) -> Array:
	var out: Array = []
	for o in objs:
		out.append((o as Dictionary).duplicate(true))
	return out


## 把一个物件挪到 np/朝向，并带动依附它的门/窗同 delta 跟随。
static func _apply_move(objs: Array, i: int, np: Vector2, new_deg: float,
		host_of: Dictionary, world_px: Vector2) -> void:
	var old := Vector2(float(objs[i].get("x", 0)), float(objs[i].get("y", 0)))
	objs[i]["x"] = int(round(np.x))
	objs[i]["y"] = int(round(np.y))
	objs[i]["rot"] = int(round(new_deg))
	var delta := np - old
	for j in objs.size():
		if int(host_of.get(j, -1)) != i:
			continue
		var fp := Vector2(float(objs[j].get("x", 0)), float(objs[j].get("y", 0)))
		objs[j]["x"] = int(clampf(fp.x + delta.x, 0.0, world_px.x))
		objs[j]["y"] = int(clampf(fp.y + delta.y, 0.0, world_px.y))


## 当前布局下的主可行走区面积（㎡）；navmesh 不可用时返回 -1。
static func _nav_main(nav_root: Node3D, math: PlanetMath, world_px: Vector2,
		objects: Array, results: Array[Dictionary]) -> float:
	var nx := _check_navmesh(nav_root, math, world_px, objects, results)
	return float((nx.get("full", {}) as Dictionary).get("main_area", -1.0))


## 从已定 rec 抽出互叠判定要用的字段。
static func _placed_of(r: Dictionary) -> Dictionary:
	return {"dir": r["dir"], "pos": r["pos"], "yaw": r["yaw"],
		"rects": r["rects"], "h": r["h"], "kind": r["kind"]}


## 门窗 → 最近同类 host 的下标（搬迁时同 delta 跟随）。
static func _map_hosts(objs: Array) -> Dictionary:
	var out := {}
	for i in objs.size():
		var k := String((objs[i] as Dictionary).get("kind", ""))
		if k != "door" and k != "window":
			continue
		var hk := String((objs[i] as Dictionary).get("host", ""))
		var best := -1
		var bd := 1e18
		for j in objs.size():
			if j == i or String((objs[j] as Dictionary).get("kind", "")) != hk:
				continue
			var d := Vector2(float(objs[i].get("x", 0)) - float(objs[j].get("x", 0)),
				float(objs[i].get("y", 0)) - float(objs[j].get("y", 0))).length_squared()
			if d < bd:
				bd = d
				best = j
		out[i] = best
	return out


## 为一个坏件找最优落点：原地 4 向优先；原地就能过 ACCEPT 就立即收手。
static func _find_best(builder: PlanetBuilder, math: PlanetMath, world_px: Vector2,
		obj: Dictionary, r: Dictionary, obstacles: Array, max_dist: float) -> Dictionary:
	var d0 := math.dir_from_px(r["px"], world_px)
	var yaw0 := float(r["yaw"])
	var rects: Array = r["rects"]
	var h := float(r["h"])
	var rings := int(max_dist / FIX_STEP_M)   # max_dist=0 → 只走 ring 0（原地 4 向）
	var best := {}
	var best_total := -1e18
	for ring in range(0, rings + 1):
		var dist := FIX_STEP_M * float(ring)
		var bearings := 1 if ring == 0 else maxi(8, ring * 6)
		var rots: Array = FIX_ROTS if ring == 0 else [0.0]
		for bi in bearings:
			var dir: Vector3
			if ring == 0:
				dir = d0
			else:
				var ang := TAU * float(bi) / float(bearings) + 0.618 * float(ring)
				dir = _offset_dir(math, d0.normalized(), ang, dist)
			# 【量化到整数 px 再评估】最终写盘就是整数 px，评估必须与写盘完全一致，
			# 否则会出现「候选评分合格、落地却变样」的错位。
			var np := math.px_from_dir(dir, world_px)
			np = Vector2(roundf(np.x), roundf(np.y))
			var cd := math.dir_from_px(np, world_px)   # 钳回图内自洽
			for rr: float in rots:
				var yaw := yaw0 + rr
				var probe := {"kind": obj.get("kind", ""), "x": np.x, "y": np.y,
					"rot": rad_to_deg(yaw), "y_lift": obj.get("y_lift", 0.0)}
				var rec := _eval_object(builder, math, world_px, probe, -1)
				# 硬伤候选直接淘汰（落空 / 摆进海里）—— 只看 score 会被海里的 0 分误导
				if not bool(rec["hit"]) or bool(rec.get("_hard", false)):
					continue
				# 【别修出新伤】候选坡度不得比「可走坡度」还陡，也不许落在孤峰/树干顶。
				# 少了这道门，为躲 1m 互叠会把车挪到 70° 崖壁上（实测 truck dot 0.85→0.34）。
				if float(rec["slope"]) < DOT_MIN_PROP or int(rec["spike"]) >= 3:
					continue
				var total := float(rec["score"])
				var cand := {"dir": cd, "pos": rec["pos"], "yaw": yaw, "rects": rects, "h": h}
				for p: Dictionary in obstacles:
					var dep := _obb_pair(math, cand, p)
					if dep > OBB_TOL:
						total -= 25.0 + dep * 8.0
				total -= dist * FIX_DIST_PENALTY   # 位移罚分：优先「就近让位」，不搬远
				if total > best_total:
					best_total = total
					best = {"px": np, "yaw": yaw, "score": total}
			if ring == 0 and not best.is_empty() and float(best["score"]) >= ACCEPT_MIN:
				return best   # 原地转个向就过，立即收手
	return best


# ================================================================
# 标记球（可视化）
# ================================================================

static func spawn_markers(host: Node3D, results: Array[Dictionary], lift := 0.7) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.55
	mesh.height = 1.1
	var mats := {}
	var col := {
		"ACCEPT": Color(0.20, 0.85, 0.35),
		"MOVE": Color(0.95, 0.80, 0.15),
		"ROTATE": Color(0.95, 0.55, 0.10),
		"REJECT": Color(0.90, 0.15, 0.12),
	}
	for v: String in col:
		var m := StandardMaterial3D.new()
		m.albedo_color = col[v]
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mats[v] = m
	var holder := Node3D.new()
	holder.name = "ValidateMarkers"
	host.add_child(holder)
	for rec: Dictionary in results:
		var v := String(rec["verdict"])
		if v == "SKIP" or v == "ACCEPT":
			continue   # 绿球太多会糊满全岛，只标出需要处理的
		if not bool(rec["hit"]):
			continue
		var pos: Vector3 = rec["pos"]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mats[v]
		mi.position = pos + pos.normalized() * lift
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)


# ================================================================
# 报告
# ================================================================

static func _format(results: Array[Dictionary], counts: Dictionary, nav: Dictionary,
		objects: Array) -> PackedStringArray:
	var L := PackedStringArray()
	L.append("=== MapValidator 地图合法性报告 ===")
	L.append("物件总数 %d：PASS(ACCEPT) %d / 需搬(MOVE) %d / 需转(ROTATE) %d / 拒收(REJECT) %d / 跳过 %d" % [
		results.size(), int(counts.get("ACCEPT", 0)), int(counts.get("MOVE", 0)),
		int(counts.get("ROTATE", 0)), int(counts.get("REJECT", 0)), int(counts.get("SKIP", 0))])
	L.append("判据：射线命中/坡度/孤峰/占地八向平整/建筑 AABB 互叠/海面海拔；Score<%.0f 或硬伤 = REJECT，<%.0f = MOVE" % [
		MOVE_MIN, ACCEPT_MIN])
	L.append("")

	# 只列出非 ACCEPT 的（ACCEPT 太多，看问题只需要异常）
	var bad: Array[Dictionary] = []
	for r: Dictionary in results:
		if r["verdict"] != "ACCEPT" and r["verdict"] != "SKIP":
			bad.append(r)
	bad.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) < float(b["score"]))
	L.append("---- 需处理物件（按分数升序）----")
	if bad.is_empty():
		L.append("  （无）")
	for r: Dictionary in bad:
		L.append("  [%s] %-12s px=(%d,%d) score=%5.1f  %s" % [
			r["verdict"], r["kind"], int(r["px"].x), int(r["px"].y), float(r["score"]),
			", ".join(r["issues"])])
	L.append("")

	# NavMesh 连通性
	L.append("---- NavMesh 连通性 ----")
	var note := String(nav.get("note", ""))
	if not note.is_empty():
		L.append("  " + note)
	else:
		var b: Dictionary = nav.get("baseline", {})
		var f: Dictionary = nav.get("full", {})
		var ta := float(b.get("total_area", 0.0))
		var tb := float(f.get("total_area", 0.0))
		L.append("  只地形：可行走 %.0f㎡ / 连通域 %d（主域 %.0f㎡，占 %.0f%%）" % [
			ta, int(b.get("components", 0)), float(b.get("main_area", 0.0)),
			100.0 * float(b.get("main_area", 0.0)) / maxf(ta, 1.0)])
		L.append("  含建筑：可行走 %.0f㎡ / 连通域 %d（主域 %.0f㎡，占 %.0f%%）" % [
			tb, int(f.get("components", 0)), float(f.get("main_area", 0.0)),
			100.0 * float(f.get("main_area", 0.0)) / maxf(tb, 1.0)])
		L.append("  建筑直接占走 %.0f㎡（正常）；主域其余缩水来自通道被切断" % maxf(ta - tb, 0.0))
		L.append("  基线连通域面积 Top5：%s（其余为坡地/崖边小平台）" % _fmt_top(b))
		var cut: Array = nav.get("cut", [])
		if cut.is_empty():
			L.append("  ✓ 没有 >20㎡ 的可走区域被建筑切断")
		else:
			L.append("  ✗ 有 %d 处可走区域被建筑切断（面积 / 位置 / 堵路大件）：" % cut.size())
			for c: Dictionary in cut:
				var px: Vector2 = c["px"]
				L.append("    %6.0f㎡ @ px=(%d,%d)  堵路大件: %s" % [
					float(c["area"]), int(px.x), int(px.y), ", ".join(c["near"])])
	return L


static func _fmt_top(d: Dictionary) -> String:
	var top: PackedFloat32Array = d.get("top5", PackedFloat32Array())
	var parts: PackedStringArray = []
	for a in top:
		parts.append("%.0f㎡" % a)
	return ", ".join(parts)


static func write_report(lines: PackedStringArray, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MapValidator: 无法写报告 " + path)
		return
	for l in lines:
		f.store_line(l)
	f.close()
