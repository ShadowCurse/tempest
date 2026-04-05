#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#define VkDeviceAddress uint64_t

struct Scene {
    mat4 camera_view;
    mat4 camera_view_inv;
    mat4 camera_projection;
};

struct MeshPushConstant {
    mat4 transform;
    VkDeviceAddress mesh_buffer;
    VkDeviceAddress scene_buffer;
    uint vertices_offset;
};

struct GridPushConstant {
    VkDeviceAddress scene_buffer;
};

struct TextPushConstant {
    VkDeviceAddress quads;
    vec2 screen_size;
    float scaling;
};

struct Vertex {
    vec3 position;
    float uv_x;
    vec3 normal;
    float uv_y;
    vec3 color;
    float _;
};

#define QuadUsage uint
struct Quad {
    vec2 position;
    vec2 size;
    vec2 uv_offset;
    vec2 uv_size;
    QuadUsage usage;
    uint _;
};

