StaticBitSet :: struct ($BITS: u32, $SLOTS := 0)
#modify {
  SLOTS = (BITS + size_of(s64)) & ~(size_of(s64) - 1);
  return true;
}
{
  storage: [SLOTS]s64;
}

reset :: (s: *StaticBitSet($T)) {
  memset(s.storage.data, 0, s.storage.count * size_of(s64));
}

set :: (s: *StaticBitSet($T), bit: u32) {
  slot   := bit / size_of(s64);
  offset := bit & (size_of(s64) - 1);
  s.storage[slot] |= (1 << offset);
}

unset :: (s: *StaticBitSet($T), bit: u32) {
  slot   := bit / size_of(s64);
  offset := bit & (size_of(s64) - 1);
  s.storage[slot] &= ~(1 << offset);
}

is_set :: (s: StaticBitSet($T), bit: u32) -> bool {
  slot   := bit / size_of(s64);
  offset := bit & (size_of(s64) - 1);
  return s.storage[slot] & (1 << offset) != 0;
}

