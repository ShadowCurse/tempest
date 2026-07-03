#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#define VkDeviceAddress uint64_t

#define RGBA uint
struct DebugMeshIndirectCommand {
    uint vertex_count;
    uint instance_count;
    uint first_vertex;
    uint first_instance;
    uint vertex_offset;
    RGBA color;
};

struct DebugMeshPushConstant {
    VkDeviceAddress scene_buffer;
    VkDeviceAddress vertex_buffer;
    VkDeviceAddress cmd_buffer;
};

struct GizmoPushConstant {
    VkDeviceAddress scene_buffer;
    VkDeviceAddress mesh_buffer;
    VkDeviceAddress instance_buffer;
    uint vertex_offset;
    uint instance_buffer_offset;
};

struct GridPushConstant {
    VkDeviceAddress scene_buffer;
};

struct MeshPushConstant {
    mat4 transform;
    mat4 transform_inv;
    VkDeviceAddress mesh_buffer;
    VkDeviceAddress scene_buffer;
    uint vertex_offset;
};

struct SceneInfo {
    mat4 camera_view;
    mat4 camera_view_inv;
    mat4 camera_projection;
};

struct UiPushConstant {
    VkDeviceAddress quads;
    vec2 screen_size;
    VkDeviceAddress data_buffer;
    uint curves_offset;
    uint bands_offset;
};

#define UiQuadUsage uint
#define RGBA uint
struct UiQuad {
    UiQuadUsage usage;
    RGBA color;
    vec2 position;
    vec4 tex;
    vec2 size;
    uint glyph_band_texel;
    uint band_min_max;
    vec2 band_scale;
    vec2 band_offset;
};

struct Vertex {
    vec3 position;
    float uv_x;
    vec3 normal;
    float uv_y;
    vec3 color;
    float _;
};

