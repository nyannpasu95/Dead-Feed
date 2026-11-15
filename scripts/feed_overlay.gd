extends Control
## 画在监控画面里的元素（随画面一起低帧率、一起过 CRT）：
## 摄像头编号、时间戳。机器人朝哪边只能看探照灯的光束。机载画面不显示任何东西。

var hud_visible := false

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


## 抓一帧监控画面前调用：更新编号和时间戳。
func update_hud(cam_name: String, stamp: String, vp_size: Vector2) -> void:
	_cam_label.text = cam_name
	_cam_label.reset_size()
	_cam_label.position = Vector2(14.0, 10.0)
	_time_label.text = stamp
	_time_label.reset_size()
	_time_label.position = vp_size - _time_label.size - Vector2(14.0, 10.0)


func show_end(text: String) -> void:
	hud_visible = false
	_end_label.text = text
	_end_label.visible = true
	_apply_visibility()


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
