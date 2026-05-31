enum_elements_count :: ($T: Type) -> s64 {
  info := type_info(T);
  assert(info.type == .ENUM);
  enum_info := cast(*Type_Info_Enum)info;
  unique: [..]s64;
  is_unique :: (v: s64, u: []s64) -> bool { for u if it == v return false; return true; } @NoProfile
  for enum_info.values if is_unique(it, unique) array_add(*unique, it);
  return unique.count;
} @NoProfile

enum_max_value :: ($T: Type) -> s64 {
  info := type_info(T);
  assert(info.type == .ENUM);
  enum_info := cast(*Type_Info_Enum)info;
  m := 0;
  for enum_info.values m = max(m, it);
  return m;
} @NoProfile

str_from_char :: (char: *u8) -> string {
  return .{ data = char, count = 1 };
} @NoProfile
