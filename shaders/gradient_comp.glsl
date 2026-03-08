#version 460

layout (local_size_x = 16, local_size_y = 16) in;
layout(set = 0, binding = 0) uniform writeonly image2D image;
layout(set = 0, binding = 1) uniform sampler2D font_texture;
layout(push_constant) uniform constants
{
   float time;
} PushConstants;

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

void main() {
    ivec2 texel_coord  = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size         = imageSize(image);
    ivec2 font_size    = textureSize(font_texture, 0);
    vec4 top_color     = vec4(0.0, 0.0, 0.0, 1.0);
    vec4 bottom_color  = vec4(0.3, 0.0, 0.4, 1.0);
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
    // if (texel_coord.x < size.x && texel_coord.y < size.y) {
        //float blend = float(texel_coord.y) / (size.y) * sin(PushConstants.time);
        //imageStore(image, texel_coord, mix(top_color, bottom_color, blend));
    if (texel_coord.x < width && texel_coord.y < height) {
        vec2 uv = (texel_coord / scale + uvs.xy) / vec2(font_size);
        vec4 mtsdf = textureLod(font_texture, uv, 0.0);
        float d = median(mtsdf.r, mtsdf.g, mtsdf.b) - 0.5;
        float screen_px_distance = d * 2 * scale;
        float opacity = clamp(screen_px_distance + 0.5, 0.0, 1.0);
        float outline_factor = clamp(screen_px_distance + outline + 0.5, 0.0, 1.0);
        vec4 color = mix(bg_color, outline_color, outline_factor);
        color = mix(color, fg_color, opacity);
        imageStore(image, texel_coord, color);
    }
}

