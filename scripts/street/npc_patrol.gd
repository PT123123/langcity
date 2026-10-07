class_name NpcPatrol
extends Node
## NPC 巡航控制器：让街上的 NPC 沿路线绕建筑行走。
##
## 路线数据直接挂在 planet.json 的 npc 条目上（编辑器「人物」页可画）：
##   {"kind":"npc","npc":"chef","x":..,"y":..,
##    "patrol": [[x1,y1],[x2,y2],...],   # 展开图像素航点（不含出生点）
##    "patrol_mode": "loop"/"pingpong",  # loop=闭环（走完回出生点再来，缺省）
##                                       # pingpong=来回（走到终点原路折返）
##    "patrol_speed": 1.1,               # 米/秒（缺省 PATROL_SPEED）
##    "patrol_wait": [1.2, 3.0]}         # 每个航点停留秒数区间（缺省 WAIT）
##
## 运动模型复刻 street.gd::_place_on_planet()：航点 px → 球面方向 → 地形射线落点；
## 段内沿球面 slerp 推进（角速度 = 线速度 / 当前半径），每帧重新贴地 + 按切向转向。
## 不走物理（NPC 无碰撞体），纯视觉移动；玩家走近自动驻足，对话中暂停。

const PATROL_SPEED := 1.1      # 缺省步行速度（米/秒）
const WAIT_MIN := 1.2          # 缺省航点停留（秒，区间下限）
const WAIT_MAX := 3.0          # 缺省航点停留（秒，区间上限）
const STANDOFF := 3.2          # 玩家进入这个半径就驻足（米），防止对话时 NPC 走远
const GROUND_EPS := 0.35       # 与 street.gd 一致的水线余量（米）

var it: Interactable               # 被驱动的 NPC 物件（整体挪动，点击盒跟着走）
var talker: Node = null            # ArtNpc（walk/idle 动画；可为 null = 纯滑动）
var math: PlanetMath
var builder: PlanetBuilder
var world_px := Vector2.ZERO
var player_pos := Vector3.INF      # street 每帧写入；INF = 无人（编辑器试走）
var paused := false                # 对话/弹窗期间暂停

var active := false                # 有效航点 ≥2 才置位
var pingpong := false              # true = 来回折返；false = 闭环（缺省）

var _dirs: Array[Vector3] = []     # 航点的球面方向（[出生点, 航点...]）
var _seg := 0                      # 当前段号：从 _dirs[_seg] 走向 _dirs[_seg + _dir]
var _dir := 1                      # pingpong 时的行进方向（+1 去程 / -1 返程）
var _t := 0.0                      # 当前段已走角度（弧度）
var _wait := 0.0                   # 剩余停留时间（>0 = 驻足中）
var speed := PATROL_SPEED
var wait_min := WAIT_MIN
var wait_max := WAIT_MAX


## 从 it.extra 读路线并构建航点。返回 false = 数据缺失/有效点不足（不启用巡航）。
func setup() -> bool:
	var extra: Dictionary = it.extra
	var raw: Variant = extra.get("patrol", null)
	if not (raw is Array) or (raw as Array).is_empty():
		return false
	speed = maxf(0.3, float(extra.get("patrol_speed", PATROL_SPEED)))
	pingpong = String(extra.get("patrol_mode", "loop")) == "pingpong"
	var wv: Variant = extra.get("patrol_wait", null)
	if wv is Array and (wv as Array).size() >= 2:
		wait_min = maxf(0.0, float((wv as Array)[0]))
		wait_max = maxf(wait_min, float((wv as Array)[1]))
	else:
		wait_min = WAIT_MIN
		wait_max = WAIT_MAX
	# 闭环：出生点收尾。命中不到地形的航点直接丢弃（编辑器会标红提示，但运行期要兜底）。
	_dirs.clear()
	var spawn_px := Vector2(float(extra.get("x", 0.0)), float(extra.get("y", 0.0)))
	var all_px: Array[Vector2] = [spawn_px]
	for p: Variant in raw:
		if p is Array and (p as Array).size() >= 2:
			all_px.append(Vector2(float((p as Array)[0]), float((p as Array)[1])))
	for px in all_px:
		var dir := math.dir_from_px(px, world_px)
		var spot := builder.surface(dir)
		if not bool(spot.get("hit", false)) \
				or (spot["pos"] as Vector3).length() < builder.water_radius + GROUND_EPS:
			continue
		_dirs.append(dir)
	if _dirs.size() < 2:
		_dirs.clear()
		return false
	active = true
	_seg = 0
	_t = 0.0
	_wait = randf_range(wait_min, wait_max)   # 开局先站一会儿，别集体齐步走
	return true


func _physics_process(delta: float) -> void:
	if not active or paused or it == null or not is_instance_valid(it):
		return
	# 玩家走近就驻足（还站在原地别挡路太狠：只停不走）。player_pos=INF 表示没有玩家。
	var talking := not player_pos.is_finite() \
		and it.position.distance_to(player_pos) <= STANDOFF
	if _wait > 0.0 or talking:
		if talker != null:
			talker.call("set_walking", false)
		if not talking:
			_wait -= delta
		else:
			_wait = maxf(_wait, 0.6)   # 玩家一直站在旁边就一直等
		return
	if talker != null:
		talker.call("set_walking", true)

	var a := _dirs[_seg]
	var next_seg := _next_seg()
	var b := _dirs[next_seg]
	# 角步长 = 线速度 / 当前球面半径。半径取当前落点海拔，随地形起伏自适应。
	var r := maxf(it.position.length(), 1.0)
	var d_ang := speed * delta / r
	var total := a.angle_to(b)
	if total < 1e-5:
		_advance_segment()
		return
	var t_ang := minf(_t + d_ang, total)
	var dir := math.slerp_dir(a, b, t_ang / total)
	var spot := builder.surface(dir)
	if not bool(spot.get("hit", false)):
		return   # 射线偶尔落空（物理宽相边界）：这帧原地不动，下帧再试
	var pos := spot["pos"] as Vector3
	var up := (spot["normal"] as Vector3).normalized()
	var h := (pos - it.position)
	h = (h - up * h.dot(up))
	if h.length_squared() > 1e-8:
		h = h.normalized()
		# 模型面朝 = 物件 +Z（ArtNpc 子节点带 PI 旋转，见 _b_npc 注释），
		# 所以基的 Z 列取行进切向 h；X 列按右手系补齐：x = up × z。
		# 【整体赋 transform】global_transform.basis 单独赋值改的是临时副本，不生效。
		it.global_transform = Transform3D(Basis(up.cross(h), up, h), pos)
	it.position = pos
	_t = t_ang
	if t_ang >= total - 1e-6:
		_advance_segment()


## 下一段号：闭环 = 环进；来回 = 撞到端点折返（端点 = 出生点 / 最远航点）。
func _next_seg() -> int:
	var last := _dirs.size() - 1
	if not pingpong:
		return (_seg + 1) % _dirs.size()
	var nxt := _seg + _dir
	if nxt < 0 or nxt > last:
		_dir = -_dir
		nxt = _seg + _dir
	return clampi(nxt, 0, last)


## 到达一个航点：推进段号（方向由 _next_seg 翻转）、按区间随机停留。
func _advance_segment() -> void:
	_seg = _next_seg()
	_t = 0.0
	_wait = randf_range(wait_min, wait_max)
