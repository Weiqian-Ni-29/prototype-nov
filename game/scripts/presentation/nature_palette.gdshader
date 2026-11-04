shader_type spatial;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
void fragment() {
    vec3 c = texture(atlas, UV).rgb;
    float grey = dot(c,vec3(0.2126,0.7152,0.0722));
    c = mix(vec3(grey),c,0.65);
    if (c.g>c.r*1.12 && c.g>c.b*1.25) c *= vec3(0.65,0.76,0.87);
    ALBEDO = c;
    ROUGHNESS = 0.9;
}
