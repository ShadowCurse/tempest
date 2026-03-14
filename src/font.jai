Font :: struct {
  size:           u32;
  line_gap:       float;
  distance_range: u32;
  char_info:      []CharInfo;
  // kerning_table: []KerningInfo;
  bitmap:         []u8;
  bitmap_width:   u32;
  bitmap_height:  u32;
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
  json_path  := tprint("resources/fonts/%.json", name);

  font: Font;
  font.bitmap    = xx platform_read_entire_file(mtsdf_path);
  font.char_info = new_array(ALL_CHARS.count, CharInfo, initialized = false);

  json    := platform_read_entire_file(json_path,, temp);
  parser: JsonParser = .{ buf = json };
  next_object_begin(*parser);
  while true {
    token := next_token(*parser);
    if token.kind == .end_of_document break;
    if token.payload == {
      case "atlas";
        while true {
          field := next_object_field(*parser);
          if field.kind == .object_end break;
          if field.payload == {
            case "distanceRange";
              number := next_number(*parser);
              font.distance_range = parse_int(*number.payload, u32);
            case "size";
              number := next_number(*parser);
              font.size = parse_int(*number.payload, u32);
            case "width";
              number := next_number(*parser);
              font.bitmap_width = parse_int(*number.payload, u32);
            case "height";
              number := next_number(*parser);
              font.bitmap_height = parse_int(*number.payload, u32);
            case;
          }
        }
    case "metrics";
      while true {
        field := next_object_field(*parser);
        if field.kind == .object_end break;
        if field.payload == {
          case "lineHeight";
            number := next_number(*parser);
            font.line_gap = parse_float(*number.payload);
        }
      }
    case "glyphs";
      next_array_begin(*parser);
      char_index: u8;
      while true {
        next := next_token(*parser);
        if next.kind == .array_end break;
        while true {
          field := next_object_field(*parser);
          if field.kind == .object_end break;
          if field.payload == {
            case "unicode";
              number := next_number(*parser);
              char_index = parse_int(*number.payload, u8) - ALL_CHARS[0];
            case "advance";
              number := next_number(*parser);
              font.char_info[char_index].advance = parse_float(*number.payload);
            case "planeBounds";
              while true {
                plane_field := next_object_field(*parser);
                if plane_field.kind == .object_end break;
                if plane_field.payload == {
                  case "left";
                      number := next_number(*parser);
                      font.char_info[char_index].x0 = parse_float(*number.payload);
                  case "top";
                      number := next_number(*parser);
                      font.char_info[char_index].y0 = parse_float(*number.payload);
                  case "right";
                      number := next_number(*parser);
                      font.char_info[char_index].x1 = parse_float(*number.payload);
                  case "bottom";
                      number := next_number(*parser);
                      font.char_info[char_index].y1 = parse_float(*number.payload);
                }
              }
            case "atlasBounds";
              while true {
                plane_field := next_object_field(*parser);
                if plane_field.kind == .object_end break;
                if plane_field.payload == {
                  case "left";
                    number := next_number(*parser);
                    font.char_info[char_index].u0 = parse_float(*number.payload);
                  case "top";
                    number := next_number(*parser);
                    font.char_info[char_index].v0 = parse_float(*number.payload);
                  case "right";
                    number := next_number(*parser);
                    font.char_info[char_index].u1 = parse_float(*number.payload);
                  case "bottom";
                    number := next_number(*parser);
                    font.char_info[char_index].v1 = parse_float(*number.payload);
                }
              }
            }
          }
        }
      }
  }
  return font;
}

#scope_file

#import,file "platform.jai";
#import,file "allocators.jai";
#import "Json";
#import "Basic";
#import "String";
