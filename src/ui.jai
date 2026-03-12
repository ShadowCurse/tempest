Quad :: struct {
    position:  Vector2;
    size:      Vector2;
    uv_offset: Vector2;
    uv_size:   Vector2;
    usage:     QuadUsage;
    _: u32 =  0;
}

QuadUsage :: enum u32 {
  color :: 0;
  text  :: 1;
}


text_layout :: (text: string, font: Font, size: float, position: Vector2, center: bool) -> []Quad {
  em_to_pixel := cast(float)font.size;
  scale       := size / em_to_pixel;
  font_scale  := scale * em_to_pixel;
  offset: Vector2;

  quads, lines := text_split_in_lines(text);
  line_start   := 0;
  for line: lines {
    line_end := line_start + line.count;
    defer line_start = line_end + 1;

    for i: 0..line.count - 1 {
      char_index := text[i + line_start] - ALL_CHARS[0];
      char_info  := ifx 0 <= char_index && char_index < font.char_info.count font.char_info[char_index];
      // const char_kern = if 0 < i {
      //     const prev_char = text[line_start + i - 1];
      //     break font.get_kerning(prev_char, c);
      // } else {
      //     break 0;
      // };

      char_width  := char_info.u1 - char_info.u0;
      char_height := char_info.v1 - char_info.v0;

      // offset.x += char_kern * font_scale;
      char_origin := position + offset;
      char_offset: Vector2 = .{ char_info.x0, char_info.y0 };
      char_offset *= em_to_pixel;
      char_offset += .{ char_width, char_height } * 0.5;
      char_position := char_origin + char_offset * scale;
      line[i] = .{
        position  = char_position,
        size      = .{ char_width, char_height } * scale,
        uv_offset = .{ char_info.u0, char_info.v0 },
        uv_size   = .{ char_width, char_height },
        usage     = .text,
      };
      offset.x += char_info.advance * font_scale;
    }

    if center {
      text_half_len := offset.x / 2.0;
      for *quad: line quad.position.x -= text_half_len;
    }
    offset.x = 0;
    offset.y += font.line_gap * em_to_pixel * scale;
  }
  return quads;
}

text_split_in_lines :: (text: string) -> quads: []Quad, lines: [][]Quad {
    total_quads := 0;
    line_breaks: [..]s64;
    line_breaks.allocator = temp;
    for text if (it == #char "\n") {
      line_length := ifx line_breaks.count == 0 it_index
                     else it_index - line_breaks[line_breaks.count - 1] - 1;
      total_quads += line_length;
      array_add(*line_breaks, it_index);
    }
    if line_breaks.count == 0 {
      total_quads = text.count;
      array_add(*line_breaks, text.count);
    } else {
      last_line_length := text.count - line_breaks[line_breaks.count - 1] - 1;
      if last_line_length != 0 {
        total_quads += last_line_length;
        array_add(*line_breaks, text.count);
      }
    }

    lines := NewArray(line_breaks.count, []Quad, initialized = false,, temp);
    quads := NewArray(total_quads, Quad, initialized = false);
    quads_offset := 0;
    for line_breaks {
      line_length := ifx it_index == 0 it else it - line_breaks[it_index - 1] - 1;
      lines[it_index] = .{ data = quads.data + quads_offset, count = line_length };
      quads_offset += line_length;
    }
    return quads, lines;
}

#import,file "font.jai";
#import "Math";
#import "Basic";
