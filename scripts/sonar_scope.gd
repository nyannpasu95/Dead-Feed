extends Control
## 操作台上的前向声呐屏：机器人在底边中央，前方永远朝上，只扫前方 120°。
## 一次 ping：一道弧从机器人向外扩散，扫到哪里，那里的回声点就亮起，然后慢慢淡掉。
## 回声是 ping 那一刻的快照：之后机器人再动，屏上的点不跟着变。

const INK := Color(0.45, 1.0, 0.62)
const BG := Color(0.02, 0.055, 0.035)
const RANGE := 7.0
const HALF_ARC := PI / 3.0
const RING_SPEED := 8.0   # 屏上扩散速度（米/秒），回声越远亮得越晚
const ECHO_LIFE := 3.2    # 回声淡出时间，略短于冷却
const MARGIN := 10.0
const LINK_ANGLE := 0.03   # 弧度：只连相邻射线（中间没有丢失的回声）
const LINK_PIXELS := 12.0

var echoes := PackedVector3Array()  # 角度（右为正）、距离、强度
var _age := 100.0


func ping(new_echoes: PackedVector3Array) -> void:
	echoes = new_echoes
	_age = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _age < RANGE / RING_SPEED + ECHO_LIFE + 0.5:
		_age += delta
		queue_redraw()


func _apex() -> Vector2:
	return Vector2(size.x * 0.5, size.y - MARGIN)


func _radius() -> float:
	return minf((size.x - MARGIN * 2.0) / (2.0 * sin(HALF_ARC)), size.y - MARGIN * 2.0)


## 角度 a（右为正）、距离 d → 屏幕坐标
func _to_screen(a: float, d: float) -> Vector2:
	return _apex() + Vector2(sin(a), -cos(a)) * d * (_radius() / RANGE)


## 回声还没扫到或已经淡完返回 0
func _echo_alpha(e: Vector3) -> float:
	var since := _age - e.y / RING_SPEED
	if since < 0.0:
		return 0.0
	var life := 1.0 - clampf(since / ECHO_LIFE, 0.0, 1.0)
	var fresh := clampf(1.0 - since / 0.25, 0.0, 1.0)
	return e.z * (life * life * 0.85 + fresh * 0.15) if life > 0.0 else 0.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var apex := _apex()
	var r := _radius()
	var from := -PI * 0.5 - HALF_ARC
	var to := -PI * 0.5 + HALF_ARC

	# 扇形刻度：三道距离环、两条边、一条中线
	for k: float in [1.0, 2.0]:
		draw_arc(apex, r * k / 3.0, from, to, 40, Color(INK, 0.09), 1.0)
	draw_arc(apex, r, from, to, 64, Color(INK, 0.22), 1.0)
	draw_line(apex, _to_screen(-HALF_ARC, RANGE), Color(INK, 0.22), 1.0)
	draw_line(apex, _to_screen(HALF_ARC, RANGE), Color(INK, 0.22), 1.0)
	draw_line(apex, _to_screen(0.0, RANGE), Color(INK, 0.06), 1.0)

	# 扩散的 ping
	var front := _age * RING_SPEED
	if front <= RANGE:
		var fade := 1.0 - front / RANGE
		draw_arc(apex, front * r / RANGE, from, to, 48, Color(INK, 0.15 + 0.55 * fade), 2.0)

	# 回声：刚亮起时最亮、略大，之后淡出。相邻射线的回声靠得近就连一道淡线，墙读起来是轮廓
	var prev := Vector3(-10.0, 0.0, 0.0)
	var prev_alpha := 0.0
	for e: Vector3 in echoes:
		var alpha := _echo_alpha(e)
		if alpha > 0.0 and prev_alpha > 0.0 and e.x - prev.x < LINK_ANGLE:
			var a := _to_screen(prev.x, prev.y)
			var b := _to_screen(e.x, e.y)
			if a.distance_to(b) < LINK_PIXELS:
				draw_line(a, b, Color(INK, minf(alpha, prev_alpha) * 0.55), 1.0)
		prev = e
		prev_alpha = alpha
	for e: Vector3 in echoes:
		var alpha := _echo_alpha(e)
		if alpha <= 0.0:
			continue
		var fresh := clampf(1.0 - (_age - e.y / RING_SPEED) / 0.25, 0.0, 1.0)
		var half := 1.4 + fresh * 1.0
		var p := _to_screen(e.x, e.y)
		draw_rect(Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0), Color(INK.lerp(Color.WHITE, fresh * 0.5), alpha))

	# 机器人：底边中央的小三角，尖朝前
	var tri := PackedVector2Array([apex + Vector2(0.0, -7.0), apex + Vector2(-5.0, 3.0), apex + Vector2(5.0, 3.0)])
	draw_colored_polygon(tri, Color(INK, 0.8))

	# 扫描线
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.0, 0.0, 0.0, 0.22), 1.0)
		y += 3.0
