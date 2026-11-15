extends Control
## Dead Feed 原型：操作台。
## 机载 / 监控切换（Shift）、直接选监控（1～9 或点平面图）、低帧率监控、CRT、
## 切换雪花与继电器声、残缺平面图、按键图标、17 号门密码面板、关卡结束。
## 同一时间只渲染一路画面：所有摄像头共用一个低分辨率 SubViewport。

const LevelData := preload("res://levels/level_01.gd")
const LevelBuilder := preload("res://scripts/level_builder.gd")
const RobotScript := preload("res://scripts/robot.gd")
const FeedOverlay := preload("res://scripts/feed_overlay.gd")
const FloorPlan := preload("res://scripts/floor_plan.gd")
const Sfx := preload("res://scripts/sfx.gd")
const CRT_SHADER := preload("res://shaders/crt.gdshader")

const ONBOARD := "onboard"
const ONBOARD_RES := Vector2i(480, 360)
const MONITOR_RES := Vector2i(320, 240)
const SWITCH_STATIC := 0.6
const CLOCK_START := 3 * 3600 + 12 * 60 + 40  # 监控时间戳从 03:12:40 开始

const PHOSPHOR := Color(0.45, 1.0, 0.62)
const AMBER := Color(1.0, 0.7, 0.25)
const KEY_BG := Color(0.15, 0.155, 0.145)
const KEY_LIT := Color(0.62, 0.45, 0.13)
const KEY_TEXT := Color(0.55, 0.55, 0.52)
const KEY_TEXT_LIT := Color(1.0, 0.92, 0.7)

# 按键图标：id, 显示, 位置, 尺寸, 动作
const KEYS := [
	["W", "W", Vector2(54, 0), Vector2(48, 48), "move_forward"],
	["A", "A", Vector2(0, 54), Vector2(48, 48), "turn_left"],
	["S", "S", Vector2(54, 54), Vector2(48, 48), "move_back"],
	["D", "D", Vector2(108, 54), Vector2(48, 48), "turn_right"],
	["F", "F", Vector2(190, 54), Vector2(48, 48), "headlight"],
	["E", "E", Vector2(244, 54), Vector2(48, 48), "interact"],
	["SHIFT", "SHIFT", Vector2(0, 108), Vector2(156, 48), "toggle_feed"],
	["R", "R", Vector2(244, 108), Vector2(48, 48), "restart"],
	["1", "1", Vector2(0, 162), Vector2(48, 48), "cam_1"],
	["2", "2", Vector2(54, 162), Vector2(48, 48), "cam_2"],
	["3", "3", Vector2(108, 162), Vector2(48, 48), "cam_3"],
]

var level: Dictionary
var built: Dictionary
var room_rects := {}
var viewport: SubViewport
var world: Node3D
var feed_rect: TextureRect
var crt: ShaderMaterial
var overlay: FeedOverlay
var floor_plan: FloorPlan
var keypad_label: Label
var robot: RobotScript

var view := ONBOARD
var last_monitor := ""
var frame_accum := 0.0
var static_left := 0.0
var static_total := SWITCH_STATIC
var clock := 0.0
var finished := false
var near_door := ""
var keypad_door := ""
var keypad_entry := ""
var keypad_flash := ""
var keypad_flash_left := 0.0

var keycaps := {}
var hint_done := {"move": false, "shift": false, "e": false}
var players := {}


