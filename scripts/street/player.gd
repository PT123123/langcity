class_name Player
extends CharacterBody3D
## 玩家（Stray 式第三人称）：可见的猫 + 弹簧臂跟拍相机。
## 移动：左摇杆/WASD 相对相机方向走；身体朝向平滑转向移动方向（不是瞬间转）。
## 相机：拖动屏幕环绕（yaw/pitch），弹簧臂自动避开建筑，停手后缓慢回正到背后。
## 跳跃：空格 / 屏幕按钮，可跳上垃圾桶、长椅、窗台、矮墙等（Stray 的核心玩法之一）。

const SPEED := 2.35           # 猫走路比人慢，但比 Stray 稍快一点，手感更跟手
const ACCEL := 11.0           # 起速
const DECEL := 15.0           # 停步
const GRAVITY := 19.0
const TURN_MAX_RATE := 6.0    # 身体转向角速度上限（弧度/秒）

# ---- 跳跃（Stray 的猫能跳上东西，这是探索感的一半）----
# 【跳跃高度是解析量】h = v²/(2g)。g=19 时：
#   v=4.35 -> 0.50m   v=4.97 -> 0.65m   v=5.40 -> 0.77m
# 选 5.0：猫体型 0.36m，能跳 0.66m ≈ 1.8 倍体高 —— 接近真实猫（1.5~2 倍）。
# 这个高度刚好够上「矮台子」（长椅座面 0.45 / 水泥管 0.4 / 花坛 0.5），
# 但上不了窗台 0.9 / 车顶 1.5 —— 那才符合「猫就是猫」的物理直觉。
const JUMP_VELOCITY := 5.0
const JUMP_CUT := 0.45# 松手时上升速度衰减（可变跳跃高度：轻点小跳，重按大跳）
const COYOTE := 0.12# 离开边缘后仍可跳的宽容时间
const JUMP_BUFFER := 0.14# 落地前提前按跳的缓冲（手游必需）
const AIR_CONTROL := 0.55    # 空中转向/加速能力（Stray 里猫在空中仍能调整落点）
const STEP_HEIGHT := 0.3# 自动上台阶高度：路缘石/低矮边框直接走上去，不用跳

## 猫的体型（Stray 里的猫约肩高 0.23m、体长 0.4m）
const CAT_HEIGHT := 0.36     # 总高（不含头）
const CAT_RADIUS := 0.15
const CAT_BODY_Y := 0.2# 碰撞胶囊中心
const CAT_VISUAL_SCALE := 0.82# 视觉缩放（模型比碰撞体略大，看起来更敦实）

const CAM_DIST := 1.32# 弹簧臂长度（猫变小后要拉近，否则猫看起来更小）
const CAM_HEIGHT := 0.34# 相机枢轴相对猫脚的高度
const CAM_PITCH_MIN := -0.95   # 相机升到接近俯视
const CAM_PITCH_MAX := 0.10# 再低就钻地面了
const CAM_PITCH_HOME := -0.20  # 静止时回正的俯角（略俯视）
const CAM_RECENT_RATE := 1.7   # 停手后相机回正速度（1/秒）
const CAM_MIN_Y := 0.2# 相机离地下限，防止插进地面

const LOOK_SENS := 0.0028

var input_vec := Vector2.ZERO      # 虚拟摇杆写入（屏幕方向：x 右 / y 下）
var input_locked := false
var jump_pressed := false         # 由跳跃按钮/键盘写入
var jump_held := false

var look_yaw := 0.0                # 相机方位角（0 = 相机在猫的正后方，朝北 -Z）
var look_pitch := CAM_PITCH_HOME
var _idle_t := 0.0                # 停手计时，用于自动回正
var _turn_rate := 0.0             # 当前转向角速度（供身体侧倾用）
var _last_dir := Vector3.ZERO
var _coyote := 0.0
var _jump_buf := 0.0
var _was_floor := true
var _last_fall_speed := 0.0
var _land_squash := 0.0

var cam: Camera3D
var avatar: CatAvatar
var _arm: SpringArm3D
var _cam_target: Node3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 3   # 地面(2) + 障碍物(1)
	# 上台阶：小于这个高度的障碍直接跨过（路缘石、低边框）
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(60)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAT_RADIUS
	capsule.height = CAT_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0, CAT_BODY_Y, 0)
	add_child(shape)

	avatar = CatAvatar.new()
	avatar.scale = Vector3.ONE * 0.82   # 体型缩小 18%
	add_child(avatar)

	# 相机枢轴：跟着猫的高度走（弹簧臂的锚点）
	_cam_target = Node3D.new()
	_cam_target.position = Vector3(0, CAM_HEIGHT, 0)
	add_child(_cam_target)

	_arm = SpringArm3D.new()
	_arm.spring_length = CAM_DIST
	_arm.margin = 0.22
	_arm.collision_mask = 1      # 只被建筑挡住，不被地面层误伤
	_cam_target.add_child(_arm)

	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.06
	cam.far = 260.0
	_arm.add_child(cam)
	cam.make_current()

	_apply_cam_rotation()


