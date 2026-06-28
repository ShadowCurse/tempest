#version 460

#extension GL_EXT_buffer_reference : require

#include "types.glsl"

layout(buffer_reference, std430) readonly buffer PositionsBytesRef {
    uint bytes[];
};
layout(buffer_reference, std430) readonly buffer SceneRef {
    SceneInfo data;
};
layout(push_constant) uniform constants {
    DebugMeshPushConstant data;
} PushConstants;

layout (location = 0) out vec4 out_color;

vec4 rgba_to_vec4(uint rgba) {
  return vec4(
    float((rgba >> 24) & 0xff) / 255.0f,
    float((rgba >> 16) & 0xff) / 255.0f,
    float((rgba >> 8)  & 0xff) / 255.0f,
    float((rgba >> 0)  & 0xff) / 255.0f
  );
}

vec3 get_vertex_position_from_bytes(uint vertex_idx) {
  DebugMeshPushConstant pc = PushConstants.data;
  PositionsBytesRef bytes = PositionsBytesRef(pc.vertex_buffer);
  uint base_offset = vertex_idx * 3;
  return vec3(
    uintBitsToFloat(bytes.bytes[base_offset + 0]),
    uintBitsToFloat(bytes.bytes[base_offset + 1]),
    uintBitsToFloat(bytes.bytes[base_offset + 2])
  );
}

void main() {
    DebugMeshPushConstant pc = PushConstants.data;
    SceneRef scene = SceneRef(pc.scene_buffer);

    vec3 position = get_vertex_position_from_bytes(pc.vertex_offset + gl_VertexIndex);
    gl_Position = scene.data.camera_projection *
                  scene.data.camera_view *
                  vec4(position, 1.0);
    out_color = rgba_to_vec4(pc.color);
}
