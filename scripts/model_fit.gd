extends RefCounted
## 资产工作台做出的模型只当外观用：碰撞、声呐、撞击声仍由代码里的灰盒负责，
## 模型按灰盒的尺寸装进去，看到的和撞到的是同一个东西。
## 模型文件还不存在时 fit() 返回 null，调用方继续用灰盒外观。


## 把模型装进 box_size 的盒子：底面落在原点，水平居中。
## per_axis = true 时三个方向各自缩放（货箱、桌子，和碰撞盒严丝合缝），否则按能装下的最大比例等比缩放。
## turn 是先转好模型的朝向（欧拉角，度），再量尺寸。
static func fit(path: String, box_size: Vector3, per_axis: bool = false, turn := Vector3.ZERO,
		layers: int = 1, shadows: bool = true) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	var turner := Node3D.new()
	turner.rotation_degrees = turn
	turner.add_child(model)
	var acc: Array[AABB] = []
	_measure(turner, Transform3D.IDENTITY, acc)
	if acc.is_empty():
		model.free()
		return null
	var box := acc[0]
	var s := Vector3.ONE
	if per_axis:
		s = Vector3(box_size.x / box.size.x, box_size.y / box.size.y, box_size.z / box.size.z)
	else:
		s = Vector3.ONE * minf(minf(box_size.x / box.size.x, box_size.y / box.size.y), box_size.z / box.size.z)
	var pivot := Node3D.new()
	pivot.scale = s
	var c := box.get_center()
	pivot.position = Vector3(-c.x * s.x, -box.position.y * s.y, -c.z * s.z)
	pivot.add_child(turner)
	var holder := Node3D.new()
	holder.add_child(pivot)
	set_layers(holder, layers, shadows)
	return holder


## 递归设渲染层和投影
static func set_layers(node: Node, layers: int, shadows: bool) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	if node is GeometryInstance3D and not shadows:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		set_layers(child, layers, shadows)


## 有了模型就把灰盒藏起来：不进任何画面、不投影，碰撞照旧
static func hide_boxes(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).layers = 0
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		hide_boxes(child)


## 所有网格合起来的包围盒（模型还没进场景树，变换自己累乘）
static func _measure(node: Node, parent: Transform3D, acc: Array[AABB]) -> void:
	var xf := parent
	if node is Node3D:
		xf = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var box: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
		if acc.is_empty():
			acc.append(box)
		else:
			acc[0] = acc[0].merge(box)
	for child in node.get_children():
		_measure(child, xf, acc)