func _unhandled_input(event: InputEvent) -> void:
	# 键盘跳跃（桌面调试用）：空格 / W+Shift 也行
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE):
		jump_pressed = true
		jump_held = true
	elif event.is_action_released("ui_accept") or (event is InputEventKey and not event.pressed and event.keycode == KEY_SPACE):
		jump_held = false


# ---------------- 视角 ----------------

## 拖动转视角（像素增量）
func look(dx_px: float, dy_px: float) -> void:
	var sens: float = LOOK_SENS * float(Game.settings.get("cam_sens", 1.0))
	look_yaw = wrapf(look_yaw - dx_px * sens, -PI, PI)
	look_pitch = clampf(look_pitch - dy_px * sens, CAM_PITCH_MIN, CAM_PITCH_MAX)
	_idle_t = 0.0
	_apply_cam_rotation()


func _apply_cam_rotation() -> void:
	_cam_target.rotation = Vector3(look_pitch, look_yaw, 0)


func teleport(pos: Vector3, yaw := NAN) -> void:
	position = pos
	velocity = Vector3.ZERO
	_last_dir = Vector3.ZERO
	_turn_rate = 0.0
	if not is_nan(yaw):
		look_yaw = yaw
	look_pitch = CAM_PITCH_HOME
	_idle_t = 0.0
	_apply_cam_rotation()


## 相机当前朝向（水平），供移动方向换算
func cam_forward() -> Vector3:
	return Vector3(-sin(look_yaw), 0, -cos(look_yaw))


func cam_right() -> Vector3:
	return Vector3(cos(look_yaw), 0, -sin(look_yaw))


## 角色当前身体朝向
func facing() -> Vector3:
	var b := global_transform.basis
	return Vector3(-b.z.x, 0, -b.z.z).normalized()


# ---------------- 移动 ----------------

