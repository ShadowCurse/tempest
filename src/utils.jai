enum_elements_count :: ($T: Type) -> s64 #expand {
  return #run -> s64 {
    info := type_info(T);
    assert(info.type == .ENUM);
    enum_info := cast(*Type_Info_Enum)info;
    unique: [..]s64;
    is_unique :: (v: s64, u: []s64) -> bool { for u if it == v return false; return true; }
    for enum_info.values if is_unique(it, unique) array_add(*unique, it);
    return unique.count;
  };
}

#scope_file

#import "Basic";
