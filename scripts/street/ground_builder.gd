class_name GroundBuilder
extends Node3D
## 3D 地面：纹理化马路/人行道/公园、车道虚线、井盖、盲道、停止线、
## 铁轨与站台、公园小径。全部几何体 + 程序纹理，一次性搭建。

const S := 0.025

const ROAD := Color("43464e")
const WALK := Color("c6c0b0")
const WALK_EDGE := Color("a8a294")
const LANE := Color("e8e0c6")
const BASE := Color("b5afa0")
const PARK := Color("7cb468")
const PARK_DEEP := Color("74ab61")
const GRAVEL := Color("a8a49a")
const TIE := Color("7a6a55")
const RAIL := Color("55575e")
const PLATFORM := Color("d9d4c8")

var _asphalt_m: StandardMaterial3D
var _walk_m: StandardMaterial3D
var _base_m: StandardMaterial3D
var _grass_m: StandardMaterial3D
var _plat_m: StandardMaterial3D
var _env_m: StandardMaterial3D
var _gravel_m: StandardMaterial3D


func setup(ground_cfg: Dictionary, world_m: Vector2, objects: Array) -> void:
	# 选贴图靠量化，不靠肉眼。三个指标：
	#   色度(max-min of RGB) 越小越中性 —— 决定"马路会不会泛粉"
	#   灰度方差 var 越小越均匀 —— 决定"放大后会不会显出大特征"
	#   dark% 越低越没水渍
	# 实测对比：
	#   road(aerial_asphalt_01) 色度5.9 var=58  <- 最中性，回退到它
	#   pavement 色度23.4 var=41  <- 均匀但暖米色，铺装偏粉像泳池砖
	#   pavers   色度20.2 var=123 <- 花纹太明显
	#   road_alt(worn_asphalt) 色度23.2    <- 有水渍
	# 之前换掉 road 是误判：它的问题（大裂缝）靠把 scale 提到 1.5 就能压掉，
	# 不该因此换到偏色的图。色度 5.9 才是马路的正确颜色。
	_asphalt_m = Interactable.mat_photo("road", Color(0.8, 0.81, 0.84), 0.9, 0.96, 1.5,
		ProceduralTex.asphalt(3), 0.5, 4.0, 0.6)
	# 人行道：pavers(105) 有足够细节。用浅色 tint 保持"人行道比马路亮"的明度关系。
	_walk_m = Interactable.mat_photo("pavers", Color(0.95, 0.94, 0.91), 0.9, 0.92, 0.75,
		ProceduralTex.pavers(5), 0.5, 3.2, 0.5)
	# 世界基底（铺满整张地图的底层）。要「低存在感」——它只在物件缝隙里露一点，
	# 用高对比贴图会在车站/铁轨区整片透出来，看起来像泥地。
	# concrete_pavers(var=104) 刚够，且压暗压灰。
	_base_m = Interactable.mat_photo("concrete_pavers", Color(0.6, 0.59, 0.56), 0.9, 0.96, 0.5,
		ProceduralTex.pavers(9), 0.5, 2.2, 0.4)
	# 草地：G 分量不能写 1.0 以上（会被钳到 1.0，写了等于没写）。
	# 想要更绿更亮靠两件事：tint_amt 高（保住贴图原色）+ detail_amount 大。
	_grass_m = Interactable.mat_photo("grass", Color(0.86, 1.0, 0.78), 0.9, 0.98, 0.6,
		ProceduralTex.grass(13), 0.5, 4.0, 0.6)
	_plat_m = Interactable.mat_photo("pavers", Color(0.96, 0.95, 0.92), 0.92, 0.9, 0.85,
		ProceduralTex.pavers(15), 0.5, 3.0, 0.45)
	_env_m = Interactable.mat_photo("grass", Color(0.74, 0.96, 0.64), 0.9, 0.98, 0.3,
		ProceduralTex.grass(21), 0.5, 2.0, 0.55)
	# 铁轨道砟
	_gravel_m = Interactable.mat_photo("concrete_pavers", Color(0.8, 0.76, 0.7), 0.9, 1.0, 0.9,
		ProceduralTex.pavers(25), 0.5, 3.0, 0.6)

	# 基底大平面 + 周边环境草地（消除世界边缘的虚空）
	_box(Vector3(500.0, 0.1, 500.0), Vector3(world_m.x * 0.5, -0.07, world_m.y * 0.5), _env_m)
	_box(Vector3(world_m.x, 0.1, world_m.y), Vector3(world_m.x * 0.5, -0.05, world_m.y * 0.5), _base_m)
	# 公园
	var park: Dictionary = ground_cfg.get("park", {})
	if park.has("rect"):
		var r: Array = park["rect"]
		var pr := Rect2(float(r[0]) * S, float(r[1]) * S, float(r[2]) * S, float(r[3]) * S)
		_box(Vector3(pr.size.x, 0.07, pr.size.y), Vector3(pr.position.x + pr.size.x * 0.5, 0.035, pr.position.y + pr.size.y * 0.5), _grass_m)

		# 公园小径
		_box(Vector3(pr.size.x - 3.0, 0.078, 1.7), Vector3(pr.position.x + pr.size.x * 0.5, 0.075, pr.position.y + pr.size.y * 0.55),
			Interactable.mat_photo("dirt_path", Color(0.82, 0.78, 0.7), 0.0, 0.98, 0.7,
				ProceduralTex.pavers(17), 0.5, 2.2, 0.4))

	var sw := float(ground_cfg.get("sidewalk", 90)) * S
	var cross_pos: Array = []
	for o: Dictionary in objects:
		if String(o.get("kind", "")) == "crosswalk":
			cross_pos.append(Vector2(float(o.get("x", 0)), float(o.get("y", 0))) * S)
	# 人行道（略高于路面，形成路缘） + 马路
	for r_h: Array in ground_cfg.get("roads_h", []):
		var y0 := float(r_h[0]) * S
		var y1 := float(r_h[1]) * S
		var mid := (y0 + y1) * 0.5
		_box(Vector3(world_m.x, 0.06, (y1 - y0) + sw * 2.0), Vector3(world_m.x * 0.5, 0.03, mid), _walk_m)
		_box(Vector3(world_m.x, 0.05, y1 - y0), Vector3(world_m.x * 0.5, 0.045, mid), _asphalt_m)
		_box_c(Vector3(world_m.x, 0.065, 0.18), Vector3(world_m.x * 0.5, 0.032, y0 - sw + 0.09), WALK_EDGE)
		_box_c(Vector3(world_m.x, 0.065, 0.18), Vector3(world_m.x * 0.5, 0.032, y1 + sw - 0.09), WALK_EDGE)
		var x := 1.3
		while x < world_m.x:
			_box_c(Vector3(1.3, 0.056, 0.14), Vector3(x, 0.075, mid), LANE)
			x += 2.8
	for r_v: Array in ground_cfg.get("roads_v", []):
		var x0 := float(r_v[0]) * S
		var x1 := float(r_v[1]) * S
		var mid := (x0 + x1) * 0.5
		_box(Vector3((x1 - x0) + sw * 2.0, 0.06, world_m.y), Vector3(mid, 0.0305, world_m.y * 0.5), _walk_m)
		_box(Vector3(x1 - x0, 0.05, world_m.y), Vector3(mid, 0.0455, world_m.y * 0.5), _asphalt_m)
		_box_c(Vector3(0.18, 0.065, world_m.y), Vector3(x0 - sw + 0.09, 0.032, world_m.y * 0.5), WALK_EDGE)
		_box_c(Vector3(0.18, 0.065, world_m.y), Vector3(x1 + sw - 0.09, 0.032, world_m.y * 0.5), WALK_EDGE)
		var z := 1.3
		while z < world_m.y:
			_box_c(Vector3(0.14, 0.056, 1.3), Vector3(mid, 0.075, z), LANE)
			z += 2.8
	# 停止线 + 盲道（每个斑马线的来向）
	for cp: Vector2 in cross_pos:
		var dir_v := cp.y < 26.0 or cp.y > 30.0  # 越过纵向路的斑马线（车流沿 Z）
		if dir_v:
			_box_c(Vector3(3.2, 0.012, 0.32), Vector3(cp.x - 1.6, 0.08, cp.y - 2.4), Color(1, 1, 1, 0.9))
			_box_c(Vector3(3.2, 0.012, 0.32), Vector3(cp.x + 1.6, 0.08, cp.y + 2.4), Color(1, 1, 1, 0.9))
			var tz := cp.y - 2.5 if cp.y < 30.0 else cp.y + 2.5
			_box_c(Vector3(1.4, 0.012, 0.5), Vector3(cp.x, 0.068, tz), Color("d8a927"))
		else:
			_box_c(Vector3(0.32, 0.012, 3.2), Vector3(cp.x - 2.4, 0.08, cp.y - 1.6), Color(1, 1, 1, 0.9))
			_box_c(Vector3(0.32, 0.012, 3.2), Vector3(cp.x + 2.4, 0.08, cp.y + 1.6), Color(1, 1, 1, 0.9))
			var tx := cp.x - 2.5 if cp.x < 30.0 else cp.x + 2.5
			_box_c(Vector3(0.5, 0.012, 1.4), Vector3(tx, 0.068, cp.y), Color("d8a927"))
	# 井盖：外圈 + 内芯 + 十字筋 + 螺栓点（之前的纯色圆片太「贴纸」了）
	var man_spots := [Vector3(18, 30, 0), Vector3(45, 30, 0), Vector3(66, 30, 0), Vector3(88, 30, 0),
		Vector3(30, 47, 0), Vector3(30, 62, 0), Vector3(70, 47, 0), Vector3(70, 62, 0),
		Vector3(24, 70, 0), Vector3(52, 70, 0), Vector3(80, 70, 0), Vector3(50, 15, 0)]
	for spot: Vector3 in man_spots:
		_manhole(Vector3(spot.x, 0.08, spot.y))
	# 铁路 + 站台
	var rail: Dictionary = ground_cfg.get("rail", {})
	if rail.has("y"):
		var ry := float(rail["y"]) * S
		var rh := float(rail["h"]) * S
		var rmid := ry + rh * 0.5
		_box(Vector3(world_m.x, 0.06, rh), Vector3(world_m.x * 0.5, 0.03, rmid), _gravel_m)
		var x := 0.5
		while x < world_m.x:
			_box_c(Vector3(0.16, 0.04, rh - 0.6), Vector3(x, 0.05, rmid), TIE)
			x += 1.8
		_box_c(Vector3(world_m.x, 0.07, 0.09), Vector3(world_m.x * 0.5, 0.085, rmid - 0.72), RAIL)
		_box_c(Vector3(world_m.x, 0.07, 0.09), Vector3(world_m.x * 0.5, 0.085, rmid + 0.72), RAIL)
		var pl: Array = rail.get("platform", [])
		if pl.size() == 2:
			var pz0 := float(pl[0]) * S
			var pz1 := float(pl[1]) * S
			var pmid := (pz0 + pz1) * 0.5
			_box(Vector3(world_m.x, 0.55, pz1 - pz0), Vector3(world_m.x * 0.5, 0.275, pmid), _plat_m)
			_box_c(Vector3(world_m.x, 0.02, 0.28), Vector3(world_m.x * 0.5, 0.56, pz1 - 0.16), Color("e3b93e"))


