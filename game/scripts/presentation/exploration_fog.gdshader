shader_type spatial;
render_mode unshaded;

varying vec2 cloud_point;
varying float edge;
varying float lift;

float hash_point(vec2 point) {
	vec3 p = fract(vec3(point.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float soft_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 t = fract(point);
	t = t * t * (3.0 - 2.0 * t);
	return mix(
		mix(hash_point(cell), hash_point(cell + vec2(1.0, 0.0)), t.x),
		mix(hash_point(cell + vec2(0.0, 1.0)), hash_point(cell + vec2(1.0, 1.0)), t.x),
		t.y
	);
}

void vertex() {
	vec2 local = abs(UV * 2.0 - 1.0);
	float hex_distance = max(local.x * 1.1547005, local.y + local.x * 0.5773503);
	vec2 map_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	cloud_point = map_point + vec2(21.7, 13.3);
	float swell = soft_noise(cloud_point * 2.8 + vec2(-0.13, 0.07) * TIME);
	lift = (0.11 + 0.18 * swell) * (1.0 - smoothstep(0.22, 0.93, hex_distance));
	VERTEX.y += lift;
	edge = hex_distance;
}

void fragment() {
	vec2 broad_flow = cloud_point * 2.8 + vec2(-0.13, 0.07) * TIME;
	float mass = soft_noise(broad_flow);
	float roll = soft_noise(cloud_point * 5.1 + vec2(-0.10, -0.045) * TIME + vec2(mass, -mass) * 0.85);
	float wisps = soft_noise(cloud_point * 10.4 + vec2(-0.16, 0.12) * TIME);
	float billow = mass * 0.48 + roll * 0.39 + wisps * 0.13;
	vec3 hollow = vec3(0.37, 0.46, 0.55);
	vec3 body = vec3(0.60, 0.69, 0.77);
	vec3 crest = vec3(0.89, 0.93, 0.96);
	vec3 cloud = mix(hollow, body, smoothstep(0.24, 0.63, billow));
	cloud = mix(cloud, crest, smoothstep(0.45, 0.73, billow + lift * 0.28));
	// Feather into the opaque unknown tile so there is no blended terrain underneath.
	float cover = 1.0 - smoothstep(0.57 + wisps * 0.16, 0.99, edge);
	ALBEDO = mix(vec3(0.29, 0.37, 0.44), cloud, cover);
}
