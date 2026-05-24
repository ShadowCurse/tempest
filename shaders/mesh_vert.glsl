#version 460

#include "mesh.glsl"

layout (location = 0) out vec3 out_color;

void main() {
    MeshPushConstant pc = PushConstants.data;
    SceneRef scene = SceneRef(pc.scene_buffer);

    Vertex vertex = get_vertex_from_mesh_bytes(gl_VertexIndex);
    vec4 p = scene.data.camera_projection * scene.data.camera_view * pc.transform * vec4(vertex.position, 1.0);
    gl_Position = p;
    vec3 n = normalize(mat3(pc.transform_inv) * vertex.normal);
    out_color = abs(n);
}
