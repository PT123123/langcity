class_name Player
extends CharacterBody3D
## 玩家（第一人称）：身体只有碰撞体，相机在头部高度。
## 视角：左摇杆走路，屏幕拖动转头（Minecraft 手游式），由街道场景喂入 look()。

const SPEED := 3.9
const GRAVITY := 18.0
const LOOK_SENS := 0.0016

var input_vec := Vector2.ZERO      # 虚拟摇杆写入（屏幕方向：x 右 / y 下）
var input_locked := false

var look_yaw := 0.0                # 初始面向北（-Z）
var look_pitch := -0.04
var _bob_t := 0.0

var cam: Camera3D
var _head: Node3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 3   # 地面(2) + 障碍物(1)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.26
	capsule.height = 1.2
	shape.shape = capsule
	shape.position = Vector3(0, 0.62, 0)
	add_child(shape)

	_head = Node3D.new()
	_head.position = Vector3(0, 1.55, 0)
	add_child(_head)

	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.08
	cam.far = 260.0
	_head.add_child(cam)
	cam.make_current()


## 拖动转视角（像素增量）
func look(dx_px: float, dy_px: float) -> void:
	look_yaw = wrapf(look_yaw - dx_px * LOOK_SENS, -PI, PI)
	look_pitch = clampf(look_pitch - dy_px * LOOK_SENS, -1.25, 1.15)
	_head.rotation.y = look_yaw
	cam.rotation.x = look_pitch


func teleport(pos: Vector3, yaw := NAN) -> void:
	position = pos
	if not is_nan(yaw):
		look_yaw = yaw
	_head.rotation.y = look_yaw
	cam.rotation.x = look_pitch


func _physics_process(delta: float) -> void:
	var v := input_vec
	if not input_locked and v.length() < 0.15:
		v = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_locked:
		v = Vector2.ZERO
	# 相机相对移动
	var fwd := Vector3(-sin(look_yaw), 0, -cos(look_yaw))
	var right := Vector3(cos(look_yaw), 0, -sin(look_yaw))
	var dir := (right * v.x + fwd * -v.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	# 走路轻微头部起伏
	var moving := Vector2(velocity.x, velocity.z).length() > 0.6
	if moving:
		_bob_t += delta * 7.5
	_head.position.y = 1.55 + (absf(sin(_bob_t)) * 0.035 if moving else 0.0)
