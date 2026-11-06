shader_type spatial;
render_mode unshaded;
#include "res://scripts/presentation/fog_cloud.gdshaderinc"

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
	// The unvisited board stays opaque, even at the border.
	ALBEDO = fog_color(cloud_point, edge, lift, TIME);
}
