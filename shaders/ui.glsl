#define UI_QUAD_USAGE_TEXT  0x00000000u
#define UI_QUAD_USAGE_COLOR 0x00000001u

struct UiQuad3d {
    vec3 position;
    uint usage;
    vec2 size;
    vec2 uv_offset;
    vec2 uv_size;
    vec2 _;
};

struct UiQuad2d {
    vec2 position;
    vec2 size;
    vec2 uv_offset;
    vec2 uv_size;
    uint usage;
    uint _;
};

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

