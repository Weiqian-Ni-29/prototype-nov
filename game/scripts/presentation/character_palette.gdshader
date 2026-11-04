shader_type spatial;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec4 clothing : source_color = vec4(0.4,0.6,0.4,1.0);
uniform vec4 hair : source_color = vec4(0.3,0.2,0.15,1.0);
uniform bool head_part = false;
uniform bool construct = false;
void fragment() {
	vec3 base = texture(atlas, UV).rgb;
	float brightness = dot(base, vec3(0.2126,0.7152,0.0722));
	float saturation = max(base.r,max(base.g,base.b))-min(base.r,min(base.g,base.b));
	bool skin = base.r > 0.55 && base.g > 0.57 && base.r > base.g && base.g > base.b;
	if (construct) {
		base = clothing.rgb*(0.55+brightness*0.65);
	} else if (head_part) {
		bool colored_hair = saturation > 0.003 && base.g < 0.57 && brightness > 0.001;
		if (colored_hair && !skin) base = hair.rgb * (0.7 + brightness * 0.6);
	} else if (!skin && saturation > 0.12 && brightness > 0.1) {
		base = clothing.rgb * (0.58 + brightness * 0.75);
	}
	ALBEDO = base;
	ROUGHNESS = construct ? 0.68 : 0.82;
	METALLIC = construct ? 0.35 : 0.0;
}
