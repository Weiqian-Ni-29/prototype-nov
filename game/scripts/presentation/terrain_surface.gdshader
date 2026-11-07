shader_type spatial;
uniform vec4 ground_color : source_color = vec4(0.5,0.6,0.4,1.0);
uniform int biome = 0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
    float wash = noise(UV*8.0)*0.10+noise(UV*24.0)*0.04-0.07;
    float grain = (hash(floor(UV*220.0))-0.5)*0.035;
    float strokes = smoothstep(0.87,0.94,noise(vec2(UV.x*40.0,UV.y*160.0)))*0.035;
    if (biome==4) strokes = sin(UV.y*100.0+noise(UV*5.0)*8.0)*0.022;
    if (biome==2 || biome==3) strokes -= smoothstep(0.80,0.88,noise(UV*35.0))*0.045;
    ALBEDO = ground_color.rgb*(1.0+wash+grain+strokes);
    ROUGHNESS = 0.95;
}
