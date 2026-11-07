shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.5,0.8,0.9,1.0);
void fragment() {
	float rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.5);
	ALBEDO = tint.rgb*(0.15+rim);
	ALPHA = rim*0.55+0.05;
}
