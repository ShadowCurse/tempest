#version 460

#include "ui.glsl"

//shader input
layout (location = 0) in vec3 inColor;
layout (location = 1) in vec2 inUV;
layout (location = 2) flat in int inInstanceId;

//output write
layout (location = 0) out vec4 outFragColor;

layout(set = 0, binding = 0) uniform sampler2D text_texture;

#define bg_color      vec4(0.0)
#define fg_color      vec4(1.0)

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

vec4 rgba_to_vec4(uint rgba) {
  return vec4(
    ((rgba >> 24) & 0xff) / 255.0,
    ((rgba >> 16) & 0xff) / 255.0,
    ((rgba >> 8)  & 0xff) / 255.0,
    ((rgba >> 0)  & 0xff) / 255.0
  );
}

void main() {
    Quad sq = get_quad(inInstanceId);
    if (sq.usage == UI_QUAD_USAGE_TEXT) {
        vec2 size = textureSize(text_texture, 0);
        vec2 uv_offset = sq.uv_offset / size;
        vec2 uv_size = sq.uv_size / size;
        vec4 mtsdf = texture(text_texture, inUV * uv_size + uv_offset);

        float d = median(mtsdf.r, mtsdf.g, mtsdf.b);
        float screen_px_distance = PushConstants.data.scaling * (d - 0.5);
        float opacity = clamp(screen_px_distance + 0.5, 0.0, 1.0);
        vec4 color = mix(bg_color, fg_color, opacity);

        outFragColor = color;
    }
    if (sq.usage == UI_QUAD_USAGE_COLOR) {
        // transform UV to physical pixel coordinates
        vec2 pixel_coord = (inUV - 0.5) * sq.size;

        vec2 half_extents = sq.size * 0.5;
        float radius = 8.0;
        float border_width_px = sq.uv_size.x;

        // Move centrer of corrdinate spacef from center of the rectangle
        // to the center of the cornere circle.
        // - The distance to the center of the corner circle is (half_extents - radius)
        // - To move coordinate system center to it we sub this value from pixel_coord
        vec2 q = abs(pixel_coord) - half_extents + radius;
        // After moving the coorinate system the final point can be in one of 4 quadrants
        //    1   |      0
        // ----------\
        //        |   |
        //   ____(*) _|____
        //    3    |   |  2
        //
        // In 0, points are outside the shape
        // In 1/2, points are also outside the shape
        // In 3, points are inside the shape
        // The first term min(max(q.x, q.y), 0.0) is for points in 1,2,3 regions since at least
        // one component needs to be negative for this to have any non 0 value
        // The second term length(max(q, vec2(0.0))) is for 0,1,2 regions. For 1,2 regions this is
        // an orthogonal distance to the borders of the rectangle. For 0 region this is just a circular
        // distance to the center of the corner.
        // Adding both terms yeilds the SDF for the 'sharp' rectangle. Subtracting `radius` moves
        // SDF values closer so the rounded corners are closer to the circle center.
        float dist = min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;

        vec4 _bg_color = rgba_to_vec4(floatBitsToUint(sq.uv_offset.x));
        vec4 _border_color = rgba_to_vec4(floatBitsToUint(sq.uv_offset.y));

        float edge_aa = fwidth(dist);
        float outer_mask = 1.0 - smoothstep(-edge_aa, 0.0, dist);
        float fill_mask = 1.0 - smoothstep(-edge_aa, 0.0, dist + border_width_px);
        float border_mask = outer_mask - fill_mask;

        vec4 color = mix(_bg_color, _border_color, border_mask);
        color.a *= outer_mask;

        outFragColor = color;
    }
}
