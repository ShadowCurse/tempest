Font :: struct {
  ascent:         float;
  descent:        float;
  line_gap:       float;
  char_info:      []CharInfo;
  kerning_table:  []KerningInfo;
}
ALL_CHARS :: " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";

CharInfo :: cslug_glyph;
KerningInfo :: struct {
  char_1:  u8;
  char_2:  u8;
  kerning: s32;
};

load_font :: (name: string) -> Font, tmp_curves: []u16, tmp_bands: []u16 {
  font_path := tprint("resources/fonts/%.ttf", name);
  font_file_bytes: []u8 = xx platform_read_entire_file(font_path);

  info: stbtt_fontinfo = ---;
  _ = stbtt_InitFont(
      *info,
      font_file_bytes.data,
      stbtt_GetFontOffsetForIndex(font_file_bytes.data, 0),
  );

  em_scale := stbtt_ScaleForMappingEmToPixels(*info, 1.0);

  asc:      s32 = ---;
  desc:     s32 = ---;
  line_gap: s32 = ---;
  stbtt_GetFontVMetrics(*info, *asc, *desc, *line_gap);
  ascent  := cast(float)asc  * em_scale;
  descent := cast(float)desc * em_scale;

  char_info := new_array(ALL_CHARS.count, cslug_glyph, initialized = false);

  buffers: cslug_buffers_packed;
  defer cslug_free_buffers_packed(*info, *buffers);

  for ALL_CHARS cslug_build_glyph_for_buffer(*info, it, em_scale, *buffers, *char_info[it_index]);

  curves_bytes := buffers.curves.len * size_of(u16);
  tmp_curves := new_array(curves_bytes , u16, initialized = false,, temp);
  memcpy(tmp_curves.data,  buffers.curves.ptr, curves_bytes );

  bands_bytes := buffers.bands.len * size_of(u16);
  tmp_bands := new_array(bands_bytes , u16, initialized = false,, temp);
  memcpy(tmp_bands.data,  buffers.bands.ptr, bands_bytes );

  kerning_table := new_array(ALL_CHARS.count * ALL_CHARS.count, KerningInfo, initialized = false);
  kerning_table_index: u32 = 0;
  for c1: ALL_CHARS {
      for c2: ALL_CHARS {
          kerning := stbtt_GetCodepointKernAdvance(*info, c1, c2);
          kerning_table[kerning_table_index] = .{
              char_1 = c1,
              char_2 = c2,
              kerning = kerning,
          };
          kerning_table_index += 1;
      }
  }

  return .{
      ascent = ascent,
      descent = descent ,
      line_gap = cast(float)line_gap,
      char_info = char_info,
      kerning_table = kerning_table,
  }, tmp_curves, tmp_bands;
}

get_char_info :: (font: Font, char: u8) -> CharInfo {
  char_info: CharInfo;
  if ALL_CHARS[0] <= char && char <= ALL_CHARS[ALL_CHARS.count - 1] {
    index: u32 = char - ALL_CHARS[0];
    char_info = font.char_info[index];
  }
  return char_info;
}

get_kerning :: (font: Font, char_1: u8, char_2: u8) -> s32 {
    index:  u32 = char_1 - ALL_CHARS[0];
    offset: u32 = char_2 - ALL_CHARS[0];
    info   := font.kerning_table[index * ALL_CHARS.count + offset];
    assert(info.char_1 == char_1 && info.char_2 == char_2,
        "Tryingt to get a kerninig info for pair %/% but got one for pair %/%",
        str_from_char(*char_1), str_from_char(*char_2),
        str_from_char(*info.char_1), str_from_char(*info.char_2),
    );
    return info.kerning;
}

#scope_file

#import,file "platform.jai";
#import,file "allocators.jai";
#import,file "utils.jai";
#import "cslug";
#import "Json";
#import "Basic";
#import "String";
