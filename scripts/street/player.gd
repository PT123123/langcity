class_name Player
extends CharacterBody3D
## 玩家（Stray 式第三人称）：可见的猫 + 弹簧臂跟拍相机。
## 移动：W/S 沿猫的身体朝向前进后退；A/D 持续转动身体（摇杆 x=转向、y=前后）。
## 相机：拖动屏幕环绕（yaw/pitch），弹簧臂自动避开建筑；停手后平滑跟回猫背后（自动回正）。
## 跳跃：空格 / 屏幕按钮，可跳上垃圾桶、长椅、窗台、矮墙等（Stray 的核心玩法之一）。
##
## 【球形重力】street 场景给 planet 赋值（PlanetMath）后，整个运动/相机框架
## 以「脚下表面」为基准：up = 径向（指向球心反向），重力沿 -up，跳跃沿 +up。
## 身体与相机的姿态各维护一个「切向参考向量」（heading / rig 参考），星球上走动时
## 把它们重新投影到新位置的切平面上 —— 相当于沿球面平行输运，转身语义与平地完全一致。
## planet == null（室内）时 up 恒为 +Y，所有公式退化为原来的平地行为。

const SPEED := 2.35           # 猫走路比人慢，但比 Stray 稍快一点，手感更跟手
const ACCEL := 11.0           # 起速
const DECEL := 15.0           # 停步
const GRAVITY := 19.0
const TURN_RATE := 3.0        # A/D 直接转向的角速度（弧度/秒，按住一直转）

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
## 台阶攀爬高度：站在地上能自动跨过的最大高度。
## 【为什么必须自己写】CharacterBody3D 只有 floor_snap_length（向下吸附），
## 没有任何"向上跨过"的机制 —— 凡是高于 0 的坎都被当成垂直墙面，
## 于是上坡被当墙、怎么绕都绕不上去。0.34m 略高于跳跃高度的一半，
## 跨路缘石/台阶/地形小坎够用，又不会让猫"爬"上汽车（车顶 1.5m）。
const STEP_CLIMB := 0.34
## 攀爬探针距离（米）：从抬起的 hypothetical 位置再往前测这么远，看是否通。
## 【它决定"能爬多陡"】台阶可爬的充要条件约是 STEP_CLIMB ≥ CLIMB_PROBE·tan(坡度)：
## 0.34/0.2 → 约 60°，与 floor_max_angle 对齐。能跨路缘石，爬不了建筑外墙。
const CLIMB_PROBE := 0.2
## 攀爬冷却（秒）：一次跨台阶后必须等这么久才能再跨。
## 【为什么必须有】万一判定在某帧失效（比如脚下的地形瞬间变化），
## 没有冷却就会每帧抬一次 STEP_CLIMB，猫直接升空（实测 2 秒飘到 2.7m）。
const CLIMB_CD := 0.12
## ---- 死局自救参数 ----
## 连续推前进但几乎不动多久算"卡住"（秒）。太小会误触发（挤墙时也在动），
## 太大玩家已经察觉到卡了还没反应。
const STUCK_TIME := 1.1
## 【诊断用】置 >999 可临时关闭死局自查（用于确认卡住到底是地形还是脱困逻辑在搅）
const STUCK_DEBUG_DISABLE := false
## 两次脱困之间的冷却（秒），防止连续触发把猫原地抖来抖去。
const UNSTICK_CD := 0.8

# ---- 爬墙（狐狸能上 90° 的垂直墙面）----
## 【核心思路：把墙当地板】整套星球运动框架以 up_axis() 为"脚下法线"基准，
## 于是爬墙时让 up_axis() 返回【墙面法线】，重力就变成"贴住墙"而不是往下掉，
## 切向插值/相机对齐/自动跟随/台阶攀爬全部原样复用 —— 不另写一套墙内运动。
## 90° 垂直墙的法线与径向垂直，是"墙"概念的极限情况，现有路径照常工作。
##
## 【墙 vs 台阶的判据】探射线用"肩高"（CAT_BODY_Y+CAT_RADIUS ≈ 0.35m）而不是
## 胯部：0.3m 的路缘石挡不住 0.35m 的射线，仍归 _try_step_climb；而窗台 0.9m/
## 汽车侧壁/建筑外墙都能命中 → 走爬墙。这也是不用 is_on_wall() 的原因 ——
## 它对胶囊体连路缘石都会报真，没法和台阶分开。
##
## 【输入语义换挡】地面上：drive=沿身体朝向前进、steer=原地转向。
## 墙上：drive=沿墙上下、steer=贴墙横移（朝向锁死为"头朝上"）。
const WALL_MIN_ANGLE := deg_to_rad(65.0)  # 法线与径向夹角 > 65° 才算墙。60° 是可走坡上限，留 5° 滞回带
## 起爬时对脚下地面平缓度的要求（地板法线与径向夹角上限）。50° 卡在
## floor_max_angle(60°) 与 WALL_MIN_ANGLE(65°) 之间当滞回带，见 _on_flat_floor。
const CLIMB_FLAT_ANGLE := deg_to_rad(50.0)
## 身高探射线长度：胶囊贴墙时中心到墙面 ≈ CAT_RADIUS(0.15)，留一倍余量吃法线抖动
const WALL_PROBE := 0.33
const CLIMB_SPEED := 1.25   # 沿墙速度。1.25/2.35=0.53 落在 walk 动画档（<0.62），不会显示成贴墙冲刺
## 挂墙不动多久掉下来（秒）。狐狸会累：抓太久抓不住 —— 这也是"想下就松手"的正确退出方式。
const CLIMB_HANG := 1.1
## 贴墙的压力（m/s，恒定朝墙里压）。v_up 恰好为 0 时 floor_snap_length 的吸附
## 可能不触发，猫就会一帧贴一帧离墙，看起来像抽搐。这 0.6 是持续接触的保证。
const WALL_PRESS := 0.6
## 墙面法线突变的平滑速率（1/秒）：拐角/曲面墙处法线会逐帧跳变，直接赋值会让猫一帧换一面墙。
const WALL_N_RATE := 10.0
## 墙面射线没打中时的宽容时间（秒）。【必须有】棱角/接缝处射线会一帧命中一帧落空，
## 没有滞回就会在 90° 拐角闪烁状态机。
const WALL_STICKY := 0.16

## 猫的体型（Stray 里的猫约肩高 0.23m、体长 0.4m）
const CAT_HEIGHT := 0.36     # 总高（不含头）
const CAT_RADIUS := 0.15
const CAT_BODY_Y := 0.2# 碰撞胶囊中心
const CAT_VISUAL_SCALE := 0.82# 视觉缩放（模型比碰撞体略大，看起来更敦实）

# ---- 爬墙几何量（依赖上面的体型常量，必须放在它们之后）----
## 肩高：探墙射线发射高度。CAT_BODY_Y(0.2)+CAT_RADIUS(0.15)=0.35 ——
## 0.35m 以下的路缘石挡不到射线，碰撞归台阶攀爬；更高的（窗台/车侧/墙）走爬墙。
const SHOULDER := CAT_BODY_Y + CAT_RADIUS
## 翻顶时沿径向抬脚的高度。【实测推导，不是拍的】头探不到墙 ⇒ origin.y ≥ 墙顶−0.35
## （SHOULDER）；爬墙姿态下胶囊底 = origin.y − CAT_HEIGHT/2(0.18)。要底边过墙沿还得
## 0.35 + 0.18 + 0.05 余量 = 0.58。当初取 0.45 时 test_move 恒被墙顶角挡住，
## mantle 永远不触发，狐狸靠宽容期越顶后摔下来 —— 表现就是"翻上去了又掉下来"。
const MANTLE_RAISE := 0.58

