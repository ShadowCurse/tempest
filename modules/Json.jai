JsonParser :: struct {
  buf:    string;
  cursor: s64;
}

JsonTokenKind :: enum {
  invalid;
  object_begin;
  object_end;
  array_begin;
  array_end;
  _true;
  _false;
  _null;
  number;
  _string;
  end_of_document;
}

JsonToken :: struct {
  kind:    JsonTokenKind;
  payload: string;
}

next_token :: (parser: *JsonParser) -> JsonToken {
  result: JsonToken;
  skip_non_essential(parser);
  if parser.buf.count == parser.cursor {
    result.kind = .end_of_document;
  } else {
    char := parser.buf[parser.cursor];
    if char == {
      case #char "{";
        result.kind = .object_begin;
        parser.cursor += 1;
      case #char "}";
        result.kind = .object_end;
        parser.cursor += 1;
      case #char "[";
        result.kind = .array_begin;
        parser.cursor += 1;
      case #char "]";
        result.kind = .array_end;
        parser.cursor += 1;
      case #char "\"";
        parser.cursor += 1;
        count := 0;
        while parser.buf[parser.cursor + count] != #char "\"" count += 1;
        result.kind = ._string;
        result.payload.data = *parser.buf[parser.cursor];
        result.payload.count = count;
        parser.cursor += count + 1;
      case #char "t";
        result.kind = ._true;
        parser.cursor += 4;
      case #char "f";
        result.kind = ._false;
        parser.cursor += 5;
      case #char "n";
        result.kind = ._null;
        parser.cursor += 4;
      case;
        if is_digit(char) {
          count := 1;
          while is_digit(parser.buf[parser.cursor + count]) count += 1;
          result.kind = .number;
          result.payload.data = *parser.buf[parser.cursor];
          result.payload.count = count;
          parser.cursor += count;
        } else parser.cursor += 1;
    }
  }
  return result;
}

next_object_begin :: (parser: *JsonParser) -> JsonToken {
  while true {
    token := next_token(parser);
    if token.kind == .object_begin return token;
  }
  return {};
}

next_object_field :: (parser: *JsonParser) -> JsonToken {
  while true {
    token := next_token(parser);
    if token.kind == {
      case .object_begin;
        continue;
      case .object_end; #through;
      case ._string;    #through;
      case .end_of_document;
        return token;
      case;
        break;
    }
  }
  return {};
}

next_string :: (parser: *JsonParser) -> JsonToken {
  while true {
    token := next_token(parser);
    if token.kind == ._string return token;
  }
  return {};
}

next_number :: (parser: *JsonParser) -> JsonToken {
  while true {
    token := next_token(parser);
    if token.kind == .number return token;
  }
  return {};
}

next_array_begin :: (parser: *JsonParser) -> JsonToken {
  while true {
    token := next_token(parser);
    if token.kind == .array_begin return token;
  }
  return {};
}

#scope_file

skip_non_essential :: (parser: *JsonParser) {
  while parser.cursor < parser.buf.count &&
        (parser.buf[parser.cursor] == #char " " ||
        parser.buf[parser.cursor] == #char "\t" ||
        parser.buf[parser.cursor] == #char "\r" ||
        parser.buf[parser.cursor] == #char "\n" ||
        parser.buf[parser.cursor] == #char "," ||
        parser.buf[parser.cursor] == #char ":")
    parser.cursor += 1;
}

is_digit :: (c: u8) -> bool {
    return (c >= #char "0" && c <= #char "9") || c == #char "." || c == #char "-";
}
