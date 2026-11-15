extends Control
## 操作台上的残缺平面图：摄像头拍到哪个房间，才补全哪个房间。
## 摄像头图标一直在（操作台知道摄像头装在哪），点击即切换。不显示机器人位置。

signal camera_picked(id: String)

const INK := Color(0.45, 1.0, 0.62)
const BG := Color(0.02, 0.055, 0.035)

var rooms: Array = []
var cameras: Array = []
var revealed := {}
var current := ""
var _bounds := Rect2()


func setup(level_rooms: Array, level_cameras: Array) -> void:
	rooms = level_rooms
	cameras = level_cameras
	var first := true
	for r in rooms:
		var rect: Rect2 = r["rect"]
		_bounds = rect if first else _bounds.merge(rect)
		first = false
	_bounds = _bounds.grow(1.2)
	queue_redraw()


func _to_map(p: Vector2) -> Vector2:
	var s := minf(size.x / _bounds.size.x, size.y / _bounds.size.y)
	var offset := (size - _bounds.size * s) * 0.5
	return offset + (p - _bounds.position) * s


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	for r in rooms:
		if not revealed.has(r["id"]):
			continue
		var rect: Rect2 = r["rect"]
		var a := _to_map(rect.position)
		var b := _to_map(rect.end)
		draw_rect(Rect2(a, b - a), Color(INK, 0.07), true)
		draw_rect(Rect2(a, b - a), Color(INK, 0.8), false, 1.5)
	var font := get_theme_default_font()
	for c in cameras:
		var p := _to_map(c["pos"])
		var dir: Vector2 = c["dir"]
		var on: bool = c["id"] == current
		var col := Color(INK, 1.0 if on else 0.45)
		for side in [-1.0, 1.0]:
			draw_line(p, p + dir.rotated(side * PI * 0.25) * (22.0 if on else 13.0), col, 1.0)
		draw_circle(p, 4.5 if on else 3.0, col)
		draw_string(font, p + Vector2(-14.0, -7.0), str(c["key"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	# 扫描线
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.0, 0.0, 0.0, 0.28), 1.0)
		y += 3.0


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var best := ""
	var best_d := 18.0
	for c in cameras:
		var d := _to_map(c["pos"]).distance_to(mb.position)
		if d < best_d:
			best_d = d
			best = c["id"]
	if best != "":
		camera_picked.emit(best)
		accept_event()