func _ready() -> void:
	_setup_input()
	_setup_audio()
	_build_console()

	level = LevelData.get_data()
	world = Node3D.new()
	world.name = "World"
	viewport.add_child(world)
	built = LevelBuilder.build(level, world)
	for r in level["rooms"]:
		room_rects[r["id"]] = r["rect"]

	robot = RobotScript.new()
	world.add_child(robot)
	var start: Dictionary = level["robot_start"]
	_place_robot(start["pos"], start["heading"])

	for id in built["doors"]:
		var area: Area3D = built["doors"][id]["area"]
		area.body_entered.connect(_on_door_area_entered.bind(id))
		area.body_exited.connect(_on_door_area_exited.bind(id))
	var end_area: Area3D = built["triggers"]["level_end"]
	end_area.body_entered.connect(_on_end_entered)

	for n in ["1", "2", "3"]:
		(keycaps[n]["panel"] as Control).visible = _camera_with_key(int(n)) != ""
	floor_plan.setup(level["rooms"], _map_cameras())
	floor_plan.camera_picked.connect(func(id: String) -> void: select_view(id))

	select_view(ONBOARD, true)
	_burst_static(1.0)  # 开机雪花

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autotest="):
			_run_autotest(arg.get_slice("=", 1))


# ---------------------------------------------------------------- 输入

func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("turn_left", [KEY_A, KEY_LEFT])
	_bind("turn_right", [KEY_D, KEY_RIGHT])
	_bind("toggle_feed", [KEY_SHIFT])
	_bind("interact", [KEY_E])
	_bind("headlight", [KEY_F])
	_bind("restart", [KEY_R])
	for i in range(1, 10):
		_bind("cam_%d" % i, [KEY_0 + i])


