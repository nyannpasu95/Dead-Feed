extends RefCounted
## 启动时程序化合成的占位音效：不依赖外部素材，Web 上同样能用。
## 之后有了正式素材，直接替换 build_all() 返回的条目即可。

const RATE := 22050


static func build_all() -> Dictionary:
	return {
		"click": relay_click(),
		"static": static_loop(),
		"motor": motor_loop(),
		"ambient": ambient_loop(),
		"beep": beep(),
		"buzz": buzz(),
		"door": door(),
		"shutter": shutter(),
		"charge": flash_charge(),
		"transmit": transmit(),
		"ping": sonar_ping(),
		"echo": sonar_echo(),
		"vent": vent_loop(),
		"lamp_hum": buzz_loop(),
		"console": console_loop(),
		"elevator": elevator_loop(),
		# 墙：钝、碎；货箱：空、木头的敲击声；金属：叮
		"thud_concrete": impact([[190.0, 0.45, 30.0], [330.0, 0.35, 45.0], [610.0, 0.15, 60.0]], 1.4, 0.55, 21),
		"thud_crate": impact([[240.0, 0.5, 26.0], [520.0, 0.4, 34.0], [890.0, 0.22, 48.0]], 0.7, 0.3, 23),
		"thud_metal": clang(),
		"scrape": scrape_loop(),
		"bump_alarm": bump_alarm(),
		"rustle": rustle(),
	}


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func _buffer(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(RATE * seconds))
	return s


## 继电器切换：两下金属咔哒 + 一点低频
static func relay_click() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var s := _buffer(0.12)
	for i in s.size():
		var t := float(i) / RATE
		var v := sin(TAU * 140.0 * t) * exp(-t * 45.0) * 0.35
		for hit in [[0.0, 1.0], [0.032, 0.6]]:
			var dt: float = t - float(hit[0])
			if dt >= 0.0:
				var e := exp(-dt * 700.0)
				v += float(hit[1]) * (rng.randf_range(-1.0, 1.0) * 0.8 + sin(TAU * 2400.0 * dt) * 0.35) * e
		s[i] = v * 0.8
	return _wav(s)


static func static_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var s := _buffer(1.0)
	var lp := 0.0
	for i in s.size():
		lp += 0.55 * (rng.randf_range(-1.0, 1.0) - lp)
		var crackle := rng.randf_range(-1.0, 1.0) if rng.randf() < 0.002 else 0.0
		s[i] = lp * 0.5 + crackle * 0.6
	return _wav(s, true)


## 电机嗡声 + 履带节拍（每秒 12 下），2 秒无缝循环
static func motor_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var s := _buffer(2.0)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var hum := sin(TAU * 60.0 * t) * 0.28 + sin(TAU * 120.0 * t) * 0.14 + sin(TAU * 180.0 * t) * 0.06
		var whine := sin(TAU * 920.0 * t) * 0.025
		var tick := exp(-fmod(t * 12.0, 1.0) * 30.0) * 0.5
		lp += 0.25 * (rng.randf_range(-1.0, 1.0) - lp)
		s[i] = (hum + whine) * 0.8 + lp * tick * 1.2
	return _wav(s, true)


## 设施环境：很低的嗡鸣和闷闷的隆隆声，4 秒无缝循环
static func ambient_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var s := _buffer(4.0)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var drone := sin(TAU * 41.0 * t) * (0.7 + 0.3 * sin(TAU * 0.25 * t)) * 0.3
		drone += sin(TAU * 55.5 * t) * 0.1 + sin(TAU * 82.0 * t) * 0.05
		lp += 0.02 * (rng.randf_range(-1.0, 1.0) - lp)
		s[i] = drone + lp * 1.6
	return _wav(s, true)


static func beep() -> AudioStreamWAV:
	var s := _buffer(0.07)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * 1250.0 * t) * 0.5 * minf(1.0, t / 0.004) * exp(-t * 30.0)
	return _wav(s)


static func buzz() -> AudioStreamWAV:
	var s := _buffer(0.38)
	for i in s.size():
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.01) * clampf((0.38 - t) / 0.05, 0.0, 1.0)
		s[i] = (1.0 if sin(TAU * 150.0 * t) > 0.0 else -1.0) * 0.28 * env
	return _wav(s)


## 重型滑门：电机 + 摩擦，最后一下到位的闷响
static func door() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var s := _buffer(2.4)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var env := clampf(t / 0.25, 0.0, 1.0) * clampf((2.05 - t) / 0.3, 0.0, 1.0)
		lp += 0.05 * (rng.randf_range(-1.0, 1.0) - lp)
		lp2 += 0.05 * (lp - lp2)
		phase += TAU * (48.0 + 4.0 * sin(TAU * 3.0 * t)) / RATE
		var v := lp2 * 4.0 * env + sin(phase) * 0.18 * env
		if t > 2.05:
			var dt := t - 2.05
			v += (sin(TAU * 85.0 * dt) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.3) * exp(-dt * 18.0)
		s[i] = v
	return _wav(s)


