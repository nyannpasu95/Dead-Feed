extends Control
## 画在监控画面里的元素（随画面一起低帧率、一起过 CRT）：
## 摄像头编号、时间戳、机器人朝向箭头。机载画面不显示任何东西。

var hud_visible := false
var arrow_visible := false
var arrow_pos := Vector2.ZERO
var arrow_dir := Vector2.UP

var _cam_label: Label
var _time_label: Label
var _end_label: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_label = _make_label(11)
	_time_label = _make_label(11)
	_end_label = _make_label(22)
	_end_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_end_label.visible = false
	_apply_visibility()


func set_hud(on: bool) -> void:
	hud_visible = on
	_apply_visibility()
	queue_redraw()


## 抓一帧监控画面前调用：更新文字和箭头位置。
func update_hud(cam: Camera3D, robot: Node3D, cam_name: String, stamp: String, vp_size: Vector2, show_arrow: bool) -> void:
	_cam_label.text = cam_name
	_cam_label.reset_size()
	_cam_label.position = Vector2(14.0, 10.0)
	_time_label.text = stamp
	_time_label.reset_size()
	_time_label.position = vp_size - _time_label.size - Vector2(14.0, 10.0)

	arrow_visible = false
	var p3 := robot.global_position + Vector3(0.0, 1.0, 0.0)
	if show_arrow and not cam.is_position_behind(p3):
		var p := cam.unproject_position(p3)
		if Rect2(Vector2.ZERO, vp_size).grow(-6.0).has_point(p):
			var fwd := -robot.global_transform.basis.z
			var d := cam.unproject_position(p3 + fwd * 0.7) - p
			arrow_dir = d.normalized() if d.length() > 0.5 else Vector2.UP
			arrow_pos = p
			arrow_visible = true
	queue_redraw()


func show_end(text: String) -> void:
	hud_visible = false
	_end_label.text = text
	_end_label.visible = true
	_apply_visibility()
	queue_redraw()


func _draw() -> void:
	if not (hud_visible and arrow_visible):
		return
	var d := arrow_dir
	var n := Vector2(-d.y, d.x)
	var tip := arrow_pos + d * 7.0
	var left := arrow_pos - d * 4.0 + n * 5.0
	var right := arrow_pos - d * 4.0 - n * 5.0
	var notch := arrow_pos - d * 1.0
	var pts := PackedVector2Array([tip, left, notch, right])
	draw_colored_polygon(pts, Color(1.0, 1.0, 1.0, 0.95))
	# 黑描边：机身在红外里也是白的，没有描边时箭头会糊进机身
	pts.append(tip)
	draw_polyline(pts, Color(0.0, 0.0, 0.0, 0.9), 1.5)


func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _apply_visibility() -> void:
	_cam_label.visible = hud_visible
	_time_label.visible = hud_visible
