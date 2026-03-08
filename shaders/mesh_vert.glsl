#version 460

#extension GL_EXT_buffer_reference : require

#include "mesh.glsl"

layout (location = 0) out vec3 outColor;

void main() {
    uint index = get_index_from_mesh_bytes(gl_VertexIndex);
    DefaultVertex vertex = get_vertex_from_mesh_bytes(index);

    uint instance_offset = PushConstants.instance_buffer_offset / (16 * 4);
    mat4 transform = PushConstants.mesh_instances.instances[instance_offset + gl_InstanceIndex];

    vec4 p = PushConstants.scene.projection * inverse(PushConstants.scene.camera) * transform * vec4(vertex.position, 1.0);
    gl_Position = p;
    outColor = abs(vertex.color);
}
