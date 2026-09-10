shader_type spatial;
render_mode diffuse_burley;
varying vec3 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec2 cell = abs(fract(world_position.xz / 2.0 - 0.5) - 0.5);
    vec2 line = cell / max(fwidth(world_position.xz / 2.0), vec2(0.001));
    float grid = 1.0 - min(min(line.x, line.y), 1.0);
    float radius = length(world_position.xz);
    float ring = 1.0 - smoothstep(0.025, 0.07, abs(radius - 5.0));
    vec3 base = mix(vec3(0.17, 0.23, 0.23), vec3(0.20, 0.27, 0.26), 1.0 - smoothstep(0.0, 19.0, radius));
    ALBEDO = mix(base, vec3(0.30, 0.38, 0.35), max(grid * 0.21, ring * 0.42));
    ROUGHNESS = 0.96;
}