func _bind(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if finished:
		if event.is_action_pressed("restart"):
			get_tree().reload_current_scene()
		return

	var key := event as InputEventKey
	if keypad_door != "" and key != null and key.pressed and not key.echo:
		var digit := _digit_of(key)
		if digit != "":
			_keypad_digit(digit)
			get_viewport().set_input_as_handled()
			return
		if key.physical_keycode == KEY_BACKSPACE:
			keypad_entry = keypad_entry.left(-1)
			_refresh_keypad()
			get_viewport().set_input_as_handled()
			return
		if key.physical_keycode == KEY_ESCAPE or event.is_action_pressed("interact"):
			_close_keypad()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("toggle_feed"):
		_toggle_feed()
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("headlight"):
		robot.toggle_headlight()
		_play("click", 1.7, -12.0)
	else:
		for cid in built["cameras"]:
			if event.is_action_pressed("cam_%d" % int(built["cameras"][cid]["key"])):
				select_view(cid)
				break


func _digit_of(key: InputEventKey) -> String:
	var code := key.physical_keycode
	if code >= KEY_0 and code <= KEY_9:
		return str(code - KEY_0)
	if code >= KEY_KP_0 and code <= KEY_KP_9:
		return str(code - KEY_KP_0)
	return ""


# ---------------------------------------------------------------- 画面切换

func select_view(id: String, silent := false) -> void:
	if finished:
		return
	if id != ONBOARD and not built["cameras"].has(id):
		return
	if id == view and not silent:
		return
	view = id
	var onboard := id == ONBOARD
	for cid in built["cameras"]:
		(built["cameras"][cid]["light"] as OmniLight3D).visible = cid == id
	if onboard:
		robot.onboard_cam.make_current()
		viewport.size = ONBOARD_RES
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		overlay.set_hud(false)
		_set_crt(0.0, 0.035, ONBOARD_RES.y, 1.0)
	else:
		last_monitor = id
		var cam: Dictionary = built["cameras"][id]
		(cam["camera"] as Camera3D).make_current()
		viewport.size = MONITOR_RES
		overlay.set_hud(true)
		_set_crt(1.0, 0.09, MONITOR_RES.y, 1.25)
		for room_id in cam["reveals"]:
			floor_plan.revealed[room_id] = true
		frame_accum = 0.0
		_capture_monitor_frame()
	floor_plan.current = "" if onboard else id
	floor_plan.queue_redraw()
	_apply_audio_view(onboard)
	if not silent:
		_burst_static(SWITCH_STATIC)
		_play("click")


func _toggle_feed() -> void:
	hint_done["shift"] = true
	if view == ONBOARD:
		select_view(last_monitor if last_monitor != "" else _camera_with_key(1))
	else:
		select_view(ONBOARD)


func _camera_with_key(k: int) -> String:
	for cid in built["cameras"]:
		if int(built["cameras"][cid]["key"]) == k:
			return cid
	return ""


func _capture_monitor_frame() -> void:
	var cam: Dictionary = built["cameras"][view]
	var in_room := _robot_in_rooms(cam["reveals"])
	overlay.update_hud(cam["camera"], robot, view, _timestamp(), Vector2(viewport.size), in_room)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## 朝向箭头只在机器人位于这路摄像头负责的房间里时出现，不会隔墙显示
func _robot_in_rooms(room_ids: Array) -> bool:
	var p := Vector2(robot.global_position.x, robot.global_position.z)
	for room_id in room_ids:
		if (room_rects[room_id] as Rect2).has_point(p):
			return true
	return false


func _timestamp() -> String:
	var t := CLOCK_START + int(clock)
	return "15.11.87  %02d:%02d:%02d" % [t / 3600 % 24, t / 60 % 60, t % 60]


func _set_crt(mono: float, noise: float, lines: int, bright: float) -> void:
	crt.set_shader_parameter("mono", mono)
	crt.set_shader_parameter("brightness", bright)
	crt.set_shader_parameter("noise_amount", noise)
	crt.set_shader_parameter("scan_lines", float(lines))


func _burst_static(seconds: float) -> void:
	static_left = seconds
	static_total = seconds


# ---------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	if not finished:
		clock += delta
	if not hint_done["move"] and robot.odometer > 0.6:
		hint_done["move"] = true

	static_left = maxf(0.0, static_left - delta)
	var amount := clampf(static_left / static_total * 1.2, 0.0, 1.0) if static_total > 0.0 else 0.0
	crt.set_shader_parameter("static_amount", amount)
	(players["static"] as AudioStreamPlayer).volume_db = linear_to_db(maxf(amount, 0.0001)) - 10.0

	if view != ONBOARD and not finished:
		var period := 1.0 / float(built["cameras"][view]["fps"])
		frame_accum += delta
		if frame_accum >= period:
			frame_accum = fmod(frame_accum, period)
			_capture_monitor_frame()

	_update_blinkers()
	_update_keypad(delta)
	_update_keys()
	var motion := robot.motion_level()
	var motor: AudioStreamPlayer = players["motor"]
	motor.volume_db = linear_to_db(0.08 + 0.92 * motion) - 6.0
	motor.pitch_scale = 0.85 + 0.35 * motion


func _update_blinkers() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for b in built["blinkers"]:
		var period: float = b["period"]
		(b["node"] as Node3D).visible = fmod(t + float(b["phase"]), period) < period * float(b["duty"])
	for id in built["doors"]:
		var door: Dictionary = built["doors"][id]
		var lamp: Node3D = door["lamp"]
		if door["open"]:
			lamp.visible = true
		else:
			lamp.visible = fmod(t, 1.2) < 0.6


# ---------------------------------------------------------------- 门与密码面板

func _on_door_area_entered(body: Node3D, id: String) -> void:
	if body == robot:
		near_door = id


func _on_door_area_exited(body: Node3D, id: String) -> void:
	if body == robot and near_door == id:
		near_door = ""
		if keypad_door == id and keypad_flash != "ok":
			_close_keypad()


func _interact() -> void:
	if near_door != "" and not built["doors"][near_door]["open"]:
		hint_done["e"] = true
		_open_keypad(near_door)


func _open_keypad(id: String) -> void:
	keypad_door = id
	keypad_entry = ""
	keypad_flash = ""
	_play("beep")
	_refresh_keypad()


func _close_keypad() -> void:
	keypad_door = ""
	keypad_entry = ""
	keypad_flash = ""
	_refresh_keypad()


func _keypad_digit(d: String) -> void:
	if keypad_flash != "":
		return
	var code: String = built["doors"][keypad_door]["code"]
	keypad_entry += d
	_play("beep")
	if keypad_entry.length() >= code.length():
		if keypad_entry == code:
			keypad_flash = "ok"
			keypad_flash_left = 1.2
			_open_door(keypad_door)
		else:
			keypad_flash = "err"
			keypad_flash_left = 0.8
			_play("buzz")
	_refresh_keypad()


func _update_keypad(delta: float) -> void:
	if keypad_flash == "":
		return
	keypad_flash_left -= delta
	if keypad_flash_left > 0.0:
		_refresh_keypad()
	elif keypad_flash == "ok":
		_close_keypad()
	else:
		keypad_flash = ""
		keypad_entry = ""
		_refresh_keypad()


func _refresh_keypad() -> void:
	if keypad_door == "":
		keypad_label.text = ""
		return
	var n: int = (built["doors"][keypad_door]["code"] as String).length()
	var parts := PackedStringArray()
	for i in n:
		parts.append(keypad_entry[i] if i < keypad_entry.length() else "_")
	keypad_label.text = " ".join(parts)
	match keypad_flash:
		"ok":
			keypad_label.modulate = PHOSPHOR
		"err":
			keypad_label.modulate = AMBER if int(keypad_flash_left * 8.0) % 2 == 0 else Color(AMBER, 0.2)
		_:
			keypad_label.modulate = Color(PHOSPHOR, 0.85)


func _open_door(id: String) -> void:
	var door: Dictionary = built["doors"][id]
	door["open"] = true
	_play("door")
	var slab: CSGBox3D = door["node"]
	var target: Vector3 = slab.position + (door["slide"] as Vector3)
	(door["lamp_mat"] as StandardMaterial3D).emission = Color(0.3, 1.0, 0.4)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void: slab.use_collision = false)
	tw.tween_property(slab, "position", target, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------- 关卡结束

func _on_end_entered(body: Node3D) -> void:
	if body != robot or finished:
		return
	finished = true
	robot.input_enabled = false
	_close_keypad()
	_play("door")
	_burst_static(1.6)
	await get_tree().create_timer(1.4).timeout
	world.visible = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var secs := int(clock)
	overlay.show_end("END\n%02d:%02d" % [secs / 60, secs % 60])
	(keycaps["R"]["panel"] as Control).visible = true


# ---------------------------------------------------------------- 操作台界面

func _build_console() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.08, 0.074)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 主显示器
	_panel(Rect2(24, 24, 856, 672), Color(0.02, 0.02, 0.02), Color(0.17, 0.17, 0.16), 12, 22)
	viewport = SubViewport.new()
	viewport.size = ONBOARD_RES
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	overlay = FeedOverlay.new()
	viewport.add_child(overlay)
	crt = ShaderMaterial.new()
	crt.shader = CRT_SHADER
	feed_rect = TextureRect.new()
	feed_rect.position = Vector2(36, 48)
	feed_rect.size = Vector2(832, 624)
	feed_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	feed_rect.stretch_mode = TextureRect.STRETCH_SCALE
	feed_rect.texture = viewport.get_texture()
	feed_rect.material = crt
	feed_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feed_rect)

	# 平面图
	_panel(Rect2(904, 24, 352, 212), Color(0.02, 0.02, 0.02), Color(0.17, 0.17, 0.16), 8, 12)
	floor_plan = FloorPlan.new()
	floor_plan.position = Vector2(916, 36)
	floor_plan.size = Vector2(328, 188)
	add_child(floor_plan)

	# 密码面板显示屏
	_panel(Rect2(904, 252, 352, 84), Color(0.02, 0.055, 0.035), Color(0.17, 0.17, 0.16), 8, 12)
	keypad_label = Label.new()
	keypad_label.position = Vector2(916, 262)
	keypad_label.size = Vector2(328, 64)
	keypad_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keypad_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	keypad_label.add_theme_font_size_override("font_size", 36)
	keypad_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(keypad_label)

	_build_keys(Vector2(934, 372))


