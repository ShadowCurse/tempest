StaticBitSet :: struct ($BITS: u32, $SLOTS := 0)
#modify {
  SLOTS = (BITS + 64) & ~(64 - 1);
  return true;
}
{
  storage: [SLOTS]s64;
}

reset :: (s: *StaticBitSet($T)) {
  memset(s.storage.data, 0, s.storage.count * size_of(s64));
}

set :: (s: *StaticBitSet($T), bit: u32) {
  slot, offset := slot_offset(bit);
  s.storage[slot] |= (1 << offset);
}

unset :: (s: *StaticBitSet($T), bit: u32) {
  slot, offset := slot_offset(bit);
  s.storage[slot] &= ~(1 << offset);
}

is_set :: (s: StaticBitSet($T), bit: u32) -> bool {
  slot, offset := slot_offset(bit);
  return s.storage[slot] & (1 << offset) != 0;
}

#scope_file

slot_offset :: (bit: u32) -> u32, u32 {
  slot   := bit / 64;
  offset := bit & (64 - 1);
  return slot, offset;
}
