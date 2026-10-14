shader_type spatial;
render_mode cull_disabled, shadows_disabled;
// Вода реки и болота: непрозрачная (дёшево), лёгкая анимация цвета и бликов в мировых координатах.

uniform vec4 shallow : source_color = vec4(0.25, 0.48, 0.55, 1.0);
uniform vec4 deep : source_color = vec4(0.1, 0.25, 0.38, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float w = sin(wpos.x * 0.35 + TIME * 1.3) * cos(wpos.z * 0.3 + TIME * 1.1);
	float w2 = sin((wpos.x + wpos.z) * 0.9 + TIME * 2.0) * 0.5;
	ALBEDO = mix(deep.rgb, shallow.rgb, 0.5 + 0.25 * w + 0.1 * w2);
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
	NORMAL_MAP = vec3(0.5 + 0.08 * w2, 0.5 + 0.08 * w, 1.0);
}