const CAM_DIST := 1.32# 弹簧臂长度（猫变小后要拉近，否则猫看起来更小）
const CAM_HEIGHT := 0.34# 相机枢轴相对猫脚的高度（沿脚下表面的法线）
const CAM_FOV := 62.0# 默认视场角（拍照取景模式会拉到 26，退出后恢复到这里）
const CAM_PITCH_MIN := -1.32   # 相机升到接近正俯视（原 -0.95，俯角更大方便看屋顶/认路）
const CAM_PITCH_MAX := 0.52# 仰视极限（原 0.10）：低角度仰拍建筑/樱花；再大弹簧臂会贴地翻-up
const CAM_PITCH_HOME := -0.20  # 静止时回正的俯角（略俯视）
const CAM_FOLLOW_RATE := 4.0   # 相机平滑跟到猫背后的速度（1/秒）
const CAM_FOLLOW_DELAY := 0.25 # 手动转视角后，停顿多久恢复自动跟随
const CAM_MIN_Y := 0.2# 相机离地下限（仅平地模式：防插进地面；星球上由弹簧臂挡地形）
## 相机枢轴「位置」的平滑速度（1/秒）。与 CAM_FOLLOW_RATE（yaw 回正）是两码事。
## 【为什么需要】上台阶时 _try_step_climb 会在**一帧内**把猫抬高最多 STEP_CLIMB(0.34m)，
## 相机若硬跟随，每上一级就是一次纵向顿挫 —— 玩家反馈「上台阶视角又快又晃」。
## 用指数阻尼跟随位置，顿挫被抹平；teleport/爬墙切换时仍直接 snap（见 teleport）。
const CAM_POS_RATE := 16.0
## 鼠标滚轮缩放：_zoom ∈ [-1, 1]，0 = 默认。负 = 拉远（看全景/找路），正 = 拉近
## （看单词/拍照取景）。同时调 FOV 与弹簧臂（TPS 的常规手感）。
const ZOOM_FOV_MIN := 26.0    # 拉到最近时的视场角（与拍照取景一致）
const ZOOM_DIST_MIN := 0.55   # 拉到最近时的弹簧臂长度（米）
const ZOOM_FOV_MAX := 72.0    # 拉到最远时的视场角（广角看全景）
const ZOOM_DIST_MAX := 3.8    # 拉到最远时的弹簧臂长度（米；弹簧臂挡地形，不会插进地里）
const ZOOM_STEP := 0.07       # 每滚一格的缩放增量（比旧 0.12 更细，档位更多）
const ZOOM_SMOOTH := 10.0     # 缩放平滑速度（1/秒）：滚轮给目标值，每帧指数逼近，手感更顺
## 台阶「视觉缓冲」回中速度（1/秒）。见 _physics_process 里的 _visual_sink。
const AVATAR_SINK_RATE := 12.0

const LOOK_SENS := 0.0028

var planet: PlanetMath = null      # 星球参数；null = 平地（室内）
var input_vec := Vector2.ZERO      # 虚拟摇杆写入（屏幕方向：x 右 / y 下）
var input_locked := false
var jump_pressed := false         # 由跳跃按钮/键盘写入
var jump_held := false

var look_yaw := 0.0                # 相机方位角（相对 _cam_rig 切平面参考；0 = 相机在猫正后方）
var look_pitch := CAM_PITCH_HOME
var _idle_t := 0.0                # 距上次手动转视角的时间，用于自动跟随
var _turn_rate := 0.0             # 当前转向角速度（供身体侧倾用）
var _zoom := 0.0                  # 滚轮缩放当前值：-1 = 最远，0 = 默认，1 = 最近（见 _apply_zoom）
var _zoom_target := 0.0           # 滚轮写入的目标缩放值（每帧向它平滑逼近）
var _visual_sink := 0.0           # 台阶抬升的视觉下沉缓冲（米，仅影响 avatar 外观）
var _prev_visual_pos := Vector3.ZERO   # 上一帧身体位置，用于量「台阶瞬移」
var cam_follow := true            # 是否自动跟随到猫背后（调试截图时关闭）
var _coyote := 0.0
var _jump_buf := 0.0
var _was_floor := true
var _last_fall_speed := 0.0
var _land_squash := 0.0
## 攀爬反馈计时（供动画/音效用；0 = 刚没在爬）
var _climb_flash := 0.0
## 死局自救状态：_stuck_t = 连续"推不动"的时长，_stuck_pos = 上次能动到的位置，
## _unstick_t = 脱困冷却剩余秒数。
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _unstick_t := 0.0
## 攀爬冷却剩余秒数（防止连续抬升把猫送上天）
var _climb_cd := 0.0
## move_and_slide() 之前的位置：用来算"这一帧实际前进了多少"（台阶攀爬判定用）
var _pre_slide_pos := Vector3.ZERO

# ---- 爬墙状态 ----
## 爬墙中：up_axis() 返回墙面法线，整套运动框架改以墙面为地板。
var climbing := false
## 当前贴着的墙面法线（世界空间，已归一）。爬墙时它就是"上"方向。
var _wall_n := Vector3.UP
## 墙面射线没打中时的宽容计时（见 WALL_STICKY）
var _wall_sticky_t := 0.0
## 爬墙期间的攀爬高度动画相位（供 avatar 四肢交替）
var _climb_phase := 0.0
## 挂墙不动的累计时间（超过 CLIMB_HANG 会因脱力而掉下来）
var _climb_hang_t := 0.0
## 【上一帧】是否"推着前进却几乎没动"——爬墙进入的触发条件，由主循环移动块置位。
## 用上一帧的信息而不是本帧，是为了在 _update_wall_climb 里可以先切换状态再读 up。
var _blocked_last := false

var cam: Camera3D
var avatar: CatAvatar
var _arm: SpringArm3D
var _shape: CollisionShape3D # 碰撞胶囊；爬墙时单独旋转（见 _climb_enter）
var _cam_rig: Node3D       # 表面对齐框架（top_level）：Y=脚下法线，由切向参考并行输运
var _cam_euler: Node3D     # yaw/pitch 欧拉层：rotation = (pitch, yaw, 0)，沿用原习惯
var _heading := Vector3(0, 0, -1)   # 身体朝向（切向单位向量 = facing）

## 【出生点必须延迟到物理帧之后再射线落位】见 _physics_process 开头。
## 街景在 _ready() 里调 PlanetBuilder.surface() 时，物理服务器还没把地形 trimesh
## 同步进宽相，射线全部落空 → surface() 返回标称球面 fallback（r=34×scale=51）。
## 真实岛面在 r≈35.5，出生点因此悬空 15m，猫一进世界就自由落体砸下去 ——
## 表现为"某些方向特别不顺畅"（实际是落地姿态与朝向都错乱）。
## 置位后在第一个物理帧用真射线重新落位。
var _need_ground_snap := false
## 落位射线方向（出生时的径向），延迟落位时沿它向下找地面
var _snap_dir := Vector3.UP


func _ready() -> void:
	collision_layer = 2
	collision_mask = 3   # 地面(2) + 障碍物(1)
	# 上台阶：小于这个高度的障碍直接跨过（路缘石、低边框）
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(60)
	# 【Godot 4 里没有 wall_max_angle；卡上坡的真开关是 floor_stop_on_slope】
	# 它默认 true：只要脚下地面被判定为"坡"（法线不贴 up），move_and_slide 就把
	# 沿坡速度整体清零，猫一步都迈不出去。星球上处处是坡，等于全岛都走不动 ——
	# 实测缓坡方向 6.4m 正常、陡坡方向 113~148 帧速度恒为 0。
	# 关掉它：坡上不再无条件刹停，速度由下面的"沿地面切向插值"自然约束。
	# 真正的墙（建筑/围墙）近乎垂直，仍由 move_and_slide 正常挡住。
	floor_stop_on_slope = false
	# 沿坡也允许贴地滑行（否则下坡会一步一顿）
	floor_constant_speed = true

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAT_RADIUS
	capsule.height = CAT_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0, CAT_BODY_Y, 0)
	add_child(shape)
	_shape = shape

	avatar = CatAvatar.new()
	avatar.scale = Vector3.ONE * 0.82   # 体型缩小 18%
	add_child(avatar)

	# 相机框架：_cam_rig 只跟随位置 + 表面对齐（top_level，不吃身体旋转），
	# _cam_euler 里才是拖动产生的 yaw/pitch。两层分开：
	# 走动引起的"脚下平面变化"不吞掉手动视角，手动视角也不污染表面参考。
	# 【关键】rig 必须 top_level：否则它继承猫的身体旋转，猫一转身相机就被甩着转。
	_cam_rig = Node3D.new()
	_cam_rig.top_level = true
	add_child(_cam_rig)
	_cam_euler = Node3D.new()
	_cam_rig.add_child(_cam_euler)

	_arm = SpringArm3D.new()
	_arm.spring_length = CAM_DIST
	_arm.margin = 0.22
	_arm.collision_mask = 1      # 被建筑/星球地形挡住（星球碰撞体含层 1）
	_cam_euler.add_child(_arm)

	cam = Camera3D.new()
	cam.fov = CAM_FOV
	cam.near = 0.06
	cam.far = 260.0
	_arm.add_child(cam)
	cam.make_current()

	teleport(global_position, 0.0, true)


