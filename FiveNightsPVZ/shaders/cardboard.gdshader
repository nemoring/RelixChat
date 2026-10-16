// Картонная коробка: оттенок, скотч, наклейка со штрихкодом.
// Работает и для MultiMesh (INSTANCE_CUSTOM), и для отдельных коробок (seed).
shader_type spatial;
render_mode diffuse_lambert;

uniform vec4 card_color : source_color = vec4(0.62, 0.47, 0.3, 1.0);
uniform float seed = 0.0;
uniform bool use_instance = false;
uniform float tape = 1.0;

varying vec3 lpos;
varying vec3 lnrm;
varying vec4 custom;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
	custom = use_instance ? INSTANCE_CUSTOM : vec4(seed, 0.0, 0.0, 0.0);
}

void fragment() {
	float s = custom.x;
	vec3 tint = card_color.rgb * (0.85 + 0.3 * hash(vec2(s, 1.7)));
	vec2 uv;
	vec3 an = abs(lnrm);
	if (an.y > 0.5) uv = lpos.xz; else if (an.x > 0.5) uv = lpos.zy; else uv = lpos.xy;
	vec3 col = tint * (0.9 + 0.12 * vnoise(uv * 30.0 + s * 10.0));
	// гофра
	col *= 0.97 + 0.03 * sin(uv.x * 220.0);
	// скотч по центру сверху
	if (an.y > 0.5 && abs(lpos.x) < 0.09 && tape > 0.5) col = mix(col, vec3(0.75, 0.62, 0.42), 0.8);
	// наклейка со штрихкодом на передней грани
	if (an.z > 0.5) {
		vec2 p = lpos.xy;
		vec2 c = vec2(-0.12 + 0.15 * hash(vec2(s, 4.0)), 0.05);
		vec2 d = abs(p - c);
		if (d.x < 0.2 && d.y < 0.14) {
			col = vec3(0.86, 0.85, 0.8);
			if (p.y < c.y + 0.02 && p.y > c.y - 0.11) {
				float bars = step(0.5, hash(vec2(floor((p.x - c.x) * 90.0), s)));
				col = mix(col, vec3(0.05), bars);
			}
			if (p.y > c.y + 0.05 && p.y < c.y + 0.1) {
				col = mix(col, vec3(0.2), step(0.55, hash(vec2(floor(p.x * 40.0), floor(p.y * 60.0) + s))) * 0.7);
			}
		}
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