func _panel(rect: Rect2, fill: Color, border: Color, border_w: int, radius: int) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p


func _build_keys(origin: Vector2) -> void:
	for k in KEYS:
		var p := Panel.new()
		p.position = origin + (k[2] as Vector2)
		p.size = k[3]
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = KEY_BG
		sb.border_color = Color(0.25, 0.25, 0.24)
		sb.set_border_width_all(2)
		sb.border_width_bottom = 5
		sb.set_corner_radius_all(6)
		p.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = k[1]
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 15)
		p.add_child(l)
		add_child(p)
		keycaps[k[0]] = {"panel": p, "label": l, "style": sb, "action": k[4]}
	(keycaps["R"]["panel"] as Control).visible = false


func _update_keys() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	var pulsing := _pulsing_keys()
	for id in keycaps:
		var k: Dictionary = keycaps[id]
		var lit := 1.0 if Input.is_action_pressed(k["action"]) else 0.0
		if pulsing.has(id):
			lit = maxf(lit, pulse)
		var action: String = k["action"]
		if action.begins_with("cam_") and view == _camera_with_key(int(action.substr(4))):
			lit = maxf(lit, 0.55)
		(k["style"] as StyleBoxFlat).bg_color = KEY_BG.lerp(KEY_LIT, lit)
		(k["label"] as Label).add_theme_color_override("font_color", KEY_TEXT.lerp(KEY_TEXT_LIT, lit))


