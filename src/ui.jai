Quad :: struct {
    position:  Vector2;
    size:      Vector2;
    uv_offset: Vector2;
    uv_size:   Vector2;
    usage:     QuadUsage; @u32
    _: u32 =  0;
} @ShaderType

QuadUsage :: enum u32 {
  COLOR :: 0;
  TEXT  :: 1;
}

ColorType :: enum u8 {
  BACKGROUND;
  BORDER;
  HEADER;
  NORMAL;
  HOVERED;
  PRESSED;
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

  // all_border: float = 2.0;
  // all_margin: float = 5.0;

  hover_id:       u32;
  pressed_id:     u32;
  // panels_pool:    [8]Panel;
  // current_layout: Layout;

  frame:              u32;
  mouse_position:     Vector2;
  old_mouse_position: Vector2;
  mouse_down:         bool;
  mouse_just_pressed:      bool;

  // debug:             bool;

  global_parent:     Widget;
  global_parent.border = 2.0;
  global_parent.margin = 2.0;

  current_parent:    *Widget;
  widgets:           [64]Widget;
  use_fixed_position := false;
  fixed_position:    Vector2;
}

init :: (c: *Context, font: *Font) {
  c.colors = *DefaultColors;
  c.font   = font;
  c.current_parent = *c.global_parent;
}

new_frame :: (c: *Context, buffer: []Quad) {
  init(*c.draw_buffer, .{ data = cast(*u8)buffer.data, count = buffer.count * size_of(Quad) });
  c.frame += 1;
  // c.mouse_just_pressed = false;
  c.old_mouse_position = c.mouse_position;
  frame_reset(*c.global_parent);
}

draw_elements :: (c: Context) -> u32 {
  return c.draw_buffer.end / cast(u16)size_of(Quad);
}

WidgetFlags :: enum_flags u32 {
  CLICK;
  DRAG;
  DRAW_BACKGROUND;
  DRAW_TEXT;
  DRAW_BORDER;
}
WidgetTextFlags :: enum_flags u8 {
  CENTER;
}
Widget :: struct {
  // per-frame update
  id:                u32;
  last_frame_update: u32;

  // per-frame reset
  parent:            *Widget;
  next:              *Widget; // next on the same level
  first:             *Widget; // firt on the level bellow
  last:              *Widget; // last on the level bellow
  layout_offset:      float;

  // customization
  flags:              WidgetFlags;
  text_flags:         WidgetTextFlags;
  text:               string;
  border:             float;
  margin:             float;

  // cross-frame data
  position:           Vector2;
  size:               Vector2;
  was_pressed:        bool;
}

frame_reset :: (w: *Widget) {
  w.parent        = null;
  w.next          = null;
  w.first         = null;
  w.last          = null;
  w.layout_offset = 0;
}

// sdbm algorithm
create_id :: (data: []u8, seed: u32 = 0) -> u32 {
  hash: u32 = seed;
  for data hash = cast(u32)it + (hash << 6) + (hash << 16) - hash;
  return hash;
}

find_existing_widget :: (c: *Context, id: u32) -> *Widget {
  for * c.widgets if it.id == id return it;
  return null;
}

find_oldest_widget :: (c: *Context) -> *Widget {
  result: *Widget;
  oldest_frame: u32 = c.frame;
  for *c.widgets {
    if it.last_frame_update <= oldest_frame {
        oldest_frame = it.last_frame_update;
        result = it;
    }
  }
  assert(result != null, "Cannot init new panel");
  return result;
}

link_widget :: (parent: *Widget, w: *Widget) {
  if !parent.first {
    parent.first, parent.last = w;
  } else {
    assert(parent.last != null);
    parent.last.next = w;
  }
  parent.last = w;
  w.parent = parent;
}

lock_layout :: (c: *Context, position: Vector2) {
  c.use_fixed_position = true;
  c.fixed_position     = position;
}

unlock_layout :: (c: *Context) {
  c.use_fixed_position = false;
}

build_widget :: (
  c: *Context,
  name: string,
  flags: WidgetFlags,
  text_flags: WidgetTextFlags,
  size: Vector2 = .{},
) -> *Widget {
  parent    := c.current_parent;
  widget_id := create_id(xx name, parent.id);
  widget    := find_existing_widget(c, widget_id);
  if !widget {
    widget    = find_oldest_widget(c);
    widget.* = .{};
  }

  s := size;
  if c.use_fixed_position {
    if widget.id == 0 widget.position = c.fixed_position;
  } else {
    margin2 := parent.margin * 2.0;
    if s == .{} {
      if flags & .DRAW_TEXT {
        s = .{ parent.size.x - margin2, c.font_size + margin2 };
      }
    }
    widget_position: Vector2 = .{ parent.border, parent.layout_offset };
    parent.layout_offset += s.y + parent.border;
    widget.position = widget_position;
  }

  frame_reset(widget);
  widget.id = widget_id;
  widget.last_frame_update = c.frame;
  link_widget(parent, widget);

  widget.flags             = flags;
  widget.text_flags        = text_flags;
  widget.text              = name;
  widget.border            = ifx flags & .DRAW_BORDER parent.border;
  widget.margin            = parent.margin;
  widget.size              = s;
  return widget;
}

