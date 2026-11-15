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
