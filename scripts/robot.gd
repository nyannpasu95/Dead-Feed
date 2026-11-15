extends CharacterBody3D
## 遥控机器人：操作始终相对自身（W/S 前进后退，A/D 原地转向，约 45°/秒）。
## 机身在渲染层 2，机载照片不渲染这一层（照片里看不到机器人自己）。
## 机载相机不能实时回传：这里只有相机挂点和闪光，拍照由操作台用单独的 SubViewport 渲染一帧。
## 声呐：一次 ping 向前方 120° 扇形发出一排水平射线，回声点（角度、距离、强度）交给操作台的扇形屏。
## 云台上一盏常亮的前向小探照灯（车体本身不发光）：照片里看不到它（拍照那一帧关掉，只有闪光），
## 监控里看得到它在前方地面和墙上投出的光斑：光斑在哪、朝哪边，机器人就在哪、朝哪边。
## 机器人被货箱挡住、或者在没有监控的地方对着门洞时，光从缝隙和门洞照进有监控的房间。
## 撞到东西发出 bumped（表面材质、力度：按垂直撞进去的速度算，擦边就轻）；
## 顶着东西开时 strain 升高（电机憋着叫）；贴着东西蹭着走时 scrape 升高。

const FORWARD_SPEED := 1.1
const BACK_SPEED := 0.6
const TURN_SPEED := 0.785398  # 45°/秒
const ACCEL := 3.0
const TURN_ACCEL := 4.0
const BODY_LAYER := 2
const MONITOR_ONLY_LAYER := 4  # 渲染层 3：只有监控看得到的东西（帧间者）
const PHOTO_CULL := 0xFFFFF & ~BODY_LAYER & ~MONITOR_ONLY_LAYER

const SONAR_RANGE := 7.0
const SONAR_HALF_ARC := PI / 3.0  # 前方 120°
const SONAR_RAYS := 121  # 每 1° 一条
const SONAR_HEIGHT := 0.3
const SONAR_DROPOUT := 0.08  # 少量射线没有回声，轮廓更像声呐

signal sonar_returned(echoes: PackedVector3Array)
signal bumped(surface: String, strength: float)

var speed := 0.0
var turn_rate := 0.0
var input_enabled := true
var odometer := 0.0
var camera_mount: Node3D
var flash: SpotLight3D
var searchlight: SpotLight3D
var strain := 0.0
var scrape := 0.0
var _was_touching := false
var _sonar_pending := false
var _rng := RandomNumberGenerator.new()


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


## 拍照用的相机：由操作台放进自己的 SubViewport，拍照时对齐到 camera_mount
static func build_photo_camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.04
	cam.far = 40.0
	cam.cull_mask = PHOTO_CULL
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	cam.environment = env
	return cam


## 下一个物理帧发一次 ping，结果从 sonar_returned 发出
func ping_sonar() -> void:
	_sonar_pending = true


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
	var pre_velocity := velocity
	move_and_slide()
	global_position.y = 0.0
	var moved := global_position.distance_to(before)
	odometer += moved
	var touching := get_slide_collision_count() > 0
	var stuck := touching and moved < absf(speed) * delta * 0.5
	if touching and not _was_touching:
		var col := get_slide_collision(0)
		var into := absf(pre_velocity.dot(col.get_normal()))
		if into > 0.08:
			bumped.emit(_surface_of(col.get_collider()), clampf(into / FORWARD_SPEED, 0.0, 1.0))
	_was_touching = touching
	strain = move_toward(strain, 1.0 if stuck and absf(drive) > 0.0 else 0.0, delta * 4.0)
	var sliding := moved / delta / FORWARD_SPEED if touching and not stuck else 0.0
	scrape = move_toward(scrape, clampf(sliding, 0.0, 1.0), delta * 6.0)
	# 顶到东西：速度掉下来，下次松开再加速
	if stuck:
		speed = move_toward(speed, 0.0, ACCEL * 2.0 * delta)
	if _sonar_pending:
		_sonar_pending = false
		sonar_returned.emit(_sonar_scan())


