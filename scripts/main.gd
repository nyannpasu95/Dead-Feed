extends Control
## Dead Feed 原型：操作台。
## 机载照片 / 监控切换（Shift）、直接选监控（1～9 或点平面图）、低帧率监控、CRT、
## 拍照（空格：闪光、逐行传回、冷却）、前向声呐（Q：扇形屏、回声、冷却）、
## 切换雪花与继电器声、残缺平面图、按键图标、17 号门密码面板、关卡结束。
## 同一时间只渲染一路画面：所有摄像头共用一个低分辨率 SubViewport；
## 照片另有两个 SubViewport 轮流用（共用同一个世界），只在按下快门那一帧渲染。
## 声音：照片是静止的，声音是实时的。听者跟着画面走——看照片时在机器人身上，
## 看监控时在那路摄像头上；机器人的声音和关卡里的声音地标都是 3D 的，隔着墙会变闷。

const LevelData := preload("res://levels/level_01.gd")
const LevelBuilder := preload("res://scripts/level_builder.gd")
const RobotScript := preload("res://scripts/robot.gd")
const FeedOverlay := preload("res://scripts/feed_overlay.gd")
const FloorPlan := preload("res://scripts/floor_plan.gd")
const Sfx := preload("res://scripts/sfx.gd")
const SonarScope := preload("res://scripts/sonar_scope.gd")
const CRT_SHADER := preload("res://shaders/crt.gdshader")

const ONBOARD := "onboard"
const PHOTO_RES := Vector2i(480, 360)
const PHOTO_COOLDOWN := 5.0
const PHOTO_SCAN_TIME := 1.0
const SONAR_COOLDOWN := 3.5
const MONITOR_RES := Vector2i(320, 240)
const SWITCH_STATIC := 0.6
const CLOCK_START := 3 * 3600 + 12 * 60 + 40  # 监控时间戳从 03:12:40 开始

# 3D 声音的基础音量（dB）和参考距离（米）
const SOUND_DB := {
	"shutter": -7.0, "charge": -21.0, "ping": -7.0, "rustle": -7.0,
	"thud_concrete": -3.0, "thud_crate": -3.0, "thud_metal": -7.0,
	"vent": -6.0, "lamp_hum": -16.0, "console": -8.0, "elevator": -4.0,
}
const SOUND_UNIT := {"vent": 1.6, "lamp_hum": 0.9, "console": 1.4, "elevator": 2.0}
# 看照片时听者在机器人相机上，离机身声源只有 0.4 米左右（距离衰减反而 +13 dB）：Robot 总线压回来
const ROBOT_CLOSE_DB := -12.0

const PHOSPHOR := Color(0.45, 1.0, 0.62)
const AMBER := Color(1.0, 0.7, 0.25)
const KEY_BG := Color(0.15, 0.155, 0.145)
const KEY_LIT := Color(0.62, 0.45, 0.13)
const KEY_TEXT := Color(0.55, 0.55, 0.52)
const KEY_TEXT_LIT := Color(1.0, 0.92, 0.7)

