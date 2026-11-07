shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, shadows_disabled;
#include "res://scripts/presentation/fog_cloud.gdshaderinc"

uniform float progress : hint_range(0.0, 1.0) = 0.0;
varying vec2 cloud_point;
varying float edge;
varying float lift;

void vertex() {
	edge = fog_hex_radius(UV * 2.0 - 1.0);
	cloud_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz + vec2(21.7, 13.3);
	lift = fog_lift(cloud_point, edge, TIME);
	VERTEX.y += FOG_SURFACE_OFFSET + lift;
}

void fragment() {
	float breaks = fog_noise(cloud_point * 5.2 + vec2(-0.09, 0.15) * TIME);
	float cleared = progress + (breaks - 0.5) * 0.72 * sin(PI * progress);
	ALBEDO = fog_color(cloud_point, edge, lift, TIME);
	ALPHA = 1.0 - smoothstep(0.0, 1.0, cleared);
}
