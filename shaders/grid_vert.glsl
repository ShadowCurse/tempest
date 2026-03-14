#version 460

layout (location = 0) out vec3 out_near;
layout (location = 1) out vec3 out_far;

layout(push_constant) uniform constants {
    mat4 projection;
    mat4 view;
    vec4 limits;
    float scale;
} PushConstants;

vec2 grid_triangle[3] = vec2[](
    vec2(-1.0,  1.0),
    vec2(-1.0, -3.0),
    vec2( 3.0,  1.0)
);

vec3 clip_to_world(vec3 point) {
  mat4 inv_view = inverse(PushConstants.view);
  mat4 inv_proj = inverse(PushConstants.projection);
  vec4 world = inv_view * inv_proj * vec4(point, 1.0);
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
