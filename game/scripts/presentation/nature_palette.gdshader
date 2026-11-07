shader_type spatial;
#include "res://scripts/presentation/nature_pigment.gdshaderinc"
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
varying vec3 world_point;
void vertex() {
    world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    ALBEDO = painted_nature(texture(atlas, UV).rgb, world_point);
    ROUGHNESS = 0.9;
}
