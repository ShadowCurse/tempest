#define UI_QUAD_USAGE_COLOR 0x00000000u
#define UI_QUAD_USAGE_TEXT  0x00000001u

#extension GL_EXT_buffer_reference : require

#include "types.glsl"

layout(buffer_reference, std430) readonly buffer Quads {
    Quad quads[];
};

layout(push_constant) uniform constants {
    TextPushConstant data;
} PushConstants;

Quad get_quad(uint idx) {
  return Quads(PushConstants.data.quads).quads[idx];
}

struct UiVertex {
    vec2 position;
    vec2 uv;
    vec4 color;
};

UiVertex[] ui_quad_vertices = {
  // Top
  {
    vec2(1.0, 1.0),
    vec2(1.0, 1.0),
    vec4(1.0, 0.0, 0.0, 1.0),
  },
  {
    vec2(1.0, -1.0),
    vec2(1.0, 0.0),
    vec4(0.0, 1.0, 0.0, 1.0),
  },
  {
    vec2(-1.0, -1.0),
    vec2(0.0, 0.0),
    vec4(0.0, 0.0, 1.0, 1.0),
  },
  // Bottom
  {
    vec2(-1.0, -1.0),
    vec2(0.0, 0.0),
    vec4(0.0, 0.0, 1.0, 1.0),
  },
  {
    vec2(-1.0, 1.0),
    vec2(0.0, 1.0),
    vec4(0.0, 1.0, 0.0, 1.0),
  },
  {
    vec2(1.0, 1.0),
    vec2(1.0, 1.0),
    vec4(0.0, 0.0, 1.0, 1.0),
  },
};