## 按键提示只以按键图标闪烁出现一次，做过就不再提示
func _pulsing_keys() -> Dictionary:
	var p := {}
	if finished:
		p["R"] = true
		return p
	if not hint_done["move"] and clock > 0.8:
		for k in ["W", "A", "S", "D"]:
			p[k] = true
	if not hint_done["shift"] and (hint_done["move"] or clock > 10.0):
		p["SHIFT"] = true
	if near_door != "" and not hint_done["e"] and not built["doors"][near_door]["open"]:
		p["E"] = true
	return p


func _map_cameras() -> Array:
	var arr := []
	for c in level["cameras"]:
		var pos: Vector3 = c["pos"]
		var target: Vector3 = c["target"]
		arr.append({
			"id": c["id"],
			"key": c["key"],
			"pos": Vector2(pos.x, pos.z),
			"dir": Vector2(target.x - pos.x, target.z - pos.z).normalized(),
		})
	return arr


# ---------------------------------------------------------------- 声音

func _setup_audio() -> void:
	_ensure_bus("Robot")
	_ensure_bus("World")
	var s := Sfx.build_all()
	_add_player("motor", s["motor"], "Robot", -30.0)
	_add_player("ambient", s["ambient"], "World", -14.0)
	_add_player("static", s["static"], "Master", -80.0)
	_add_player("click", s["click"], "Master", -4.0)
	_add_player("beep", s["beep"], "Master", -10.0)
	_add_player("buzz", s["buzz"], "Master", -8.0)
	_add_player("door", s["door"], "World", -2.0)
	for loop_name in ["motor", "ambient", "static"]:
		(players[loop_name] as AudioStreamPlayer).play()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(idx, lp)


