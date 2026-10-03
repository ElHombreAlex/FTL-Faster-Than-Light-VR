shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never;

uniform vec4 shield_color : source_color = vec4(0.18, 0.58, 1.0, 1.0);
uniform float strength = 0.5;
uniform float hit_flash = 0.0;

void fragment() {
	float edge = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.4);
	vec2 grid = abs(fract(UV * vec2(40.0, 22.0)) - 0.5);
	float line = smoothstep(0.45, 0.49, max(grid.x, grid.y));
	ALBEDO = shield_color.rgb;
	EMISSION = shield_color.rgb * (0.5 + hit_flash * 2.0);
	ALPHA = (0.025 + edge * 0.3 + line * 0.035) * strength + hit_flash * 0.2;
}
