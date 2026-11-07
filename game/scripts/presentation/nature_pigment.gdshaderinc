float paint_cell(vec2 cell) {
	return fract(sin(dot(cell, vec2(41.53, 109.21))) * 43758.5);
}

float paint_wash(vec2 point) {
	vec2 cell = floor(point);
	vec2 t = smoothstep(0.0, 1.0, fract(point));
	return mix(mix(paint_cell(cell), paint_cell(cell + vec2(1, 0)), t.x),
		mix(paint_cell(cell + vec2(0, 1)), paint_cell(cell + vec2(1, 1)), t.x), t.y);
}

vec3 painted_nature(vec3 color, vec3 point) {
	float grey = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(grey), color, 0.65);
	if (color.g > color.r * 1.12 && color.g > color.b * 1.25) {
		vec2 brush = vec2(point.x + point.y * 0.64, point.z - point.y * 0.43);
		float large_stroke = paint_wash(brush * 13.0);
		float fleck = paint_wash(brush * 38.0);
		color *= mix(vec3(0.60, 0.70, 0.79), vec3(0.79, 0.86, 0.92), large_stroke * 0.77 + fleck * 0.23);
	}
	if (color.r > color.g * 1.23 && color.g > color.b * 1.12) {
		color *= vec3(0.74, 0.83, 0.90);
	}
	return color;
}
