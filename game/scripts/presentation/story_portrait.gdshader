shader_type canvas_item;
uniform sampler2D silhouette : filter_linear, repeat_disable;

void fragment() {
	vec4 portrait = texture(TEXTURE, UV);
	float matte = texture(silhouette, UV).r;
	float hem = 1.0 - smoothstep(0.84, 1.0, UV.y);
	COLOR = vec4(portrait.rgb, portrait.a * matte * hem);
}
