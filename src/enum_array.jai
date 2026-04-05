EnumArray :: struct ($ENUM: Type, $V: Type)
#modify {
  ti := cast(*Type_Info)ENUM;
  if ti.type != .ENUM {
    log_error("Trying to use type: % instead of ENUM for EnumArray", ti.type);
    return false;
  } else {
    enum_info: *Type_Info_Enum = xx ti;
    for enum_info.values {
      if it_index == 0 {
        if it != 0 {
          log_error("Trying to use ENUM with starting value % instead of 0", it);
          return false;
        }
      } else {
        if it - 1 != enum_info.values[it_index - 1] {
          log_error("Trying to use ENUM with non sequential values", it);
          return false;
        }
      }
    }
  }
  return true;
}
{
  values: [#run enum_elements_count(ENUM)]V;
};

operator [] :: (ea: EnumArray, index: ea.ENUM) -> ea.V {
  i: u64 = xx index;
  return ea.values[i];
}

operator *[] :: (ea: *EnumArray, index: ea.ENUM) -> ea.V {
  i: u64 = xx index;
  return *ea.values[i];
}

operator []= :: (ea: *EnumArray, index: ea.ENUM, value: ea.V) {
  i: u64 = xx index;
  ea.values[i] = value;
}

#scope_file

#import,file "utils.jai";
#import "Basic";
