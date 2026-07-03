UiQuad :: struct {
  usage:            UiQuadUsage; @u32
  color:            RGBA;      @u32
  position:         Vector2;
  tex:              Vector4; // also border_width
  size:             Vector2;
  glyph_band_texel: u32;     // also border color
  band_min_max:     u32;
  band_scale:       Vector2;
  band_offset:      Vector2;
} @ShaderType

UiQuadUsage :: enum_flags u32 {
  COLOR    :: 1 << 0;
  NO_ROUND :: 1 << 1;
  TEXT     :: 1 << 2;
}

UiColorType :: enum u8 {
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
}

UiColors :: #run -> EnumArray(UiColorType, RGBA) {
  colors: EnumArray(UiColorType, RGBA) = ---;
  colors.values = RGBA.[
    /* NONE;        */ 0x000000ff,
    /* FOREGROUND;  */ 0xfef8f2ff,
    /* BACKGROUND;  */ 0x000000ff,
    /* BACKGROUND1; */ 0x111111ff,
    /* BACKGROUND2; */ 0x222222ff,
    /* BACKGROUND3; */ 0x333333ff,
    /* BORDER;      */ 0x292f36ff,
    /* RED;         */ 0xfb3741ff,
    /* GREEN;       */ 0x608030ff,
    /* GREEN1;      */ 0x74c365ff,
    /* GREEN2;      */ 0x95C561ff,
    /* BLUE;        */ 0x1282a2ff,
  ];
  return colors;
}

// note(sc): maybe add ui context to the `context` to avoid using global one
// but for now use explicitly passed one
UiContext :: struct {
  draw_buffer:             BufferAllocator;
  frame_arena:             BufferAllocator;

  font_size:               float = 20.0;
  font:                    *Font;

  hover_id:                u32;
  pressed_id:              u32;

  frame:                   u32;
  mouse_position:          Vector2;
  old_mouse_position:      Vector2;
  mouse_down:              bool;
  mouse_just_pressed:      bool;

  consumed_mouse_event:    bool;
  consumed_keyboard_event: bool;

  global_parent:           UiWidget;
  global_parent.border =   2.0;
  global_parent.margin =   8.0;

  current_parent:          *UiWidget;
  widgets:                 [1024]UiWidget;
}

ui_init :: (c: *UiContext, font: *Font) {
  init(*c.frame_arena, new_array(4096, u8, initialized = false));
  c.font   = font;
  c.current_parent = *c.global_parent;
}

ui_new_frame :: (c: *UiContext, buffer: []UiQuad) {
  init(*c.draw_buffer, .{ data = cast(*u8)buffer.data, count = buffer.count * size_of(UiQuad) });
  reset(*c.frame_arena);
  c.frame += 1;
  c.consumed_mouse_event    = false;
  c.consumed_keyboard_event = false;
  c.old_mouse_position = c.mouse_position;
  ui_widget_reset(*c.global_parent);
}

ui_pending_elements :: (c: UiContext) -> u32 {
  return c.draw_buffer.end / cast(u16)size_of(UiQuad);
}

UiWidgetFlags :: enum_flags u32 {
  CLICK;
  DRAG_ALL;
  DRAG_HORIZONTAL;
  DRAG_VERTICAL;
  DRAW_BACKGROUND;
  DRAW_TEXT;
  DRAW_BORDER;
  DRAW_ROUNDED;
  DRAW_CENTERED; // Provided position value is the center of the rectangle instead of top-left corner.
  FIXED_SIZE_X;
  FIXED_SIZE_Y;
  FIXED_POSITION_X;
  FIXED_POSITION_Y;
}

UiWidget :: struct {
  // per-frame update
  id:                u32;
  last_frame_update: u32;

  // per-frame reset
  parent:            *UiWidget;
  next:              *UiWidget; // next on the same level
  first:             *UiWidget; // firt on the level bellow
  last:              *UiWidget; // last on the level bellow
  layout_offset:      float;

  // customization
  flags:              UiWidgetFlags;
  payload:            []u8;
  bg_color:           RGBA;
  border_color:       RGBA;
  border:             float;
  margin:             float;

  // cross-frame data
  position_delta:     Vector2;
  position:           Vector2;
  size:               Vector2;
  was_pressed:        bool;
}

