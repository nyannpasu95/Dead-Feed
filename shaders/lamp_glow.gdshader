shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// 灯头的眩光：迎着探照灯看过去时，灯头是一团化开的亮点；从侧面、背后看几乎没有。

uniform float strength = 0.9;
uniform float toward_camera = 0.25;  // 往镜头挪一点，免得被灯罩自己挡住

varying float facing;

void vertex() {
	vec3 fwd = normalize(-MODEL_MATRIX[2].xyz);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
	facing = dot(fwd, to_cam);
	// 公告板：始终正对镜头，不跟着灯转
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[3].z += toward_camera;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float core = pow(clamp(1.0 - r, 0.0, 1.0), 3.0);
	ALBEDO = vec3(1.0);
	ALPHA = clamp(strength * core * smoothstep(0.3, 0.95, facing), 0.0, 1.0);
}
