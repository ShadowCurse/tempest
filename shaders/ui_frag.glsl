#version 460

#include "ui.glsl"

//shader input
layout (location = 0)      in vec2 inUV;
layout (location = 1) flat in int  inInstanceId;
layout (location = 2)      in vec2 v_texcoord;

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
    float((rgba >> 24) & 0xff) / 255.0f,
    float((rgba >> 16) & 0xff) / 255.0f,
    float((rgba >> 8)  & 0xff) / 255.0f,
    float((rgba >> 0)  & 0xff) / 255.0f
  );
}

uint calculate_root_code(float y1, float y2, float y3) {
    uint i1 = floatBitsToUint(y1) >> 31u;
    uint i2 = floatBitsToUint(y2) >> 30u;
    uint i3 = floatBitsToUint(y3) >> 29u;

    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift = (i3 & 4u) | (shift & ~4u);

    return ((0x2E74u >> shift) & 0x0101u);
}

vec2 solve_horizontal_poly(vec2[3] p123) {
    vec2 a = p123[0] - p123[1] * 2.0 + p123[2];
    vec2 b = p123[0] - p123[1];
    float ra = 1.0 / a.y;
    float rb = 0.5 / b.y;

    float d = sqrt(max(b.y * b.y - a.y * p123[0].y, 0.0));
    float t1 = (b.y - d) * ra;
    float t2 = (b.y + d) * ra;

    if (abs(a.y) < 1.0 / 65536.0) {
        t1 = p123[0].y * rb;
        t2 = t1;
    }

    return vec2((a.x * t1 - b.x * 2.0) * t1 + p123[0].x,
                (a.x * t2 - b.x * 2.0) * t2 + p123[0].x);
}

vec2 solve_vertical_poly(vec2[3] p123) {
    vec2 a = p123[0] - p123[1] * 2.0 + p123[2];
    vec2 b = p123[0] - p123[1];
    float ra = 1.0 / a.x;
    float rb = 0.5 / b.x;

    float d = sqrt(max(b.x * b.x - a.x * p123[0].x, 0.0));
    float t1 = (b.x - d) * ra;
    float t2 = (b.x + d) * ra;

    if (abs(a.x) < 1.0 / 65536.0) {
        t1 = p123[0].x * rb;
        t2 = t1;
    }

    return vec2((a.y * t1 - b.y * 2.0) * t1 + p123[0].y,
                (a.y * t2 - b.y * 2.0) * t2 + p123[0].y);
}

float calculate_coverage(float xcov, float ycov, float xwgt, float ywgt) {
    float coverage = max(
        abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0),
        min(abs(xcov), abs(ycov))
    );
    coverage = clamp(coverage, 0.0, 1.0);
    return coverage;
}

vec4 draw_glyph() {
    Quad sq = get_quad(inInstanceId);

    vec2 em_per_pixel = fwidth(v_texcoord);
    vec2 pixels_per_em = 1.0 / em_per_pixel;

    uvec2 band_max = uvec2(sq.band_min_max & 0xFFFFu, sq.band_min_max >> 16u);
    band_max.y &= uint(0x00FF);

    uvec2 band_index = clamp(uvec2(v_texcoord * sq.band_scale + sq.band_offset),
                            uvec2(0), band_max);
    uint glyph_loc = sq.glyph_band_texel;

    float xcov = 0.0;
    float xwgt = 0.0;

    uvec2 hband_data = get_band(glyph_loc + band_index.y);
    uint hband_loc = glyph_loc + hband_data.y;

    for (uint curve_index = uint(0); curve_index < hband_data.x; curve_index++) {
        uint curve_loc  = get_band(hband_loc + curve_index).x;

        vec2[3] p123 = get_curve(curve_loc);
        p123[0] -= v_texcoord;
        p123[1] -= v_texcoord;
        p123[2] -= v_texcoord;

        if (max(max(p123[0].x, p123[1].x), p123[2].x) * pixels_per_em.x < -0.5) break;

        uint code = calculate_root_code(p123[0].y, p123[1].y, p123[2].y);
        if (code != 0u) {
            vec2 r = solve_horizontal_poly(p123) * pixels_per_em.x;

            if ((code & 1u) != 0u) {
                xcov += clamp(r.x + 0.5, 0.0, 1.0);
                xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
            }

            if (code > 1u) {
                xcov -= clamp(r.y + 0.5, 0.0, 1.0);
                xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
            }
        }
    }

    float ycov = 0.0;
    float ywgt = 0.0;

    uvec2 vband_data = get_band(glyph_loc + band_index.x + band_max.y + 1);
    uint vband_loc = glyph_loc + vband_data.y;

    for (uint curve_index = uint(0); curve_index < vband_data.x; curve_index++) {
        uint curve_loc  = get_band(vband_loc + curve_index).x;

        vec2[3] p123 = get_curve(curve_loc);
        p123[0] -= v_texcoord;
        p123[1] -= v_texcoord;
        p123[2] -= v_texcoord;

        if (max(max(p123[0].y, p123[1].y), p123[2].y) * pixels_per_em.y < -0.5) break;

        uint code = calculate_root_code(p123[0].x, p123[1].x, p123[2].x);
        if (code != 0u) {
            vec2 r = solve_vertical_poly(p123) * pixels_per_em.y;

            if ((code & 1u) != 0u) {
                ycov -= clamp(r.x + 0.5, 0.0, 1.0);
                ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
            }

            if (code > 1u) {
                ycov += clamp(r.y + 0.5, 0.0, 1.0);
                ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
            }
        }
    }

    float coverage = calculate_coverage(xcov, ycov, xwgt, ywgt);
    return rgba_to_vec4(sq.color) * coverage;
}

void main() {
    Quad sq = get_quad(inInstanceId);
    if (sq.usage == UI_QUAD_USAGE_TEXT) {
        outFragColor = draw_glyph();
    }
    if (sq.usage == UI_QUAD_USAGE_COLOR) {
        // transform UV to physical pixel coordinates
        vec2 pixel_coord = (inUV - 0.5) * sq.size;

        vec2 half_extents = sq.size * 0.5;
        float radius = 8.0;
        float border_width_px = sq.tex.x;

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

        vec4 _bg_color = rgba_to_vec4(sq.color);
        vec4 _border_color = rgba_to_vec4(sq.glyph_band_texel);

        float edge_aa = fwidth(dist);
        float outer_mask = 1.0 - smoothstep(-edge_aa, 0.0, dist);
        float fill_mask = 1.0 - smoothstep(-edge_aa, 0.0, dist + border_width_px);
        float border_mask = outer_mask - fill_mask;

        vec4 color = mix(_bg_color, _border_color, border_mask);
        color.a *= outer_mask;

        outFragColor = color;
    }
}