# 按键图标：id, 显示, 位置, 尺寸, 动作。排成键盘上的样子，空格键不写字
const KEYS := [
	["1", "1", Vector2(0, 0), Vector2(48, 48), "cam_1"],
	["2", "2", Vector2(54, 0), Vector2(48, 48), "cam_2"],
	["3", "3", Vector2(108, 0), Vector2(48, 48), "cam_3"],
	["Q", "Q", Vector2(0, 54), Vector2(48, 48), "sonar"],
	["W", "W", Vector2(54, 54), Vector2(48, 48), "move_forward"],
	["E", "E", Vector2(108, 54), Vector2(48, 48), "interact"],
	["R", "R", Vector2(162, 54), Vector2(48, 48), "restart"],
	["A", "A", Vector2(0, 108), Vector2(48, 48), "turn_left"],
	["S", "S", Vector2(54, 108), Vector2(48, 48), "move_back"],
	["D", "D", Vector2(108, 108), Vector2(48, 48), "turn_right"],
	["SHIFT", "SHIFT", Vector2(0, 162), Vector2(102, 48), "toggle_feed"],
	["SPACE", "", Vector2(108, 162), Vector2(156, 48), "photo"],
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
var sonar: SonarScope
var keypad_label: Label
var robot: RobotScript

# 照片：两个 SubViewport 轮流用，photo_front 是最新一张
var photo_vps: Array[SubViewport] = []
var photo_cams: Array[Camera3D] = []
var photo_stamps: Array[Label] = []
var photo_front := 1
var has_photo := false
var photo_rendering := false
var photo_reveal := 1.0
var photo_cooldown := 0.0
var sonar_cooldown := 0.0
var black_tex: ImageTexture

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

var ear: AudioListener3D
var sfx := {}
var field_sources: Array = []   # 关卡声源：{player, base_db, follows, occ}
var robot_occ := 0.0
var motor_db := -40.0
var papers: Array = []
var paper_under := {}
var last_bump := ""
var bump_time := -100.0
var last_bump_strength := 0.0
var peak_log: Array = []  # 自动测试：[时间, 总线峰值]
var peak_bus := -1
var rustle_count := 0

var keycaps := {}
var hint_done := {"move": false, "photo": false, "shift": false, "sonar": false, "e": false}
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
	robot.sonar_returned.connect(_on_sonar_returned)
	robot.bumped.connect(_on_robot_bumped)
	papers = built["papers"]
	_setup_field_audio()
	var start: Dictionary = level["robot_start"]
	_place_robot(start["pos"], start["heading"])

	for id in built["doors"]:
		var area: Area3D = built["doors"][id]["area"]
		area.body_entered.connect(_on_door_area_entered.bind(id))
		area.body_exited.connect(_on_door_area_exited.bind(id))
	var end_area: Area3D = built["triggers"]["level_end"]
	end_area.body_entered.connect(_on_end_entered)
	for s in built["skippers"]:
		s.arrived.connect(_on_skipper_arrived.bind(s.camera_id))

	for n in ["1", "2", "3"]:
		(keycaps[n]["panel"] as Control).visible = _camera_with_key(int(n)) != ""
	floor_plan.setup(level["rooms"], _map_cameras(), level["walls"], _map_doors())
	floor_plan.camera_picked.connect(func(id: String) -> void: select_view(id))

	crt.set_shader_parameter("prev_tex", black_tex)
	photo_reveal = 0.0
	select_view(ONBOARD, true)
	_burst_static(1.0)  # 开机雪花，雪花散去后自动传回第一张照片
	get_tree().create_timer(0.9).timeout.connect(_take_photo.bind(true))

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
	_bind("photo", [KEY_SPACE])
	_bind("sonar", [KEY_Q])
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
	elif event.is_action_pressed("photo"):
		_take_photo()
	elif event.is_action_pressed("sonar"):
		_ping_sonar()
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
	_set_monitor_lights(true)
	if onboard:
		# 机载不能实时回传：主屏显示最近一张照片，监控画面停止渲染
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		overlay.set_hud(false)
		_set_crt(0.0, 0.035, PHOTO_RES.y, 1.0)
	else:
		last_monitor = id
		var cam: Dictionary = built["cameras"][id]
		(cam["camera"] as Camera3D).make_current()
		viewport.size = MONITOR_RES
		overlay.set_hud(true)
		_set_crt(1.0, 0.09, MONITOR_RES.y, 1.35)
		for room_id in cam["reveals"]:
			floor_plan.revealed[room_id] = true
		frame_accum = 0.0
		_capture_monitor_frame()
	_refresh_feed_texture()
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


## 红外补光只开正在看的那一路；拍照那一帧全关，照片里只有闪光
func _set_monitor_lights(on: bool) -> void:
	for cid in built["cameras"]:
		(built["cameras"][cid]["light"] as OmniLight3D).visible = on and cid == view


func _refresh_feed_texture() -> void:
	if view == ONBOARD and not finished:
		feed_rect.texture = photo_vps[photo_front].get_texture()
	else:
		feed_rect.texture = viewport.get_texture()


func _camera_with_key(k: int) -> String:
	for cid in built["cameras"]:
		if int(built["cameras"][cid]["key"]) == k:
			return cid
	return ""


func _capture_monitor_frame() -> void:
	var cam: Dictionary = built["cameras"][view]
	for s in built["skippers"]:
		s.on_frame(view)
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
		if frame_accum >= period and not photo_rendering:
			frame_accum = fmod(frame_accum, period)
			_capture_monitor_frame()

	if photo_cooldown > 0.0:
		photo_cooldown = maxf(0.0, photo_cooldown - delta)
		if photo_cooldown == 0.0:
			_play("beep", 1.7, -12.0)  # 闪光充好
	sonar_cooldown = maxf(0.0, sonar_cooldown - delta)
	if has_photo and not photo_rendering:
		photo_reveal = minf(1.0, photo_reveal + delta / PHOTO_SCAN_TIME)
	crt.set_shader_parameter("reveal", photo_reveal if view == ONBOARD and not finished else 1.0)

	if peak_bus >= 0:
		peak_log.append([clock, maxf(AudioServer.get_bus_peak_volume_left_db(peak_bus, 0), AudioServer.get_bus_peak_volume_right_db(peak_bus, 0))])
	_update_blinkers()
	_update_keypad(delta)
	_update_keys(delta)
	# 电机：开得越快越响；顶着东西开时憋着叫（音调升高）
	var motion := robot.motion_level()
	var motor: AudioStreamPlayer3D = players["motor"]
	motor.volume_db = linear_to_db(0.08 + 0.92 * maxf(motion, robot.strain)) - 7.0 + 3.0 * robot.strain
	motor.pitch_scale = 0.85 + 0.35 * motion + 0.3 * robot.strain
	# 贴着墙蹭：越快越响
	var scrape_player: AudioStreamPlayer3D = players["scrape"]
	scrape_player.volume_db = linear_to_db(maxf(robot.scrape, 0.0001)) - 7.0
	scrape_player.pitch_scale = 0.8 + 0.4 * robot.scrape
	_update_ear()


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


# ---------------------------------------------------------------- 拍照与声呐

## 拍一张：闪光只亮这一帧，照片渲染进另一个照片 SubViewport，再约 1 秒逐行传回。
## 拍完之后机器人再怎么动，屏幕上还是这一张。
func _take_photo(force := false) -> void:
	if photo_rendering:
		return
	if photo_cooldown > 0.0 and not force:
		_play("click", 2.4, -16.0)  # 还没充好电
		return
	if not force:
		hint_done["photo"] = true
	photo_cooldown = PHOTO_COOLDOWN
	var prev := photo_front
	photo_front = 1 - photo_front
	crt.set_shader_parameter("prev_tex", photo_vps[prev].get_texture() if has_photo else black_tex)
	has_photo = true
	photo_reveal = 0.0
	photo_cams[photo_front].global_transform = robot.camera_mount.global_transform
	var stamp := photo_stamps[photo_front]
	stamp.text = _timestamp()
	stamp.reset_size()
	stamp.position = Vector2(PHOTO_RES) - stamp.size - Vector2(16.0, 12.0)
	robot.flash.visible = true
	robot.searchlight.visible = false  # 曝光很短，照片里只有闪光
	photo_rendering = true
	_set_monitor_lights(false)
	photo_vps[photo_front].render_target_update_mode = SubViewport.UPDATE_ONCE
	_refresh_feed_texture()
	_play("shutter")
	await RenderingServer.frame_post_draw
	photo_rendering = false
	robot.searchlight.visible = true
	_set_monitor_lights(true)
	# 正看着监控的话，补抓一帧：画面里闪一下，看得出机器人在哪（哪怕它本身被挡住）
	if view != ONBOARD and not finished:
		_capture_monitor_frame()
		await RenderingServer.frame_post_draw
	robot.flash.visible = false
	_play("transmit")
	_play("charge")


func _ping_sonar() -> void:
	if sonar_cooldown > 0.0:
		_play("click", 2.4, -16.0)
		return
	hint_done["sonar"] = true
	sonar_cooldown = SONAR_COOLDOWN
	robot.ping_sonar()
	_play("ping")


## 回声点交给扇形屏；正前方最近的回声再响一声，越晚越远，前方没东西就没有回声
func _on_sonar_returned(echoes: PackedVector3Array) -> void:
	sonar.ping(echoes)
	var nearest := INF
	for e: Vector3 in echoes:
		if absf(e.x) < deg_to_rad(12.0):
			nearest = minf(nearest, e.y)
	if nearest == INF:
		return
	await get_tree().create_timer(nearest / SonarScope.RING_SPEED).timeout
	_play("echo", 1.0, -12.0 * nearest / RobotScript.SONAR_RANGE)


## 机器人不在任何一路监控负责的房间里
func _in_blind_spot() -> bool:
	for cid in built["cameras"]:
		if _robot_in_rooms(built["cameras"][cid]["reveals"]):
			return false
	return true


# ---------------------------------------------------------------- 3D 声音

## 关卡搭好之后：听者、机器人身上的声音、关卡声源、门
func _setup_field_audio() -> void:
	viewport.audio_listener_enable_3d = true
	ear = AudioListener3D.new()
	world.add_child(ear)
	ear.make_current()
	# 机器人身上的声音走 Robot 总线：隔着墙时整条总线变闷
	_add_player_3d("motor", sfx["motor"], robot, Vector3(0.0, 0.3, 0.0), "Robot", 2.0, -40.0)
	for n in ["shutter", "charge", "ping", "thud_concrete", "thud_crate", "thud_metal", "rustle"]:
		_add_player_3d(n, sfx[n], robot, Vector3(0.0, 0.3, 0.0), "Robot", 2.0, SOUND_DB[n])
	_add_player_3d("scrape", sfx["scrape"], robot, Vector3(0.0, 0.3, 0.0), "Robot", 2.0, -80.0)
	for n in ["motor", "scrape", "shutter", "charge", "ping", "thud_concrete", "thud_crate", "thud_metal", "rustle"]:
		(players[n] as AudioStreamPlayer3D).max_db = 24.0  # 不封顶，音量差靠 volume_db 和 Robot 总线
	(players["motor"] as AudioStreamPlayer3D).play()
	(players["scrape"] as AudioStreamPlayer3D).play()
	for d in level["doors"]:
		var dp: Vector2 = d["pos"]
		_add_player_3d("door_" + str(d["id"]), sfx["door"], world, Vector3(dp.x, 1.3, dp.y), "Field", 2.5, 0.0)
	for snd in built["sounds"]:
		var kind: String = snd["type"]
		var base: float = SOUND_DB[kind]
		var player := _add_player_3d("", sfx[kind], world, snd["pos"], "Field", SOUND_UNIT[kind], base)
		player.max_distance = 16.0
		player.play()
		field_sources.append({"player": player, "base_db": base, "follows": snd.get("follows"), "occ": 0.0})


func _add_player_3d(player_name: String, stream: AudioStream, parent: Node3D, pos: Vector3, bus: String, unit: float, volume: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = bus
	p.unit_size = unit
	p.max_db = 3.0
	p.volume_db = volume
	p.attenuation_filter_cutoff_hz = 6000.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	parent.add_child(p)
	p.position = pos
	if player_name != "":
		players[player_name] = p
	return p


## 听者跟着画面：看照片时在机器人的相机上，看监控时在那路摄像头上
func _update_ear() -> void:
	if view == ONBOARD or finished:
		ear.global_transform = robot.camera_mount.global_transform
	else:
		ear.global_transform = (built["cameras"][view]["camera"] as Camera3D).global_transform


## 每个声源和听者之间有墙或货箱挡着，就变小、变闷；台灯灭了，电流声也停
func _physics_process(delta: float) -> void:
	if ear == null:
		return
	var space := world.get_world_3d().direct_space_state
	var ear_pos := ear.global_position
	robot_occ = move_toward(robot_occ, 1.0 if _blocked(space, ear_pos, robot.global_position + Vector3(0.0, 0.4, 0.0)) else 0.0, delta * 3.0)
	var rb := AudioServer.get_bus_index("Robot")
	var close_db := ROBOT_CLOSE_DB if view == ONBOARD or finished else 0.0
	AudioServer.set_bus_volume_db(rb, close_db - 12.0 * robot_occ)
	(AudioServer.get_bus_effect(rb, 0) as AudioEffectLowPassFilter).cutoff_hz = lerpf(20000.0, 700.0, robot_occ)
	for src in field_sources:
		var p: AudioStreamPlayer3D = src["player"]
		var occ := move_toward(float(src["occ"]), 1.0 if _blocked(space, ear_pos, p.global_position) else 0.0, delta * 3.0)
		src["occ"] = occ
		var db: float = float(src["base_db"]) - 12.0 * occ
		var follows: Node3D = src["follows"]
		if follows != null and not follows.is_visible_in_tree():
			db = -80.0
		p.volume_db = db
		p.attenuation_filter_cutoff_hz = lerpf(6000.0, 650.0, occ)
	_check_papers()


func _blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var dist := from.distance_to(to)
	if dist < 0.8:
		return false
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	if hit.is_empty():
		return false
	var at: Vector3 = hit["position"]
	return from.distance_to(at) < dist - 0.6  # 打到声源自己所在的物体不算


## 履带压过纸：沙沙一声。照片里看不出自己压在纸上，听得出
func _check_papers() -> void:
	var rp := Vector2(robot.global_position.x, robot.global_position.z)
	for i in papers.size():
		var paper_pos: Vector2 = papers[i]
		var under := rp.distance_to(paper_pos) < 0.4
		if under and not paper_under.has(i) and absf(robot.speed) > 0.08:
			_play("rustle", randf_range(0.9, 1.15))
			rustle_count += 1
		if under:
			paper_under[i] = true
		else:
			paper_under.erase(i)


## 撞到东西：机器人那里一声按材质的撞击（3D，看监控时从摄像头的位置听），
## 操作台上的碰撞传感器再短短响一下（不管看哪路画面都听得到）
func _on_robot_bumped(surface: String, strength: float) -> void:
	last_bump = surface
	bump_time = clock
	last_bump_strength = strength
	var key := "thud_" + surface
	if not players.has(key):
		key = "thud_concrete"
	_play(key, randf_range(0.92, 1.08), linear_to_db(0.35 + 0.65 * strength))
	_play("bump_alarm", 1.0, linear_to_db(0.5 + 0.5 * strength))


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
	floor_plan.open_doors[id] = true
	floor_plan.queue_redraw()
	_play("door_" + id)
	var slab: CSGBox3D = door["node"]
	var target: Vector3 = slab.position + (door["slide"] as Vector3)
	(door["lamp_mat"] as StandardMaterial3D).emission = Color(0.3, 1.0, 0.4)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void: slab.use_collision = false)
	tw.tween_property(slab, "position", target, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 帧间者走完路线：正看着那路画面的话，一阵雪花 + 一声闷响，然后它就不在了
func _on_skipper_arrived(_id: String, cam_id: String) -> void:
	if view == cam_id:
		_burst_static(1.1)
		_play("click", 0.45, -2.0)


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
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Field"), true)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_refresh_feed_texture()
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
	viewport.size = MONITOR_RES
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	overlay = FeedOverlay.new()
	viewport.add_child(overlay)
	_build_photo_viewports()
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
	_panel(Rect2(904, 24, 352, 166), Color(0.02, 0.02, 0.02), Color(0.17, 0.17, 0.16), 8, 12)
	floor_plan = FloorPlan.new()
	floor_plan.position = Vector2(916, 36)
	floor_plan.size = Vector2(328, 142)
	add_child(floor_plan)

	# 声呐扇形屏：一直显示，看监控时也在
	_panel(Rect2(904, 202, 352, 200), Color(0.02, 0.02, 0.02), Color(0.17, 0.17, 0.16), 8, 12)
	sonar = SonarScope.new()
	sonar.position = Vector2(916, 214)
	sonar.size = Vector2(328, 176)
	sonar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sonar)

	# 密码面板显示屏
	_panel(Rect2(904, 414, 352, 60), Color(0.02, 0.055, 0.035), Color(0.17, 0.17, 0.16), 8, 12)
	keypad_label = Label.new()
	keypad_label.position = Vector2(916, 420)
	keypad_label.size = Vector2(328, 48)
	keypad_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keypad_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	keypad_label.add_theme_font_size_override("font_size", 32)
	keypad_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(keypad_label)

	_build_keys(Vector2(946, 486))


## 两个照片 SubViewport 共用监控画面的世界，各带一台相机和一个拍摄时间戳
func _build_photo_viewports() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	black_tex = ImageTexture.create_from_image(img)
	for i in 2:
		var vp := SubViewport.new()
		vp.size = PHOTO_RES
		vp.world_3d = viewport.find_world_3d()
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var cam := RobotScript.build_photo_camera()
		vp.add_child(cam)
		cam.current = true
		var stamp := Label.new()
		stamp.add_theme_font_size_override("font_size", 15)
		stamp.add_theme_color_override("font_color", Color(1.0, 0.62, 0.22))
		vp.add_child(stamp)
		photo_vps.append(vp)
		photo_cams.append(cam)
		photo_stamps.append(stamp)


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
		keycaps[k[0]] = {"panel": p, "label": l, "style": sb, "action": k[4], "glow": 0.0}
		# 有冷却的键：底部一道细条随充能长满，满了就消失
		if k[4] == "photo" or k[4] == "sonar":
			var bar := ColorRect.new()
			bar.color = Color(AMBER, 0.8)
			bar.position = Vector2(8.0, (k[3] as Vector2).y - 12.0)
			bar.size = Vector2(0.0, 3.0)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.visible = false
			p.add_child(bar)
			keycaps[k[0]]["bar"] = bar
	(keycaps["R"]["panel"] as Control).visible = false


func _update_keys(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	var pulsing := _pulsing_keys()
	for id in keycaps:
		var k: Dictionary = keycaps[id]
		var action: String = k["action"]
		var lit := 1.0 if Input.is_action_pressed(action) else 0.0
		if pulsing.has(id):
			lit = maxf(lit, pulse)
		if action.begins_with("cam_") and view == _camera_with_key(int(action.substr(4))):
			lit = maxf(lit, 0.55)
		if k.has("bar"):
			var left := photo_cooldown / PHOTO_COOLDOWN if action == "photo" else sonar_cooldown / SONAR_COOLDOWN
			var bar: ColorRect = k["bar"]
			if bar.visible and left <= 0.0:
				k["glow"] = 1.0  # 充好的一瞬间亮一下
			bar.visible = left > 0.0
			bar.size.x = ((k["panel"] as Control).size.x - 16.0) * (1.0 - left)
			if left > 0.0:
				lit *= 0.3
		k["glow"] = maxf(0.0, float(k["glow"]) - delta * 2.5)
		lit = maxf(lit, float(k["glow"]) * 0.7)
		(k["style"] as StyleBoxFlat).bg_color = KEY_BG.lerp(KEY_LIT, lit)
		(k["label"] as Label).add_theme_color_override("font_color", KEY_TEXT.lerp(KEY_TEXT_LIT, lit))


## 按键提示只以按键图标闪烁出现一次，做过就不再提示
func _pulsing_keys() -> Dictionary:
	var p := {}
	if finished:
		p["R"] = true
		return p
	if not hint_done["move"] and clock > 1.6:
		for k in ["W", "A", "S", "D"]:
			p[k] = true
	# 开动之后屏幕上还是开机那张照片：先教拍照，再教切监控
	if hint_done["move"] and not hint_done["photo"] and not hint_done["shift"]:
		p["SPACE"] = true
	if not hint_done["shift"] and (hint_done["photo"] or clock > 16.0):
		p["SHIFT"] = true
	if not hint_done["sonar"] and hint_done["shift"] and _in_blind_spot():
		p["Q"] = true
	if near_door != "" and not hint_done["e"] and not built["doors"][near_door]["open"]:
		p["E"] = true
	return p


## 门在平面图上是一条线段；门板沿 z 方向（和 level_builder 一致）
func _map_doors() -> Array:
	var arr := []
	for d in level["doors"]:
		var pos: Vector2 = d["pos"]
		var half: float = float(d["width"]) * 0.5
		arr.append({"id": d["id"], "a": Vector2(pos.x, pos.y - half), "b": Vector2(pos.x, pos.y + half)})
	return arr


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

## 总线：Field = 关卡里的 3D 声音（摄像头的麦克风很差：看监控时变窄变闷）；
## Robot = 机器人身上的声音，送进 Field（隔着墙时整条变闷）；World = 设施的底噪；
## 操作台自己的声音（继电器、雪花、按键、传回、回声）直接走 Master。
func _setup_audio() -> void:
	_ensure_bus("Field", "Master", true)
	_ensure_bus("Robot", "Field", false)
	_ensure_bus("World", "Master", false)
	for b in ["Field", "Robot", "World"]:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(b), false)  # 重开一局时复位
	sfx = Sfx.build_all()
	_add_player("ambient", sfx["ambient"], "World", -14.0)
	_add_player("static", sfx["static"], "Master", -80.0)
	_add_player("click", sfx["click"], "Master", -4.0)
	_add_player("beep", sfx["beep"], "Master", -10.0)
	_add_player("buzz", sfx["buzz"], "Master", -8.0)
	_add_player("door", sfx["door"], "World", -2.0)
	_add_player("transmit", sfx["transmit"], "Master", -22.0)
	_add_player("echo", sfx["echo"], "Master", -12.0)
	_add_player("bump_alarm", sfx["bump_alarm"], "Master", -14.0)
	for loop_name in ["ambient", "static"]:
		(players[loop_name] as AudioStreamPlayer).play()


func _ensure_bus(bus_name: String, send: String, highpass: bool) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(idx, lp)
	if highpass:
		var hp := AudioEffectHighPassFilter.new()
		hp.cutoff_hz = 10.0
		AudioServer.add_bus_effect(idx, hp)


func _add_player(player_name: String, stream: AudioStream, bus: String, volume: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = volume
	add_child(p)
	players[player_name] = p


func _play(player_name: String, pitch := 1.0, volume_offset := 0.0) -> void:
	var p = players[player_name]  # AudioStreamPlayer 或 AudioStreamPlayer3D
	if not p.has_meta("base_db"):
		p.set_meta("base_db", p.volume_db)
	p.pitch_scale = pitch
	p.volume_db = float(p.get_meta("base_db")) + volume_offset
	p.play()


## 机载：机器人的麦克风，声音完整、贴耳；监控：摄像头的麦克风，又窄又闷，设施底噪成为主体。
## 远近和左右由 3D 声音自己算（听者跟着画面走，见 _update_ear）。
func _apply_audio_view(onboard: bool) -> void:
	var f := AudioServer.get_bus_index("Field")
	var w := AudioServer.get_bus_index("World")
	(AudioServer.get_bus_effect(f, 0) as AudioEffectLowPassFilter).cutoff_hz = 20000.0 if onboard else 3200.0
	(AudioServer.get_bus_effect(f, 1) as AudioEffectHighPassFilter).cutoff_hz = 10.0 if onboard else 260.0
	AudioServer.set_bus_volume_db(f, 0.0 if onboard else -2.0)
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
	await _shot(dir + "/01a_boot_photo_scanin.png")
	await _wait(0.8)
	await _shot(dir + "/01_onboard_start.png")

	var z0 := robot.global_position.z
	_start_peak_log("Robot")
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	_report_bump("机载（照片）时，Robot 总线")
	print("AUTOTEST 正对货箱前进 1.5 秒，z 变化 = %.3f（应约 -0.82：顶到货箱停下）" % (robot.global_position.z - z0))
	Input.action_press("turn_right")
	await _wait(2.0)
	Input.action_release("turn_right")
	await _wait(0.4)
	print("AUTOTEST 右转约 2.4 秒后 heading = %.1f°（应接近 90）" % -rad_to_deg(robot.rotation.y))
	print("AUTOTEST 撞上货箱的声音材质：%s（应为 crate）" % last_bump)
	await _shot(dir + "/01b_onboard_stale_photo.png")
	await _sonar_now()
	await _shot(dir + "/01c_sonar_loading.png")
	photo_cooldown = 0.0
	_take_photo()
	await _wait(0.45)
	await _shot(dir + "/01d_photo_scanin.png")
	await _wait(0.9)
	await _shot(dir + "/01e_photo_new.png")
	_take_photo()
	print("AUTOTEST 冷却中再按空格：cooldown = %.1f（应 > 3）" % photo_cooldown)

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
	await _photo_now()
	await _shot(dir + "/05_photo_code_paper.png")
	_place_robot(Vector3(15.1, 0.0, 6.7), 0.0)
	await _photo_now()
	await _shot(dir + "/06_photo_decoys.png")
	select_view("CAM-2")
	await _wait(1.2)
	await _shot(dir + "/07_cam2_robot.png")

	_place_robot(Vector3(20.6, 0.0, 4.2), 90.0)
	select_view(ONBOARD)
	await _photo_now()
	await _shot(dir + "/08_photo_trail.png")
	_place_robot(Vector3(22.35, 0.0, 4.6), 0.0)
	await _photo_now()
	await _sonar_now()
	await _shot(dir + "/09_photo_sonar_under_console.png")
	select_view("CAM-3")
	await _wait(1.2)
	await _shot(dir + "/09b_cam3_trail_hidden.png")
	# 探照灯照在拖痕上，单色监控里也不该看出来
	_place_robot(Vector3(22.35, 0.0, 3.6), 180.0)
	await _wait(1.2)
	await _shot(dir + "/09e_cam3_beam_on_trail.png")
	select_view(ONBOARD)

	_place_robot(Vector3(9.6, 0.0, 0.8), 90.0)
	await _photo_now()
	await _sonar_now()
	await _shot(dir + "/09d_corridor_photo_sonar.png")
	print("AUTOTEST 走廊里 _in_blind_spot = %s（应为 true）" % _in_blind_spot())
	_place_robot(Vector3(15.2, 0.0, 0.8), 90.0)
	await _photo_now()
	await _sonar_now()
	await _shot(dir + "/09c_door17_photo_sonar.png")
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

	# 帧间者预兆：只在被看时移动，切走就停；照片里没有，声呐也没有回声
	var omen: Node3D = built["skippers"][0]
	select_view("CAM-1")
	await _wait(5.0)
	await _shot(dir + "/13_cam1_omen.png")
	var i1: int = omen.index
	var target: Vector3 = omen.position
	var back: Vector3 = omen.points[maxi(i1 - 2, 0)]
	_place_robot(back, rad_to_deg(atan2(target.x - back.x, -(target.z - back.z))))
	select_view(ONBOARD)
	await _photo_now()
	await _sonar_now()
	await _shot(dir + "/14_photo_sonar_omen_invisible.png")
	await _wait(1.0)
	print("AUTOTEST 切走约 3 秒，人影步数 %d → %d（应不变）" % [i1, omen.index])
	select_view("CAM-1")
	await _wait(4.0)
	await _shot(dir + "/15_cam1_omen_closer.png")
	await _wait(14.0)
	print("AUTOTEST 人影走到摄像头下消失：%s（共 %d 步）" % [omen.done, omen.points.size()])

	# 光：探照灯在监控里投出朝前的光斑，光斑跟着机器人转；在没有监控的走廊里对着门洞，光照进有监控的房间
	select_view("CAM-1")
	_place_robot(Vector3(3.75, 0.0, 3.75), 90.0)
	await _wait(1.0)
	await _shot(dir + "/16_cam1_beam_east.png")
	_place_robot(Vector3(3.75, 0.0, 3.75), 180.0)
	await _wait(1.0)
	await _shot(dir + "/16b_cam1_beam_south.png")
	_place_robot(Vector3(22.0, 0.0, 5.0), 0.0)
	await _wait(1.0)
	await _shot(dir + "/17a_cam1_exit_no_robot.png")
	_place_robot(Vector3(9.8, 0.0, 0.8), 270.0)
	await _wait(1.0)
	await _shot(dir + "/17_cam1_beam_into_exit.png")
	_place_robot(Vector3(22.0, 0.0, 5.0), 0.0)
	select_view("CAM-2")
	await _wait(1.0)
	await _shot(dir + "/18a_cam2_door_no_robot.png")
	_place_robot(Vector3(12.2, 0.0, 0.8), 180.0)
	await _wait(1.0)
	await _shot(dir + "/18_cam2_beam_into_door.png")
	_place_robot(Vector3(12.2, 0.0, 0.8), 90.0)
	await _wait(1.0)
	await _shot(dir + "/18b_cam2_beam_along_corridor.png")
	print("AUTOTEST 看 CAM-2 时听者在摄像头上：%s" % ear.global_position.is_equal_approx((built["cameras"]["CAM-2"]["camera"] as Camera3D).global_position))
	print("AUTOTEST 机器人在墙后的走廊里，CAM-2 听它的遮挡 = %.2f（应接近 1）" % robot_occ)
	_place_robot(Vector3(13.6, 0.0, 5.0), 0.0)
	await _wait(1.0)
	print("AUTOTEST 机器人在警卫室里，CAM-2 听它的遮挡 = %.2f（应接近 0）" % robot_occ)

	# 闪光：看着监控拍照，监控里也闪一下
	_place_robot(Vector3(3.75, 0.0, 6.0), 0.0)
	select_view("CAM-1")
	await _wait(1.0)
	photo_cooldown = 0.0
	_take_photo()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await _shot(dir + "/19_cam1_flash.png")

	# 撞击：看着监控时，从摄像头的位置也听得到；擦着墙走是轻撞 + 蹭墙声
	_place_robot(Vector3(2.25, 0.0, 7.2), 0.0)
	await _wait(0.5)
	_start_peak_log("Field")
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	_report_bump("看 CAM-1 时，Field 总线")
	select_view(ONBOARD)
	_place_robot(Vector3(10.5, 0.0, 0.8), 75.0)
	await _wait(0.3)
	var max_scrape := 0.0
	bump_time = -100.0
	Input.action_press("move_forward")
	for i in 150:
		await get_tree().process_frame
		max_scrape = maxf(max_scrape, robot.scrape)
	Input.action_release("move_forward")
	print("AUTOTEST 斜着擦北墙开：撞击力度 %.2f（应 < 0.4，擦边轻），蹭墙声最高 %.2f（应 > 0.5）" % [last_bump_strength if bump_time > 0.0 else -1.0, max_scrape])

	# 声音：压过纸会沙沙响；机载时听者回到机器人身上
	select_view(ONBOARD)
	_place_robot(Vector3(12.8, 0.0, 3.5), 90.0)
	await _wait(0.3)
	rustle_count = 0
	Input.action_press("move_forward")
	await _wait(1.2)
	var field_peak := AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index("Field"), 0)
	await _wait(1.3)
	Input.action_release("move_forward")
	print("AUTOTEST 开过散落的纸，沙沙响 %d 次（应 ≥ 2）；Field 总线峰值 %.1f dB（应 > -60）" % [rustle_count, field_peak])
	print("AUTOTEST 机载时听者在机器人身上：%s" % (ear.global_position.distance_to(robot.global_position) < 0.8))

	await _topdown(dir + "/00_topdown.png")

	select_view(ONBOARD, true)
	_place_robot(Vector3(25.9, 0.0, 6.7), 90.0)
	await _wait(2.4)
	await _shot(dir + "/12_end.png")
	print("AUTOTEST 完成")
	get_tree().quit()


func _start_peak_log(bus: String) -> void:
	peak_log.clear()
	peak_bus = AudioServer.get_bus_index(bus)
	bump_time = -100.0


## 撞击那一下（之后 0.3 秒）比撞之前 0.6 秒里电机声的峰值高多少
func _report_bump(label: String) -> void:
	peak_bus = -1
	if bump_time < 0.0:
		print("AUTOTEST %s：没有检测到撞击" % label)
		return
	var before := -200.0
	var after := -200.0
	for e in peak_log:
		var t: float = e[0]
		var db: float = e[1]
		if t >= bump_time - 0.6 and t < bump_time - 0.05:
			before = maxf(before, db)
		elif t >= bump_time and t < bump_time + 0.3:
			after = maxf(after, db)
	print("AUTOTEST %s：撞前 %.1f dB → 撞击 %.1f dB（高出 %.1f dB，应 ≥ 6）力度 %.2f" % [label, before, after, after - before, last_bump_strength])


## 跳过冷却拍一张，等它传完
func _photo_now() -> void:
	await _wait(0.1)
	photo_cooldown = 0.0
	_take_photo()
	await _wait(PHOTO_SCAN_TIME + 0.25)


## 跳过冷却发一次 ping，等回声扫到最远
func _sonar_now() -> void:
	sonar_cooldown = 0.0
	_ping_sonar()
	await _wait(0.95)
	print("AUTOTEST 声呐回声点 %d 个" % sonar.echoes.size())


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
	cam.cull_mask = 0xFFFFF & ~LevelBuilder.CEILING_LAYER
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
	viewport.size = MONITOR_RES
