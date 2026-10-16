// Лицо Безликого: плывущее «размытие», которое нельзя рассмотреть.
shader_type spatial;
render_mode cull_back, diffuse_lambert;

uniform vec4 skin : source_color = vec4(0.55, 0.47, 0.42, 1.0);
uniform float intensity = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float t = TIME * 0.6;
	float a = atan(uv.y, uv.x) + t + vnoise(uv * 3.0 + t) * 2.0;
	float r = length(uv);
	float swirl = vnoise(vec2(a * 2.0, r * 6.0 - t * 2.0));
	vec3 col = skin.rgb * (0.55 + 0.6 * swirl);
	// намёк на глаза и рот, расплывающийся
	float eyes = smoothstep(0.25, 0.0, length((uv - vec2(-0.3, 0.2)) * vec2(1.0, 2.0) + vnoise(uv * 5.0 + t) * 0.3));
	eyes += smoothstep(0.25, 0.0, length((uv - vec2(0.3, 0.2)) * vec2(1.0, 2.0) + vnoise(uv * 5.0 - t) * 0.3));
	float mouth = smoothstep(0.2, 0.0, length((uv - vec2(0.0, -0.45)) * vec2(0.6, 3.0) + vnoise(uv * 4.0 + t) * 0.4));
	col = mix(col, vec3(0.05), clamp((eyes + mouth) * intensity * 0.8, 0.0, 0.9));
	ALBEDO = col;
}
