const float FOG_SURFACE_OFFSET = 0.015;

float fog_hash(vec2 point) {
	vec3 p = fract(vec3(point.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float fog_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 t = fract(point);
	t = t * t * (3.0 - 2.0 * t);
	return mix(
		mix(fog_hash(cell), fog_hash(cell + vec2(1.0, 0.0)), t.x),
		mix(fog_hash(cell + vec2(0.0, 1.0)), fog_hash(cell + vec2(1.0, 1.0)), t.x),
		t.y
	);
}

float fog_lift(vec2 point, float edge, float time) {
	float swell = fog_noise(point * 2.8 + vec2(-0.13, 0.07) * time);
	return (0.11 + 0.18 * swell) * (1.0 - smoothstep(0.22, 0.93, edge));
}

vec3 fog_color(vec2 point, float edge, float lift, float time) {
	vec2 flow = point * 2.8 + vec2(-0.13, 0.07) * time;
	float mass = fog_noise(flow);
	float roll = fog_noise(point * 5.1 + vec2(-0.10, -0.045) * time + vec2(mass, -mass) * 0.85);
	float wisps = fog_noise(point * 10.4 + vec2(-0.16, 0.12) * time);
	float billow = mass * 0.48 + roll * 0.39 + wisps * 0.13;
	vec3 cloud = mix(vec3(0.37, 0.46, 0.55), vec3(0.60, 0.69, 0.77), smoothstep(0.24, 0.63, billow));
	cloud = mix(cloud, vec3(0.89, 0.93, 0.96), smoothstep(0.45, 0.73, billow + lift * 0.28));
	float cover = 1.0 - smoothstep(0.57 + wisps * 0.16, 0.99, edge);
	return mix(vec3(0.29, 0.37, 0.44), cloud, cover);
}

float fog_hex_radius(vec2 local) {
	vec2 p = abs(local);
	return max(p.x * 1.1547005, p.y + p.x * 0.5773503);
}
