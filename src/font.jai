Font :: struct {
  size:          float;
  ascent:        float;
  decent:        float;
  line_gap:      float;
  char_info:     []CharInfo;
  // kerning_table: []KerningInfo;
  bitmap:        []u8;
  bitmap_width:  u32;
  bitmap_height: u32;
}
ALL_CHARS :: " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";

CharInfo :: struct {
  advance:        float;
  x0, y0, x1, y1: float;
  u0, v0, u1, v1: float;
}

KerningInfo :: struct {
  char_1:  u8;
  char_2:  u8;
  kerning: s32;
};

load_font :: (name: string) -> Font {
  mtsdf_path := tprint("resources/fonts/%.mtsdf", name);
  csv_path   := tprint("resources/fonts/%.csv", name);

  bitmap := platform_read_entire_file(mtsdf_path);
  csv    := platform_read_entire_file(csv_path,, temp);

  char_info := NewArray(ALL_CHARS.count, CharInfo, initialized = false);
  found, left, right := split_from_left(csv, #char "\n");
  while found {
    parts := split(left, #char ",",, temp);
    if parts.count == 10 {
      char_index := parse_int(*parts[0], u32);
      advance    := parse_float(*parts[1]);

      x0 := parse_float(*parts[2]);
      y0 := parse_float(*parts[3]);
      x1 := parse_float(*parts[4]);
      y1 := parse_float(*parts[5]);

      u0 := parse_float(*parts[6]);
      v0 := parse_float(*parts[7]);
      u1 := parse_float(*parts[8]);
      v1 := parse_float(*parts[9]);

      info_index := char_index - ALL_CHARS[0];
      char_info[info_index] = .{ advance, x0, y0, x1, y0, u0, v0, u1, v1 };
    } else {
      log_error("Font CVS contains strange line with % parts, but we expect 10 parts", parts.count);
    }
    found, left, right = split_from_left(right, #char "\n");
  }

  return .{
    size          = 32,
    ascent        = 1.069,
    decent        = -0.292,
    line_gap      = 1.362,
    char_info     = char_info,
    bitmap        = xx bitmap,
    bitmap_width  = 216,
    bitmap_height = 216,
  };
}

#scope_file

// "type":"mtsdf","distanceRange":2,"distanceRangeMiddle":0,"size":32,"width":216,"height":216,"yOrigin":"bottom"
// "emSize":1,"lineHeight":1.3620000000000001,"ascender":1.069,"descender":-0.29299999999999998,"underlineY":-0.125,"underlineThickness":0.050000000000000003},

#import,file "platform.jai";
#import "Basic";
#import "String";
