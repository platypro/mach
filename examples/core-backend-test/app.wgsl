@group(0) @binding(0) var<uniform> xform : mat4x4<f32>;

struct FragPass {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
};

@vertex fn vertMain(
    @location(0) Vertex: vec2<f32>,
    @location(1) Color: vec3<f32>,
) -> FragPass {
    var result: FragPass;
    result.position = xform * vec4<f32>(Vertex, 0.0, 1.0);
    result.color = vec4<f32>(Color, 1.0);
    return result;
}

@fragment fn fragMain(
    @location(0) Color: vec4<f32>
) -> @location(0) vec4<f32> {
    return Color;
}
