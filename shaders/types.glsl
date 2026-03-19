#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

struct Vertex {
    vec3 position;
    float uv_x;
    vec3 normal;
    float uv_y;
    vec3 color;
    float _;
};

struct Scene {
    mat4 camera_view;
    mat4 camera_view_inv;
    mat4 camera_projection;
};

struct MeshPushConstant {
    uint64_t mesh_buffer;
    uint64_t scene_buffer;
    uint vertices_offset;
};

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