ui_widget_reset :: (w: *UiWidget) {
  w.parent        = null;
  w.next          = null;
  w.first         = null;
  w.last          = null;
  w.layout_offset = 0;
}

// sdbm algorithm
ui_create_id :: (data: []u8, seed: u32 = 0) -> u32 {
  hash: u32 = seed;
  for data hash = cast(u32)it + (hash << 6) + (hash << 16) - hash;
  return hash;
}

ui_find_existing_widget :: (c: *UiContext, id: u32) -> *UiWidget {
  for * c.widgets if it.id == id return it;
  return null;
}

ui_find_oldest_widget :: (c: *UiContext) -> *UiWidget {
  result: *UiWidget;
  oldest_frame: u32 = c.frame;
  for *c.widgets {
    if it.last_frame_update < oldest_frame {
        oldest_frame = it.last_frame_update;
        result = it;
    }
  }
  assert(result != null, "Cannot find oldest widget. Most likely due to widgets array exhaustion");
  return result;
}

ui_push_parent :: (c: *UiContext, w: *UiWidget) {
  c.current_parent = w;
}

ui_pop_parent :: (c: *UiContext) {
  c.current_parent = c.current_parent.parent;
}

ui_link_widget :: (parent: *UiWidget, w: *UiWidget) {
  if !parent.first {
    parent.first, parent.last = w;
  } else {
    assert(parent.last != null);
    parent.last.next = w;
  }
  parent.last = w;
  w.parent = parent;
}

ui_build_widget :: (
  c:          *UiContext,
  name:       string,
  flags:      UiWidgetFlags,
  size:       Vector2 = .{},
  position:   Vector2 = .{},
) -> *UiWidget {
  parent    := c.current_parent;
  widget_id := ui_create_id(xx name, parent.id);
  widget    := ui_find_existing_widget(c, widget_id);
  if !widget {
    widget   = ui_find_oldest_widget(c);
    widget.* = .{};
  }

  widget.border = ifx flags & .DRAW_BORDER parent.border;
  widget.margin = parent.margin;

  if flags & .FIXED_SIZE_X { widget.size.x = size.x; }
  else widget.size.x = parent.size.x - parent.margin * 2.0;
  if flags & .FIXED_SIZE_Y { widget.size.y = size.y; }
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

  ui_widget_reset(widget);
  widget.id = widget_id;
  widget.last_frame_update = c.frame;
  ui_link_widget(parent, widget);

  widget.flags    = flags;
  widget.payload  = clone(cast([]u8)name,, allocator(*c.frame_arena));
  return widget;
}

ui_panel_start :: (c: *UiContext, name: string, size: Vector2) {
  widget: *UiWidget;
  flags: UiWidgetFlags = .DRAW_BACKGROUND | .DRAW_BORDER | .DRAW_ROUNDED | .FIXED_SIZE_X | .FIXED_SIZE_Y;
  widget = ui_build_widget(c, name, flags, size);
  widget.bg_color = UiColors[UiColorType.BACKGROUND];
  ui_push_parent(c, widget);
}

ui_panel_start :: (c: *UiContext, name: string, size: Vector2, position: Vector2) {
  widget: *UiWidget;
  flags: UiWidgetFlags = .DRAW_BACKGROUND | .DRAW_BORDER | .DRAW_ROUNDED | .FIXED_SIZE_X | .FIXED_SIZE_Y |
                         .DRAG_ALL | .FIXED_POSITION_X | .FIXED_POSITION_Y;
  widget = ui_build_widget(c, name, flags, size, position);
  widget.bg_color = UiColors[UiColorType.BACKGROUND];
  ui_push_parent(c, widget);
}

ui_panel_end :: (c: *UiContext) {
  // note(sc): can this ensure that it is called on panel and not on any other widget?
  ui_pop_parent(c);
}

ui_label :: (
  c:         *UiContext,
  text:      string,
  flags:     UiWidgetFlags = 0,
  position:  Vector2     = .{},
  size:      Vector2     = .{},
) {
  f := ifx flags else .DRAW_TEXT;
  ui_build_widget(c, text, f, size, position);
}