func _unhandled_input(event: InputEvent) -> void:
	# 鼠标滚轮缩放视野：滚上 = 拉近（收窄 FOV），滚下 = 拉远（越过默认值看全景）
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target + ZOOM_STEP, -1.0, 1.0)
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target - ZOOM_STEP, -1.0, 1.0)
			get_viewport().set_input_as_handled()
			return
	# 键盘跳跃（桌面调试用）：空格 / W+Shift 也行
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE):
		jump_pressed = true
		jump_held = true
	elif event.is_action_released("ui_accept") or (event is InputEventKey and not event.pressed and event.keycode == KEY_SPACE):
		jump_held = false


## 每物理帧：缩放平滑逼近目标值。滚轮只写 _zoom_target，FOV/臂长在这里渐变 ——
## 一步到位的硬切在近距离时画面跳动明显，恒速逼近手感更顺（全程约 0.2 秒）。
func _smooth_zoom(delta: float) -> void:
	if is_equal_approx(_zoom, _zoom_target):
		return
	_zoom = move_toward(_zoom, _zoom_target, ZOOM_SMOOTH * delta)
	if absf(_zoom_target - _zoom) < 0.003:
		_zoom = _zoom_target
	_apply_zoom()


## 应用缩放：_zoom 0 = 默认（CAM_FOV / CAM_DIST），1 = 最近，-1 = 最远。
## FOV 全程线性；臂长分两段（负值段拉远、正值段拉近），0 处斜率不连续无妨 —— 都很远。
func _apply_zoom() -> void:
	if _zoom >= 0.0:
		cam.fov = lerpf(CAM_FOV, ZOOM_FOV_MIN, _zoom)
		if _arm != null:
			_arm.spring_length = lerpf(CAM_DIST, ZOOM_DIST_MIN, _zoom)
	else:
		cam.fov = lerpf(CAM_FOV, ZOOM_FOV_MAX, -_zoom)
		if _arm != null:
			_arm.spring_length = lerpf(CAM_DIST, ZOOM_DIST_MAX, -_zoom)


## 当前视场角（含滚轮缩放）。拍照取景退出时用它恢复，别硬写 CAM_FOV 把缩放吞了。
func zoom_fov() -> float:
	return cam.fov


# ---------------- 表面基准 ----------------

## 脚下的"上"方向：星球上 = 径向；平地 = +Y
##
## 【爬墙接入点】爬墙时返回【墙面法线】而不是径向 —— 于是重力、相机对齐、切向插值
## 全部自动改以墙面为地板。这是"墙当地板"思路能免费复用整套框架的唯一原因。
func up_axis() -> Vector3:
	if climbing:
		return _wall_n
	return _gravity_up()


## 相机用的"上"方向：爬墙时【仍是径向】，不跟着墙面翻。
## 【为什么与运动分开】如果相机 up 也换成墙面法线，爬垂直墙时整个画面会绕视野轴
## 滚 90°，玩家瞬间失去方向感（"墙朝哪边"都判断不了）。运动跟着墙、镜头不跟，
## 是爬墙游戏（《镜之边缘》《只狼》）的通行做法：身体横过来，镜头保持世界朝向。
func cam_up() -> Vector3:
	return _gravity_up()


## 重力反方向（星球 = 径向，平地 = +Y）。【不响应 climbing】—— 是"世界意义"的上，
## up_axis()/cam_up() 都从它派生，爬墙逻辑判定墙面陡峭程度也用它。
## 爬墙逻辑到处要它（判定墙面陡不陡、"往上爬"的方向），提成一个函数避免每次重复内联。
## 【只此一份】曾经在本文件 859 行附近重复定义过一次，整个 Player 类解析失败 →
## 依赖它的 street.gd / 探针脚本一起挂掉（"Could not resolve class Player" 级联）。
## 加同名函数前先 grep "func <名字>"。
func _gravity_up() -> Vector3:
	if planet != null:
		var up := global_position - planet.center
		if up.length_squared() > 1e-6:
			return up.normalized()
	return Vector3.UP


## 把切向向量投影回当前切平面并归一（并行输运的核心步骤）；退化时回退到 fallback
static func _reproject(v: Vector3, up: Vector3, fallback: Vector3) -> Vector3:
	var t := v - up * v.dot(up)
	if t.length_squared() < 1e-6:
		t = fallback - up * fallback.dot(up)
	if t.length_squared() < 1e-6:
		return fallback
	return t.normalized()


## 由「上方向 + 朝向」拼身体基（X=右 Y=上 Z=-朝向，右手系）
static func _basis_from(up: Vector3, heading: Vector3) -> Basis:
	return Basis(heading.cross(up), up, -heading)


## 速度的水平（切向）分量长度
func tangent_speed() -> float:
	var up := up_axis()
	return (velocity - up * velocity.dot(up)).length()


# ---------------- 视角 ----------------

## 拖动转视角（像素增量）
func look(dx_px: float, dy_px: float) -> void:
	var sens: float = LOOK_SENS * float(Game.settings.get("cam_sens", 1.0))
	look_yaw = wrapf(look_yaw - dx_px * sens, -PI, PI)
	look_pitch = clampf(look_pitch - dy_px * sens, CAM_PITCH_MIN, CAM_PITCH_MAX)
	_idle_t = 0.0
	_apply_cam_rotation()


func _apply_cam_rotation() -> void:
	_cam_euler.rotation = Vector3(look_pitch, look_yaw, 0)


## 请求在下一个物理帧重新贴地（出生时用；见 _need_ground_snap 注释）
func request_ground_snap() -> void:
	if planet == null:
		return
	_need_ground_snap = true
	_snap_dir = up_axis()


## 延迟落位：出生后第一个物理帧，沿出生径向向岛心打射线找真实地面并贴上去。
## 只处理"射线有命中"的情况；打不到（出生点本就在空处）就保留原位。
func _ground_snap() -> void:
	if planet == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var d := _snap_dir.normalized()
	# 从岛外高处沿 -d 打进来，命中第一个地形面（层 2 = 地形）
	var far := planet.radius * 3.0 + 30.0
	var q := PhysicsRayQueryParameters3D.create(d * far, -d * 2.0, 2)
	q.collide_with_bodies = true
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var pos: Vector3 = hit["position"]
	var n: Vector3 = (hit["normal"] as Vector3).normalized()
	# 法线朝外才认（岛面法线应与径向同侧）；否则说明打到了内壁/背面，跳过
	if n.dot(d) <= 0.0:
		return
	teleport(pos + n * 0.15, NAN, true)


