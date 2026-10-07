class_name PlanetMath
extends RefCounted
## 小星球球面数学：把地图像素坐标解释为星球顶部岛冠上的经纬度。
##
## 【为什么复用像素坐标】整个学习栈（存档位置、进屋返回点、跑腿航点）都以
## (px, yaw) 持久化。星球世界不改这套 schema —— px 在星球上不再表示"米"，
## 而是「岛冠展开图上的经纬度」，进星球前正映射、存档时逆映射，双向无损。
##
## 坐标约定（与旧平面地图一致）：
##   x → 东（λ 经度增大），y → 南（φ 离极点角距增大），0 = 北（朝岛顶/极点）。
##   球心在原点，极点 = +Y。dir(λ, φ) = (sinφ·sinλ, cosφ, sinφ·cosλ)。
##   λ=0、φ=90° 时 dir=(0,0,1)，东向切量为 +X —— 与旧图 x→+X 完全对齐。
##
## 表面朝向（yaw=0 的切平面基）：Y=法线（径向），X=东，Z=南。
## 物件局部代码全部假设「站在自己的 +Y 地面上」，对齐这个基即可原样复用。

var center := Vector3.ZERO   # 星球中心（世界坐标；岛心挪到原点后即 Vector3.ZERO）
var radius := 34.0           # 标称半径（米）：小地图/远裁剪面/可走边界用，落点以射线检测为准
var lon_span := 2.27         # 半经度跨度（弧度）：px x=0 → -span，x=W → +span
var lat_top := 0.17          # px y=0 处的离极角距（弧度），留一点点给极点相机退化兜底
var lat_bottom := 1.36       # px y=H 处的离极角距（弧度）
var walk_phi := 1.48         # 可走边界（弧度）：超过就往回推（= 海边软墙；>=PI 视为不设限）


func _init(p_cfg: Dictionary = {}) -> void:
	center = _to_v3(p_cfg.get("center", [0, 0, 0]))
	# radius 是 GLB 原生标称半径，scale 是星球整体缩放（PlanetBuilder 同步缩放模型）
	radius = float(p_cfg.get("radius", 34.0)) * float(p_cfg.get("scale", 1.0))
	lon_span = deg_to_rad(float(p_cfg.get("lon_span_deg", 130.0)))
	lat_top = deg_to_rad(float(p_cfg.get("lat_top_deg", 10.0)))
	lat_bottom = deg_to_rad(float(p_cfg.get("lat_bottom_deg", 78.0)))
	walk_phi = deg_to_rad(float(p_cfg.get("walk_lat_deg", 85.0)))


static func _to_v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


## 地图像素 → 球面方向（单位向量，自 center 指向表面上空）
func dir_from_px(px: Vector2, world: Vector2) -> Vector3:
	var u := clampf(px.x / maxf(world.x, 1.0), 0.0, 1.0)
	var v := clampf(px.y / maxf(world.y, 1.0), 0.0, 1.0)
	return dir_from_uv(u, v)


func dir_from_uv(u: float, v: float) -> Vector3:
	var lam := (u - 0.5) * 2.0 * lon_span
	var phi := lerpf(lat_top, lat_bottom, v)
	return Vector3(sin(phi) * sin(lam), cos(phi), sin(phi) * cos(lam))


## 球面方向 → 地图像素（逆映射；超出岛冠范围时钳到图边，保证存档合法）
func px_from_dir(dir: Vector3, world: Vector2) -> Vector2:
	var u := (atan2(dir.x, dir.z) / (2.0 * lon_span)) + 0.5
	var phi := acos(clampf(dir.y, -1.0, 1.0))
	var v := inverse_lerp(lat_top, lat_bottom, phi)
	return Vector2(clampf(u, 0.0, 1.0) * world.x, clampf(v, 0.0, 1.0) * world.y)


func px_from_world(world_pos: Vector3, world_size: Vector2) -> Vector2:
	return px_from_dir((world_pos - center).normalized(), world_size)


## 该方向的"北"切向（指向极点的表面方向）。dir 接近极轴时退化，回退用 +X。
func north_at(dir: Vector3) -> Vector3:
	var n := Vector3.UP - dir * dir.y
	if n.length_squared() < 1e-6:
		n = Vector3.RIGHT - dir * dir.x
	return n.normalized()


## 该方向的"东"切向
func east_at(dir: Vector3) -> Vector3:
	return north_at(dir).cross(dir).normalized()


## 该方向处、绕法线旋转 yaw 后的表面基（X=东 Y=上 Z=南，右手系）。
## 验证：dir=(0,0,1) 时 north=(0,1,0)、east=(1,0,0)、south=(0,-1,0)，
## X×Y = (0,-1,0) = Z —— 与旧平面图 x→+X / y→+Z 的朝向约定逐项一致。
func basis_at(dir: Vector3, yaw := 0.0) -> Basis:
	var up := dir.normalized()
	var e := east_at(up)
	var s := -north_at(up)
	var b := Basis(e, up, s)
	if yaw != 0.0:
		b = b * Basis(Vector3.UP, yaw)
	return b


## 可走边界软墙：dir 的离极角距超过 walk_phi 时，给出钳回边界后的方向。
## 返回 null 表示在界内不用管。
func clamp_walk(dir: Vector3) -> Variant:
	if walk_phi >= PI:
		return null
	var phi := acos(clampf(dir.y, -1.0, 1.0))
	if phi <= walk_phi:
		return null
	var lam := atan2(dir.x, dir.z)
	return Vector3(sin(walk_phi) * sin(lam), cos(walk_phi), sin(walk_phi) * cos(lam))


## 沿大圆从 a 到 b 采样 t∈[0,1] 的方向（小地图虚线路径用）
func slerp_dir(a: Vector3, b: Vector3, t: float) -> Vector3:
	var axis := a.cross(b)
	var la := axis.length()
	if la < 1e-6:
		return a
	var ang := atan2(la, a.dot(b))
	return (a * sin((1.0 - t) * ang) + b * sin(t * ang)) / sin(ang)
