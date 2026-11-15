shader_type canvas_item;
// 操作台显示器：桶形畸变、扫描线、噪点、切换雪花。
// mono = 0 机载（有颜色，偏暗去饱和）；mono = 1 监控（红外单色）。

uniform float mono : hint_range(0.0, 1.0) = 0.0;
uniform float desaturate : hint_range(0.0, 1.0) = 0.45;
uniform float noise_amount : hint_range(0.0, 1.0) = 0.04;
uniform float static_amount : hint_range(0.0, 1.0) = 0.0;
uniform float curvature : hint_range(0.0, 0.3) = 0.07;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.22;
uniform float scan_lines = 360.0;
uniform float brightness = 1.0;
uniform vec3 ir_tint = vec3(0.86, 1.0, 0.9);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 barrel(vec2 uv) {
	vec2 c = uv * 2.0 - 1.0;
	c *= 1.0 + curvature * dot(c, c);
	return c * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = barrel(UV);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		float frame = mod(floor(TIME * 50.0), 997.0);
		float line = floor(uv.y * scan_lines);
		uv.x += (hash(vec2(line, frame)) - 0.5) * 0.03 * static_amount;
		vec3 col = texture(TEXTURE, uv).rgb;
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		vec3 onboard = mix(col, vec3(lum), desaturate);
		vec3 ir = vec3(lum) * ir_tint;
		col = mix(onboard, ir, mono);
		float n = hash(floor(uv * vec2(scan_lines * 1.333, scan_lines)) + vec2(frame * 0.37, frame * 0.11));
		col += (n - 0.5) * noise_amount;
		float s = hash(floor(uv * vec2(240.0, 180.0)) + vec2(frame * 1.7, frame * 0.3));
		col = mix(col, vec3(s * 0.9), static_amount);
		float sl = 0.5 + 0.5 * cos(uv.y * scan_lines * 6.2831853);
		col *= 1.0 - scanline_strength * sl;
		vec2 d = uv - 0.5;
		col *= clamp(1.0 - dot(d, d) * 1.4, 0.0, 1.0);
		COLOR = vec4(col * brightness, 1.0);
	}
}
