// Универсальная процедурная поверхность: кафель, крашеная стена, бетон, линолеум,
// потолочные плиты. Проекция в мировых координатах — одинаковая плотность везде.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform int mode = 0; // 0 краска, 1 кафель, 2 бетон, 3 линолеум, 4 потолок
uniform vec4 base_color : source_color = vec4(0.7, 0.7, 0.68, 1.0);
uniform vec4 alt_color : source_color = vec4(0.6, 0.62, 0.6, 1.0);
uniform vec4 grout_color : source_color = vec4(0.25, 0.24, 0.22, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.22, 0.19, 0.14, 1.0);
uniform vec2 tile_size = vec2(0.3, 0.3);
uniform float grout = 0.012;
uniform float variation = 0.08;
uniform float dirt = 0.35;
uniform float leaks = 0.0;      // подтёки на стенах
uniform float floor_grime = 0.5; // грязь у пола на стенах
uniform float roughness_v = 0.8;
uniform float wet = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int k = 0; k < 4; k++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(wnrm);
	vec2 uv;
	bool is_wall = false;
	if (an.y > 0.6) { uv = wpos.xz; }
	else if (an.x > an.z) { uv = vec2(wpos.z, wpos.y); is_wall = true; }
	else { uv = vec2(wpos.x, wpos.y); is_wall = true; }

	vec3 col = base_color.rgb;
	float rough = roughness_v;
	float n = fbm(uv * 1.7);
	float fine = vnoise(uv * 40.0);

	if (mode == 1 || mode == 4) {
		vec2 t = uv / tile_size;
		vec2 id = floor(t);
		vec2 f = fract(t);
		float g = grout / min(tile_size.x, tile_size.y);
		float edge = step(f.x, g) + step(f.y, g);
		float h = hash(id);
		col = mix(base_color.rgb, alt_color.rgb, step(0.85, h) * 0.6) * (1.0 - variation + variation * 2.0 * h);
		// трещины на отдельных плитках
		float crack = smoothstep(0.985, 1.0, 1.0 - abs(f.x - f.y - (hash(id + 3.1) - 0.5) * 0.4)) * step(0.93, hash(id + 7.7));
		col = mix(col, grout_color.rgb, clamp(edge, 0.0, 1.0));
		col = mix(col, grout_color.rgb * 0.8, crack);
		rough = mix(mode == 4 ? 0.95 : 0.35, 0.95, clamp(edge, 0.0, 1.0));
	} else if (mode == 2) {
		col = base_color.rgb * (0.82 + 0.3 * n) + vec3(fine * 0.04);
		rough = 0.92;
	} else if (mode == 3) {
		col = base_color.rgb * (0.9 + 0.15 * vnoise(uv * vec2(0.6, 6.0)));
		rough = 0.55;
	} else {
		col = base_color.rgb * (0.94 + 0.08 * n);
	}

	// Грязь и пятна.
	float d = (smoothstep(0.38, 0.72, fbm(uv * 0.6 + 11.0)) * 0.8 + smoothstep(0.5, 0.9, vnoise(uv * 7.0 + 2.0)) * 0.25) * dirt;
	if (is_wall) {
		float h = wpos.y;
		d += smoothstep(0.5, 0.0, h) * floor_grime * (0.6 + 0.4 * n);
		// подтёки сверху вниз
		float streak = smoothstep(0.62, 0.9, vnoise(vec2(uv.x * 3.0, 0.0) + 5.0));
		float fall = smoothstep(0.0, 2.6, h) * (0.6 + 0.4 * vnoise(vec2(uv.x * 9.0, h * 1.5)));
		d += streak * fall * leaks;
		// пятно от протечки у потолка
		float stain = smoothstep(0.55, 0.75, fbm(uv * 0.35 + 3.3)) * smoothstep(1.8, 3.0, h);
		d += stain * leaks * 1.3;
	}
	col = mix(col, dirt_color.rgb, clamp(d, 0.0, 0.85));
	ALBEDO = col;
	ROUGHNESS = clamp(rough - wet * 0.5, 0.05, 1.0);
	SPECULAR = 0.4;
}
