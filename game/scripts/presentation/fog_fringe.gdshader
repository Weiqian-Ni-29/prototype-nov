shader_type spatial;
render_mode unshaded, depth_draw_never, shadows_disabled;
#include "res://scripts/presentation/fog_cloud.gdshaderinc"

uniform float progress : hint_range(0.0, 1.0) = 0.0;
varying vec2 cloud_point;
varying float border_mask;

void vertex() {
	cloud_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz + vec2(21.7, 13.3);
	border_mask = UV2.x;
	VERTEX.y += FOG_SURFACE_OFFSET;
}

void fragment() {
	vec2 local = UV * 2.0 - 1.0;
	int mask = int(round(border_mask));
	float distance_to_fog = 2.0;
	for (int i = 0; i < 6; i++) {
		if ((mask & (1 << i)) != 0) {
			float angle = -float(i) * TAU / 6.0;
			vec2 normal = vec2(cos(angle), sin(angle));
			vec2 tangent = vec2(-normal.y, normal.x);
			vec2 edge_point = normal * 0.8660254;
			float along = clamp(dot(local - edge_point, tangent), -0.5, 0.5);
			distance_to_fog = min(distance_to_fog, length(local - edge_point - tangent * along));
		}
	}
	float drift = fog_noise(cloud_point * 4.1 + vec2(-0.17, 0.12) * TIME);
	float detail = fog_noise(cloud_point * 8.7 - vec2(0.11, 0.05) * TIME);
	float reach = mix(0.28, 0.65, drift * 0.75 + detail * 0.25);
	ALPHA = (1.0 - smoothstep(0.012, reach, distance_to_fog)) * (1.0 - smoothstep(0.0, 1.0, progress));
	ALBEDO = mix(fog_color(cloud_point, 1.0, 0.0, TIME), fog_color(cloud_point, 0.3, 0.0, TIME),
		smoothstep(0.0, 0.21, distance_to_fog) * 0.76);
}