func _physics_process(delta: float) -> void:
	var v := input_vec
	if not input_locked and v.length() < 0.15:
		v = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_locked:
		v = Vector2.ZERO

	# 相机相对移动
	var want := (cam_right() * v.x + cam_forward() * -v.y)
	if want.length() > 1.0:
		want = want.normalized()
	var moving := want.length() > 0.08
	if moving:
		_idle_t = 0.0
	else:
		_idle_t += delta

	# 速度：平滑起停，猫没有急停急起
	var target := want * SPEED
	var on_floor := is_on_floor()
	# 空中操控力弱一些，但够玩家微调落点（Stray 里的猫能空中修正）
	var accel := (ACCEL if on_floor else ACCEL * AIR_CONTROL)
	var rate := (accel if moving else DECEL)
	if not on_floor and not moving:
		rate = DECEL * 0.35   # 空中松手几乎不减速度，抛物线更干净
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)

	# ---- 重力 ----
	# 【必须先加重力，再做跳跃判定】以前重力/落地清零在跳起之后才执行，
	# 跳起当帧 velocity.y = JUMP_VELOCITY 会被下面 else 分支的 = 0.0 同帧抹掉，
	# 猫永远离不了地 —— 「按跳没反应」的元凶。
	if not on_floor:
		velocity.y -= GRAVITY * delta

	# ---- 跳跃 ----
	# coyote time：刚离开边缘仍可跳；jump buffer：落地前提前按也生效。
	# 这两个是手游跳跃手感的命门，少一个都会觉得"跳不动"或"没反应"。
	if on_floor:
		_coyote = COYOTE
	else:
		_coyote = maxf(0.0, _coyote - delta)
	if jump_pressed:
		_jump_buf = JUMP_BUFFER
	else:
		_jump_buf = maxf(0.0, _jump_buf - delta)
	if _jump_buf > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buf = 0.0
		_coyote = 0.0
		jump_pressed = false   # 消费掉这次按压：按住不松也不会落地自动连跳
		Game.play_sfx("click")
	# 可变跳跃高度：上升途中松手就减速，短按小跳、长按大跳
	if velocity.y > 0.0 and not jump_held:
		velocity.y -= GRAVITY * JUMP_CUT * delta * 8.0

	# 身体朝向：平滑转向移动方向（Stray 的关键手感）
	if moving:
		_last_dir = want.normalized()
	var target_yaw := atan2(-_last_dir.x, -_last_dir.z) if _last_dir.length() > 0.1 else rotation.y
	var prev_yaw := rotation.y
	rotation.y = _rotate_toward(rotation.y, target_yaw, TURN_MAX_RATE * delta)
	_turn_rate = wrapf(rotation.y - prev_yaw, -PI, PI) / maxf(delta, 0.0001)

	move_and_slide()

	# 相机停手后缓慢回正到猫背后（指数插值，帧率无关）
	# 【有移动输入时绝不回正】以前只判断速度 < 1.2：摇杆轻推半格时猫在慢走，
	# 相机却持续往"猫背后"转，而移动方向又是相对相机算的 → 方向被带着转，越走越歪画圈。
	if bool(Game.settings.get("cam_auto_recenter", true)) \
			and _idle_t > 0.5 and not input_locked \
			and not moving \
			and Vector2(velocity.x, velocity.z).length() < 1.2:
		look_yaw = wrapf(look_yaw + _yaw_diff() * (1.0 - exp(-CAM_RECENT_RATE * delta)), -PI, PI)
		look_pitch = lerpf(look_pitch, CAM_PITCH_HOME, 1.0 - exp(-CAM_RECENT_RATE * delta))
		_apply_cam_rotation()

	# ---- 落地压缩（squash & stretch）----
	# 落地瞬间按冲击速度把猫压扁，然后弹回。这是「有重量」的关键，Stray 里也是这么做的。
	# 【用移动后的 is_on_floor() 对比移动前的 _was_floor】之前两个都是移动前的旧值，
	# 条件永远为假 —— 落地压扁其实从没生效过。
	var now_floor := is_on_floor()
	if now_floor and not _was_floor:
		var impact := clampf(_last_fall_speed / 6.0, 0.0, 1.0)
		_land_squash = impact
		_last_fall_speed = 0.0
	elif not now_floor:
		_last_fall_speed = maxf(_last_fall_speed, -velocity.y)
	_was_floor = now_floor
	# 落地后清掉残留的下落速度（跳起当帧 vy > 0，不会被这里误伤）
	if now_floor and velocity.y < 0.0:
		velocity.y = 0.0
	if _land_squash > 0.0:
		_land_squash = maxf(0.0, _land_squash - delta * 3.6)
		# 压扁量 0.22，横向撑开同样的比例（体积守恒的近似）
		var s := _land_squash * 0.22
		avatar.scale = Vector3.ONE * CAT_VISUAL_SCALE * Vector3(1.0 + s * 0.7, 1.0 - s, 1.0 + s * 0.7)
	else:
		avatar.scale = Vector3.ONE * CAT_VISUAL_SCALE

	# 角色动画
	var gait := clampf(Vector2(velocity.x, velocity.z).length() / SPEED, 0.0, 1.0)
	avatar.animate(delta, gait, _turn_rate)
	_air_pose()


## 空中姿态：上升时纵向拉伸、下落时纵向压缩（配合落地 squash）。
## 幅度要小 —— 拉太大会像被橡皮筋拽着，猫会显得假。
func _air_pose() -> void:
	if is_on_floor() or _land_squash > 0.0:
		return
	# 上升（vy>0）拉伸 4%，下落压缩 4%。四足动物在空中其实收得更紧，
	# 但 Stray 那只猫是「伸直腿落地」的感觉，所以这里做小幅拉伸。
	var stretch := clampf(velocity.y / 12.0, -0.05, 0.05)
	avatar.scale = Vector3.ONE * CAT_VISUAL_SCALE * Vector3(1.0 - stretch, 1.0 + stretch, 1.0 - stretch)


func _process(_delta: float) -> void:
	# 相机不钻进地面（弹簧臂只挡建筑，挡不住地形）
	if cam.global_position.y < CAM_MIN_Y:
		cam.global_position.y = CAM_MIN_Y


## 把 from 转向 to，单次最多 max_step
func _rotate_toward(from: float, to: float, max_step: float) -> float:
	var d := wrapf(to - from, -PI, PI)
	return wrapf(from + clampf(d, -max_step, max_step), -PI, PI)


## 相机 yaw 需要回正的角度（猫背后对应的 yaw）
func _yaw_diff() -> float:
	var behind := atan2(sin(rotation.y), cos(rotation.y))
	return wrapf(behind - look_yaw, -PI, PI)
