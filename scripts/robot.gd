extends CharacterBody3D
## 遥控机器人：操作始终相对自身（W/S 前进后退，A/D 原地转向，约 45°/秒）。
## 机身在渲染层 2，机载摄像头不渲染这一层（机载画面看不到机器人自己）。

const FORWARD_SPEED := 1.1
const BACK_SPEED := 0.6
const TURN_SPEED := 0.785398  # 45°/秒
const ACCEL := 3.0
const TURN_ACCEL := 4.0
const BODY_LAYER := 2

var speed := 0.0
var turn_rate := 0.0
var input_enabled := true
var odometer := 0.0
var onboard_cam: Camera3D
var headlight: SpotLight3D


func _init() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1
	var shape := CylinderShape3D.new()
	shape.radius = 0.42
	shape.height = 0.5
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, 0.3, 0.0)
	add_child(cs)
	_build_body()
	_build_onboard()


func forward() -> Vector3:
	return -global_transform.basis.z


func motion_level() -> float:
	return clampf(absf(speed) / FORWARD_SPEED + absf(turn_rate) / TURN_SPEED * 0.6, 0.0, 1.0)


func toggle_headlight() -> void:
	headlight.visible = not headlight.visible


func _physics_process(delta: float) -> void:
	var drive := 0.0
	var steer := 0.0
	if input_enabled:
		drive = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		steer = Input.get_action_strength("turn_left") - Input.get_action_strength("turn_right")
	var target := drive * (FORWARD_SPEED if drive > 0.0 else BACK_SPEED)
	speed = move_toward(speed, target, ACCEL * delta)
	turn_rate = move_toward(turn_rate, steer * TURN_SPEED, TURN_SPEED * TURN_ACCEL * delta)
	rotate_y(turn_rate * delta)
	var before := global_position
	velocity = forward() * speed
	move_and_slide()
	global_position.y = 0.0
	var moved := global_position.distance_to(before)
	odometer += moved
	# 顶到东西：速度掉下来，下次松开再加速
	if get_slide_collision_count() > 0 and moved < absf(speed) * delta * 0.5:
		speed = move_toward(speed, 0.0, ACCEL * 2.0 * delta)


func _build_body() -> void:
	var shell := _mat(Color(0.74, 0.74, 0.70))
	var dark := _mat(Color(0.10, 0.10, 0.10))
	_part(Vector3(0.0, 0.22, 0.02), Vector3(0.56, 0.22, 0.72), shell)       # 车体
	_part(Vector3(0.33, 0.10, 0.0), Vector3(0.12, 0.20, 0.82), dark)        # 履带
	_part(Vector3(-0.33, 0.10, 0.0), Vector3(0.12, 0.20, 0.82), dark)
	_part(Vector3(0.0, 0.40, -0.24), Vector3(0.22, 0.14, 0.18), shell)      # 摄像头云台
	_part(Vector3(0.0, 0.37, 0.28), Vector3(0.26, 0.10, 0.12), dark)        # 电缆卷盘
	# 前方小灯：监控里靠它分辨机器人朝向
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0.3, 0.2, 0.05)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.65, 0.2)
	lamp.emission_energy_multiplier = 3.0
	_part(Vector3(0.0, 0.34, -0.37), Vector3(0.10, 0.05, 0.02), lamp)


func _build_onboard() -> void:
	onboard_cam = Camera3D.new()
	onboard_cam.fov = 60.0
	onboard_cam.keep_aspect = Camera3D.KEEP_WIDTH
	onboard_cam.near = 0.04
	onboard_cam.far = 40.0
	onboard_cam.position = Vector3(0.0, 0.45, -0.38)
	onboard_cam.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	onboard_cam.cull_mask = 0xFFFFF & ~BODY_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	onboard_cam.environment = env
	add_child(onboard_cam)

	# 头灯：只照亮前方 3～4 米
	headlight = SpotLight3D.new()
	headlight.position = Vector3(0.0, 0.40, -0.36)
	headlight.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	headlight.spot_range = 4.6
	headlight.spot_angle = 34.0
	headlight.spot_attenuation = 0.8
	headlight.light_energy = 1.35
	headlight.light_color = Color(1.0, 0.92, 0.78)
	headlight.shadow_enabled = true
	add_child(headlight)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	return mat


func _part(center: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	mi.layers = BODY_LAYER
	add_child(mi)