func _box(size: Vector3, pos: Vector3, material: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)


func _box_c(size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = Interactable.mat(color)
	mi.position = pos
	add_child(mi)


func _flat_disc(r: float, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = 0.01
	mesh.radial_segments = 12
	mi.mesh = mesh
	mi.material_override = Interactable.mat(color)
	mi.position = pos
	add_child(mi)


func _disc(pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.34
	mesh.bottom_radius = 0.34
	mesh.height = 0.014
	mesh.radial_segments = 16
	mi.mesh = mesh
	mi.material_override = Interactable.mat(color)
	mi.position = pos
	add_child(mi)


## 细节版井盖：深色外圈 + 略亮内芯 + 十字筋 + 四颗螺栓点。
## 全部轴对齐/圆柱，无旋转开销；一眼可认出是「井盖」而不是灰圆片。
func _manhole(pos: Vector3) -> void:
	_disc(pos, Color("34373e"))                       # 外圈（最深）
	_disc2(pos, 0.27, Color("41454e"))                # 内芯
	_box_c(Vector3(0.5, 0.014, 0.05), pos + Vector3(0, 0.006, 0), Color("2c2f36"))
	_box_c(Vector3(0.05, 0.014, 0.5), pos + Vector3(0, 0.006, 0), Color("2c2f36"))
	for dx in [-0.2, 0.2]:
		for dz in [-0.2, 0.2]:
			_flat_disc(0.02, pos + Vector3(dx, 0.008, dz), Color("555a63"))


func _disc2(pos: Vector3, r: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = 0.012
	mesh.radial_segments = 16
	mi.mesh = mesh
	mi.material_override = Interactable.mat(color)
	mi.position = pos
	add_child(mi)
