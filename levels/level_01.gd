extends RefCounted
## 第 1 关：控制室走廊（设计见 docs/level-design.md）。
## 坐标：x 向东，z 向南（平面图上 = 向下），y 向上；单位米。
## heading 用罗盘角度：0 = 北（-z），90 = 东（+x）。


static func get_data() -> Dictionary:
	return {
		"id": "level_01",
		"wall_height": 5.2,
		"floor": Rect2(-1.0, -3.0, 29.0, 14.5),

		# 平面图上的房间；摄像头第一次被看到时补全对应房间
		"rooms": [
			{"id": "loading", "rect": Rect2(0.0, 0.0, 9.0, 10.5)},
			{"id": "corridor", "rect": Rect2(9.0, 0.0, 9.0, 1.6)},
			{"id": "guard", "rect": Rect2(11.0, 1.6, 6.0, 6.4)},
			{"id": "control", "rect": Rect2(18.0, -2.0, 9.0, 10.0)},
		],

		# 墙段 [x1, z1, x2, z2]，只用横竖两种；门洞就是墙段之间的空缺
		"walls": [
			[0.0, 0.0, 18.0, 0.0],      # 装载区 + 走廊北墙
			[0.0, 0.0, 0.0, 10.5],      # 装载区西墙
			[0.0, 10.5, 9.0, 10.5],     # 装载区南墙
			[9.0, 1.6, 9.0, 10.5],      # 装载区东墙（北端 0～1.6 是出口）
			[9.0, 1.6, 11.6, 1.6],      # 走廊南墙（西段）
			[12.8, 1.6, 18.0, 1.6],     # 走廊南墙（东段）；11.6～12.8 是警卫室门
			[11.0, 1.6, 11.0, 8.0],     # 警卫室
			[11.0, 8.0, 17.0, 8.0],
			[17.0, 1.6, 17.0, 8.0],
			[18.0, -2.0, 18.0, 0.0],    # 控制室西墙；0～1.6 是 17 号门
			[18.0, 1.6, 18.0, 8.0],
			[18.0, -2.0, 27.0, -2.0],
			[27.0, -2.0, 27.0, 8.0],
			[18.0, 8.0, 27.0, 8.0],
		],

		# 货箱迷宫：# = 一堆货箱，S = 机器人起点；每格 1.5 米
		# 右下角一片 CAM-1 拍不到，整块堆满，不藏玩法
		"crates": {
			"origin": Vector2(0.0, 0.0),
			"cell": 1.5,
			"size": 1.42,
			"heights": [1.5, 2.0, 2.3],
			"rows": [
				"....#.",
				".##.#.",
				".#....",
				".#.##.",
				"#S.#..",
				"...###",
				"..####",
			],
		},

		# 起点正对倒塌的货箱，留一点距离，头灯不至于糊成一片
		"robot_start": {"pos": Vector3(2.25, 0.0, 7.2), "heading": 0.0},

		"cameras": [
			{
				"id": "CAM-1", "key": 1, "fps": 6.0, "fov": 90.0,
				"pos": Vector3(0.35, 4.8, 10.15), "target": Vector3(3.1, 0.0, 4.0),
				"reveals": ["loading"],
			},
			{
				"id": "CAM-2", "key": 2, "fps": 7.0, "fov": 90.0,
				"pos": Vector3(16.7, 4.4, 7.7), "target": Vector3(13.6, 0.0, 5.0),
				"reveals": ["guard"],
			},
			{
				"id": "CAM-3", "key": 3, "fps": 5.0, "fov": 90.0,
				"pos": Vector3(26.7, 4.6, -1.7), "target": Vector3(22.2, 0.0, 4.6),
				"reveals": ["control"],
			},
		],

		"doors": [
			{
				"id": "door_17", "number": "17", "code": "4071",
				"pos": Vector2(18.0, 0.8), "width": 1.6, "height": 2.6,
				"slide": Vector3(0.0, 0.0, 1.62),
				"panel": Vector3(17.55, 0.78, 0.13),
				"area": Rect2(16.3, 0.0, 1.62, 1.6),
			},
		],

		"props": [
			# 跨画面地标：红色地面条纹，从装载区出口一直到 17 号门后
			{"type": "stripe", "from": Vector2(7.5, 0.8), "to": Vector2(19.2, 0.8), "width": 0.22},

			# 警卫室：桌子、翻倒的椅子、散落的纸；写着密码的那张单独落在椅子旁
			{"type": "desk", "pos": Vector2(15.1, 2.6), "size": Vector2(1.8, 0.8), "height": 0.75},
			{"type": "chair_fallen", "pos": Vector2(12.3, 6.9), "yaw": 30.0},
			# 倒地的台灯朝门口照：走廊没有摄像头，对面墙上的光斑告诉机载这里有个门
			{"type": "lamp_fallen", "pos": Vector2(12.6, 2.4), "yaw": -10.0},
			{"type": "paper", "pos": Vector2(12.95, 7.35), "yaw": 15.0, "text": "4071"},
			# 其余的纸从桌上滑落，堆在桌前一片；从上面看，椅子旁那张孤零零的最显眼
			{"type": "paper", "pos": Vector2(14.3, 3.5), "yaw": 40.0, "text": "2958"},
			{"type": "paper", "pos": Vector2(14.9, 3.3), "yaw": -20.0, "text": "7714"},
			{"type": "paper", "pos": Vector2(15.6, 3.5), "yaw": 75.0, "text": "1360"},
			{"type": "paper", "pos": Vector2(16.2, 3.9), "yaw": 10.0, "text": "8823"},
			{"type": "paper", "pos": Vector2(14.0, 4.2), "yaw": -60.0, "text": "5097"},
			{"type": "paper", "pos": Vector2(14.7, 4.1), "yaw": 110.0, "text": "3341"},
			{"type": "paper", "pos": Vector2(15.4, 4.3), "yaw": -35.0, "text": "6402"},
			{"type": "paper", "pos": Vector2(16.0, 4.7), "yaw": 20.0, "text": "9185"},
			{"type": "paper", "pos": Vector2(14.4, 4.9), "yaw": -80.0, "text": "2736"},
			{"type": "paper", "pos": Vector2(15.1, 5.0), "yaw": 55.0, "text": "4469"},
			{"type": "paper", "pos": Vector2(15.8, 5.4), "yaw": -15.0, "text": "7051"},

			# 控制室：控制台、拖痕（和地面亮度相同、只有颜色不同 → 只有机载看得出）、电梯
			{"type": "console", "pos": Vector2(22.4, 2.8), "size": Vector2(2.8, 0.8)},
			{"type": "drag_mark", "from": Vector2(22.35, 7.0), "to": Vector2(22.35, 2.5), "width": 0.09},
			{"type": "elevator", "rect": Rect2(24.6, 5.4, 2.4, 2.6)},
		],

		# 帧间者预兆：CAM-1 远端、通往出口的拐角处站着一个人影，只在玩家看着 CAM-1 时，
	# 沿机器人要走的路反向走向摄像头；走到摄像头正下方出画，画面一阵雪花后消失。无伤害。
	"frame_skippers": [
		{
			"id": "omen_cam1", "camera": "CAM-1",
			"frames_per_step": 6, "step": 0.9,  # CAM-1 6 fps → 每看 1 秒走一步，约 15 秒走完
			"path": [
				Vector2(8.25, 3.75), Vector2(3.75, 3.75), Vector2(3.75, 8.25),
				Vector2(2.25, 8.25), Vector2(2.25, 9.75), Vector2(0.9, 9.9),
			],
		},
	],

	"triggers": [
			{"id": "level_end", "rect": Rect2(25.1, 5.95, 1.7, 1.5)},
		],
	}
