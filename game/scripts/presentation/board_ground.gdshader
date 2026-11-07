shader_type spatial;
uniform bool deep_ocean = false;
varying highp vec2 world_xz;

highp float hash(highp vec2 point) {
	highp vec3 p = fract(vec3(point.xyx) * vec3(0.1031, 0.1099, 0.1379));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

highp float wash(highp vec2 p) {
	highp vec2 i = floor(p);
	highp vec2 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	highp vec2 p = world_xz;
	// Offset the brush pattern continuously in world space, across hexes and chunks.
	vec2 brush = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	brush += vec2(wash(p * 1.7 + vec2(8.2, 4.6)), wash(p * 1.7)) * 0.36;
	float grain = wash(brush * vec2(31.0, 39.0)) - 0.5;
	float pigment = (wash(brush * 2.7) - 0.5) * 0.17
		+ (wash(brush * vec2(8.0, 12.0)) - 0.5) * 0.075 + grain * 0.045 - 0.01;
	float sand = UV.x;
	float stone = UV.y;
	float marsh = UV2.x;
	float depth = deep_ocean ? 0.65 : UV2.y;
	vec3 ground = COLOR.rgb * vec3(0.91, 0.94, 0.97) * (1.0 + pigment);
	float winds = sin(dot(p, vec2(15.0, 22.0)) + wash(p * 1.6) * 3.7);
	ground += vec3(0.17, 0.12, 0.065) * winds * sand * 0.18;
	float strata = sin(dot(p, vec2(12.0, 20.0)) + wash(p * 3.2) * 6.2);
	float incline = 1.0 - clamp(dot(NORMAL, (VIEW_MATRIX * vec4(0, 1, 0, 0)).xyz), 0.0, 1.0);
	float outcrop = smoothstep(0.09, 0.45, incline + (wash(brush * 4.0) - 0.5) * 0.11) * stone;
	vec3 rock = ground * (0.78 + strata * 0.11) + vec3(0.11, 0.115, 0.12);
	ground = mix(ground, rock, outcrop * 0.72);
	float mire = smoothstep(0.34, 0.65, marsh * 0.61 + wash(p * 2.0) * 0.39) * marsh;
	ground = mix(ground, vec3(0.24, 0.38, 0.31) + vec3(pigment * 0.7), mire * 0.72);

	float lake = deep_ocean ? 0.0 : COLOR.a;
	vec3 shallow = mix(vec3(0.32, 0.59, 0.60), vec3(0.32, 0.57, 0.49), lake);
	vec3 deep = mix(vec3(0.12, 0.32, 0.46), vec3(0.14, 0.34, 0.34), lake);
	float ripple = sin(dot(p, vec2(4.0, 8.5)) + wash(p * 1.25) * 5.5 + TIME * 1.18)
		* sin(dot(p, vec2(-2.7, 4.5)) + wash(p * 0.90) * 3.1 - TIME * 0.55);
	float glint = smoothstep(0.64, 0.95, ripple) * smoothstep(0.28, 0.79, wash(p * 3.4 + TIME * 0.12));
	float shallows = smoothstep(0.025, 0.55, depth);
	vec3 water = mix(shallow, deep, shallows) + vec3(ripple * 0.012 + glint * 0.055);
	water = mix(water, water * vec3(0.79, 0.89, 0.74), marsh * 0.7);
	float foam = (1.0 - smoothstep(0.009, 0.075, abs(depth - 0.025 + ripple * 0.012)))
		* smoothstep(0.26, 0.7, wash(p * 4.8 + TIME * 0.08)) * mix(0.76, 0.37, lake) * (1.0 - marsh * 0.82);
	water = mix(water, vec3(0.68, 0.81, 0.70), foam);
	float beach = (1.0 - smoothstep(0.035, 0.24, abs(depth))) * (1.0 - smoothstep(0.0, 0.035, depth));
	vec3 bank = mix(vec3(0.60, 0.54, 0.35), vec3(0.32, 0.34, 0.24), marsh);
	ground = mix(ground, bank + pigment, beach * 0.8);
	float wet = smoothstep(-0.02, 0.055, depth);
	ALBEDO = mix(ground, water, wet);
	EMISSION = water * wet * 0.18;
	ROUGHNESS = mix(0.96, 0.63, max(wet, mire));
}