func _add_player(player_name: String, stream: AudioStream, bus: String, volume: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = volume
	add_child(p)
	players[player_name] = p


func _play(player_name: String, pitch := 1.0, volume_offset := 0.0) -> void:
	var p: AudioStreamPlayer = players[player_name]
	if not p.has_meta("base_db"):
		p.set_meta("base_db", p.volume_db)
	p.pitch_scale = pitch
	p.volume_db = float(p.get_meta("base_db")) + volume_offset
	p.play()


## 机载：机器人声音贴耳、环境声小；监控：机器人声音变远变闷，环境声成为主体
func _apply_audio_view(onboard: bool) -> void:
	var r := AudioServer.get_bus_index("Robot")
	var w := AudioServer.get_bus_index("World")
	(AudioServer.get_bus_effect(r, 0) as AudioEffectLowPassFilter).cutoff_hz = 20000.0 if onboard else 600.0
	AudioServer.set_bus_volume_db(r, 0.0 if onboard else -12.0)
	(AudioServer.get_bus_effect(w, 0) as AudioEffectLowPassFilter).cutoff_hz = 2500.0 if onboard else 900.0
	AudioServer.set_bus_volume_db(w, -6.0 if onboard else 0.0)


# ---------------------------------------------------------------- 工具

func _place_robot(pos: Vector3, heading_deg: float) -> void:
	robot.global_position = pos
	robot.rotation = Vector3(0.0, deg_to_rad(-heading_deg), 0.0)
	robot.speed = 0.0
	robot.turn_rate = 0.0


## 自动截图检查：godot --path . -- --autotest=<目录>
func _run_autotest(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _wait(1.4)
	await _shot(dir + "/01_onboard_start.png")

	var z0 := robot.global_position.z
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	print("AUTOTEST 正对货箱前进 1.5 秒，z 变化 = %.3f（应约 -0.82：顶到货箱停下）" % (robot.global_position.z - z0))
	Input.action_press("turn_right")
	await _wait(2.0)
	Input.action_release("turn_right")
	await _wait(0.4)
	print("AUTOTEST 右转约 2.4 秒后 heading = %.1f°（应接近 90）" % -rad_to_deg(robot.rotation.y))

	_toggle_feed()
	await _wait(1.2)
	await _shot(dir + "/02_cam1.png")
	select_view("CAM-2")
	await _wait(1.2)
	await _shot(dir + "/03_cam2.png")
	select_view("CAM-3")
	await _wait(1.2)
	await _shot(dir + "/04_cam3.png")

	_place_robot(Vector3(12.95, 0.0, 6.0), 180.0)
	select_view(ONBOARD)
	await _wait(1.2)
	await _shot(dir + "/05_onboard_code_paper.png")
	_place_robot(Vector3(15.1, 0.0, 6.7), 0.0)
	await _wait(1.0)
	await _shot(dir + "/06_onboard_decoys.png")
	select_view("CAM-2")
	await _wait(1.2)
	await _shot(dir + "/07_cam2_robot.png")

	_place_robot(Vector3(20.6, 0.0, 4.2), 90.0)
	select_view(ONBOARD)
	await _wait(1.2)
	await _shot(dir + "/08_onboard_trail.png")
	_place_robot(Vector3(22.35, 0.0, 4.6), 0.0)
	await _wait(1.0)
	await _shot(dir + "/09_onboard_under_console.png")
	select_view("CAM-3")
	await _wait(1.2)
	await _shot(dir + "/09b_cam3_trail_hidden.png")
	select_view(ONBOARD)

	_place_robot(Vector3(15.2, 0.0, 0.8), 90.0)
	await _wait(1.0)
	await _shot(dir + "/09c_onboard_door17.png")
	_place_robot(Vector3(16.6, 0.0, 0.8), 90.0)
	await _wait(0.8)
	_interact()
	for d in "40":
		_keypad_digit(d)
	await _wait(0.2)
	await _shot(dir + "/10_keypad.png")
	for d in "71":
		_keypad_digit(d)
	await _wait(3.2)
	print("AUTOTEST 17 号门已开：", built["doors"]["door_17"]["open"])
	select_view("CAM-3")
	await _wait(1.2)
	await _shot(dir + "/11_cam3_door_open.png")

	await _topdown(dir + "/00_topdown.png")

	select_view(ONBOARD, true)
	_place_robot(Vector3(25.9, 0.0, 6.7), 90.0)
	await _wait(2.4)
	await _shot(dir + "/12_end.png")
	print("AUTOTEST 完成")
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("AUTOTEST 截图 ", path)


## 俯视全图（只用于检查布局）
func _topdown(path: String) -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = 30.0
	cam.far = 80.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	cam.environment = env
	world.add_child(cam)
	cam.position = Vector3(13.5, 30.0, 4.25)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.make_current()
	viewport.size = Vector2i(1200, 600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	overlay.set_hud(false)
	await _wait(0.5)
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(path)
	print("AUTOTEST 截图 ", path)
	cam.queue_free()
