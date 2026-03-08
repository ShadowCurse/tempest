#version 460

#extension GL_EXT_buffer_reference : require

#include "ui.glsl"

//shader input
layout (location = 0) in vec3 inColor;
layout (location = 1) in vec2 inUV;
layout (location = 2) flat in int inInstanceId;

//output write
layout (location = 0) out vec4 outFragColor;

layout(set = 0, binding = 0) uniform sampler2D text_texture;

layout(buffer_reference, std430) readonly buffer Quads {
    UiQuad2d quads[];
};

layout(push_constant) uniform constants {
    Quads quads;
    vec2 screen_size;
    float v;
} PushConstants;

void main() {
    UiQuad2d sq = PushConstants.quads.quads[inInstanceId];
    if (sq.usage == UI_QUAD_USAGE_TEXT) {
        vec2 size = textureSize(text_texture, 0);
        vec2 uv_offset = sq.uv_offset / size;
        vec2 uv_size = sq.uv_size / size;
        // vec4 color = texture(text_texture, inUV * uv_size + uv_offset).rrrr;
        // outFragColor = color;
        float v = texture(text_texture, inUV * uv_size + uv_offset).r;
        if (PushConstants.v < v) {
          outFragColor = vec4(1.0);
        } else {
          outFragColor = vec4(0.0);
        }
    }
    if (sq.usage == UI_QUAD_USAGE_COLOR) {
        vec4 color = vec4(sq.uv_offset.xy, sq.uv_size.xy);
        outFragColor = color;
    }
}
