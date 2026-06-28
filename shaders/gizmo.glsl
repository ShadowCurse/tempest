#extension GL_EXT_buffer_reference : require

#include "types.glsl"

layout(buffer_reference, std430) readonly buffer MeshBytesRef {
    uint bytes[];
};
layout(buffer_reference, std430) readonly buffer InstancesRef {
    mat4 instances[];
};
layout(buffer_reference, std430) readonly buffer SceneRef {
    SceneInfo data;
};
layout(push_constant) uniform constants {
    GizmoPushConstant data;
} PushConstants;

Vertex get_vertex_from_mesh_bytes(uint vertex_idx) {
  GizmoPushConstant pc = PushConstants.data;
  MeshBytesRef bytes = MeshBytesRef(pc.mesh_buffer);
  uint base_offset = pc.vertex_offset / 4 + vertex_idx * 48 / 4;
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

mat4 get_instance_transform(uint instance_idx) {
  GizmoPushConstant pc = PushConstants.data;
  InstancesRef instances = InstancesRef(pc.instance_buffer);
  uint index = pc.instance_buffer_offset + instance_idx;
  return instances.instances[index];
}
