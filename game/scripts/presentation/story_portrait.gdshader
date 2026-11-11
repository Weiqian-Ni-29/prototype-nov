shader_type canvas_item;

uniform float portrait_height = 1.0;
varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	float progress = local_y / max(portrait_height, 1.0);
	// Some poses are cropped slightly above the bottom of their atlas cell.
	COLOR.a *= 1.0 - smoothstep(0.78, 0.92, progress);
}
