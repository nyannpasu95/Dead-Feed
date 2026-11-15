extends RefCounted
## 把关卡数据（levels/*.gd 返回的字典）搭成 3D 场景。
## 墙、货箱、家具用 CSGBox3D（带碰撞）；贴地的条纹、纸、拖痕用 MeshInstance3D。
## 以后用资产工作台做出的模型，用 "scene" 类型的道具放进来即可。

const WALL_T := 0.2
const DECAL_Y := 0.006

static var _monitor_env: Environment


static func build(data: Dictionary, root: Node3D) -> Dictionary:
	var out := {
		"cameras": {},
		"doors": {},
		"triggers": {},
		"blinkers": [],
	}
	var m := _materials()
	var wall_h: float = data["wall_height"]

	var fr: Rect2 = data["floor"]
	_box(root, Vector3(fr.get_center().x, -0.1, fr.get_center().y), Vector3(fr.size.x, 0.2, fr.size.y), m["floor"], true)
	# 天花板：监控仰角高时不会看到墙顶外的黑洞
	_box(root, Vector3(fr.get_center().x, wall_h + 0.1, fr.get_center().y), Vector3(fr.size.x, 0.2, fr.size.y), m["wall"], false)
	for w in data["walls"]:
		_wall(root, w, wall_h, m["wall"])
	_crates(root, data["crates"], m)
	for p in data["props"]:
		_prop(root, p, m, out)
	for c in data["cameras"]:
		out["cameras"][c["id"]] = _camera(root, c)
	for d in data["doors"]:
		out["doors"][d["id"]] = _door(root, d, wall_h, m)
	for t in data["triggers"]:
		out["triggers"][t["id"]] = _area(root, t["rect"], 1.2)
	return out


static func monitor_env() -> Environment:
	if _monitor_env == null:
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color.BLACK
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(1.0, 1.0, 1.0)
		e.ambient_light_energy = 0.15
		_monitor_env = e
	return _monitor_env


# ---------------------------------------------------------------- 基础件

static func _mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat


static func _glow(color: Color, energy := 1.6) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.8)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


static func _materials() -> Dictionary:
	return {
		"floor": _mat(Color(0.27, 0.27, 0.26), 0.95),
		"wall": _mat(Color(0.46, 0.46, 0.44), 0.95),
		"crate": _mat(Color(0.58, 0.48, 0.33), 0.9),
		"metal": _mat(Color(0.30, 0.32, 0.31), 0.6),
		"metal_light": _mat(Color(0.44, 0.46, 0.45), 0.6),
		"paper": _mat(Color(0.86, 0.85, 0.80), 0.9),
		"stripe": _mat(Color(0.62, 0.09, 0.07), 0.8),
		# 和地面亮度相同（Rec.601 亮度 ≈ 0.27，与 CRT shader 的单色换算一致），单色监控里看不出来
		"trail": _mat(Color(0.55, 0.16, 0.12), 0.55),
		"dark": _mat(Color(0.12, 0.12, 0.12), 0.9),
		"glow_red": _glow(Color(1.0, 0.12, 0.08), 2.5),
		"glow_green": _glow(Color(0.3, 1.0, 0.45), 1.6),
		"glow_amber": _glow(Color(1.0, 0.62, 0.15), 1.6),
		"glow_pale": _glow(Color(0.85, 0.9, 1.0), 1.3),
	}


static func _box(parent: Node, center: Vector3, size: Vector3, mat: Material, collide: bool) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = center
	b.material = mat
	b.use_collision = collide
	parent.add_child(b)
	return b


