FixedArray :: struct($T: Type, $N: I, $I: Type = u32) {
  data:  [N]T;
  count: u32;
}

array_add :: (fa: *FixedArray, item: fa.T) {
  assert(fa.count + 1 < fa.N);
  fa.data[fa.count] = item;
  fa.count += 1;
}

array_add :: (fa: *FixedArray) -> *fa.T {
  assert(fa.count + 1 < fa.N);
  result := *fa.data[fa.count];
  fa.count += 1;
  return result;
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
  for i: 0..fa.count - 1 {
    `it_index := i;
    `it       := fa.data[i];
    #insert body;
  }
}

for_expansion :: (fa: *FixedArray, body: Code, flags: For_Flags) #expand {
  for i: 0..fa.count - 1 {
    `it_index := i;
    `it       := *fa.data[i];
    #insert body;
  }
}

#scope_file

#import "Basic";
