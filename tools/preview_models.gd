extends SceneTree
## 模型预览：每个模型从 +z、-z、+x、正上方各拍一张，检查朝向和比例。
## 用法：Godot --path . -s tools/preview_models.gd -- <输出目录> <模型名…>

const VIEWS := {
	"pz": Vector3(0.0, 0.25, 1.0),
	"nz": Vector3(0.0, 0.25, -1.0),
	"px": Vector3(1.0, 0.25, 0.0),
	"top": Vector3(0.0, 1.0, 0.001),
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(512, 512)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.34, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	root.add_child(sun)
	var cam := Camera3D.new()
	root.add_child(cam)
	for name in args.slice(1):
		var packed := load("res://assets/models/%s.glb" % name) as PackedScene
		var model := packed.instantiate() as Node3D
		root.add_child(model)
		await process_frame
		var box := _aabb(model)
		var r := box.size.length() * 0.5
		for view: String in VIEWS:
			var dir: Vector3 = VIEWS[view]
			cam.position = box.get_center() + dir.normalized() * r * 2.6
			cam.look_at(box.get_center(), Vector3.UP if view != "top" else Vector3.FORWARD)
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, name, view])
		print("PREVIEW %s size %s" % [name, box.size])
		model.queue_free()
		await process_frame
	quit()


func _aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
