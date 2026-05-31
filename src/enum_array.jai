EnumArray :: struct ($ENUM: Type, $V: Type)
#modify {
  ti := cast(*Type_Info)ENUM;
  if ti.type != .ENUM {
    log_error("Trying to use type: % instead of ENUM for EnumArray", ti.type);
    return false;
  }
  return true;
}
{
  values: [#run enum_max_value(ENUM) + 1]V;
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
