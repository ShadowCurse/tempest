BufferAllocator :: struct {
  data:      *u8;
  capacity:  u16;
  end:       u16;
}

init :: (allocator: *BufferAllocator, buffer: []u8) {
  allocator.data      = buffer.data;
  allocator.capacity  = xx buffer.count;
  allocator.end       = 0;
}

reset :: (allocator: *BufferAllocator) {
  allocator.end = 0;
}

buffer_allocator_proc :: (
  mode: Allocator_Mode,
  size: s64,
  old_size: s64,
  old_memory: *void,
  allocator_data: *void,
  alignment: s64,
) -> *void {
  allocator := cast(*BufferAllocator) allocator_data;
  assert(allocator != null);

  if #complete mode == {
    case .FREE;   return null;
    case .RESIZE; #through;
    case .ALLOCATE;
      if mode == .RESIZE && allocator.data + allocator.end - old_size == old_memory {
        assert(cast(s64)old_memory & (alignment - 1) == 0);
        new_end := allocator.end - cast(u16)old_size + cast(u16)size;
        if new_end < allocator.capacity {
          allocator.end = new_end;
          return old_memory;
        } else {
          return null;
        }
      } else {
        last_addr := cast(s64)(allocator.data + allocator.end);
        last_addr  = align_up(last_addr, alignment);
        end_addr  := last_addr + size;
        new_end   := end_addr - cast(s64)allocator.data;
        if new_end < allocator.capacity {
          allocator.end = xx new_end;
          return cast(*void)last_addr;
        } else {
          return null;
        }
      }
    case .STARTUP;      #through;
    case .SHUTDOWN;
      return null;
    case .THREAD_START; #through;
    case .THREAD_STOP;
      assert(false, "BufferAllocator does not support multithreading\n");
      return null;
    case .CREATE_HEAP; #through;
    case .DESTROY_HEAP;
      assert(false, "BufferAllocator does not support heaps\n");
      return null;
    case .IS_THIS_YOURS;
      start  := allocator.data;
      end    := allocator.data + allocator.capacity;
      result := start <= old_memory && old_memory < end;
      return cast(*void) cast(s64) result;
    case .CAPS;
      if old_memory { (cast(*string)old_memory).* = "BufferAllocator"; }
      return cast(*void)(Allocator_Caps.HINT_I_AM_A_FAST_BUMP_ALLOCATOR|.IS_THIS_YOURS);
  }
}

align_of :: ($T: Type) -> s64 #expand {
  return #run -> s64 {
    info := type_info(struct{ p: u8; t: T; });
    return info.members[1].offset_in_bytes;
  };
}

align_up :: inline (n: $T, $$PAGE_SIZE: $D) -> T {
  page_size: T = xx PAGE_SIZE;
  return (n + page_size - 1) & ~(page_size - 1);
}

alloc_aligned :: (size: s64, alignment: s64) -> *void {
  a := context.allocator;
  result := a.proc(.ALLOCATE, size, 0, null, a.data, alignment);
  return result;
}

realloc_aligned :: (memory: *void, size: s64, old_size: s64, alignment: s64) -> *void {
  a := context.allocator;
  result := a.proc(.RESIZE, size, old_size, memory, a.data, alignment);
  return result;
}

new :: ($T: Type, $initialized := true) -> *T {
  memory := alloc_aligned(size_of(T), align_of(T));
  #if initialized {
    ini :: initializer_of(T);
    #if ini  inline ini(memory);
    else     memset(memory, 0, size_of(T));
  }
  return cast(*T)memory;
}

new_array :: (count: s64, $T: Type, $initialized := true) -> result: []T {
  size   := count * size_of(T);
  result: []T;
  result.data = xx alloc_aligned(size, align_of(T));
  result.count = count;
  #if initialized {
    ini :: initializer_of(T);
    #if ini {
      for *r: result inline ini(r);
    } else {
      memset(result.data, 0, size);
    }
  }
  return result;
}

#scope_file

#import "Basic";
