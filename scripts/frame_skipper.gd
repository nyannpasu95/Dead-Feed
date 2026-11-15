extends Node3D
## 帧间者：只在「正在被看的那路监控」抓帧时移动，每 frames_per_step 帧走一步；切走就停。
## 看着能知道它在哪，但它在逼近；不看它不动，但玩家只能凭记忆开车。
## 机载摄像头不渲染它所在的层：机载开到那里什么都没有。
## 第 1 关是无伤害的预兆版：走到路线终点后，下一步就消失（arrived 信号由操作台接管）。

signal arrived(id: String)

const RobotScript := preload("res://scripts/robot.gd")

var id := ""
var camera_id := ""
var frames_per_step := 6
var points := PackedVector3Array()
var index := 0
var done := false
var _frames := 0


func setup(data: Dictionary) -> void:
	id = data["id"]
	camera_id = data["camera"]
	frames_per_step = int(data.get("frames_per_step", 6))
	points = _resample(data["path"], float(data.get("step", 0.9)))
	_build_figure()
	_place()


## 操作台每抓一帧监控画面调用一次（在画面渲染之前），cam_id 是这一帧所属的摄像头。
func on_frame(cam_id: String) -> void:
	if done or cam_id != camera_id:
		return
	_frames += 1
	if _frames < frames_per_step:
		return
	_frames = 0
	if index >= points.size() - 1:
		done = true
		visible = false
		arrived.emit(id)
		return
	index += 1
	_place()


func _place() -> void:
	position = points[index]
	var nxt := points[mini(index + 1, points.size() - 1)]
	var prv := points[maxi(index - 1, 0)]
	var dir := nxt - prv
	if dir.length() > 0.01:
		rotation.y = atan2(-dir.x, -dir.z)


## 把折线路径按固定步长切成一个个落脚点（包含终点）
static func _resample(path: Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var first: Vector2 = path[0]
	out.append(Vector3(first.x, 0.0, first.y))
	var carry := 0.0
	for i in range(1, path.size()):
		var a: Vector2 = path[i - 1]
		var b: Vector2 = path[i]
		var seg := a.distance_to(b)
		var d := step - carry
		while d <= seg:
			var p := a.lerp(b, d / seg)
			out.append(Vector3(p.x, 0.0, p.y))
			d += step
		carry = seg - (d - step)
	var last: Vector2 = path[path.size() - 1]
	if Vector2(out[out.size() - 1].x, out[out.size() - 1].z).distance_to(last) > step * 0.3:
		out.append(Vector3(last.x, 0.0, last.y))
	return out


## 细长的黑色人影：手臂垂得过长，红外画面里是一块没有细节的黑
func _build_figure() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.025, 0.025, 0.025)
	mat.roughness = 1.0
	_part(false, Vector3(0.0, 0.47, 0.0), Vector3(0.30, 0.94, 0.18), mat)       # 腿
	_part(false, Vector3(0.0, 1.34, 0.0), Vector3(0.44, 0.80, 0.24), mat)       # 躯干
	_part(false, Vector3(0.27, 1.12, 0.0), Vector3(0.08, 1.05, 0.08), mat)      # 手臂
	_part(false, Vector3(-0.27, 1.12, 0.0), Vector3(0.08, 1.05, 0.08), mat)
	_part(true, Vector3(0.0, 1.90, 0.0), Vector3(0.26, 0.30, 0.26), mat)        # 头


func _part(sphere: bool, center: Vector3, size: Vector3, mat: Material) -> void:
	var mesh: PrimitiveMesh
	if sphere:
		var s := SphereMesh.new()
		s.radius = size.x * 0.5
		s.height = size.y
		mesh = s
	else:
		var b := BoxMesh.new()
		b.size = size
		mesh = b
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	mi.layers = RobotScript.MONITOR_ONLY_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
