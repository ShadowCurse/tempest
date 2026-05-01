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

// 2 f16 per curve point / 2 u16 per band
layout(buffer_reference, std430) readonly buffer CurvesBandsRef {
    uint data[];
};

Quad get_quad(uint idx) {
  return Quads(PushConstants.data.quads).quads[idx];
}

vec2[3] get_curve(uint idx) {
    CurvesBandsRef data = CurvesBandsRef(PushConstants.data.data_buffer);
    uint c_offset = PushConstants.data.curves_offset;
    return vec2[3](
        unpackHalf2x16(data.data[c_offset + idx * 3u / 2u + 0]),
        unpackHalf2x16(data.data[c_offset + idx * 3u / 2u + 1]),
        unpackHalf2x16(data.data[c_offset + idx * 3u / 2u + 2])
    );
}

uvec2 get_band(uint idx) {
    CurvesBandsRef data = CurvesBandsRef(PushConstants.data.data_buffer);
    uint b_offset = PushConstants.data.bands_offset;
    uint p = data.data[b_offset + idx];
    return uvec2(p & 0xFFFFu, p >> 16u);
}

struct UiVertex {
    vec2 position;
    vec2 uv;
};

UiVertex[] ui_quad_vertices = {
  // Top
  {
    vec2(1.0, 1.0),
    vec2(1.0, 1.0),
  },
  {
    vec2(1.0, -1.0),
    vec2(1.0, 0.0),
  },
  {
    vec2(-1.0, -1.0),
    vec2(0.0, 0.0),
  },
  // Bottom
  {
    vec2(-1.0, -1.0),
    vec2(0.0, 0.0),
  },
  {
    vec2(-1.0, 1.0),
    vec2(0.0, 1.0),
  },
  {
    vec2(1.0, 1.0),
    vec2(1.0, 1.0),
  },
};

