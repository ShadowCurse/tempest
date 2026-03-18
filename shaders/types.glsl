#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

struct GridPushConstant {
    mat4 projection;
    mat4 view;
    vec3 camera_position;
};

struct TextPushConstant {
    uint64_t quads;
    vec2 screen_size;
    float scaling;
};

struct Quad {
    vec2 position;
    vec2 size;
    vec2 uv_offset;
    vec2 uv_size;
    uint usage;
    uint _;
};

