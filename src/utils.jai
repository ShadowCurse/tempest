enum_elements_count :: ($T: Type) -> s64 #expand {
  return #run -> s64 {
    info := type_info(T);
    assert(info.type == .ENUM);
    enum_info := cast(*Type_Info_Enum)info;
    return enum_info.values.count;
  };
}

#scope_file

#import "Basic";