## 摆到指定位置。yaw 的语义：星球上 0 = 朝北（朝岛顶），绕脚下法线旋转；
## 平地上与旧版 rotation.y 完全一致。keep_heading=true 时不改朝向（仅 _ready 初始化用）。
func teleport(pos: Vector3, yaw := NAN, keep_heading := false) -> void:
	position = pos
	velocity = Vector3.ZERO
	_turn_rate = 0.0
	# 瞬移后重置卡死检测：否则新位置还没动过就被判成"卡住一秒"然后莫名脱困
	_stuck_pos = pos
	_stuck_t = 0.0
	_unstick_t = 0.0
	_climb_cd = 0.0
	# 台阶视觉缓冲复位：否则瞬移后残留的下沉偏移会让猫短暂“陷”一下
	_visual_sink = 0.0
	_prev_visual_pos = pos
	# 【瞬移必须清爬墙】否则仍 clinging 着旧位置的墙，新位置却在半空 ——
	# up_axis() 继续返回旧墙法线，整套框架的"上"方向是错的，会持续往旧墙贴。
	climbing = false
	_wall_sticky_t = 0.0
	_climb_hang_t = 0.0
	_blocked_last = false
	var up := up_axis()
	if not keep_heading:
		if not is_nan(yaw):
			if planet != null:
				_heading = Basis(up, yaw) * planet.north_at(up)
			else:
				_heading = Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
		global_transform.basis = _basis_from(up, _heading)
		# 相机参考与身体朝向对齐：look_yaw=0 即相机在猫正背后。
		# 相机基用 cam_up()：teleport 通常不在爬墙中，但保持单一入口更安全。
		_cam_rig.global_transform.basis = _basis_from(cam_up(), _heading)
		look_yaw = 0.0
	look_pitch = CAM_PITCH_HOME
	_idle_t = 0.0
	_cam_rig.global_position = global_position + cam_up() * CAM_HEIGHT
	_apply_cam_rotation()


## 相机当前朝向（切向投影），供罗盘/任务指引换算。
## 平地时与旧公式 (-sin yaw, 0, -cos yaw) 逐项相等。
## 【用 cam_up 而非 up_axis】爬墙时镜头不该跟着墙翻（见 cam_up 注释）。
func cam_forward() -> Vector3:
	var up := cam_up()
	return _reproject(-_cam_euler.global_basis.z, up, _heading)


func cam_right() -> Vector3:
	return cam_forward().cross(up_axis()).normalized()


## 角色当前身体朝向（切向单位向量）
func facing() -> Vector3:
	return _heading


## 瞄准世界坐标 target 所需的 (yaw, pitch)：取景自动对准 / 截图钩子共用。
## yaw 是 look_yaw 的目标值（相对当前 rig 参考），pitch 相对脚下切平面。
func aim_angles(target: Vector3) -> Vector2:
	var pivot: Vector3 = _cam_rig.global_position
	var to := target - pivot
	var up := up_axis()
	var f := cam_forward()
	var t := _reproject(to, up, f)
	var yaw_d := atan2(f.cross(t).dot(up), f.dot(t))
	return Vector2(look_yaw + wrapf(yaw_d, -PI, PI), asin(clampf(to.normalized().dot(up), -1.0, 1.0)))


# ---------------- 移动 ----------------

func _physics_process(delta: float) -> void:
	_idle_t += delta
	_smooth_zoom(delta)
	_unstick_t = maxf(0.0, _unstick_t - delta)
	_climb_cd = maxf(0.0, _climb_cd - delta)
	_climb_flash = maxf(0.0, _climb_flash - delta)

	# ---- 出生点延迟落位（必须在物理帧内，物理服务器此时才有地形）----
	if _need_ground_snap:
		_need_ground_snap = false
		_ground_snap()

	# ---- 输入：W/S 前后，A/D 转向。摇杆 x=转向、y=前后（上为前进）----
	var steer := 0.0
	var drive := 0.0
	if not input_locked:
		if input_vec.length() > 0.12:
			steer = clampf(input_vec.x, -1.0, 1.0)
			drive = clampf(-input_vec.y, -1.0, 1.0)
		else:
			steer = Input.get_axis("move_left", "move_right")
			drive = -Input.get_axis("move_up", "move_down")

	# ---- 爬墙状态机：必须在读 up 之前跑，因为 climbing 会改变 up_axis() 的语义 ----
	_update_wall_climb(delta, steer, drive)
	var up := up_axis()
	var cup := cam_up()

	# 【球面重力的命门】CharacterBody3D.is_on_floor() 是拿碰撞面法线和【up_direction】
	# 比夹角（floor_max_angle）来判定"踩没踩在地上"，而 up_direction 默认是全局 +Y。
	# 星球上只有北极附近才碰巧对：走到中低纬度，地面法线与 +Y 的夹角 = 极轴角距 + 地形坡度，
	# 一旦超过 floor_max_angle，is_on_floor() 永远返回 false。后果是连锁的：
	#   重力每帧继续累积下坠速度（猫永远在"掉"）→ accel 降成 AIR_CONTROL → floor_snap 失效
	#   → 落地清零分支永不执行 → 下坠速度无上限。
	# 表现就是"某些方向特别不顺畅"：上坡/离极轴方向地面法线更偏离 +Y，先失效；
	# 下坡/靠极轴方向侥幸还在阈值内，于是只有一路顺畅。
	# 每帧把 up_direction 同步成当地法线，地板判定才跟着球面走。
	# 爬墙时 up 已是墙面法线，于是地板判定自动跟到墙上 —— 这正是"墙当地板"的关键。
	up_direction = up

	# ---- 表面框架输运：星球上走动后，把身体朝向与相机参考投影到新切平面 ----
	# 相机用 cup（不跟墙翻）、身体用 up（跟墙），两者刻意分开，见 cam_up()。
	if planet != null:
		var fb := global_transform.basis.x
		_heading = _reproject(_heading, up, fb)
		var ref := _reproject(_cam_rig.global_basis.z, cup, _heading)
		global_transform.basis = _basis_from(up, _heading)
		_cam_rig.global_transform.basis = Basis(cup.cross(ref), cup, ref)
	# 位置用指数阻尼跟随（见 CAM_POS_RATE）：逐级台阶的瞬时抬高被抹平，不再一顿一顿
	_cam_rig.global_position = _cam_rig.global_position.lerp(
		global_position + cup * CAM_HEIGHT, 1.0 - exp(-CAM_POS_RATE * delta))

	# ---- 转向：按住 A/D 身体绕脚下法线持续旋转（原地也能转，不依赖移动方向）----
	# 【爬墙禁用原地转向】爬墙上 steer = 横移（上面 want 已加上侧向项）；
	# 若这里还转身体，横移和转身会同时发生 —— 狐狸在墙上原地转圈，非常诡。
	if not climbing and absf(steer) > 0.001:
		_heading = _reproject(Basis(up, -steer * TURN_RATE * delta) * _heading, up, up)
		global_transform.basis = _basis_from(up, _heading)
	_turn_rate = -steer * TURN_RATE if not climbing else 0.0

	# ---- 前后移动：沿猫的身体朝向前进 / 后退 ----
	# 【SPEED 必须乘在这里】球面化重构时曾丢掉这个乘数，目标速度变成 drive（上限
	# 1.0 m/s），猫全程像陷在泥里 —— "某些方向阻力特别大"的主因就是它。
	# 【want 必须躺在地面上】径向 up 只在正对山壁时才等于"水平"。上坡时目标速度
	# 有一半是扎进山体的，move_and_slide 把它当撞墙吃掉，猫就顶在坡上走不动
	# （实测 44° 坡位移 1.9m、113 帧速度为 0；缓坡 13° 位移 6.4m 正常）。
	# 所以站地上时把 want 投影到【实际地面法线】张成的平面，再按地面法线重算切向速度。
	# 站地上用【真实地面法线】建切向基，空中用径向。
	# 对照实测（固定起点、四个朝向各走 3 秒的位移）：
	#   纯径向基   → 0.67 / 2.35 / 1.86 / 6.51 m（180° 方向又憋回去了）
	#   地面法线基 → 0.64 / 2.39 / 5.43 / 6.42 m（明显更均匀）
	# 所以基向量必须跟着地面走，不能一律用径向。
	var ground_n := get_floor_normal() if is_on_floor() else Vector3.ZERO
	var use_n := up
	if ground_n.length_squared() > 0.5 and ground_n.dot(up) > 0.0:
		use_n = ground_n.normalized() if ground_n.dot(up) > 0.0 else -ground_n.normalized()
	var heading_move := _reproject(_heading, use_n, _heading)
	# 【爬墙 = 输入语义换挡】地上：drive=沿身体朝向前进，steer=原地转身体。
	# 墙上：朝向已被 _update_wall_climb 锁死为"头朝上"（= 径向在墙面上的投影），
	# 于是 heading_move 就是沿墙的纵向，drive 直接是"爬上/爬下"；
	# steer 不再转身体，而是给贴墙平面里的横移分量（即 want 的侧向项）。
	var want := heading_move * (drive * (CLIMB_SPEED if climbing else SPEED))
	if climbing:
		want += heading_move.cross(use_n).normalized() * (steer * CLIMB_SPEED)
	if want.length() > (CLIMB_SPEED if climbing else SPEED):
		want = want.normalized() * (CLIMB_SPEED if climbing else SPEED)
	var moving := absf(drive) > 0.08

	# 速度：平滑起停，猫没有急停急起（切向与法向分开算，重力不被"减速"污染）
	var on_floor := is_on_floor()
	# 空中操控力弱一些，但够玩家微调落点（Stray 里的猫能空中修正）
	var accel := (ACCEL if on_floor else ACCEL * AIR_CONTROL)
	var rate := (accel if moving else DECEL)
	if not on_floor and not moving:
		rate = DECEL * 0.35   # 空中松手几乎不减速度，抛物线更干净
	var v_up := velocity.dot(up)          # 径向分量（重力/跳跃/落地冲击都用它）
	# 【法向轴随地面】站地上用真实地面法线、空中用径向。切向速度在【垂直于该轴】
	# 的平面内插值：不能在切平面里插值完又拿径向 up 去重组 —— 斜坡上这两个平面
	# 不一致，径向分量会被重复计入，越陡越离谱（44° 坡实测速度只剩 0.32m/s）。
	# 法向轴（站地上=真实地面法线，空中=径向）只用于【切向基的朝向】。
	# 重组时法向仍沿径向 up —— 用 use_n 重组会让猫每帧被地面法线"甩"离地
	# （实测 is_on_floor 从 180/180 掉到 1/180，整只猫在贴地飞行）。
	var v_n := velocity.dot(use_n)
	var v_tan := velocity - use_n * v_n
	# 【必须在切向基里插值，不能按世界 x/y/z 分量逐轴 move_toward】
	# 逐轴写法只在平面恰好与世界轴对齐时等价。在星球上，走到中低纬度切平面
	# 相对世界轴是斜的，逐轴逼近会漏出沿法线的分量（往地里钻/浮空），
	# 且漏多少取决于 want 在世界轴上的符号组合 —— 正是"某个方向特别费劲"的形状。
	var right := heading_move.cross(use_n).normalized()
	var v_fwd := v_tan.dot(heading_move)
	var v_side := v_tan.dot(right)
	var want_fwd := want.dot(heading_move)
	var want_side := want.dot(right)
	v_fwd = move_toward(v_fwd, want_fwd, rate * delta)
	v_side = move_toward(v_side, want_side, rate * delta)
	v_tan = heading_move * v_fwd + right * v_side

	# ---- 重力（沿 -up）----
	# 【必须先加重力，再做跳跃判定】跳起当帧的 v_up = JUMP_VELOCITY 不能被同帧清零
	if not on_floor:
		if climbing:
			# 爬墙时"重力"是贴墙压力，不是自由落体：法向速度锁在 -WALL_PRESS，
			# 不累加 —— 自由落体的累加会把猫死死按进墙里（move_and_slide 把法向速度
			# 全吃掉，位移为零，看起来像卡墙），而向上的法向速度也必须禁止，
			# 否则摇杆推满时法向插值会试图脱离墙面。
			v_up = -WALL_PRESS
		else:
			v_up -= GRAVITY * delta

