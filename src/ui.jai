Quad :: struct {
    position:  Vector2;
    size:      Vector2;
    uv_offset: Vector2; // or background color, border color
    uv_size:   Vector2; // or border width, 0
    usage:     QuadUsage; @u32
    _: u32 =  0;
} @ShaderType

QuadUsage :: enum u32 {
  COLOR :: 0;
  TEXT  :: 1;
}

ColorType :: enum u8 {
  NONE;        // 0x000000
  FOREGROUND;  // 0xfef8f2
  BACKGROUND;  // 0x000000
  BACKGROUND1; // 0x111111
  BACKGROUND2; // 0x222222
  BACKGROUND3; // 0x333333
  BORDER;      // 0x292f36
  RED;         // 0xfb3741
  GREEN;       // 0x608030
  GREEN1;      // 0x74c365
  GREEN2;      // 0x95C561
  BLUE;        // 0x1282a2

  BUTTON_NORMAL  :: GREEN;
  BUTTON_HOVERED :: GREEN1;
  BUTTON_PRESSED :: GREEN2;
};

Colors :: [#run enum_elements_count(ColorType)]RGBA;

DefaultColors :: RGBA.[
  0x00000000,
  // FOREGROUND
  0xfef8f2ff,
  // BACKGROUND
  0x000000ff,
  0x111111ff,
  0x222222ff,
  0x333333ff,
  // BORDER
  0x292f36ff,
  // RED
  0xfb3741ff,
  // GREEN
  0x608030ff,
  0x74c365ff,
  0x95C561ff,
  // BLUE
  0x1282a2ff,
];

// note(sc): maybe add ui context to the `context` to avoid using global one
// but for now use explicitly passed one
Context :: struct {
  draw_buffer: BufferAllocator;

  colors:    *Colors;
  font_size: float = 20.0;
  font:      *Font;

  hover_id:       u32;
  pressed_id:     u32;

  frame:              u32;
  mouse_position:     Vector2;
  old_mouse_position: Vector2;
  mouse_down:         bool;
  mouse_just_pressed: bool;

  consumed_mouse_event:    bool;
  consumed_keyboard_event: bool;

  global_parent:     Widget;
  global_parent.border = 2.0;
  global_parent.margin = 8.0;

  current_parent:    *Widget;
  widgets:           [64]Widget;
}

init :: (c: *Context, font: *Font) {
  c.colors = *DefaultColors;
  c.font   = font;
  c.current_parent = *c.global_parent;
}

new_frame :: (c: *Context, buffer: []Quad) {
  init(*c.draw_buffer, .{ data = cast(*u8)buffer.data, count = buffer.count * size_of(Quad) });
  c.frame += 1;
  c.consumed_mouse_event    = false;
  c.consumed_keyboard_event = false;
  c.old_mouse_position = c.mouse_position;
  frame_reset(*c.global_parent);
}

draw_elements :: (c: Context) -> u32 {
  return c.draw_buffer.end / cast(u16)size_of(Quad);
}

WidgetFlags :: enum_flags u32 {
  CLICK;
  DRAG_ALL;
  DRAG_HORIZONTAL;
  DRAG_VERTICAL;
  DRAW_BACKGROUND;
  DRAW_TEXT;
  DRAW_BORDER;
  FIXED_SIZE_X;
  FIXED_SIZE_Y;
  FIXED_POSITION_X;
  FIXED_POSITION_Y;
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
  color:              ColorType;
  border:             float;
  margin:             float;

  // cross-frame data
  position_delta:     Vector2;
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

build_widget :: (
  c:          *Context,
  name:       string,
  flags:      WidgetFlags,
  text_flags: WidgetTextFlags,
  size:       Vector2 = .{},
  position:   Vector2 = .{},
) -> *Widget {
  parent    := c.current_parent;
  widget_id := create_id(xx name, parent.id);
  widget    := find_existing_widget(c, widget_id);
  if !widget {
    widget    = find_oldest_widget(c);
    widget.* = .{};
  }

  widget.border            = ifx flags & .DRAW_BORDER parent.border;
  widget.margin            = parent.margin;

  if flags & .FIXED_SIZE_X { if widget.id == 0 widget.size.x = size.x; }
  else widget.size.x = parent.size.x - parent.margin * 2.0;
  if flags & .FIXED_SIZE_Y { if widget.id == 0 widget.size.y = size.y; }
  else widget.size.y = ifx flags & .DRAW_TEXT c.font_size + parent.margin * 2.0;

  if flags & .FIXED_POSITION_X {
    if flags & .DRAG_ALL {
      if widget.id == 0 widget.position.x = position.x;
    } else {
      widget.position.x = position.x;
    }
  } else widget.position.x = parent.margin;
  if flags & .FIXED_POSITION_Y {
    if flags & .DRAG_ALL {
      if widget.id == 0 widget.position.y = position.y;
    } else {
      widget.position.y = position.y;
    }
  } else {
    widget.position.y = parent.layout_offset;
    parent.layout_offset += widget.size.y + widget.border * 2;
  }

  frame_reset(widget);
  widget.id = widget_id;
  widget.last_frame_update = c.frame;
  link_widget(parent, widget);

  widget.flags             = flags;
  widget.text_flags        = text_flags;
  widget.text              = name;
  return widget;
}

panel_start :: (c: *Context, name: string, size: Vector2, position: Vector2 = .{}) {
  widget: *Widget;
  flags: WidgetFlags = .DRAW_BACKGROUND | .DRAW_BORDER | .FIXED_SIZE_X | .FIXED_SIZE_Y;
  if position != .{} flags |= .DRAG_ALL | .FIXED_POSITION_X | .FIXED_POSITION_Y;
  widget = build_widget(c, name, flags, 0, size, position);
  widget.color = .BACKGROUND;
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
  widget.color = .BUTTON_NORMAL;
  return result;
}

toggle :: (c: *Context, text: string, v: *bool) {
  widget := build_widget(c, text, .CLICK | .DRAW_TEXT | .DRAW_BACKGROUND, .CENTER);
  pressed := c.pressed_id == widget.id;
  result := pressed && !widget.was_pressed;
  widget.was_pressed = pressed;
  widget.color = ifx v.* then .BACKGROUND3 else .BACKGROUND1;
  if result then v.* = !v.*;
}

slider :: (c: *Context, name: string, lo: float, hi: float, v: *float) {
  label(c, tprint("%: %", name, v.*));

  ratio := (v.* - lo) / (hi - lo);
  ratio = clamp(ratio, 0.0, 1.0);
  tag   := tprint("%_bg", name);
  flags: WidgetFlags = .DRAW_BACKGROUND | .DRAW_BORDER | .FIXED_SIZE_Y;
  bg    := build_widget(c, tag, flags, 0, .{ y = 20.0 });
  bg.color = .BACKGROUND3;

  tag   = tprint("%_knob", name);
  flags = .DRAG_HORIZONTAL | .DRAW_BACKGROUND | .DRAW_BORDER |
          .FIXED_SIZE_X | .FIXED_SIZE_Y | .FIXED_POSITION_X | .FIXED_POSITION_Y;
  knob := build_widget(c, tag, flags, 0, .{ 20.0, 20.0 }, .{ (bg.size.x - 20.0) * ratio, bg.position.y });

  knob.color = .BUTTON_PRESSED;
  if c.pressed_id == knob.id {
    new_ratio := (knob.position.x + knob.position_delta.x) / (bg.size.x - 20.0);
    new_ratio = clamp(new_ratio, 0.0, 1.0);
    v.* = (hi - lo) * new_ratio;
  }
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
    color: ColorType = w.color;
    check_rect_interaction(c, w.id, current_p, w.size);
    if w.flags & .CLICK {
      if c.hover_id   == w.id color = .BUTTON_HOVERED;
      if c.pressed_id == w.id color = .BUTTON_PRESSED;
    }
    if c.pressed_id == w.id && c.mouse_down {
      delta := c.mouse_position - c.old_mouse_position;
      if w.flags & .DRAG_ALL        { w.position += delta;     w.position_delta = delta; }
      if w.flags & .DRAG_HORIZONTAL { w.position.x += delta.x; w.position_delta.x = delta.x; }
      if w.flags & .DRAG_VERTICAL   { w.position.y += delta.y; w.position_delta.y = delta.y; }
    } else {
      w.position_delta = .{};
    }
    if w.flags & .DRAW_BACKGROUND {
      if w.flags & .DRAW_BORDER {
        draw_rect(c, current_p, w.size, color, .BORDER, w.border);
      } else {
        draw_rect(c, current_p, w.size, color, .NONE, 0.0);
      }
    } else if w.flags & .DRAW_BORDER draw_border(c, current_p, w.size, .BORDER, w.border);
    if w.flags & .DRAW_TEXT {
      text_offset_x: float;
      text_offset_y := (w.size.y + c.font_size) / 2.0;
      if w.text_flags & .CENTER text_offset_x = w.size.x / 2.0;
      else                      text_offset_x = w.margin;
      text_position := current_p + .{ text_offset_x, text_offset_y };
      draw_text(c, text_position, w.text, cast(bool)(w.text_flags & .CENTER));
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
  if hovered && !c.mouse_just_pressed {
    c.consumed_mouse_event = true;
    c.hover_id = id;
  }
  if c.pressed_id == id {
    if !hovered && c.mouse_just_pressed c.pressed_id = 0;
    if !c.mouse_down                    c.pressed_id = 0;
  }
  if c.hover_id == id {
    if c.mouse_just_pressed c.pressed_id = id;
    else if !hovered   c.hover_id = 0;
  }
}

draw_rect :: (
  c:                *Context,
  position:         Vector2,
  size:             Vector2,
  background_color: ColorType,
  border_color:     ColorType,
  border_width:     float,
) {
  rect_position := rect_center(position, size);
  quad := new(Quad,, allocator(*c.draw_buffer));
  quad.* = .{
    position  = rect_position,
    size      = size,
    uv_offset = .{
      (cast,no_check(*float) *c.colors.*[background_color]).*,
      (cast,no_check(*float) *c.colors.*[border_color]).*,
    },
    uv_size   = .{ border_width, 0 },
    usage     = .COLOR,
  };
}

draw_border :: (c:*Context, position: Vector2, size: Vector2, color: ColorType, width: float) {
  draw_rect(c, position, size, .NONE, color, width);
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
