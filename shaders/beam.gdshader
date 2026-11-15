shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// 探照灯在空气里的光柱：锥面正对视线的部分亮、侧面淡掉（看起来像一团实心的光），
// 离灯越远越暗，碰到地面墙面的地方柔和地消失，空气里的灰尘让光柱有一点斑驳。
// Compatibility 渲染器没有体积雾，这是假的。

uniform float strength = 0.5;
uniform float shaft_length = 5.0;
uniform float soft_depth = 0.45;
uniform float dust = 0.35;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying float dist;
varying vec3 world_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	dist = length(VERTEX);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = facing * facing;
	float fall = pow(clamp(1.0 - dist / shaft_length, 0.0, 1.0), 1.2);
	float start = smoothstep(0.03, 0.3, dist);

	float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_z = -scene.z / scene.w;
	float soft = clamp((scene_z + VERTEX.z) / soft_depth, 0.0, 1.0);

	float motes = noise(world_pos * 5.0 + vec3(0.0, TIME * 0.08, TIME * 0.05));
	float grain = mix(1.0 - dust, 1.0 + dust, motes);

	ALBEDO = vec3(1.0);
	ALPHA = clamp(strength * body * fall * start * soft * grain, 0.0, 1.0);
}
