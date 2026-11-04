shader_type spatial;
render_mode unshaded, cull_disabled;
uniform bool far_water = false;
varying vec3 world_point;
varying float depth;
void vertex() {
    world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    depth = far_water ? 1.0 : INSTANCE_CUSTOM.r;
}
void fragment() {
    float waves = sin(world_point.x * 2.4 + world_point.z * 1.3 + TIME * 0.7)
                * sin(world_point.z * 3.8 - TIME * 0.5);
    float glint = pow(max(0.0, waves), 14.0);
    vec3 shallow = vec3(0.16, 0.52, 0.61);
    vec3 deep = vec3(0.10, 0.32, 0.48);
    vec3 water = mix(shallow, deep, clamp(depth, 0.0, 1.0));
    float edge = far_water ? 0.0 : smoothstep(0.91, 0.985, UV.x);
    ALBEDO = water + waves * 0.018 + glint * 0.075 + edge * 0.045;
}
