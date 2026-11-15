extends SpotLight3D
## 机器人云台上的前向探照灯。除了主光束本身，还有：
## - 光柱：空气里看得见的一道光。锥面的每条母线朝前打一条射线，撞到东西就截在那，光柱不会穿墙露到隔壁房间
## - 眩光：迎着灯看过去时，灯头是一团化开的亮点
## - 溢光：主光束外一圈很弱的宽光，照亮机器人前方和两侧
## - 反射光：光斑落在哪，那里就朝外反射一点光，把周围的墙、地面、天花板照亮一些
## 全挂在这盏灯下面：拍照那一帧把灯关掉，它们一起消失（照片里只有闪光）。
## 全部是白光：有颜色会让拖痕和地面在单色监控里亮度不同。

const BEAM_SHADER := preload("res://shaders/beam.gdshader")
const GLOW_SHADER := preload("res://shaders/lamp_glow.gdshader")
const WORLD_MASK := 1
const SHAFT_LENGTH := 5.0  # 空气里看得见光柱的最远距离（光本身照得更远）
const SHAFT_HALF_ANGLE := 13.0  # 比光斑略窄：光斑边缘本来就暗
const SHAFT_SIDES := 16
const SHAFT_RINGS := 6
const SHAFT_START_RADIUS := 0.03  # 灯罩的大小
const SHAFT_OVERSHOOT := 0.12  # 母线伸进撞到的表面一点，交界处由深度柔化，不留缝
const SHAFT_STRENGTH := 0.5
const BOUNCE_ENERGY := 0.7
const BOUNCE_RANGE := 3.4
const BOUNCE_OFFSET := 0.06

var spill: SpotLight3D
var bounce: SpotLight3D
var _shaft: MeshInstance3D
var _shaft_mesh := ImmediateMesh.new()
var _dirs: Array[Vector3] = []
var _radial: Array[Vector3] = []


func build(layer: int) -> void:
	spot_range = 7.0
	spot_angle = 17.0
	spot_angle_attenuation = 1.1
	spot_attenuation = 0.6
	light_energy = 7.0
	light_color = Color.WHITE
	shadow_enabled = true

	spill = SpotLight3D.new()
	spill.spot_range = 4.0
	spill.spot_angle = 50.0
	spill.spot_angle_attenuation = 0.5  # 边缘软：擦过墙面时不留一道硬弧
	spill.spot_attenuation = 1.4
	spill.light_energy = 0.45
	spill.shadow_enabled = true
	add_child(spill)

	# 反射光朝撞到的表面外侧照：只照亮表面这一侧，不会透到墙后面
	bounce = SpotLight3D.new()
	bounce.top_level = true
	bounce.spot_range = BOUNCE_RANGE
	bounce.spot_angle = 75.0
	bounce.spot_angle_attenuation = 0.8
	bounce.spot_attenuation = 1.2
	bounce.light_energy = 0.0
	bounce.shadow_enabled = true
	add_child(bounce)

	for i in SHAFT_SIDES:
		var phi := TAU * float(i) / float(SHAFT_SIDES)
		var a := deg_to_rad(SHAFT_HALF_ANGLE)
		_radial.append(Vector3(cos(phi), sin(phi), 0.0))
		_dirs.append(Vector3(sin(a) * cos(phi), sin(a) * sin(phi), -cos(a)))
	var shaft_mat := ShaderMaterial.new()
	shaft_mat.shader = BEAM_SHADER
	shaft_mat.set_shader_parameter("shaft_length", SHAFT_LENGTH)
	shaft_mat.set_shader_parameter("strength", SHAFT_STRENGTH)
	_shaft = MeshInstance3D.new()
	_shaft.mesh = _shaft_mesh
	_shaft.material_override = shaft_mat
	_shaft.layers = layer
	_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shaft)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = GLOW_SHADER
	var glow := MeshInstance3D.new()
	glow.mesh = quad
	glow.material_override = glow_mat
	glow.layers = layer
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)


func _physics_process(_delta: float) -> void:
	if _dirs.is_empty() or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	_update_bounce(space)
	_update_shaft(space)


## 光斑中心落在哪个表面上，反射光就放在那，朝表面外侧，越远越弱
func _update_bounce(space: PhysicsDirectSpaceState3D) -> void:
	var from := global_position
	var axis := -global_basis.z
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + axis * spot_range, WORLD_MASK))
	if hit.is_empty():
		bounce.light_energy = 0.0
		return
	var at: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	var up := Vector3.UP if absf(n.y) < 0.9 else Vector3.FORWARD
	bounce.global_transform = Transform3D(Basis.looking_at(n, up), at + n * BOUNCE_OFFSET)
	var k := clampf(1.0 - from.distance_to(at) / spot_range, 0.0, 1.0)
	bounce.light_energy = BOUNCE_ENERGY * pow(k, 1.2)


## 每条母线打一条射线，截短到撞上的地方，再按截出来的长度重搭锥面
func _update_shaft(space: PhysicsDirectSpaceState3D) -> void:
	var xf := global_transform
	var lens := PackedFloat32Array()
	lens.resize(SHAFT_SIDES)
	for i in SHAFT_SIDES:
		var start := xf * (_radial[i] * SHAFT_START_RADIUS)
		var end := xf * (_radial[i] * SHAFT_START_RADIUS + _dirs[i] * SHAFT_LENGTH)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, WORLD_MASK))
		var reach := SHAFT_LENGTH
		if not hit.is_empty():
			reach = minf(SHAFT_LENGTH, start.distance_to(hit["position"]) + SHAFT_OVERSHOOT)
		lens[i] = reach
	_shaft_mesh.clear_surfaces()
	_shaft_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SHAFT_SIDES:
		var j := (i + 1) % SHAFT_SIDES
		for k in SHAFT_RINGS:
			var t0 := float(k) / float(SHAFT_RINGS)
			var t1 := float(k + 1) / float(SHAFT_RINGS)
			_vertex(i, lens[i] * t0)
			_vertex(j, lens[j] * t0)
			_vertex(i, lens[i] * t1)
			_vertex(j, lens[j] * t0)
			_vertex(j, lens[j] * t1)
			_vertex(i, lens[i] * t1)
	_shaft_mesh.surface_end()


func _vertex(side: int, along: float) -> void:
	_shaft_mesh.surface_set_normal(_radial[side])
	_shaft_mesh.surface_add_vertex(_radial[side] * SHAFT_START_RADIUS + _dirs[side] * along)