## 快门：两下机械咔哒 + 闪光放电时一声往下滑的细响
static func shutter() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var s := _buffer(0.3)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for hit in [[0.0, 0.9], [0.055, 0.65]]:
			var dt: float = t - float(hit[0])
			if dt >= 0.0:
				v += float(hit[1]) * rng.randf_range(-1.0, 1.0) * exp(-dt * 900.0)
				v += float(hit[1]) * sin(TAU * 3200.0 * dt) * exp(-dt * 400.0) * 0.4
		phase += TAU * (1200.0 + 3800.0 * exp(-t * 25.0)) / RATE
		v += sin(phase) * 0.12 * exp(-t * 14.0)
		s[i] = v * 0.8
	return _wav(s)


## 闪光充电：细细的、越来越高的啸叫，充满时停
static func flash_charge() -> AudioStreamWAV:
	var length := 4.4
	var s := _buffer(length)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / length
		phase += TAU * (1800.0 + 5200.0 * (1.0 - pow(1.0 - k, 2.0))) / RATE
		var env := minf(1.0, t / 0.3) * clampf((length - t) / 0.4, 0.0, 1.0) * (0.6 + 0.4 * k)
		s[i] = sin(phase) * 0.06 * env
	return _wav(s)


## 照片传回：每行开头一个同步音，后面是快速跳变的数据音（约 1 秒）
static func transmit() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var length := 1.0
	var s := _buffer(length)
	var phase := 0.0
	var f := 1500.0
	var next_switch := 0.0
	for i in s.size():
		var t := float(i) / RATE
		if fmod(t, 1.0 / 30.0) < 0.005:
			f = 1200.0
		elif t >= next_switch:
			f = rng.randf_range(1500.0, 2300.0)
			next_switch = t + rng.randf_range(0.006, 0.018)
		phase += TAU * f / RATE
		var env := minf(1.0, t / 0.02) * clampf((length - t) / 0.03, 0.0, 1.0)
		s[i] = sin(phase) * 0.2 * env
	return _wav(s)


## 声呐 ping：清脆的一声，尾音略往下沉
static func sonar_ping() -> AudioStreamWAV:
	var s := _buffer(0.9)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		phase += TAU * (1150.0 - 60.0 * t) / RATE
		var env := minf(1.0, t / 0.004) * exp(-t * 7.0)
		s[i] = (sin(phase) * 0.45 + sin(phase * 2.0) * 0.06) * env
	return _wav(s)


## 回声：更软、更短，有一点颤
static func sonar_echo() -> AudioStreamWAV:
	var s := _buffer(0.5)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		phase += TAU * 1080.0 / RATE
		var env := minf(1.0, t / 0.02) * exp(-t * 11.0)
		s[i] = sin(phase) * 0.3 * env * (0.85 + 0.15 * sin(TAU * 31.0 * t))
	return _wav(s)



# ---------------------------------------------------------------- 声音地标（循环，挂在关卡里的 3D 声源上）

## 通风口：低沉的风声，叶片每秒转 7 下带出一点起伏
static func vent_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var length := 2.0
	var s := _buffer(length)
	var lp := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += 0.08 * (rng.randf_range(-1.0, 1.0) - lp)
		lp2 += 0.08 * (lp - lp2)
		var blade := 0.75 + 0.25 * sin(TAU * 7.0 * t)
		s[i] = lp2 * 3.2 * blade + sin(TAU * 98.0 * t) * 0.05
	return _wav(s, true)


## 台灯电流声：100 Hz 的嗡和高次谐波，偶尔噼啪一下
static func buzz_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var s := _buffer(1.0)
	for i in s.size():
		var t := float(i) / RATE
		var saw := fmod(t * 100.0, 1.0) * 2.0 - 1.0
		var v := saw * 0.16 + sin(TAU * 200.0 * t) * 0.08 + sin(TAU * 300.0 * t) * 0.04
		if rng.randf() < 0.0015:
			v += rng.randf_range(-0.6, 0.6)
		s[i] = v
	return _wav(s, true)


## 控制台：不规律的继电器咔哒，每 1.5 秒一声短提示音，底下一层变压器嗡声
static func console_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var length := 3.0
	var s := _buffer(length)
	var ticks := [0.21, 0.37, 0.9, 1.33, 1.41, 2.05, 2.62]
	for i in s.size():
		var t := float(i) / RATE
		var v := sin(TAU * 50.0 * t) * 0.05 + sin(TAU * 150.0 * t) * 0.02
		for tk in ticks:
			var dt: float = t - float(tk)
			if dt >= 0.0 and dt < 0.03:
				v += rng.randf_range(-1.0, 1.0) * exp(-dt * 600.0) * 0.5
		var bt := fmod(t, 1.5)
		if bt < 0.08:
			v += sin(TAU * 1800.0 * t) * 0.12 * minf(1.0, bt / 0.005) * clampf((0.08 - bt) / 0.01, 0.0, 1.0)
		s[i] = v
	return _wav(s, true)


