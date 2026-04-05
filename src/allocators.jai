BufferAllocator :: struct {
  data:      *u8;
  capacity:  u32;
  end:       u32;
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

allocator :: inline (a: *BufferAllocator) -> Allocator {
  return .{ buffer_allocator_proc, a };
}

// maybe make `host_mem` an comptime optional to distinguise between host visible and
// not host visible gpu memory?
GpuMemory :: struct {
  #as device_memory: VkDeviceMemory;
  capacity:   u32;
  host_mem:   []u8;
};

allocate_gpu_memory :: (size: u32, flags: VkMemoryPropertyFlags) -> GpuMemory {
  index  := find_arena_index(~cast(u32)0, flags);
  device_memory := allocate_memory(index, size);
  host_mem := ifx flags & .HOST_VISIBLE_BIT map_memory(device_memory, size);
  return .{ device_memory, size, host_mem };
}

GpuBufferArena :: struct {
  #as using memory: GpuMemory;
  buffer:           VkBuffer;
  device_address:   VkDeviceAddress;
  end:              u32;
};

init :: (arena: *GpuBufferArena, memory: GpuMemory, usage: VkBufferUsageFlags) {
  buffer_create_info: VkBufferCreateInfo = .{
    size        = memory.capacity,
    usage       = usage,
    sharingMode = .EXCLUSIVE,
  };
  buffer := create_buffer(buffer_create_info);
  bind_buffer_memory(buffer, memory, 0);
  device_address := ifx usage & .SHADER_DEVICE_ADDRESS_BIT get_buffer_address(buffer);
  arena.* = .{ memory, buffer, device_address, 0 };
}

GpuBufferSlice :: struct ($T: Type) {
  // memory:         VkDeviceMemory;
  buffer:         VkBuffer;
  byte_offset:    u32;
  device_address: VkDeviceAddress;
  host_ptr:       *T;
  count:          u32;
}

push :: (arena: *GpuBufferArena, $T: Type, count: u32 = 1) -> GpuBufferSlice(T) {
  alignment := align_of(T);
  bytes     := size_of(T) * count;

  start_address := arena.device_address + cast(u64)arena.end;
  start_address  = align_up(start_address, alignment);
  end_address   := start_address + bytes;
  new_end := end_address - arena.device_address;
  if new_end <= arena.capacity {
    byte_offset := start_address - arena.device_address;
    host_ptr := ifx arena.host_mem cast(*T)(arena.host_mem.data + byte_offset);
    arena.end = cast(u32)new_end;
    return .{ arena.buffer, cast(u32)byte_offset, start_address, host_ptr, count };
  } else {
    return .{};
  }
}

host_memory :: inline (slice: GpuBufferSlice) -> []slice.T {
  result: []slice.T;
  if slice.host_ptr result = .{ data = slice.host_ptr, count = slice.count };
  return result;
}

slice :: (slice: GpuBufferSlice, start: u32, end: u32) -> GpuBufferSlice(slice.T) {
  assert(start <= slice.count, "start: % slice.count: %", start, slice.count);
  assert(end   <= slice.count, "end: % slice.count: %", end, slice.count);
  assert(start <= end,         "start: % end: %", start, end);
  count       := end - start;
  added_bytes := start * size_of(slice.T);
  result: GpuBufferSlice(slice.T) = .{
    buffer         = slice.buffer,
    byte_offset    = slice.byte_offset    + added_bytes,
    device_address = slice.device_address + added_bytes,
    host_ptr       = ifx slice.host_ptr slice.host_ptr + start,
    count          = count,
  };
  return result;
}

cmd_copy_buffer_slice_to_buffer_slice :: (cmd: VkCommandBuffer, dst: GpuBufferSlice, src: GpuBufferSlice) {
  dst_bytes := size_of(dst.T) * dst.count;
  src_bytes := size_of(src.T) * src.count;
  assert(dst_bytes == src_bytes);
  cmd_copy_buffer_to_buffer(cmd, dst.buffer, src.buffer, .{
    srcOffset = src.byte_offset,
    dstOffset = dst.byte_offset,
    size      = dst_bytes,
  });
}

GpuImageArena :: struct {
  #as using memory: GpuMemory;
  end:              u32;
};

init :: (arena: *GpuImageArena, memory: GpuMemory) {
  arena.* = .{ memory, 0 };
}

GpuImage :: struct {
  image:       VkImage;
  view:        VkImageView;
  extent:      VkExtent3D;
  format:      VkFormat;
  usage:       VkImageUsageFlags;
  total_bytes: u32; // total bytes used to satisfy alignment and size
}

push :: (
  arena: *GpuImageArena,
  width: u32,
  height: u32,
  format: VkFormat,
  usage: VkImageUsageFlags
) -> GpuImage {
  extent: VkExtent3D = .{
    width = width,
    height = height,
    depth = 1,
  };
  image_create_info: VkImageCreateInfo = .{
    imageType = ._2D,
    format = format,
    extent = extent,
    usage = usage,
    mipLevels = 1,
    arrayLayers = 1,
    samples = ._1_BIT,
    tiling = .OPTIMAL,
    initialLayout = .UNDEFINED,
    sharingMode = .EXCLUSIVE,
  };

  image := create_image(image_create_info);

  requirements := get_image_memory_requirements(image);
  alignment: u32 = xx requirements.alignment;
  size     : u32 = xx requirements.size;
  start := align_up(arena.end, alignment);
  end   := start + size;
  if end < arena.capacity {
    bind_image_memory(image, arena, start);
    total_bytes := end - arena.end;
    arena.end = end;

    view_create_info: VkImageViewCreateInfo = .{
      image = image,
      viewType = ._2D,
      format = image_create_info.format,
      components = .{ .IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY },
      subresourceRange = .{
        aspectMask = ifx usage & .DEPTH_STENCIL_ATTACHMENT_BIT then .DEPTH_BIT else .COLOR_BIT,
        baseMipLevel = 0,
        levelCount = 1,
        baseArrayLayer = 0,
        layerCount = 1,
      },
    };
    view := create_image_view(view_create_info);
    return .{ image, view, extent, format, usage, total_bytes };
  } else {
    destroy_image(image);
    return .{};
  }
}

// note(sc): assume this is the last image allocated from this arena
pop :: (arena: *GpuImageArena, image: GpuImage) {
  destroy_image_view(image.view);
  destroy_image(image.image);
  arena.end -= image.total_bytes;
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

slice :: inline (slice: []$T, start: u32, end: u32) -> []T {
  assert(start <= slice.count);
  assert(end   <= slice.count);
  assert(start <= end);
  count = end - start;
  return .{ data = slice.data + start, count = count };
}

new :: ($T: Type, $initialized := true) -> *T {
  size   := size_of(T);
  memory := alloc_aligned(size, align_of(T));
  assert(memory != null, "Cound not allocate type of % bytes", size);
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
  assert(result.data != null, "Cound not allocate array of % bytes", size);
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

#import,file "vulkan.jai";
#import "Basic";
#import "Vulkan";
