BufferAllocator :: struct {
  data:      *u8;
  capacity:  u16;
  end:       u16;
  alignment: u8 = 1;
}

init :: (allocator: *BufferAllocator, buffer: []u8, alignment: u8) {
  allocator.data      = buffer.data;
  allocator.capacity  = xx buffer.count;
  allocator.end       = 0;
  allocator.alignment = alignment;
}

reset :: (allocator: *BufferAllocator) {
  allocator.end = 0;
}

buffer_allocator_proc :: (
  mode: Allocator_Mode,
  size: s64,
  old_size: s64,
  old_memory: *void,
  allocator_data: *void
) -> *void {
  allocator := cast(*BufferAllocator) allocator_data;
  assert(allocator != null);

  if #complete mode == {
    case .FREE;   return null;
    case .RESIZE; #through;
    case .ALLOCATE;
      if mode == .RESIZE && allocator.data + allocator.end - old_size == old_memory {
        new_end := allocator.end - cast(u16)old_size + cast(u16)size;
        if new_end < allocator.capacity {
          allocator.end = new_end;
          return old_memory;
        } else {
          return null;
        }
      } else {
        last_addr := cast(s64)(allocator.data + allocator.end);
        last_addr  = align_up(last_addr, allocator.alignment);
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

align_up :: inline (n: $T, $$PAGE_SIZE: $D) -> T {
    page_size: T = xx PAGE_SIZE;
    return (n + page_size - 1) & ~(page_size - 1);
}

#scope_file

#import "Basic";