## 电梯：很低的电机嗡鸣，两个相近的频率慢慢拍
static func elevator_loop() -> AudioStreamWAV:
	var length := 4.0
	var s := _buffer(length)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * 55.0 * t) * 0.25 + sin(TAU * 55.5 * t) * 0.2 + sin(TAU * 110.0 * t) * 0.06
	return _wav(s, true)


# ---------------------------------------------------------------- 机器人碰撞与地面

## 撞击：几个衰减很快的共振 + 一下宽频的碰撞噪声 + 机身自己的金属颤响。
## 要在笔记本扬声器和监控的窄麦克风（约 260～3200 Hz）里都听得清，所以主要能量放在中频。
## modes：[[频率, 幅度, 衰减], ...]；noise：碰撞噪声的量；grit：低通系数，越小越闷
static func impact(modes: Array, noise: float, grit: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var s := _buffer(0.5)
	var lp := 0.0
	var lp_slow := 0.0
	var rattle := [[1340.0, 0.10, 22.0], [2215.0, 0.07, 28.0], [3120.0, 0.04, 35.0]]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for m in modes:
			var f: float = float(m[0]) * (1.0 - 0.15 * minf(t * 8.0, 1.0))  # 撞上的一瞬间音高略往下掉
			v += sin(TAU * f * t) * float(m[1]) * exp(-t * float(m[2]))
		lp += grit * (rng.randf_range(-1.0, 1.0) - lp)
		lp_slow += 0.02 * (lp - lp_slow)
		v += (lp - lp_slow) * noise * exp(-t * 55.0)
		# 机身颤响：开头稍晚一点、有点抖
		var tr := maxf(t - 0.008, 0.0)
		for m in rattle:
			v += sin(TAU * float(m[0]) * tr) * float(m[1]) * exp(-tr * float(m[2])) * (0.7 + 0.3 * sin(TAU * 37.0 * tr))
		s[i] = v * minf(1.0, t / 0.0015)
	return _wav(s)


## 贴着墙蹭过去：粗糙的摩擦噪声，颗粒不规则，1.5 秒无缝循环
static func scrape_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	var length := 1.5
	var s := _buffer(length)
	var lp := 0.0
	var lp_slow := 0.0
	var grain := 0.5
	for i in s.size():
		var t := float(i) / RATE
		if rng.randf() < 0.004:
			grain = rng.randf_range(0.3, 1.0)
		lp += 0.35 * (rng.randf_range(-1.0, 1.0) - lp)
		lp_slow += 0.03 * (lp - lp_slow)
		var edge := minf(t / 0.05, 1.0) * minf((length - t) / 0.05, 1.0)  # 首尾淡入淡出，循环接缝不爆
		s[i] = (lp - lp_slow) * 0.9 * grain * (0.75 + 0.25 * sin(TAU * 9.0 * t)) * (0.5 + 0.5 * edge)
	return _wav(s, true)


## 操作台上的碰撞传感器：保险杠一碰，蜂鸣器短短响一下（看哪路画面都听得到）
static func bump_alarm() -> AudioStreamWAV:
	var s := _buffer(0.11)
	for i in s.size():
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.003) * clampf((0.11 - t) / 0.02, 0.0, 1.0)
		var sq := 1.0 if sin(TAU * 520.0 * t) > 0.0 else -1.0
		s[i] = (sq * 0.18 + sin(TAU * 1040.0 * t) * 0.08) * env
	return _wav(s)


## 撞到金属（门、控制台）：几个不成谐波的频率叮一声
static func clang() -> AudioStreamWAV:
	var s := _buffer(0.9)
	var partials := [[410.0, 0.5, 6.0], [1037.0, 0.3, 9.0], [1781.0, 0.18, 12.0], [2650.0, 0.1, 16.0]]
	for i in s.size():
		var t := float(i) / RATE
		var v := sin(TAU * 90.0 * t) * exp(-t * 30.0) * 0.5
		for pt in partials:
			v += sin(TAU * float(pt[0]) * t) * float(pt[1]) * exp(-t * float(pt[2]))
		s[i] = v * 0.6
	return _wav(s)


## 履带压过纸：几下细碎的沙沙声
static func rustle() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	var s := _buffer(0.45)
	var hp_prev := 0.0
	var bursts := [0.0, 0.07, 0.16, 0.22, 0.31]
	for i in s.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		var hp := n - hp_prev
		hp_prev = n
		var env := 0.0
		for b in bursts:
			var dt: float = t - float(b)
			if dt >= 0.0:
				env += exp(-dt * 40.0) * (0.6 + 0.4 * rng.randf())
		s[i] = hp * 0.25 * minf(env, 1.2)
	return _wav(s)