panel_start :: (c: *Context, name: string, size: Vector2, position: Vector2 = .{}) {
  widget: *Widget;
  if position != .{} {
    lock_layout(c, position);
    widget = build_widget(c, name, .DRAG | .DRAW_BACKGROUND | .DRAW_BORDER, 0, size);
    unlock_layout(c);
  } else {
    widget = build_widget(c, name, .DRAW_BACKGROUND | .DRAW_BORDER, 0, size);
  }
  c.current_parent = widget;
}

panel_end :: (c: *Context) {
  // note(sc): can this ensure that it is called on panel and not on any other widget?
  c.current_parent = c.current_parent.parent;
}

label :: (c: *Context, text: string) {
  widget := build_widget(c, text, .DRAW_TEXT, 0);
}

button :: (c: *Context, text: string) -> bool {
  widget := build_widget(c, text, .CLICK | .DRAW_TEXT | .DRAW_BACKGROUND, .CENTER);
  pressed := c.pressed_id == widget.id;
  result := pressed && !widget.was_pressed;
  widget.was_pressed = pressed;
  return result;
}

print_widgets :: (c: *Context) {
  indent := 0;
  w := *c.global_parent;
  while w != null {
    for 0..indent - 1 print(" ");
    log("id: % flags: % position: %", w.id, w.flags, w.position);
    if w.first {
      indent += 1;
      w = w.first;
    } else if w.next {
      w = w.next;
    } else {
      indent -= 1;
      w = w.parent.next;
    }
  }
}

finish_widgets :: (c: *Context) {
  current_p := c.global_parent.position;
  w := *c.global_parent;
  while w != null {
    current_p += w.position;
    color: ColorType = .BACKGROUND;
    if w.flags & .CLICK {
      color = .NORMAL;
      check_rect_interaction(c, w.id, current_p, w.size);
      if c.hover_id   == w.id color = .HOVERED;
      if c.pressed_id == w.id color = .PRESSED;
    }
    if w.flags & .DRAG {
      check_rect_interaction(c, w.id, current_p, w.size);
      if c.pressed_id == w.id && c.mouse_down {
        delta := c.mouse_position - c.old_mouse_position;
        w.position += delta;
        current_p  += delta;
      }
    }
    if w.flags & .DRAW_BACKGROUND {
      draw_rect(c, current_p, w.size, color);
    }
    if w.flags & .DRAW_TEXT {
      text_offset_x: float;
      text_offset_y := (w.size.y + c.font_size) / 2.0;
      if w.text_flags & .CENTER text_offset_x = w.size.x / 2.0;
      else                      text_offset_x = w.border;
      text_position := current_p + .{ text_offset_x, text_offset_y };
      draw_text(c, text_position, w.text, cast(bool)(w.text_flags & .CENTER));
    }
    if w.flags & .DRAW_BORDER {
      draw_border(c, current_p, w.size, w.border);
    }

    if w.first {
      w = w.first;
    } else if w.next {
      current_p -= w.position;
      w = w.next;
    } else {
      if w.parent && w.parent.parent current_p = w.parent.parent.position;
      else current_p = .{};
      w = w.parent.next;
    }
  }
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

check_rect_interaction :: (c: *Context, id: u32, position: Vector2, size: Vector2) {
  hovered: bool = false;
  if point_in_rect(position, size, c.mouse_position) hovered = true;
  if hovered && !c.mouse_just_pressed c.hover_id = id;
  if c.pressed_id == id {
    if !hovered && c.mouse_just_pressed c.pressed_id = 0;
    if !c.mouse_down                    c.pressed_id = 0;
  }
  if c.hover_id == id {
    if c.mouse_just_pressed c.pressed_id = id;
    else if !hovered   c.hover_id = 0;
  }
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
    usage     = .COLOR,
  };
}

draw_border :: (c: *Context, position: Vector2, size: Vector2, width: float) {
  border        := width;
  double_border := border * 2.0;

  top_position: Vector2 = .{ position.x - border, position.y - border };
  top_size:     Vector2 = .{ size.x + double_border, border };
  draw_rect(c, top_position, top_size, .BORDER);

  bot_position: Vector2 = .{ position.x - border, position.y + size.y };
  bot_size             := top_size;
  draw_rect(c, bot_position, bot_size, .BORDER);

  left_position     := top_position;
  left_size: Vector2 = .{ border, size.y + double_border };
  draw_rect(c, left_position, left_size, .BORDER);

  right_position: Vector2 = .{ position.x + size.x, position.y - border };
  right_size             := left_size;
  draw_rect(c, right_position, right_size, .BORDER);
}

draw_text :: (c: *Context, position: Vector2, text: string, centered: bool) {
  text_layout(text, c.font, c.font_size, position, centered,, allocator(*c.draw_buffer));
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
        usage     = .TEXT,
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

#import,file "math.jai";
#import,file "font.jai";
#import,file "utils.jai";
#import,file "allocators.jai";
#import "Basic";