# ---- 跳跃 ----
	# coyote time：刚离开边缘仍可跳；jump buffer：落地前提前按也生效。
	# 这两个是手游跳跃手感的命门，少一个都会觉得"跳不动"或"没反应"。
	# 【爬墙中禁用跳跃】跳跃冲量沿 up，而爬墙时 up 是墙法线 —— 等于朝墙里猛撞一下，
	# move_and_slide 全部吃掉，玩家看到的是"按跳没反应"。爬墙想离墙靠松开摇杆或跳离墙沿。
	if climbing:
		jump_pressed = false
		_jump_buf = 0.0
		_coyote = 0.0
	if on_floor:
		_coyote = COYOTE
	else:
		_coyote = maxf(0.0, _coyote - delta)
	if jump_pressed:
		_jump_buf = JUMP_BUFFER
	else:
		_jump_buf = maxf(0.0, _jump_buf - delta)
	var jumped := false
	if _jump_buf > 0.0 and _coyote > 0.0:
		jumped = true
		_jump_buf = 0.0
		_coyote = 0.0
		jump_pressed = false   # 消费掉这次按压：按住不松也不会落地自动连跳
		Game.play_sfx("click")
	# 可变跳跃高度：上升途中松手就减速，短按小跳、长按大跳
	if v_up > 0.0 and not jump_held and not jumped:
		v_up -= GRAVITY * JUMP_CUT * delta * 8.0

	# ---- 爬墙：动画相位随速度走（切向速度已由上面的通用插值给出）----
	if moving or climbing:
		_climb_phase += delta * (4.0 + v_tan.length() * 4.5)
	# 重组：切向在"垂直于 use_n"的平面内（贴着地面走），法向沿径向 up。
	# 【不要在站地上省掉 up*v_up】试过"站地上只用 v_tan"，径向分量一丢，
	# 球面重力就没有法向约束，猫会顺着坡面滑出去/贴地飞行，180° 方向从
	# 5.45m 掉回 1.87m。保留法向项，由 move_and_slide 负责约束。
	# 跳跃沿径向给冲量（斜坡上沿地面法线起跳会横着飞出去）。
	if jumped:
		velocity = v_tan + up * JUMP_VELOCITY
	else:
		velocity = v_tan + up * v_up
	_pre_slide_pos = global_position
	move_and_slide()
	# ---- 台阶攀爬（Godot 没有内置，必须自己写）----
	# floor_snap_length 只能把猫【向下】吸附到地面，不能往上抬 —— 所以任何
	# 高于 0 的坎都是一堵墙，表现为"上坡被当墙 / 怎么绕都绕不上去"。
	# 【触发条件必须用"几乎没动"，不能用 is_on_wall()，也不能用"没走满"】
	# is_on_wall()：矮台阶会被胶囊当斜面处理 → 为假，矮台阶反而爬不上去。
	# "没走满 70%"：斜坡上猫本来就走得慢（会滑），会误判成被挡 → 每一帧都
	#   抬起 0.34m 再掉回来，进度被反复清零（实测 20° 缓坡方向 3 秒只走 0.78m）。
	# 所以门槛取"几乎零进展"：正常滑行/爬坡都有明显位移，不会触发。
	# 【爬墙中禁用台阶攀爬】它沿 up 抬起 STEP_CLIMB，而爬墙时 up 是墙法线 ——
	# 于是"抬起 0.34m"变成"往墙里塞 0.34m"，紧接着 test_move 探针必然失败，
	# 而且每帧一次会把贴墙压力打断，猫一卡一顿。
	# 同时把"推着前进却几乎没动"记下来给下一帧的爬墙状态机用（_blocked_last）：
	# 台阶攀爬先试，矮台阶能过就过；过不去（真的是墙）时，下一帧才会转向爬墙。
	_blocked_last = false
	if not jumped and not climbing and (on_floor or _coyote > 0.0) and moving:
		var want_dist := SPEED * delta
		var real_dist := (global_position - _pre_slide_pos).dot(heading_move)
		if real_dist < want_dist * 0.25:
			_blocked_last = true
			_try_step_climb(heading_move, delta)
	# 【爬墙中不做死局自救】爬墙时"几乎不动"是常态（顶在墙上不动），
	# _update_stuck 会判定卡住然后把猫跳走/侧推 —— 玩家正在爬墙却被自动踢下来。
	if not climbing:
		_update_stuck(delta, moving)

	# 自动跟随 / 回正：手动转视角后停顿一下，就平滑跟回猫背后。
	# 移动基准是身体朝向，相机不影响移动方向，不存在"边走边回正画圈"的反馈环。
	if cam_follow and bool(Game.settings.get("cam_auto_recenter", true)) \
			and _idle_t > CAM_FOLLOW_DELAY and not input_locked:
		var f := 1.0 - exp(-CAM_FOLLOW_RATE * delta)
		look_yaw = wrapf(look_yaw + _yaw_diff() * f, -PI, PI)
		look_pitch = lerpf(look_pitch, CAM_PITCH_HOME, f)
		_apply_cam_rotation()

	# ---- 落地压缩（squash & stretch）----
	# 落地瞬间按冲击速度把猫压扁，然后弹回。这是「有重量」的关键。
	# 【爬墙中排除】爬墙时 is_on_floor() 也为真（墙就是地板），于是每个物理帧
	# 都判成"刚落地"→ _land_squash 被反复拉满，猫变成一直在原地抽搐的一团。
	# 而且下面那段"清残留法向速度"会把贴墙压力 WALL_PRESS 一起清零，
	# 正好和爬墙需要的持续接触相冲突。所以整个落地分支都要判 not climbing。
	var now_floor := is_on_floor() and not climbing
	if now_floor and not _was_floor:
		var impact := clampf(_last_fall_speed / 6.0, 0.0, 1.0)
		_land_squash = impact
		_last_fall_speed = 0.0
	elif not now_floor:
		_last_fall_speed = maxf(_last_fall_speed, -v_up)
	_was_floor = now_floor
	# 落地后清掉残留的法向速度（跳起当帧 v_up > 0，不会被这里误伤）
	# 【沿真实地面法线投影，而不是径向】站在斜坡上时"多余"的速度分量是相对地面的，
	# 不是相对径向的。用 up 投影会把下坡时沿坡向下的合法速度也一起削掉 ——
	# 那正是"下坡顺畅、上坡憋住"里被误伤的一半。地面法线才是正确的投影轴。
	var up2 := up_axis()
	if now_floor:
		var fn := get_floor_normal()
		var axis := up2 if fn.length_squared() < 0.5 else fn.normalized()
		if velocity.dot(axis) < 0.0:
			velocity -= axis * velocity.dot(axis)
	# 爬墙期间 _land_squash 强制归零：进爬墙前若残留落地压缩，
	# 会让贴墙的狐狸一直是压扁的形状。
	if climbing:
		_land_squash = 0.0
		_last_fall_speed = 0.0
	if _land_squash > 0.0:
		_land_squash = maxf(0.0, _land_squash - delta * 3.6)
		# 压扁量 0.22，横向撑开同样的比例（体积守恒的近似）
		var s := _land_squash * 0.22
		avatar.scale = Vector3.ONE * CAT_VISUAL_SCALE * Vector3(1.0 + s * 0.7, 1.0 - s, 1.0 + s * 0.7)
	else:
		avatar.scale = Vector3.ONE * CAT_VISUAL_SCALE

	# 角色动画（步速按切向速度算，星球上沿球面走不误判为下落）
	var gait := clampf(tangent_speed() / SPEED, 0.0, 1.0)
	avatar.animate(delta, gait, _turn_rate, climbing, _climb_phase)
	_air_pose(up2)

	# 台阶「视觉缓冲」：_try_step_climb 会在**一帧内**把身体抬高最多 STEP_CLIMB(0.34m)，
	# 猫模型若硬跟，每一级台阶都是一次向上弹跳（玩家反馈「爬楼梯一跳一跳」）。
	# 给 avatar 一个向下的临时偏移并指数回中，纵向被抹平。阈值 0.15m 只抓「台阶瞬移」——
	# 正常上坡每帧才 ~0.03m，不会误触发（否则上坡时猫会一直微微下沉）。
	var rise := (global_position - _prev_visual_pos).dot(up_axis())
	if rise > 0.15:
		_visual_sink = minf(_visual_sink + rise, STEP_CLIMB)
	_visual_sink = lerpf(_visual_sink, 0.0, 1.0 - exp(-AVATAR_SINK_RATE * delta))
	_prev_visual_pos = global_position
	avatar.position = Vector3(0, -_visual_sink, 0)


