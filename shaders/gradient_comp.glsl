#version 460

layout (local_size_x = 16, local_size_y = 16) in;
layout(set = 0, binding = 0) uniform writeonly image2D image;
layout(set = 0, binding = 1) uniform sampler2D font_texture;
layout(push_constant) uniform constants
{
   float time;
} PushConstants;

void main() {
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size        = imageSize(image);
    ivec2 font_size   = textureSize(font_texture, 0);
    vec4 top_color    = vec4(0.0, 0.0, 0.0, 1.0);
    vec4 bottom_color = vec4(0.3, 0.0, 0.4, 1.0);

    if (texel_coord.x < size.x && texel_coord.y < size.y) {
        //float blend = float(texel_coord.y) / (size.y) * sin(PushConstants.time);
        //imageStore(image, texel_coord, mix(top_color, bottom_color, blend));
        vec2 uv = (texel_coord + 0.5) / vec2(font_size);
        vec4 color = textureLod(font_texture, uv, 0.0);
        color.a = 1.0;
        imageStore(image, texel_coord, color);
    }
}

