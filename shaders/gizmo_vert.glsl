#version 460

#include "gizmo.glsl"

layout (location = 0) out vec3 out_color;

void main() {
    GizmoPushConstant pc = PushConstants.data;
    SceneRef scene = SceneRef(pc.scene_buffer);

    Vertex vertex = get_vertex_from_mesh_bytes(gl_VertexIndex);
    mat4 transform = get_instance_transform(gl_InstanceIndex);
    vec4 p = scene.data.camera_projection * scene.data.camera_view * transform * vec4(vertex.position, 1.0);
    gl_Position = p;
    out_color = vec3(gl_InstanceIndex == 0 ? 1.0 : 0.0,
                     gl_InstanceIndex == 1 ? 1.0 : 0.0,
                     gl_InstanceIndex == 2 ? 1.0 : 0.0);
}
