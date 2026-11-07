shader_type spatial;
render_mode depth_prepass_alpha;
#include "res://scripts/presentation/nature_pigment.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool textured = false;
uniform float fade = 0.0;
uniform vec3 target;
uniform vec3 sight;
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 color = tint.rgb;
	if (textured) {
		color = painted_nature(texture(atlas, UV).rgb, world_point);
	}
	vec3 offset = world_point - target;
	vec3 across = offset - sight * dot(offset, sight);
	float window = 1.0 - smoothstep(0.19, 0.39, length(across * vec3(1.0, 0.72, 0.72)));
	ALBEDO = color;
	ROUGHNESS = 0.9;
	ALPHA = 1.0 - fade * window * 0.83;
}