## 台阶攀爬：被挡住且在推前进时，尝试"抬腿跨过去"。heading 是期望前进方向。
## 判定用 test_move（无副作用），三步全过才真正改变位置。
## 【探针距离决定"能爬多陡"】用固定的 CLIMB_PROBE 而不是当帧位移来测前方：
## 台阶可爬的充要条件是 CLIMB_CLIMB >= probe·tan(坡度)，即 probe 越大越严格。
## probe=0.2、STEP_CLIMB=0.34 → 上限约 60°，与 floor_max_angle 对齐 ——
## 这样能跨路缘石/台阶，但爬不了建筑外墙（近乎垂直，测试直接失败）。
## 台阶攀爬：被挡住且在推前进时，尝试"抬腿跨过去"。heading 是期望前进方向。
## 【必须是"抬起→前进→落下"三段式，不能只往上抬】
## 只抬不落 = 猫被顶在空中持续上升（实测 2 秒飘到 2.7m 高，像坐火箭）。
## 正确顺序：① 抬起后头顶无碰撞 ② 抬起后前方可通行（台阶 vs 真墙的分界）
##          ③ 真的抬起并前进 ④ 【落下贴回台阶顶面】—— 这一步是关键，
##          缺了它猫就悬在半空，下一帧又触发一次，越抬越高。
## 另加 _climb_cd 冷却兜底：万一判定异常，也不会每帧抬一次。
func _try_step_climb(heading: Vector3, delta: float) -> void:
	if _climb_cd > 0.0:
		return
	var up := up_axis()
	# ① 头顶空间
	if test_move(global_transform, up * STEP_CLIMB):
		return
	# ② 抬起来之后前方要能走通。
	#    台阶：抬到顶面之上，前方是通的 → 继续。
	#    墙/车/建筑：抬上去前面还是实的 → 放弃，保持被挡（玩家可以绕）。
	var probe_xf := global_transform
	probe_xf.origin += up * STEP_CLIMB
	if test_move(probe_xf, heading * CLIMB_PROBE):
		return
	# ③ 抬起 + 前进当帧位移
	var landed := global_transform
	landed.origin += up * STEP_CLIMB + heading * (SPEED * delta)
	# ④ 落下：把猫放回台阶顶面。用 test_move 逐步下探，找出第一个不碰的位置。
	#    探到底（下方无地面）就说明这是悬空边缘而不是台阶 —— 放弃，别把人扔下去。
	var rest := landed
	var found := false
	for step in 5:
		var probe := rest
		probe.origin -= up * (STEP_CLIMB / 5.0)
		if not test_move(probe, Vector3.ZERO):
			rest = probe
			found = true
			break
	if not found:
		return
	global_transform.origin = rest.origin
	_climb_cd = CLIMB_CD
	_climb_flash = 0.18


## ---- 死局自救 ----
## 【为什么需要】玩家反馈"掉到一个地方就变成死局"：球面岛 + 建筑/围墙碰撞体
## 会围出一些封闭凹坑（两栋楼之间、围墙转角、台阶形成的平台），
## 一旦猫落进去，四面都被挡、跳跃高度又不够，就再也出不来 —— 只能重开。
## 这里的做法是"卡住检测 + 自动脱困"：
##   ① 卡住 = 玩家在推前进，但实际切向位移几乎为 0，且持续 STUCK_TIME 秒
##   ② 脱困 = 先试着原地跳一下（多数凹坑一跳就出去了）
##   ③ 还不行 → 沿"最空的方向"被推开一小段（用 test_move 验证不会穿墙）
## 不做"随机传送"：那会把玩家糊在一个陌生且可能更糟的位置。
func _update_stuck(delta: float, moving: bool) -> void:
	if not moving or input_locked:
		_stuck_t = 0.0
		_stuck_pos = global_position
		_unstick_t = 0.0
		return
	# 真的没动（切向位移 < 阈值）才算卡住；慢慢挪动不算
	if global_position.distance_to(_stuck_pos) < CAT_RADIUS * 0.35:
		_stuck_t += delta
	else:
		_stuck_t = 0.0
	_stuck_pos = global_position
	if STUCK_DEBUG_DISABLE:
		_stuck_t = 0.0
		return
	if _stuck_t < STUCK_TIME:
		return
	_stuck_t = 0.0
	_escape()