## 关卡搭建时给带碰撞的 CSG 标了 surface（concrete / crate / metal）
static func _surface_of(collider: Object) -> String:
	if collider != null and collider.has_meta("surface"):
		return str(collider.get_meta("surface"))
	return "concrete"


## 每个回声：x = 相对正前方的角度（右为正，弧度），y = 距离（米），z = 强度（正对表面强，擦过弱）
func _sonar_scan() -> PackedVector3Array:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * SONAR_HEIGHT
	var fwd := forward()
	var right := global_transform.basis.x
	var out := PackedVector3Array()
	for i in SONAR_RAYS:
		var a := lerpf(-SONAR_HALF_ARC, SONAR_HALF_ARC, float(i) / float(SONAR_RAYS - 1))
		var dir := fwd * cos(a) + right * sin(a)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * SONAR_RANGE, 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or _rng.randf() < SONAR_DROPOUT:
			continue
		var pos: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		var dist := origin.distance_to(pos) + _rng.randf_range(-0.04, 0.04)
		out.append(Vector3(a, dist, 0.45 + 0.55 * absf(normal.dot(dir))))
	return out


func _build_body() -> void:
	var shell := _mat(Color(0.74, 0.74, 0.70))
	var dark := _mat(Color(0.10, 0.10, 0.10))
	_part(Vector3(0.0, 0.22, 0.02), Vector3(0.56, 0.22, 0.72), shell)       # 车体
	_part(Vector3(0.33, 0.10, 0.0), Vector3(0.12, 0.20, 0.82), dark)        # 履带
	_part(Vector3(-0.33, 0.10, 0.0), Vector3(0.12, 0.20, 0.82), dark)
	_part(Vector3(0.0, 0.40, -0.24), Vector3(0.22, 0.14, 0.18), shell)      # 摄像头云台
	_part(Vector3(0.0, 0.37, 0.28), Vector3(0.26, 0.10, 0.12), dark)        # 电缆卷盘
	# 探照灯：云台顶上的小灯筒，只有前面的灯罩亮（不投影，免得挡住自己的光）
	_part(Vector3(0.0, 0.52, -0.26), Vector3(0.11, 0.09, 0.16), dark).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.3, 0.25, 0.15)
	lens.emission_enabled = true
	lens.emission = Color(1.0, 0.85, 0.6)
	lens.emission_energy_multiplier = 2.5
	_part(Vector3(0.0, 0.52, -0.345), Vector3(0.08, 0.065, 0.01), lens).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_onboard() -> void:
	camera_mount = Node3D.new()
	camera_mount.position = Vector3(0.0, 0.45, -0.38)
	camera_mount.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	add_child(camera_mount)

	# 闪光：只在拍照那一帧亮，照亮前方 3～4 米
	flash = SpotLight3D.new()
	flash.position = Vector3(0.0, 0.40, -0.36)
	flash.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	flash.spot_range = 4.6
	flash.spot_angle = 34.0
	flash.spot_attenuation = 0.8
	flash.light_energy = 1.35
	flash.light_color = Color(1.0, 0.94, 0.84)
	flash.shadow_enabled = true
	flash.visible = false
	add_child(flash)

	# 探照灯：常亮，窄光束略朝下，前方一两米外的地面上一块长光斑，远处照上墙
	searchlight = SpotLight3D.new()
	searchlight.position = Vector3(0.0, 0.52, -0.36)
	searchlight.rotation_degrees = Vector3(-9.0, 0.0, 0.0)
	searchlight.spot_range = 7.0
	searchlight.spot_angle = 17.0
	searchlight.spot_angle_attenuation = 1.1
	searchlight.spot_attenuation = 0.6
	searchlight.light_energy = 7.0
	searchlight.light_color = Color.WHITE  # 只在单色监控里看得到；有颜色会让拖痕和地面亮度不同
	searchlight.shadow_enabled = true
	add_child(searchlight)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	return mat


func _part(center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	mi.layers = BODY_LAYER
	add_child(mi)
	return mi
