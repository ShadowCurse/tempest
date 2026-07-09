FixedArray :: struct($T: Type, $N: I, $I: Type = u32) {
  data:  [N]T;
  count: u32;
}

fixed_array_add :: (fa: *FixedArray, item: fa.T) {
  assert(fa.count + 1 < fa.N);
  fa.data[fa.count] = item;
  fa.count += 1;
}

fixed_array_add :: (fa: *FixedArray) -> *fa.T {
  assert(fa.count + 1 < fa.N);
  result := *fa.data[fa.count];
  fa.count += 1;
  return result;
}

fixed_array_reset :: (fa: *FixedArray) {
  fa.count = 0;
}

fixed_array_last :: (fa: *FixedArray) -> (success: bool, result: *fa.T) {
  if fa.count == 0 then return false, null;
                   else return true, *fa.data[fa.count - 1];
}

operator [] :: (fa: FixedArray, idx: fa.I, loc := #caller_location) -> fa.T {
  i := cast(u32) idx;
  assert(i < fa.count, "[%:%]: index: % count: %", loc.fully_pathed_filename, loc.line_number, i, fa.count);
  return fa.data[i];
}

operator *[] :: (fa: *FixedArray, idx: fa.I, loc := #caller_location) -> *fa.T {
  i := cast(u32) idx;
  assert(i < fa.count, "[%:%]: index: % count: %", loc.fully_pathed_filename, loc.line_number, i, fa.count);
  return *fa.data[i];
}

operator []= :: (fa: *FixedArray, idx: fa.I, value: fa.T, loc := #caller_location) {
  i := cast(u32) idx;
  assert(i < fa.count, "[%:%]: index: % count: %", loc.fully_pathed_filename, loc.line_number, i, fa.count);
  fa.data[i] = value;
}

for_expansion :: (fa: FixedArray, body: Code, flags: For_Flags) #expand {
  if fa.count != 0 for i: 0..fa.count - 1 {
    `it_index := i;
    `it       := fa.data[i];
    #insert body;
  }
}

for_expansion :: (fa: *FixedArray, body: Code, flags: For_Flags) #expand {
  if fa.count != 0 for i: 0..fa.count - 1 {
    `it_index := i;
    `it       := *fa.data[i];
    #insert body;
  }
}