ui_button :: (
  c:         *UiContext,
  text:      string,
  flags:     UiWidgetFlags = 0,
  position:  Vector2     = .{},
  size:      Vector2     = .{},
  color:     RGBA        = 0,
) -> pressed: bool, hovered: bool {
  f           := ifx flags else .CLICK | .DRAW_TEXT | .DRAW_BACKGROUND | .DRAW_ROUNDED;
  button_text := tprint("button_%", text);
  button      := ui_build_widget(c, button_text, f, size, position);
  pressed     := c.pressed_id == button.id;
  hovered     := c.hover_id == button.id;
  result      := pressed && !button.was_pressed;
  button.was_pressed = pressed;
  button.bg_color = ifx color == 0 then UiColors[UiColorType.BUTTON_NORMAL] else color;
  if (f & .DRAW_TEXT) != 0 {
    button.flags &= ~UiWidgetFlags.DRAW_TEXT;

    ui_push_parent(c, button);
    defer ui_pop_parent(c);

    text_flags: UiWidgetFlags = .DRAW_TEXT | .DRAW_CENTERED | .FIXED_POSITION_X | .FIXED_POSITION_Y;
    text_position := position + button.size / 2.0;
    _             := ui_build_widget(c, text, text_flags, .{}, text_position);
  }
  return result, hovered;
}

ui_toggle :: (c: *UiContext, text: string, v: *bool) {
  flags: UiWidgetFlags = .CLICK | .DRAW_BACKGROUND | .DRAW_ROUNDED | .FIXED_SIZE_X | .FIXED_SIZE_Y;
  tag := tprint("%_toggle", text);
  toggle_size := c.font_size;
  toggle := ui_build_widget(c, tag, flags, .{toggle_size , toggle_size});
  toggle.bg_color = UiColors[ifx v.* then UiColorType.GREEN1 else .BACKGROUND1];

  pressed := c.pressed_id == toggle.id;
  result  := pressed && !toggle.was_pressed;
  toggle.was_pressed = pressed;
  if result then v.* = !v.*;

  flags     = .DRAW_TEXT | .FIXED_SIZE_X | .FIXED_POSITION_X | .FIXED_POSITION_Y;
  size     := Vector2.{x = toggle.parent.size.x - toggle_size};
  position := Vector2.{toggle.position.x + toggle_size, toggle.position.y - toggle_size / 2.0};
  _        := ui_build_widget(c, text, flags, size, position);
}

ui_select :: (c: *UiContext, text: string, e: *$T, $names: []string)
#modify {
  ti := cast(*Type_Info)T;
  if ti.type != .ENUM {
    log_error("select only works with ENUM types but it is given %", T);
    return false;
  } else {
    info := cast(*Type_Info_Enum)ti;
    for names {
      if !array_find(info.names, it) {
        log_error("Enum % does not have name % in it", T, it);
        return false;
      }
    }
    return true;
  }
}
{
  ui_label(c, text);
  info := cast(*Type_Info_Enum )type_info(T);
  for info.names {
    if array_find(names, it) {
      is_selected := cast(s64)e.* == info.values[it_index];
      was_selected := is_selected;
      ui_toggle(c, it, *is_selected);
      if !was_selected && is_selected {
        e.* = xx info.values[it_index];
      }
    }
  }
}

ui_slider :: (c: *UiContext, name: string, lo: float, hi: float, v: *float) {
  ui_label(c, tprint("%: %", name, v.*));

  ratio := (v.* - lo) / (hi - lo);
  ratio = clamp(ratio, 0.0, 1.0);
  tag   := tprint("%_bg", name);
  flags: UiWidgetFlags = .DRAW_BACKGROUND | .DRAW_BORDER | .DRAW_ROUNDED | .FIXED_SIZE_Y;
  bg    := ui_build_widget(c, tag, flags, .{y = 20.0});
  bg.bg_color = UiColors[UiColorType.BACKGROUND3];

  tag   = tprint("%_knob", name);
  flags = .DRAG_HORIZONTAL | .DRAW_BACKGROUND | .DRAW_BORDER | .DRAW_ROUNDED |
          .FIXED_SIZE_X | .FIXED_SIZE_Y | .FIXED_POSITION_X | .FIXED_POSITION_Y;
  knob_size := 20.0;
  knob_position_offset := knob_size / 2.0;
  knob_travel_distance := bg.size.x - knob_size;
  knob_position: Vector2 = .{knob_position_offset + knob_travel_distance * ratio, bg.position.y};
  knob := ui_build_widget(c, tag, flags, .{20.0, 20.0}, knob_position);

  knob.bg_color = UiColors[UiColorType.BUTTON_PRESSED];
  if c.pressed_id == knob.id {
    new_ratio := (knob_position.x - knob_position_offset + knob.position_delta.x) / knob_travel_distance;
    new_ratio = clamp(new_ratio, 0.0, 1.0);
    v.* = (hi - lo) * new_ratio;
  }
}

