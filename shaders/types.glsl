#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#define VkDeviceAddress uint64_t

struct SceneInfo {
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
    VkDeviceAddress data_buffer;
    uint curves_offset;
    uint bands_offset;
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
#define RGBA uint
struct Quad {
    QuadUsage usage;
    RGBA color;
    vec2 position;
    vec4 tex;
    vec2 size;
    uint glyph_band_texel;
    uint band_min_max;
    vec2 band_scale;
    vec2 band_offset;
};

