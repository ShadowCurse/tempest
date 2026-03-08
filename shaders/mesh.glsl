struct DefaultVertex {
    vec3 position;
    float uv_x;
    vec3 normal;
    float uv_y;
    vec3 color;
    float _;
};

layout(buffer_reference, std430) readonly buffer MeshBytes {
    uint bytes[];
};
layout(buffer_reference, std430) readonly buffer MeshInstances {
    mat4 instances[];
};
layout(buffer_reference, std430) readonly buffer Scene {
    mat4 camera;
    mat4 projection;
    mat4 cube_transform;
};
layout(push_constant) uniform constants {
    MeshBytes mesh_bytes;
    MeshInstances mesh_instances;
    uint index_buffer_offset;
    uint vertex_buffer_offset;
    uint instance_buffer_offset;
    Scene scene;
} PushConstants;

uint get_index_from_mesh_bytes(uint index_idx) {
  uint result = PushConstants.mesh_bytes.bytes[PushConstants.index_buffer_offset / 4 + index_idx];
  return result;
}

DefaultVertex  get_vertex_from_mesh_bytes(uint vertex_idx) {
  uint base_offset = PushConstants.vertex_buffer_offset / 4 + vertex_idx * 48 / 4;
  DefaultVertex result = DefaultVertex(
      vec3(
        uintBitsToFloat(PushConstants.mesh_bytes.bytes[base_offset + 0]),
        uintBitsToFloat(PushConstants.mesh_bytes.bytes[base_offset + 1]),
        uintBitsToFloat(PushConstants.mesh_bytes.bytes[base_offset + 2])
      ),
      uintBitsToFloat(PushConstants.mesh_bytes.bytes[base_offset + 4]),
      vec3(
        uintBitsToFloat(PushConstants.mesh_bytes.bytes[base_offset + 5]),
        uintBitsToFloat(PushConstants.mesh_bytes.bytes[base_offset + 6]),
        uintBitsToFloat(PushConstants.mesh_bytes.bytes[base_offset + 7])
      ),
      uintBitsToFloat(PushConstants.mesh_bytes.bytes[base_offset + 8]),
      vec3(
        uintBitsToFloat(PushConstants.mesh_bytes.bytes[base_offset + 9]),
        uintBitsToFloat(PushConstants.mesh_bytes.bytes[base_offset + 10]),
        uintBitsToFloat(PushConstants.mesh_bytes.bytes[base_offset + 11])
      ),
      uintBitsToFloat(PushConstants.mesh_bytes.bytes[base_offset + 12])
  );
  return result;
}
