FixedSlice :: struct($T: Type, $I: Type = u32) {
  data:  []T;
  count: u32;
}

fixed_slice :: (slice: []$T) -> FixedSlice(T) {
  return .{ slice, 0 };
}

push :: (fa: *FixedSlice, item: fa.T) {
  assert(fa.count + 1 <= fa.data.count);
  fa.data[fa.count] = item;
  fa.count += 1;
}

push :: (fa: *FixedSlice) -> *fa.T {
  assert(fa.count + 1 <= fa.data.count);
  result := *fa.data[fa.count];
  fa.count += 1;
  return result;
}

operator [] :: (fa: FixedSlice, idx: fa.I, loc := #caller_location) -> fa.T {
  i := cast(u32) idx;
  assert(i < fa.count, "[%:%]: index: % count: %", loc.fully_pathed_filename, loc.line_number, i, fa.count);
  return fa.data[i];
}

operator *[] :: (fa: *FixedSlice, idx: fa.I, loc := #caller_location) -> *fa.T {
  i := cast(u32) idx;
  assert(i < fa.count, "[%:%]: index: % count: %", loc.fully_pathed_filename, loc.line_number, i, fa.count);
  return *fa.data[i];
}

operator []= :: (fa: *FixedSlice, idx: fa.I, value: fa.T, loc := #caller_location) {
  i := cast(u32) idx;
  assert(i < fa.count, "[%:%]: index: % count: %", loc.fully_pathed_filename, loc.line_number, i, fa.count);
  fa.data[i] = value;
}

for_expansion :: (fa: FixedSlice, body: Code, flags: For_Flags) #expand {
  for i: 0..fa.count - 1 {
    `it_index := i;
    `it       := fa.data[i];
    #insert body;
  }
}

for_expansion :: (fa: *FixedSlice, body: Code, flags: For_Flags) #expand {
  for i: 0..fa.count - 1 {
    `it_index := i;
    `it       := *fa.data[i];
    #insert body;
  }
}

#scope_file

#import "Basic";
