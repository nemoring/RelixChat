shader_type canvas_item;
// Мобильный glitch-эффект: сдвиг RGB-каналов, полосы, шум. Дешёвый — без циклов.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = floor(TIME * 24.0);
	float band = step(0.82, rand(vec2(t, floor(uv.y * 18.0))));
	uv.x += (rand(vec2(t, uv.y)) - 0.5) * 0.08 * band * intensity;
	float shift = 0.012 * intensity;
	float r = texture(screen_tex, uv + vec2(shift, 0.0)).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - vec2(shift, 0.0)).b;
	vec3 col = vec3(r, g, b);
	col += (rand(uv * TIME) - 0.5) * 0.15 * intensity;
	float scan = sin(uv.y * 900.0) * 0.04 * intensity;
	COLOR = vec4(col - scan, 1.0);
}