ui_print_widgets :: (c: *UiContext) {
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

ui_finish_widgets :: (c: *UiContext) {
  current_p := c.global_parent.position;
  w := *c.global_parent;
  while w != null {
    widget_p := w.position;
    if (w.flags & .DRAW_CENTERED) != 0 {
      widget_p -= w.size / 2.0;
    }
    current_p += widget_p;
    bg_color := w.bg_color;
    check_rect_interaction(c, w.id, current_p, w.size);
    if w.flags & .CLICK {
      if c.hover_id   == w.id then bg_color = UiColors[UiColorType.BUTTON_HOVERED];
      if c.pressed_id == w.id then bg_color = UiColors[UiColorType.BUTTON_PRESSED];
    }
    if c.pressed_id == w.id && c.mouse_down {
      delta := c.mouse_position - c.old_mouse_position;
      if w.flags & .DRAG_ALL        { w.position += delta;     w.position_delta = delta; }
      if w.flags & .DRAG_HORIZONTAL { w.position.x += delta.x; w.position_delta.x = delta.x; }
      if w.flags & .DRAG_VERTICAL   { w.position.y += delta.y; w.position_delta.y = delta.y; }
    } else {
      w.position_delta = .{};
    }
    rounded := (w.flags & .DRAW_ROUNDED) != 0;
    if w.flags & .DRAW_BACKGROUND {
      border_color := UiColors[UiColorType.NONE];
      border_width := 0.0;
      if w.flags & .DRAW_BORDER {
        border_color = UiColors[UiColorType.BORDER];
        border_width = w.border;
      }
      ui_draw_rect(c, current_p, w.size, bg_color, border_color, border_width, rounded);
    } else if w.flags & .DRAW_BORDER {
      ui_draw_border(c, current_p, w.size, UiColors[UiColorType.BORDER], w.border, rounded);
    }
    if w.flags & .DRAW_TEXT {
      text_centered := false;
      text_position := current_p;
      text_offset_x := w.margin;
      if (w.flags & .DRAW_CENTERED) != 0 {
        text_centered = true;
        text_position.x += w.size.x / 2.0;
        text_offset_x = 0.0;
      }
      text_offset_y := (w.size.y + c.font_size) / 2.0;
      text_position += .{text_offset_x, text_offset_y};
      text := cast(string)w.payload;
      ui_draw_text(c, text_position, text, text_centered, w.size.x);
    }
    if w.first {
      w = w.first;
    } else if w.next {
      current_p -= widget_p;
      w = w.next;
    } else {
      if w.parent && w.parent.parent current_p = w.parent.parent.position;
      else current_p = .{};
      w = w.parent.next;
    }
  }
}

ui_rect_center :: (position: Vector2, size: Vector2) -> Vector2 {
  result := position + size / 2.0;
  return result;
}

ui_point_in_rect :: (position: Vector2, size: Vector2, point: Vector2) -> bool {
  left   := position.x;
  right  := position.x + size.x;
  up     := position.y;
  bottom := position.y + size.y;
  return left <= point.x && point.x <= right && up <= point.y && point.y <= bottom;
}

check_rect_interaction :: (c: *UiContext, id: u32, position: Vector2, size: Vector2) {
  hovered: bool = false;
  if ui_point_in_rect(position, size, c.mouse_position) hovered = true;
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

ui_draw_rect :: (
  c:                *UiContext,
  position:         Vector2,
  size:             Vector2,
  background_color: RGBA,
  border_color:     RGBA,
  border_width:     float,
  rounded := true,
) {
  rect_position := ui_rect_center(position, size);
  quad := new(UiQuad,, allocator(*c.draw_buffer));
  if !quad then return;
  quad.* = .{
    usage            = .COLOR | ifx !rounded UiQuadUsage.NO_ROUND,
    color            = background_color,
    position         = rect_position,
    size             = size,
    tex              = .{border_width, 0, 0, 0},
    glyph_band_texel = cast(u32)border_color,
  };
}

ui_draw_border :: (c:*UiContext, position: Vector2, size: Vector2, color: RGBA, width: float, rounded := true) {
  ui_draw_rect(c, position, size, UiColors[UiColorType.NONE], color, width);
}

ui_draw_text :: (c: *UiContext, position: Vector2, text: string, centered: bool, max_width := 1000.0) {
  ui_text_layout(text, c.font, c.font_size, position, centered, max_width,, allocator(*c.draw_buffer));
}

ui_text_layout :: (
  text:     string,
  font:     Font,
  size:     float,
  position: Vector2,
  center:   bool,
  max_width := 1000.0,
) -> []UiQuad {
  scale := size;
  offset: Vector2;
  max_width = position.x + max_width;

  quads, lines := ui_text_split_in_lines(text);
  line_start   := 0;
  for line: lines {
    line_end := line_start + line.count;
    defer line_start = line_end + 1;

    for i: 0..line.count - 1 {
      char       := text[i + line_start];
      char_info  := get_char_info(font, char);
      char_kern  := ifx 0 < i then get_kerning(font, text[i + line_start - 1], char);

      offset.x += char_kern * scale;
      if !ui_text_setup_quad(*line[i], char_info, char_kern, scale, position + offset, max_width) {
        if 3 <= i {
          char_info = get_char_info(font, #char ".");
          char_kern = 1;
          offset.x = max_width - position.x -
                     ((char_info.x1 - char_info.x0) * 3.0 + char_info.advance * 2.0) * scale;
          for j: i - 3..i - 1 {
            ui_text_setup_quad(*line[j], char_info, char_kern, scale, position + offset);
            offset.x += char_info.advance * scale;
          }
        } else {
          log("Widget with text % is too narrow for the text to render", text, flags = .WARNING);
        }
        for j: i..line.count - 1 ui_text_setup_quad(*line[j], .{}, 0, 0, .{}, max_width);
        break;
      } else {
        offset.x += char_info.advance * scale;
      }
    }

    if center {
      text_half_len := offset.x / 2.0;
      for *quad: line quad.position.x -= text_half_len;
    }
    offset.x = 0;
    offset.y += font.line_gap * scale;
  }
  return quads;
}

ui_text_split_in_lines :: (text: string) -> quads: []UiQuad, lines: [][]UiQuad {
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

    lines := new_array(line_breaks.count, []UiQuad, initialized = false,, temp);
    if !lines then return .[], .[];
    quads := new_array(total_quads,         UiQuad, initialized = false);
    if !quads then return .[], .[];
    quads_offset := 0;
    for line_breaks {
      line_length := ifx it_index == 0 it else it - line_breaks[it_index - 1] - 1;
      lines[it_index] = .{data = quads.data + quads_offset, count = line_length};
      quads_offset += line_length;
    }
    return quads, lines;
}

ui_text_setup_quad :: (
  quad:      *UiQuad,
  char_info: CharInfo,
  kerning:   s32,
  scale:     float,
  position:  Vector2,
  max_width := 1000.0,
) -> bool {
  char_width  := char_info.x1 - char_info.x0;
  char_height := char_info.y1 - char_info.y0;

  if max_width < position.x + char_width then return false;

  char_position := position + Vector2.{
    char_info.x1 + char_info.x0,
    -(char_info.y1 + char_info.y0)
  } * 0.5 * scale;

  band_min_max        := (char_info.band_max_y << 16) | char_info.band_max_x;
  band_scale:  Vector2 = .{char_info.band_scale_x,  char_info.band_scale_y};
  band_offset: Vector2 = .{char_info.band_offset_x, char_info.band_offset_y};

  quad.* = .{
    usage     = .TEXT,
    color     = 0xffffffff,
    position  = char_position,
    size      = .{char_width, char_height} * scale,
    tex       = .{char_info.x0, char_info.y1, char_info.x1, char_info.y0},
    glyph_band_texel = char_info.glyph_band_texel,
    band_min_max = band_min_max,
    band_scale = band_scale,
    band_offset = band_offset,
  };
  return true;
}
