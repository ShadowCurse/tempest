#extension GL_EXT_buffer_reference : require

#include "types.glsl"

layout(buffer_reference, std430) readonly buffer MeshBytesRef {
    uint bytes[];
};
layout(buffer_reference, std430) readonly buffer SceneRef {
    SceneInfo data;
};
layout(push_constant) uniform constants {
    MeshPushConstant data;
} PushConstants;

Vertex get_vertex_from_mesh_bytes(uint vertex_idx) {
  MeshPushConstant pc = PushConstants.data;
  MeshBytesRef bytes = MeshBytesRef(pc.mesh_buffer);
  uint base_offset = pc.vertices_offset / 4 + vertex_idx * 48 / 4;
  Vertex result = Vertex(
      vec3(
        uintBitsToFloat(bytes.bytes[base_offset + 0]),
        uintBitsToFloat(bytes.bytes[base_offset + 1]),
        uintBitsToFloat(bytes.bytes[base_offset + 2])
      ),
      uintBitsToFloat(bytes.bytes[base_offset + 3]),
      vec3(
        uintBitsToFloat(bytes.bytes[base_offset + 4]),
        uintBitsToFloat(bytes.bytes[base_offset + 5]),
        uintBitsToFloat(bytes.bytes[base_offset + 6])
      ),
      uintBitsToFloat(bytes.bytes[base_offset + 7]),
      vec3(
        uintBitsToFloat(bytes.bytes[base_offset + 8]),
        uintBitsToFloat(bytes.bytes[base_offset + 9]),
        uintBitsToFloat(bytes.bytes[base_offset + 10])
      ),
      uintBitsToFloat(bytes.bytes[base_offset + 11])
  );
  return result;
}
