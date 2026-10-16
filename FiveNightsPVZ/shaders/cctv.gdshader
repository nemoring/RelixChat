// Изображение камеры наблюдения: шум, строки развёртки, ночное видение,
// искажения времени, потеря сигнала, «рябь» рядом с невидимыми сущностями.
shader_type canvas_item;

uniform float noise_amount = 0.12;
uniform float night_vision = 0.0;
uniform float distortion = 0.0;
uniform float signal_loss = 0.0;
uniform float entity_static = 0.0;
uniform float brightness = 1.0;
uniform float time_offset = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float t = TIME + time_offset;
	// горизонтальный срыв строк
	float band = step(0.985 - distortion * 0.25, hash(vec2(floor(uv.y * 60.0), floor(t * 8.0))));
	uv.x += band * (hash(vec2(t, uv.y)) - 0.5) * 0.08 * (0.3 + distortion);
	uv.x += sin(uv.y * 30.0 + t * 3.0) * 0.002 * distortion;
	// бочкообразное искажение линзы
	vec2 cc = uv - 0.5;
	uv = 0.5 + cc * (1.0 + 0.08 * dot(cc, cc));
	vec3 col = texture(TEXTURE, uv).rgb;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) col = vec3(0.0);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 mono = vec3(lum);
	col = mix(col, mono, 0.65) * brightness;
	if (night_vision > 0.5) {
		float l = pow(clamp(lum * 3.2, 0.0, 1.0), 0.7);
		col = vec3(0.25, 1.0, 0.35) * l;
	}
	float n = hash(uv * vec2(320.0, 240.0) + fract(t * 13.0));
	col += (n - 0.5) * (noise_amount + entity_static * 0.6);
	col *= 0.9 + 0.1 * sin(uv.y * 480.0);
	float roll = smoothstep(0.0, 0.02, abs(fract(uv.y * 0.5 - t * 0.1) - 0.5));
	col *= mix(0.92, 1.0, roll);
	// рябь от сущности: полосы «снега»
	col = mix(col, vec3(n), entity_static * step(0.5, hash(vec2(floor(uv.y * 40.0), floor(t * 20.0)))) * 0.5);
	col = mix(col, vec3(n * 0.6), signal_loss);
	vec2 v = UV - 0.5;
	col *= 1.0 - dot(v, v) * 1.1;
	COLOR = vec4(col, 1.0);
}
