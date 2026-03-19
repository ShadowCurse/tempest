#version 460

#include "mesh.glsl"

layout (location = 0) out vec3 outColor;

void main() {
    MeshPushConstant pc = PushConstants.data;
    SceneRef scene = SceneRef(pc.scene_buffer);

    Vertex vertex = get_vertex_from_mesh_bytes(gl_VertexIndex);
    vec4 p = scene.data.camera_projection * scene.data.camera_view * vec4(vertex.position, 1.0);
    gl_Position = p;
    outColor = abs(vertex.color);
}
