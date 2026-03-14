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

ColorType :: enum u8 {
  background;
  border;
  header;
  normal;
  hovered;
  pressed;
};

Colors :: [#run enum_elements_count(ColorType)]Vector3;

DefaultColors :: Vector3.[
  .{0.3, 0.3, 0.3},
  .{0.2, 0.1, 0.9},
  .{0.1, 0.1, 0.1},
  .{0.2, 0.2, 0.2},
  .{0.2, 0.2, 0.3},
  .{0.2, 0.3, 0.3},
];

// note(sc): maybe add ui context to the `context` to avoid using global one
// but for now use explicitly passed one
Context :: struct {
  draw_buffer: BufferAllocator;

  colors:    *Colors;
  font_size: float = 20.0;
  font:      *Font;

  all_border: float = 2.0;
  all_margin: float = 5.0;

  hover_id:       u32;
  pressed_id:     u32;
  panels_pool:    [8]Panel;
  current_layout: Layout;

  frame:              u32;
  mouse_position:     Vector2;
  old_mouse_position: Vector2;
  mouse_down:         bool;
  mouse_pressed:      bool;

  debug:             bool;
}

Panel :: struct {
  position:          Vector2;
  size:              Vector2;
  last_frame_update: u32;
  id:                u32;
};

Layout :: struct {
  panel:            *Panel;
  current_y_offset: float;
}

init :: (c: *Context, buffer: []u8, font: *Font) {
  init(*c.draw_buffer, buffer);
  c.colors = *DefaultColors;
  c.font   = font;
}

new_frame :: (c: *Context) {
  reset(*c.draw_buffer);
  c.frame += 1;
  c.mouse_pressed = false;
  c.old_mouse_position = c.mouse_position;
}

draw_elements :: (c: Context) -> u32 {
  return c.draw_buffer.end / cast(u16)size_of(Quad);
}

current_placement :: (layout: Layout) -> Vector2 {
  result: Vector2 = .{layout.panel.position.x, layout.panel.position.y + layout.current_y_offset};
  return result;
}

max_width :: (layout: Layout) -> float {
  result := layout.panel.size.x;
  return result;
}

add_offset :: (layout: *Layout, v: float) {
  layout.current_y_offset += v;
}

rect_center :: (position: Vector2, size: Vector2) -> Vector2 {
  result := position + size / 2.0;
  return result;
}

point_in_rect :: (position: Vector2, size: Vector2, point: Vector2) -> bool {
  left   := position.x;
  right  := position.x + size.x;
  up     := position.y;
  bottom := position.y + size.y;
  return left <= point.x && point.x <= right && up <= point.y && point.y <= bottom;
}

find_existing_panel :: (c: *Context, id: u32) -> *Panel {
  for *panel: c.panels_pool if panel.id == id return panel;
  return null;
}

find_oldest_panel :: (c: *Context) -> *Panel {
  result: *Panel;
  oldest_frame: u32 = c.frame;
  for *panel: c.panels_pool {
    if panel.last_frame_update <= oldest_frame {
        oldest_frame = panel.last_frame_update;
        result = panel;
    }
  }
  assert(result != null, "Cannot init new panel");
  return result;
}

check_rect_interaction :: (c: *Context, id: u32, position: Vector2, size: Vector2) {
  hovered: bool = false;
  if point_in_rect(position, size, c.mouse_position) hovered = true;
  if hovered && !c.mouse_pressed c.hover_id = id;
  if c.pressed_id == id {
    if !hovered && c.mouse_pressed c.pressed_id = 0;
    if !c.mouse_down               c.pressed_id = 0;
  }
  if c.hover_id == id {
    if c.mouse_pressed c.pressed_id = id;
    else if !hovered c.hover_id = 0;
  }
}

// sdbm algorithm
create_id :: (data: []u8) -> u32 {
  hash: u32 = 0;
  for data hash = cast(u32)it + (hash << 6) + (hash << 16) - hash;
  return hash;
}

draw_rect :: (c: *Context, position: Vector2, size: Vector2, color_type: ColorType) {
  color         := c.colors.*[color_type];
  rect_position := rect_center(position, size);

  quad := new(Quad,, allocator(*c.draw_buffer));
  quad.* = .{
    position  = rect_position,
    size      = size,
    uv_offset = .{ color.x, color.y },
    uv_size   = .{ color.z, 1.0 },
    usage     = .color,
  };
}

draw_border :: (c: *Context, position: Vector2, size: Vector2) {
  border        := c.all_border;
  double_border := border * 2.0;

  top_position: Vector2 = .{ position.x - border, position.y - border };
  top_size:     Vector2 = .{ size.x + double_border, border };
  draw_rect(c, top_position, top_size, .border);

  bot_position: Vector2 = .{ position.x - border, position.y + size.y };
  bot_size             := top_size;
  draw_rect(c, bot_position, bot_size, .border);

  left_position     := top_position;
  left_size: Vector2 = .{ border, size.y + double_border };
  draw_rect(c, left_position, left_size, .border);

  right_position: Vector2 = .{ position.x + size.x, position.y - border };
  right_size             := left_size;
  draw_rect(c, right_position, right_size, .border);
}

draw_text :: (c: *Context, position: Vector2, text: string, centered: bool) {
  text_layout(text, c.font, c.font_size, position, centered,, allocator(*c.draw_buffer));
}

panel_start :: (c: *Context, position: Vector2, size: Vector2, title: string) {
  panel_id := create_id(xx title);
  panel := find_existing_panel(c, panel_id);
  if !panel {
    panel = find_oldest_panel(c);
    panel.id       = panel_id;
    panel.position = position;
    panel.size     = size;
  }
  panel.last_frame_update = c.frame;
  c.current_layout = .{ panel = panel };

  // Panel dragging
  {
    header_position     := current_placement(c.current_layout);
    header_size: Vector2 = .{ c.current_layout.panel.size.x, c.font_size };
    check_rect_interaction(c, panel_id, header_position, header_size);
    if c.pressed_id == panel_id && c.mouse_down {
      delta := c.mouse_position - c.old_mouse_position;
      c.current_layout.panel.position = c.current_layout.panel.position + delta;
    }
  }

  // Background
  panel_position := current_placement(c.current_layout);
  panel_size     := c.current_layout.panel.size;
  draw_rect(c, panel_position, panel_size, .background);
  draw_border(c, panel_position, panel_size);

  // Header
  header_position     := panel_position;
  header_size: Vector2 = .{ max_width(c.current_layout), c.font_size };
  draw_rect(c, header_position, header_size, .header);

  // Header text
  text_offset_x := header_size.x / 2.0;
  text_offset_y := (header_size.y + c.font_size / 2.0) / 2.0;
  name_position := header_position + .{ text_offset_x, text_offset_y };
  draw_text(c, name_position, title, true);

  offset := header_size.y;
  add_offset(*c.current_layout, offset);
}

label :: (c: *Context, text: string) {
  label_position := current_placement(c.current_layout);
  text_offset_x  := c.all_margin;
  text_offset_y  := c.all_margin + c.font_size;
  text_position  := label_position + .{ text_offset_x, text_offset_y };
  draw_text(c, text_position, text, false);

  offset := c.font_size + c.all_margin * 2.0;
  add_offset(*c.current_layout, offset);
}

button :: (c: *Context, text: string) -> bool {
  button_id        : u32 = 5;
  current_position := current_placement(c.current_layout);
  button_position  := current_position + .{ c.all_margin, c.all_margin };
  button_size: Vector2 = .{ max_width(c.current_layout) - c.all_margin * 2.0, c.font_size };
  check_rect_interaction(c, button_id, button_position, button_size);

  // Background
  button_color: ColorType = .normal;
  if c.hover_id   == button_id button_color = .hovered;
  if c.pressed_id == button_id button_color = .pressed;
  draw_rect(c, button_position, button_size, button_color);

  // Text
  text_offset_x := button_size.x / 2.0;
  text_offset_y := (button_size.y + c.font_size / 2.0) / 2.0;
  text_position := button_position + .{ text_offset_x, text_offset_y };
  draw_text(c, text_position, text, true);

  result := false;
  if c.pressed_id == button_id && c.mouse_pressed result = true;

  offset := button_size.y;
  add_offset(*c.current_layout, offset);

  return result;
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

    lines := new_array(line_breaks.count, []Quad, initialized = false,, temp);
    quads := new_array(total_quads, Quad, initialized = false);
    quads_offset := 0;
    for line_breaks {
      line_length := ifx it_index == 0 it else it - line_breaks[it_index - 1] - 1;
      lines[it_index] = .{ data = quads.data + quads_offset, count = line_length };
      quads_offset += line_length;
    }
    return quads, lines;
}

#scope_file

#import,file "font.jai";
#import,file "utils.jai";
#import,file "allocators.jai";
#import "Math";
#import "Basic";
