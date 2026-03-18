#version 460

layout (location = 0) in vec3 in_near;
layout (location = 1) in vec3 in_far;

layout (location = 0) out vec4 out_color;

#include "types.glsl"

layout(push_constant) uniform constants {
  GridPushConstant data;
} PushConstants;

#define LINE_WIDTH 2.0
#define LINE_COLOR vec3(0.2, 0.2, 0.2)
#define FADE_DISTANCE 100.0

// world_pos - world position of the fragment
// scale - distance between lines, high == more distance
vec4 grid_point_color(vec3 world_pos, float scale) {
  // scale world by the `scale`
  vec2 coord = world_pos.xy / scale;

  // calculate how did the `coord` change over neighbouring pixels
  // since we use `coord` and not `world_pos`, the diff is also scaled
  // by the `scale` factor
  // The multiplication by the `LINE_WIDTH`, changes the .. line width
  vec2 d = LINE_WIDTH * fwidth(coord);

  vec4 axis_colors = vec4(0.0);
  if (-d.y / 2.0 < coord.y && coord.y < d.y / 2.0)
      axis_colors.r = 1.0;
  if (-d.x / 2.0 < coord.x && coord.x < d.x / 2.0)
      axis_colors.g = 1.0;

  // move the world by half the square, so the lines will align
  // with x/y lines
  coord -= 0.5;
  // after scaling by `scale`, the `coord` still is unbounded.
  // using `fract` moves any `coord` into 0..1 scale
  coord = fract(coord);
  // now move 0..1 into -0.5..0.5
  coord -= 0.5;
  // this clamps -0.5..0.5 into just 0..0.5
  // this makes values which were close to 0 or 1 to be close to 0.5, while
  // everythin in bettween gets values lower than 0.5
  // 1.0 -> 0.5
  // .   -> 0.0
  // -----------
  // .   -> 0.0
  // 0.0 -> 0.5
  coord = abs(coord);

  // now the `coord` will already look like a grid in some sence. If `min(coord.x, coord.y)`
  // is used as a final color, the grid will look like a bunch of pyramids with dark at the
  // edges and grey at the centers.
  // The devision by some number will make this pyramid higher or lower (edges will be more or less
  // vertical). To create a grid instead, the pyramid needs to be super high, so basically all of
  // it's surface is above 1.0 and only edges will be still near 0.0. The devision by very small
  // number can do the trick (like 0.005). This will produce sharp grid near the camera. But it
  // will result in artifacts in areas far from the camera. This is where `d` comes into the picture.
  // `d` will be small near the camera (because objects near camera take up more pixels, so there
  // is less change between those pixels for the same distance), but for further objects it will be
  // bigger.
  // Using `d` directly will result in very thin grid lines. In order to make them a bit wider,
  // we can divide the result (or pre multipy `d`) by the desired line width constant.
  vec2 grid = coord / d;

  // now tha we have sharp grid, we need to understand if the pixel falls into the valley between
  // these very tall pyramids in X or in Y direction. This is done by simply taking the smallest
  // value of `grid`.
  float line = min(grid.x, grid.y);

  // sinse pyramids are very tall, their values range from 0.0 at the edge to some positive value
  // at the top. To draw actual lines, the pyramid value needs to be clamped to be maxumum of 1.0
  // and inverted (1.0 - value)
  vec4 color = vec4(LINE_COLOR, 1.0 - min(line, 1.0));

  // add colors of axis if any
  color += axis_colors;

  return color;
}

float depth(vec3 world_pos) {
  vec4 clip = PushConstants.data.projection * PushConstants.data.view * vec4(world_pos, 1.0);
  return clip.z / clip.w;
}

void main() {
    float t = in_near.z / (in_near.z - in_far.z);
    vec3 world_pos = in_near + t * (in_far - in_near);
    float depth = depth(world_pos);

    float height = in_near.z;
    float e = max(1.0, log(height) / log(4.0));
    float power = floor(e);
    float grid_size = pow(2.0, power);
    float lod_fade = fract(e);

    float fade = smoothstep(
        0.0,
        1.0,
        (FADE_DISTANCE - length(world_pos - PushConstants.data.camera_position)) / FADE_DISTANCE
    );

    // high dencity
    float grid_size_0 = grid_size;
    // low dencity
    float grid_size_1 = grid_size * 2.0;

    vec4 lod_0_color = grid_point_color(world_pos, grid_size_0);
    lod_0_color.a *= (1.0 - lod_fade) * fade;

    vec4 lod_1_color = grid_point_color(world_pos, grid_size_1);
    lod_1_color.a *= lod_fade * fade;

    // the `0.0 < t` prevents mirroring the grid in the upper part of the screen
    vec4 color = (lod_0_color + lod_1_color) * float(0.0 < t);

    gl_FragDepth = depth;
    out_color = color;
}
