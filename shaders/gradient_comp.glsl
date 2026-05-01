#version 460

layout (local_size_x = 16, local_size_y = 16) in;
layout(set = 0, binding = 0) uniform writeonly image2D image;
layout(push_constant) uniform constants
{
   float time;
} PushConstants;

void main() {
    ivec2 texel_coord  = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size         = imageSize(image);
    vec4 top_color     = vec4(0.0, 0.0, 0.0, 1.0);
    vec4 bottom_color  = vec4(0.38, 0.50, 0.19, 1.0);
    vec4 bg_color      = vec4(0.1, 0.4, 0.45, 1.0);
    vec4 fg_color      = vec4(1.0);
    vec4 outline_color = vec4(0.0);

    vec4 uvs      = vec4(40.5,146.5,63.5,172.5);
    float width   = uvs.z - uvs.x;
    float height  = uvs.w - uvs.y;
    float scale   = 20.0;
    float outline = 1.5;
    width  *= scale;
    height *= scale;
    if (texel_coord.x < size.x && texel_coord.y < size.y) {
        float blend = float(texel_coord.y) / (size.y) * sin(PushConstants.time);
        imageStore(image, texel_coord, mix(top_color, bottom_color, blend));
    }
}

