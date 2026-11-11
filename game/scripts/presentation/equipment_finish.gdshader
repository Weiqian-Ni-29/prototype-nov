shader_type canvas_item;

uniform float level : hint_range(0.0, 5.0) = 0.0;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	vec2 position = (UV - region.xy) / region.zw;
	vec4 art = COLOR;
	float luminance = dot(art.rgb, vec3(0.2126, 0.7152, 0.0722));
	float progress = level / 5.0;
	float polish = smoothstep(0.10, 0.77, luminance) * progress;
	vec3 metal_light = mix(vec3(0.52, 0.68, 0.76), vec3(1.0, 0.77, 0.39), smoothstep(0.25, 0.88, progress));
	float diagonal = position.x - position.y * 0.62;
	float line = 1.0 - smoothstep(0.007, 0.021, abs(diagonal - 0.21));
	float second_line = 1.0 - smoothstep(0.006, 0.016, abs(diagonal - 0.29));
	float inlay = line * smoothstep(1.0, 3.0, level) + second_line * smoothstep(3.0, 5.0, level);
	vec2 edge_sample = region.zw * vec2(0.010, 0.014);
	float edge = clamp(art.a - texture(TEXTURE, UV - edge_sample).a, 0.0, 1.0);
	art.rgb = mix(art.rgb, art.rgb * 1.14 + metal_light * 0.24, polish);
	art.rgb += metal_light * (edge * progress * 0.32 + inlay * polish * 0.22);
	COLOR = art;
}
