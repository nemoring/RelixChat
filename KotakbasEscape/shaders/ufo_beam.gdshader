shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Луч захвата НЛО: бегущие вверх полосы, прозрачные края. Дёшево для мобильных.

uniform vec4 beam_color : source_color = vec4(0.35, 1.0, 0.6, 1.0);
uniform float intensity = 1.0;

void fragment() {
	float stripes = 0.55 + 0.45 * sin(UV.y * 40.0 - TIME * 9.0);
	float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float fade = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.75, UV.y);
	float a = (0.08 + 0.16 * (1.0 - edge)) * stripes * intensity * (0.4 + 0.6 * fade);
	ALBEDO = beam_color.rgb * a;
}