static func _flat(parent: Node, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi


static func _label(parent: Node, text: String, font_size: int, pixel: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


static func _area(parent: Node, rect: Rect2, height: float) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 2  # 只看机器人
	a.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(rect.size.x, height, rect.size.y)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	a.add_child(cs)
	a.position = Vector3(rect.get_center().x, height * 0.5, rect.get_center().y)
	parent.add_child(a)
	return a


# ---------------------------------------------------------------- 结构

static func _wall(root: Node3D, w: Array, h: float, mat: Material) -> void:
	var a := Vector2(w[0], w[1])
	var b := Vector2(w[2], w[3])
	var c := (a + b) * 0.5
	var size: Vector3
	if is_equal_approx(a.y, b.y):
		size = Vector3(absf(b.x - a.x) + WALL_T, h, WALL_T)
	else:
		size = Vector3(WALL_T, h, absf(b.y - a.y) + WALL_T)
	_box(root, Vector3(c.x, h * 0.5, c.y), size, mat, true)


static func _crates(root: Node3D, c: Dictionary, m: Dictionary) -> void:
	var origin: Vector2 = c["origin"]
	var cell: float = c["cell"]
	var s: float = c["size"]
	var heights: Array = c["heights"]
	var rows: Array = c["rows"]
	for r in rows.size():
		var row: String = rows[r]
		for col in row.length():
			if row[col] != "#":
				continue
			var h: float = heights[(r * 3 + col * 5) % heights.size()]
			var center := Vector3(origin.x + (col + 0.5) * cell, h * 0.5, origin.y + (r + 0.5) * cell)
			_box(root, center, Vector3(s, h, s), m["crate"], true)
			# 每堆货箱南北两面同样的喷字，凑近也分不出是哪一堆
			for side in [-1.0, 1.0]:
				var lab := _label(root, "ОБЪЕКТ-17", 40, 0.0045, Color(0.14, 0.12, 0.10))
				lab.position = Vector3(center.x, 0.5, center.z + side * (s * 0.5 + 0.004))
				lab.rotation.y = 0.0 if side > 0.0 else PI


static func _camera(root: Node3D, c: Dictionary) -> Dictionary:
	var cam := Camera3D.new()
	cam.fov = c.get("fov", 90.0)
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.1
	cam.far = 60.0
	cam.environment = monitor_env()
	root.add_child(cam)
	var pos: Vector3 = c["pos"]
	var target: Vector3 = c["target"]
	cam.look_at_from_position(pos, target, Vector3.UP)
	# 红外补光：只在这一路画面被看的时候打开（同一时间只渲染一路）
	var light := OmniLight3D.new()
	light.omni_range = 22.0
	light.omni_attenuation = 0.6
	light.light_energy = 3.0
	light.position = pos + Vector3(0.0, -0.3, 0.0)
	light.visible = false
	root.add_child(light)
	return {
		"camera": cam,
		"light": light,
		"fps": float(c["fps"]),
		"key": int(c["key"]),
		"reveals": c["reveals"],
	}


static func _door(root: Node3D, d: Dictionary, wall_h: float, m: Dictionary) -> Dictionary:
	var pos: Vector2 = d["pos"]
	var width: float = d["width"]
	var dh: float = d["height"]
	var slab := _box(root, Vector3(pos.x, dh * 0.5, pos.y), Vector3(0.14, dh, width), m["metal_light"], true)
	_box(root, Vector3(pos.x, (dh + wall_h) * 0.5, pos.y), Vector3(WALL_T, wall_h - dh, width), m["wall"], true)
	for side in [-1.0, 1.0]:
		# 门号刷得低：机载摄像头离地 45 cm、略向下看，2～4 米外就能进画面
		var lab := _label(slab, str(d["number"]), 120, 0.004, Color(0.92, 0.9, 0.82))
		lab.position = Vector3(side * 0.075, 0.8 - dh * 0.5, 0.0)
		lab.rotation.y = PI * 0.5 if side > 0.0 else -PI * 0.5
	# 门上的灯：锁着时红灯闪，开了变绿；两面都看得到
	var lamp_mat: StandardMaterial3D = (m["glow_red"] as StandardMaterial3D).duplicate()
	var lamp := _flat(root, Vector3(pos.x, dh + 0.22, pos.y), Vector3(0.34, 0.12, 0.42), lamp_mat)
	# 密码面板
	var pp: Vector3 = d["panel"]
	_box(root, pp, Vector3(0.26, 0.34, 0.06), m["metal"], false)
	_flat(root, pp + Vector3(0.0, 0.08, 0.032), Vector3(0.18, 0.06, 0.004), m["glow_green"])
	for row in 3:
		for col in 3:
			_flat(root, pp + Vector3(-0.06 + col * 0.06, -0.02 - row * 0.045, 0.032), Vector3(0.04, 0.03, 0.006), m["dark"])
	return {
		"node": slab,
		"lamp": lamp,
		"lamp_mat": lamp_mat,
		"area": _area(root, d["area"], 1.2),
		"code": str(d["code"]),
		"slide": d["slide"],
		"open": false,
	}


# ---------------------------------------------------------------- 道具

static func _prop(root: Node3D, p: Dictionary, m: Dictionary, out: Dictionary) -> void:
	match str(p["type"]):
		"stripe":
			_strip(root, p["from"], p["to"], p["width"], m["stripe"])
		"paper":
			_paper(root, p, m)
		"desk":
			_table(root, p["pos"], p["size"], p.get("height", 0.75), m["metal"])
		"chair_fallen":
			_chair_fallen(root, p, m)
		"console":
			_console(root, p, m, out)
		"drag_mark":
			_drag_mark(root, p, m)
		"elevator":
			_elevator(root, p, m)
		"scene":
			_scene(root, p)
		_:
			push_warning("未知道具类型：%s" % p["type"])


static func _strip(root: Node3D, a: Vector2, b: Vector2, width: float, mat: Material) -> void:
	var c := (a + b) * 0.5
	var size: Vector3
	if is_equal_approx(a.y, b.y):
		size = Vector3(absf(b.x - a.x), 0.004, width)
	else:
		size = Vector3(width, 0.004, absf(b.y - a.y))
	_flat(root, Vector3(c.x, DECAL_Y, c.y), size, mat)


static func _paper(root: Node3D, p: Dictionary, m: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	var node := Node3D.new()
	node.position = Vector3(pos.x, 0.0, pos.y)
	node.rotation.y = deg_to_rad(-float(p.get("yaw", 0.0)))
	root.add_child(node)
	_flat(node, Vector3(0.0, 0.003, 0.0), Vector3(0.21, 0.004, 0.297), m["paper"])
	var lab := _label(node, "ЖУРНАЛ\n" + str(p["text"]), 40, 0.0011, Color(0.12, 0.12, 0.2))
	lab.position = Vector3(0.0, 0.0065, 0.0)
	lab.rotation.x = -PI * 0.5


static func _table(root: Node3D, c: Vector2, size: Vector2, h: float, mat: Material) -> CSGBox3D:
	var top := _box(root, Vector3(c.x, h - 0.03, c.y), Vector3(size.x, 0.06, size.y), mat, true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := Vector3(c.x + sx * (size.x * 0.5 - 0.05), (h - 0.06) * 0.5, c.y + sz * (size.y * 0.5 - 0.05))
			_box(root, leg, Vector3(0.05, h - 0.06, 0.05), mat, true)
	return top


static func _chair_fallen(root: Node3D, p: Dictionary, m: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	var node := Node3D.new()
	node.position = Vector3(pos.x, 0.0, pos.y)
	node.rotation.y = deg_to_rad(-float(p.get("yaw", 0.0)))
	root.add_child(node)
	# 仰面倒地：靠背平躺，座面竖起，四条腿横着朝外
	_box(node, Vector3(0.0, 0.02, 0.0), Vector3(0.44, 0.04, 0.5), m["metal_light"], true)
	_box(node, Vector3(0.0, 0.22, 0.27), Vector3(0.44, 0.44, 0.04), m["metal_light"], true)
	for sx in [-1.0, 1.0]:
		for y in [0.05, 0.40]:
			_box(node, Vector3(sx * 0.19, y, 0.5), Vector3(0.03, 0.03, 0.44), m["metal"], false)


static func _console(root: Node3D, p: Dictionary, m: Dictionary, out: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var size: Vector2 = p["size"]
	_table(root, c, size, 0.95, m["metal_light"])
	# 背板：桌下是一个黑洞洞的柜膛，拖痕在里面消失
	_box(root, Vector3(c.x, 0.47, c.y - size.y * 0.5 + 0.06), Vector3(size.x - 0.12, 0.86, 0.04), m["dark"], true)
	# 仪表面板在北侧，朝南倾斜（操作员坐南面）
	var panel := _box(root, Vector3(c.x, 1.17, c.y - size.y * 0.5 + 0.1), Vector3(size.x, 0.42, 0.1), m["metal"], true)
	panel.rotation.x = deg_to_rad(-22.0)
	var colors := ["glow_green", "glow_amber", "glow_green", "glow_green", "glow_amber", "glow_green", "glow_red"]
	for i in colors.size():
		var x := -size.x * 0.5 + 0.3 + i * (size.x - 0.6) / float(colors.size() - 1)
		var dot := _flat(panel, Vector3(x, 0.08, 0.053), Vector3(0.05, 0.035, 0.006), m[colors[i]])
		if i % 3 != 1:
			out["blinkers"].append({"node": dot, "period": 0.9 + i * 0.37, "duty": 0.55, "phase": i * 0.61})


static func _drag_mark(root: Node3D, p: Dictionary, m: Dictionary) -> void:
	var a: Vector2 = p["from"]
	var b: Vector2 = p["to"]
	var w: float = p["width"]
	var dir := b - a
	var length := dir.length()
	dir /= length
	var n := Vector2(-dir.y, dir.x)
	var count := maxi(1, roundi(length / 0.45))
	var seg := length / count
	for i in count:
		for lane: float in [-1.0, 1.0]:
			var wobble := sin(i * 1.7 + lane) * 0.025
			var c := a + dir * (i * seg + seg * 0.5) + n * (lane * 0.1 + wobble)
			var l := seg * (0.55 + 0.45 * absf(sin(i * 2.3 + lane)))
			var lw := w * (0.6 + 0.6 * absf(sin(i * 1.3 + lane * 2.0)))
			var mi := _flat(root, Vector3(c.x, DECAL_Y, c.y), Vector3(lw, 0.004, l), m["trail"])
			mi.rotation.y = atan2(dir.x, dir.y)


static func _elevator(root: Node3D, p: Dictionary, m: Dictionary) -> void:
	var r: Rect2 = p["rect"]
	var h := 2.8
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var cz := r.get_center().y
	_flat(root, Vector3(r.get_center().x, 0.005, cz), Vector3(r.size.x, 0.01, r.size.y), m["dark"])
	_box(root, Vector3(r.get_center().x, h * 0.5, z0), Vector3(r.size.x, h, WALL_T), m["metal"], true)  # 北壁
	_box(root, Vector3(r.get_center().x, h + 0.05, cz), Vector3(r.size.x, 0.1, r.size.y), m["metal"], true)  # 顶
	# 入口两侧立柱，留 1.6 米宽的门
	var post := (r.size.y - 1.6) * 0.5
	_box(root, Vector3(x0, h * 0.5, z0 + post * 0.5), Vector3(WALL_T, h, post), m["metal"], true)
	_box(root, Vector3(x0, h * 0.5, z1 - post * 0.5), Vector3(WALL_T, h, post), m["metal"], true)
	# 轿厢后壁一条灯带：黑暗里远远就能看见的目标
	_flat(root, Vector3(x1 - 0.12, 2.1, cz), Vector3(0.04, 0.08, 1.4), m["glow_pale"])
	_flat(root, Vector3(x1 - 0.12, 1.1, z0 + post + 0.2), Vector3(0.03, 0.12, 0.08), m["glow_amber"])


static func _scene(root: Node3D, p: Dictionary) -> void:
	var packed := load(str(p["path"])) as PackedScene
	if packed == null:
		push_warning("找不到场景：%s" % p["path"])
		return
	var inst := packed.instantiate() as Node3D
	var pos: Vector3 = p["pos"]
	inst.position = pos
	inst.rotation.y = deg_to_rad(-float(p.get("yaw", 0.0)))
	inst.scale = Vector3.ONE * float(p.get("scale", 1.0))
	root.add_child(inst)