## 被困住时的脱困尝试：先跳，再"往最空的方向挪"。
func _escape() -> void:
	# 冷却，避免连续触发把自己抖来抖去
	if _unstick_t > 0.0:
		return
	_unstick_t = UNSTICK_CD
	var up := up_axis()
	# ① 原地起跳：多数凹坑（台阶平台、围墙转角）一跳就出去了
	velocity = up * JUMP_VELOCITY * 1.05
	_coyote = 0.0
	# ② 沿"最空方向"侧向挪：把 8 个方向都试一遍，选碰撞最少的那个推开。
	#    test_move 无副作用，可以安全地试。
	var best_dir := Vector3.ZERO
	var best_clear := -1.0
	for k in 8:
		var ang := TAU * float(k) / 8.0
		var d := _reproject(Basis(up, ang) * _heading, up, _heading)
		# 只考虑有横向净空的方向（别往墙里推）
		var clear := 0.0
		for dist in [CAT_RADIUS, CAT_RADIUS * 2.0, CAT_RADIUS * 3.0]:
			if not test_move(global_transform, d * dist):
				clear += 1.0
			else:
				break
		if clear > best_clear:
			best_clear = clear
			best_dir = d
	if best_clear > 0.0 and best_dir != Vector3.ZERO:
		global_position += best_dir * (CAT_RADIUS * best_clear)
		velocity = best_dir * SPEED * 0.6


# ---- 爬墙 ----

## 爬墙状态机。每帧跑一次，【必须在读 up 之前调用】—— climbing 会改变 up_axis()
## 的返回值，而后面所有运动/相机/落地判定都基于 up。
##
## 输入语义在爬墙时换挡（见常量区注释）：
##   drive（W/S）     = 沿墙向上爬 / 向下滑
##   steer（A/D）     = 贴墙左右横移（身体不再原地转身）
##
## 进入条件：
##   ① 上一帧确实"推着前进却几乎没动"（_blocked_last，由台阶攀爬流程置位 ——
##      它先给矮台阶机会，只有台阶也过不去时才轮到爬墙）
##   ② 玩家仍在推（pushing），且脚下踩着足够平的地面
##   ③ 肩高探到够陡的面（法线与径向夹角 > WALL_MIN_ANGLE）
## 退出条件：
##   胸口探不到墙且宽容期结束 → 松手掉落（爬到顶、走向墙的边缘）
##   头较高 / 胸还贴着 + 仍在往上推 → 触发翻顶（mantle）
##
## 【为什么在 move 之前就判定 climbing】后面的 up_direction、表面输运、
## 期望速度、重力、落地判定全依赖 up；若在 move_and_slide 之后再切换状态，
## 本帧的运动仍是"地面语义"，会有一帧"贴着墙却在下坠"的错位。
## 判定用【上一帧】的接触信息（_blocked_last / is_on_floor），行为稳定、无巧合依赖。
func _update_wall_climb(delta: float, steer: float, drive: float) -> void:
	var radial := _gravity_up()
	var pushing := absf(drive) > 0.08 or absf(steer) > 0.08

	if not climbing:
		if not pushing or not _blocked_last or _climb_cd > 0.0:
			return
		if not _on_flat_floor(is_on_floor(), radial):
			return
		# 肩高（≈0.35m）探射线：路缘石(≤0.3m)够不着 → 归台阶攀爬；窗台/车侧壁/建筑外墙都能命中
		var probe := _wall_ray(global_position + radial * SHOULDER, _heading)
		var n: Vector3 = probe["n"]
		if n == Vector3.ZERO or radial.angle_to(n) <= WALL_MIN_ANGLE:
			return
		# 朝向转成"头朝上"（径向在墙面上的投影）—— 身体横过来贴到墙面。
		# 【退化兜底】墙近水平（天花板/地板面）时投影接近零，此时不爬（防 NaN 基）。
		var wall_up := _reproject(radial, n, _heading.cross(n))
		if wall_up.length_squared() < 0.5:
			return
		_wall_n = n
		_heading = wall_up.normalized()
		climbing = true
		_wall_sticky_t = WALL_STICKY
		_climb_hang_t = 0.0
		_climb_flash = 0.18
		# 【碰撞胶囊必须单独扶正】身体基翻转 90° 后，胶囊的轴（local Y）会跟着指向
		# 墙外 —— 整个胶囊横着戳出墙面，而且本地偏移 (0,0.2,0) 把它塞进墙里 0.13m，
		# 探针起点随之落进墙体内部（射线从内部发射被 Godot 忽略）→ 每帧都判"离墙"
		# → 0.16s 后退出 → 掉落 → 再进……实测只爬到 0.33m 就开始无限锯齿。
		# 所以爬墙期间把胶囊【单独】转回竖直：轴沿墙面朝上、轴线离墙面 CAT_RADIUS，
		# 底边抬到原脚底高度。视觉网格（avatar）照常横贴墙。
		_shape.rotation = Vector3(-PI / 2, 0, 0)   # local Y(轴) → local -Z = 沿墙面向上
		_shape.position = Vector3.ZERO
		global_position += _wall_n * ((probe["pos"] as Vector3 - global_position).dot(_wall_n) \
			+ CAT_RADIUS)
		global_position += radial * (CAT_HEIGHT * 0.5)
		# 相机参考也转到墙面上 —— 相当于瞬移后的对齐，look_yaw/pitch 重置，
		# 否则旧 yaw 在新基下指向别处。
		look_yaw = 0.0
		look_pitch = CAM_PITCH_HOME
		_cam_rig.global_transform.basis = _basis_from(_wall_n, _heading)
		_idle_t = 0.0
		_apply_cam_rotation()
		Game.play_sfx("click")
		return

	# --- 已在爬墙：朝向锁死为"头朝上"，横移只挪位置不转身体 ---
	var wall_up := _reproject(radial, _wall_n, _heading)
	if wall_up.length_squared() > 0.5:
		_heading = wall_up.normalized()
	global_transform.basis = _basis_from(_wall_n, _heading)

	# 墙面追踪：胸口那条命中且够陡 → 更新墙面法线（曲面墙/拐角跟随，突变平滑化）
	var chest_n: Vector3 = _wall_ray(global_position + radial * CAT_BODY_Y, -_wall_n)["n"]
	var head_n: Vector3 = _wall_ray(global_position + radial * SHOULDER, -_wall_n)["n"]
	# 【翻顶（mantle）】头探不到、胸还探得到 → 头已越过墙沿，把它抬上去。
	# 【为什么要显式翻】不翻的后果是"到顶 → 探不到 → 松手掉落 → 再爬 → 再到顶"
	# 死循环：狐狸永远差半步上不去，看起来像 bug。翻顶 = 主动把身体抬过墙沿。
	if chest_n != Vector3.ZERO and radial.angle_to(chest_n) > WALL_MIN_ANGLE:
		# 只在【往上推】时翻顶：下墙途中头探不到是正常回程，翻上去就反了
		if head_n == Vector3.ZERO and drive > 0.05 and _climb_mantle(radial):
			return
		_wall_n = _wall_n.slerp(chest_n, 1.0 - exp(-WALL_N_RATE * delta)).normalized()
		_wall_sticky_t = WALL_STICKY
	elif _wall_sticky_t > 0.0:
		# 胸口没探到但宽容期未过：棱角/接缝抖动，保留最后已知墙面法线继续贴
		_wall_sticky_t -= delta
	else:
		# 真的离开墙面（爬到顶被动越过、走向墙边缘）→ 回到正常物理
		_climb_exit()
		return

	# 挂墙不动太久就掉下来：不推输入超过 CLIMB_HANG —— 狐狸会累，
	# 也让"贴着墙永远挂着"不成一种可以赖着的姿势。
	if not pushing:
		_climb_hang_t += delta
		if _climb_hang_t > CLIMB_HANG:
			_climb_exit()
	else:
		_climb_hang_t = 0.0


