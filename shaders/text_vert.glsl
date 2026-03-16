#version 460

#extension GL_EXT_buffer_reference : require

#include "ui.glsl"

layout (location = 0) out vec3 outColor;
layout (location = 1) out vec2 outUV;
layout (location = 2) out int outInstanceId;

layout(buffer_reference, std430) readonly buffer Quads {
    UiQuad quads[];
};

layout(push_constant) uniform constants {
    Quads quads;
    vec2 screen_size;
    float scaling;
} PushConstants;

void main() {
    UiVertex v = ui_quad_vertices[gl_VertexIndex];
    UiQuad sq = PushConstants.quads.quads[gl_InstanceIndex];
    vec2 screen_size = PushConstants.screen_size;

    vec2 vertex_position = v.position;
    vec2 qp = sq.position;
    vec2 quad_pos = (qp / (screen_size / 2.0)) - vec2(1.0);
    vec2 quad_size = sq.size / screen_size;
    vec4 new_position = vec4(
        (vertex_position * quad_size + quad_pos),
        1.0,
        1.0);
    gl_Position = vec4(new_position.xy, 1.0, 1.0);

    outColor = v.color.xyz;
    outUV = v.uv;
    outInstanceId = gl_InstanceIndex;
}
