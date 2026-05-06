#version 460

#extension GL_EXT_buffer_reference : require

#include "ui.glsl"

layout (location = 0) out vec2 outUV;
layout (location = 1) out int  outInstanceId;
layout (location = 2) out vec2 v_texcoord;

void main() {
    Quad sq = get_quad(gl_InstanceIndex);
    UiVertex v = ui_quad_vertices[gl_VertexIndex];
    vec2 screen_size = PushConstants.data.screen_size;

    vec2 vertex_position = v.position;
    vec2 qp = sq.position;
    vec2 quad_pos = (qp / (screen_size / 2.0)) - vec2(1.0);
    vec2 quad_size = sq.size / screen_size;
    vec4 new_position = vec4(
        (vertex_position * quad_size + quad_pos),
        1.0,
        1.0);
    gl_Position = vec4(new_position.xy, 1.0, 1.0);

    const vec2 tex_coords[6] = vec2[6](
        vec2(sq.tex.z, sq.tex.w),
        vec2(sq.tex.z, sq.tex.y),
        vec2(sq.tex.x, sq.tex.y),
        vec2(sq.tex.x, sq.tex.y),
        vec2(sq.tex.x, sq.tex.w),
        vec2(sq.tex.z, sq.tex.w)
    );

    outUV = v.uv;
    outInstanceId = gl_InstanceIndex;
    v_texcoord = tex_coords[gl_VertexIndex];
}