## 翻上墙顶：身体沿径向抬 MANTLE_RAISE、往墙里（-墙法线）挪半个半径，然后退出爬墙。
## 抬起的量保证"脚高于墙沿"，抬完脚下的墙顶面就在正下方 —— 退出后重力把它落上去。
## 【必须 test_move 先试】墙顶若有檐口/管道会挡住抬起的位置；试不过就不翻，
## 继续沿着最后的墙面待着（宽容期之后自然掉落），不会把猫塞进模型里。
func _climb_mantle(radial: Vector3) -> bool:
	var onto := global_transform
	# 爬墙时胶囊轴线离墙面 CAT_RADIUS。只推一个半径会把轴线正好落在【墙沿线上】，
	# 落点五五开，滑掉就从头再爬（实测）。多推半半径让轴线进到顶面中间 ——
	# 薄墙（护栏）会推过头掉到另一侧，那正是"翻过墙"的预期行为。
	onto.origin -= _wall_n * (CAT_RADIUS * 1.5)
	onto.origin += radial * MANTLE_RAISE
	if test_move(onto, Vector3.ZERO):
		return false
	climbing = false
	global_transform.origin = onto.origin
	velocity = radial * 0.35
	_climb_exit(true)
	return true


## 探墙射线：从 from 沿 dir 打墙。返回 {"n": 法线(朝向from侧), "pos": 命中点}；
## 未命中或命中法线不朝我们来（薄墙背面）时 n 为零向量。
func _wall_ray(from: Vector3, dir: Vector3) -> Dictionary:
	var miss := {"n": Vector3.ZERO, "pos": Vector3.ZERO}
	if dir.length_squared() < 1e-6:
		return miss
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * WALL_PROBE, 1)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return miss
	var n: Vector3 = (hit["normal"] as Vector3).normalized()
	if n.dot(dir) >= 0.0:
		return miss   # 法线不朝我们来 → 打到了背面
	return {"n": n, "pos": hit["position"]}


## 脚下是不是"接近平的地面"——起爬的前置条件。
## 【为什么必须有】斜坡上被挡只是坡太陡，应该交给 STEP_CLIMB/脱困逻辑；
## 只有站在平地上还推不动、且前方够陡，才是墙。
## 判据：地板法线与径向（重力反方向）的夹角 <= CLIMB_FLAT_ANGLE(50°)。
## 【阈值为什么是 50°】必须同时夹在 floor_max_angle(60°) 与 WALL_MIN_ANGLE(65°)
## 之间：比 60° 严格才轮得到这里判，比 65° 松才留得出滞回带 —— 两道判定卡在同
## 一个阈值上时会在"斜坡/墙"边界反复横跳。
## 【on_floor 形参】调用点在 move_and_slide 之前，is_on_floor() 读到的是上一帧
## 结果；由调用方显式传同一个值，保证两处判定看到同一份地板信息。
## 【本文件被并发编辑过】这个函数曾经被一次爬墙重构覆盖掉，连带 street.gd 报
## "Function _on_flat_floor() not found"、整场编译失败。改爬墙代码时先 grep
## "func <函数名>" 确认没把别的函数挤掉。
func _on_flat_floor(on_floor: bool, radial: Vector3) -> bool:
	if not on_floor:
		return false
	var fn := get_floor_normal()
	if fn.length_squared() < 1e-6:
		# 拿不到法线（刚传送/刚生成的落地帧）：保守当平地，交给已有的滞回逻辑纠正。
		return true
	return rad_to_deg(fn.normalized().angle_to(radial)) <= rad_to_deg(CLIMB_FLAT_ANGLE)


## 爬墙退出：把整套框架切回"径向为地板"。smooth_yaw=true 时把镜头 yaw 对到
## 当前相机朝向上（从墙面回到地面的瞬间不跳视角）。
func _climb_exit(smooth_yaw := false) -> void:
	# 【先记旧墙法线再清状态】后面 up_axis() 会因 climbing=false 切回径向，
	# 到那时旧的墙面法线就读不到了。
	var old_n := _wall_n
	climbing = false
	_wall_sticky_t = 0.0
	_climb_hang_t = 0.0
	_climb_cd = CLIMB_CD
	# 碰撞胶囊还原成"站立"姿态（爬墙时被单独转成竖直贴墙，见 _climb_enter）。
	# 【顺序】必须在 climbing=false 之后：还原瞬间胶囊底边会比 origin 低 0.02，
	# 让重力自己把它落到墙顶/地面上即可，不再手动对位。
	_shape.rotation = Vector3.ZERO
	_shape.position = Vector3(0, CAT_BODY_Y, 0)
	# 保相机朝向：先把换基前的朝向算出来，再换基 —— 顺序反了就读不到旧方向
	var keep_f := cam_forward() if smooth_yaw else Vector3.ZERO
	# 朝向：wall_up 接近径向（头朝上爬）→ 投影到径向切平面会退化。退化的
	# fallback 用【贴墙平面里的侧向向量】，即当前身体基的 X —— 它是合法的水平方向。
	var up := up_axis()
	_heading = _reproject(_heading, up, global_transform.basis.x)
	if _heading.length_squared() < 0.5:
		_heading = global_transform.basis.x
	_heading = _heading.normalized()
	global_transform.basis = _basis_from(up, _heading)
	var cup := cam_up()
	_cam_rig.global_transform.basis = _basis_from(cup, _heading)
	_cam_rig.global_position = global_position + cup * CAM_HEIGHT
	if smooth_yaw and keep_f.length_squared() > 0.5:
		look_yaw = atan2(_heading.cross(keep_f).dot(cup), _heading.dot(keep_f))
	else:
		look_yaw = 0.0
	look_pitch = CAM_PITCH_HOME
	_idle_t = 0.0
	_apply_cam_rotation()
	# 丢掉贴墙压力残余：爬墙时法向分量一直是 -WALL_PRESS（沿旧墙法线朝里压），
	# 不清会先朝墙里钻一小段再被弹回，看起来像弹簧起步。只清这一项，
	# 径向自由落体的分量别动（那是合法的）。
	velocity -= old_n * velocity.dot(old_n)


## 空中姿态：上升时纵向拉伸、下落时纵向压缩（配合落地 squash）。
## 幅度要小 —— 拉太大会像被橡皮筋拽着，猫会显得假。
## 【爬墙中排除】爬墙时 is_on_floor() 为真（墙当地板），本来就会被这里挡掉；
## 但为了不依赖那个副作用，额外显式判一次更清楚 —— 万一以后给爬墙加了 floor_snap
## 特殊处理，_air_pose 不会突然开始拉伸一只贴墙的狐狸。
func _air_pose(up: Vector3) -> void:
	if climbing or is_on_floor() or _land_squash > 0.0:
		return
	var v_up := velocity.dot(up)
	var stretch := clampf(v_up / 12.0, -0.05, 0.05)
	avatar.scale = Vector3.ONE * CAT_VISUAL_SCALE * Vector3(1.0 - stretch, 1.0 + stretch, 1.0 - stretch)


func _process(_delta: float) -> void:
	# 相机不钻进地面 —— 仅平地模式（星球上地形在弹簧臂碰撞层里，臂会自动缩短）
	if planet == null and cam.global_position.y < CAM_MIN_Y:
		cam.global_position.y = CAM_MIN_Y


## 演示/截图钩子用：原地给一次跳跃冲量（沿脚下法线）
func do_jump_impulse() -> void:
	velocity += up_axis() * JUMP_VELOCITY
	_coyote = COYOTE


## 相机 yaw 需要回正的角度（猫背后对应的 yaw）：当前相机朝向 → 身体朝向的
## 绕 up 有符号角。平地时与旧版 atan2 公式等价。
## 【用 cam_up】相机参考系在爬墙时不跟墙翻，这里必须与 cam_forward 同一个轴。
func _yaw_diff() -> float:
	var up := cam_up()
	var f := cam_forward()
	return atan2(f.cross(_heading).dot(up), f.dot(_heading))
