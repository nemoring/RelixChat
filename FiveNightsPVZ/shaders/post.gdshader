// Пост-обработка экрана: яркость, виньетка от страха, зерно, хроматическая аберрация.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float brightness = 1.0;
uniform float fear = 0.0;
uniform float grain = 0.05;
uniform float stare = 0.0;   // взгляд на Безликого
uniform float blackout = 0.0;
uniform float aberration = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float ab = (aberration + stare * 0.008 + fear * 0.002) * dot(c, c) * 4.0;
	vec3 col;
	col.r = texture(screen_tex, uv + c * ab).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - c * ab).b;
	// яркость: гамма-подъём теней, чтобы не было «чёрного экрана»
	col = pow(max(col, vec3(0.0)), vec3(1.0 / brightness));
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(l), clamp(fear * 0.35 + stare * 0.5, 0.0, 0.9));
	float vig = smoothstep(0.85, 0.2, length(c) * (1.0 + fear * 0.6 + stare * 1.2));
	col *= mix(1.0, vig, 0.55 + fear * 0.35);
	col += (hash(uv * 900.0 + fract(TIME * 7.0)) - 0.5) * (grain + stare * 0.15);
	col *= 1.0 - blackout;
	COLOR = vec4(col, 1.0);
}
