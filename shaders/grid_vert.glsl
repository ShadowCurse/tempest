#version 460
#extension GL_EXT_buffer_reference : require
#include "types.glsl"

layout (location = 0) out vec3 out_near;
layout (location = 1) out vec3 out_far;

layout(buffer_reference, std430) readonly buffer SceneRef {
    Scene data;
};
layout(push_constant) uniform constants {
  GridPushConstant data;
} PushConstants;

vec2 grid_triangle[3] = vec2[](
    vec2(-1.0,  1.0),
    vec2(-1.0, -3.0),
    vec2( 3.0,  1.0)
);

vec3 clip_to_world(vec3 point) {
  SceneRef scene = SceneRef(PushConstants.data.scene_buffer);
  mat4 view_inv = scene.data.camera_view_inv;
  mat4 proj_inv = inverse(scene.data.camera_projection);
  vec4 world = view_inv * proj_inv * vec4(point, 1.0);
  return world.xyz / world.w;
}

void main() {
    vec2 point = grid_triangle[gl_VertexIndex];
    vec3 world_near = clip_to_world(vec3(point.xy, 1.0));
    vec3 world_far = clip_to_world(vec3(point.xy, 0.0));

    out_near = world_near;
    out_far = world_far;
    gl_Position = vec4(point, 0.0, 1.0);
}
