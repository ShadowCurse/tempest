WATCHED_FILES :: string.[
  "shaders/gradient_comp.glsl",
  "shaders/grid_frag.glsl",
  "shaders/grid_vert.glsl",
  "shaders/mesh_frag.glsl",
  "shaders/mesh_vert.glsl",
  "shaders/text_frag.glsl",
  "shaders/text_vert.glsl",
];

file_watcher: FileWatcher;

FRAMES :: 2;
current_frame_idx: u8 = 0;
// note(sc): create one additional command for immediate actions
render_commands: [FRAMES + 1]RenderCommand = ---;
NO_LAST_SWAPCHAIN_INDEX : u32 = ~cast(u32)0;

gpu_memory: GpuMemory;
cpu_to_gpu_memory: GpuMemory;
staging_buffer: Buffer;

mesh_buffer: Buffer;
ui_buffers: [FRAMES]Buffer;
scene_buffer: Buffer;

Timestamp :: enum u8 {
  COMPUTE_START :: 0;
  COMPUTE_END;
  GRID_START;
  GRID_END;
  MESH_START;
  MESH_END;
  UI_START;
  UI_END;
};
timestamp_array: EnumArray(Timestamp, u64);
timestamp_pool:  VkQueryPool;

cube_mesh_info: GpuMeshInfo;
depth_buffer: Image;

compute_pipeline: Pipeline;
text_pipeline:    Pipeline;
grid_pipeline:    Pipeline;
mesh_pipeline:    Pipeline;

main :: () {
  if !platform_init() return;
  defer platform_quit();
  if !vulkan_init(true) return;

  if init(*file_watcher) {
    for WATCHED_FILES {
      if !add_file(*file_watcher, it) log_error("Cannot setup watch for file: %", it);
    }
    log("Watcher: %", file_watcher);
  }

  for *rc: render_commands rc.* = create_render_command();
  gpu_memory        = allocate_gpu_memory(64 << 20, .DEVICE_LOCAL_BIT);
  cpu_to_gpu_memory = allocate_gpu_memory(64 << 20, .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT);
  staging_buffer    = create_and_alloc_buffer(1 << 20,
                                              .TRANSFER_SRC_BIT,
                                              .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT,
                                              *cpu_to_gpu_memory);
  mesh_buffer       = create_and_alloc_buffer(1 << 20,
                                              .TRANSFER_DST_BIT | .INDEX_BUFFER_BIT | .SHADER_DEVICE_ADDRESS_BIT,
                                              .DEVICE_LOCAL_BIT,
                                              *gpu_memory);

  for * ui_buffers it.* = create_and_alloc_buffer(size_of(Quad) * 1024,
                                              .SHADER_DEVICE_ADDRESS_BIT,
                                              .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT,
                                              *cpu_to_gpu_memory);

  scene_buffer      = create_and_alloc_buffer(size_of(Scene),
                                              .SHADER_DEVICE_ADDRESS_BIT,
                                              .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT,
                                              *cpu_to_gpu_memory);

  pool_create_info: VkQueryPoolCreateInfo = .{
    queryType  = .TIMESTAMP,
    queryCount = xx timestamp_array.values.count,
  };
  timestamp_pool = create_query_pool(pool_create_info);

  font := load_font("NotoSans-Regular");
  font_image := create_and_alloc_image(
    font.bitmap_width,
    font.bitmap_height,
    .R8G8B8A8_UNORM,
    .SAMPLED_BIT  | .TRANSFER_DST_BIT,
    .DEVICE_LOCAL_BIT,
    *gpu_memory,
  );
  sampler_create_info: VkSamplerCreateInfo = .{
      magFilter    = .VK_FILTER_LINEAR,
      minFilter    = .VK_FILTER_LINEAR,
      mipmapMode   = .LINEAR,
      addressModeU = .VK_SAMPLER_ADDRESS_MODE_REPEAT,
      addressModeV = .VK_SAMPLER_ADDRESS_MODE_REPEAT,
      addressModeW = .VK_SAMPLER_ADDRESS_MODE_REPEAT,
      compareOp    = .VK_COMPARE_OP_NEVER,
      borderColor  = .VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK,
  };
  font_sampler := create_sampler(sampler_create_info);

  depth_buffer      = create_and_alloc_image(window_width,
                                             window_height,
                                             .D32_SFLOAT,
                                             .DEPTH_STENCIL_ATTACHMENT_BIT,
                                             .DEVICE_LOCAL_BIT,
                                             *gpu_memory);

  {
    imm_command := *render_commands[FRAMES];
    {
      begin_render_command(imm_command);
      defer end_render_command(imm_command);

      transition_image(
        imm_command,
        depth_buffer.image,
        depth_buffer.usage,
        .UNDEFINED,
        .GENERAL,
        VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT,
        VK_ACCESS_2_NONE,
        VK_ACCESS_2_MEMORY_WRITE_BIT,
      );
    }
    submit_wait_reset(imm_command);


    memcpy(staging_buffer.host_mem.data, font.bitmap.data, font.bitmap_width * font.bitmap_height * 4);
    {
      begin_render_command(imm_command);
      defer end_render_command(imm_command);

      transition_image(
        imm_command,
        font_image.image,
        font_image.usage,
        .UNDEFINED,
        .GENERAL,
        VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT,
        VK_ACCESS_2_NONE,
        VK_ACCESS_2_MEMORY_WRITE_BIT,
      );
      cmd_copy_buffer_to_image(imm_command, staging_buffer.buffer, font_image.image, .{
        width  = font.bitmap_width,
        height = font.bitmap_height,
        depth  = 1,
      });
    }
    submit_wait_reset(imm_command);

    vertices_bytes := Cube.vertices.count * size_of(Vertex);
    indices_bytes  := Cube.indices.count * size_of(u32);
    assert(vertices_bytes + indices_bytes < staging_buffer.host_mem.count);
    memcpy(staging_buffer.host_mem.data, Cube.vertices.data, vertices_bytes);
    memcpy(staging_buffer.host_mem.data + vertices_bytes, Cube.indices.data, indices_bytes);
    cube_mesh_info = .{ 0, xx vertices_bytes, xx Cube.indices.count, xx Cube.vertices.count };
    {
      begin_render_command(imm_command);
      defer end_render_command(imm_command);

      cmd_copy_buffer_to_buffer(imm_command, mesh_buffer.buffer, staging_buffer.buffer, .{
        srcOffset = 0,
        dstOffset = 0,
        size      = xx (vertices_bytes + indices_bytes),
      });
    }
    submit_wait_reset(imm_command);
  }

  compute_pipeline = create_full_screen_effect_comptue_pipeline();
  text_pipeline    = create_text_pipeline();
  grid_pipeline    = create_grid_pipeline();
  mesh_pipeline    = create_mesh_pipeline();

  ui: Context;
  init(*ui, *font);

  camera_position: Vector3 = .{ 0.0, -5.0, 5.0 };
  camera_rotation: Vector2 = .{ 0.78, 0.0 };

  v := 1.0;
  need_swapchain_recreation := false;
  last_swapchain_image_index: u32 = NO_LAST_SWAPCHAIN_INDEX ;
  while (!quit) {
    reset_temporary_storage();
    platform_new_frame();
    new_frame(*ui, ui_buffers[current_frame_idx].host_mem);

    rebuild_pipelines_if_needed();

    ui.mouse_position = mouse_position;
    ui.mouse_pressed  = just_pressed(mouse_state, .LMB);
    ui.mouse_down     = pressed(mouse_state, .LMB);

    camera_velocity: Vector3;
    if pressed(keyboard_state, .W)     camera_velocity.z += 1.0;
    if pressed(keyboard_state, .S)     camera_velocity.z -= 1.0;
    if pressed(keyboard_state, .A)     camera_velocity.x -= 1.0;
    if pressed(keyboard_state, .D)     camera_velocity.x += 1.0;
    if pressed(keyboard_state, .LCTRL) camera_velocity.y += 1.0;
    if pressed(keyboard_state, .SPACE) camera_velocity.y -= 1.0;
    if pressed(mouse_state, .LMB) {
      camera_rotation.y -= mouse_movement.x * (1.0 / 120.0);
      camera_rotation.x -= mouse_movement.y * (1.0 / 120.0);
      camera_rotation.x = clamp(camera_rotation.x, 0, PI);
    }

    // note(sc): the caller will get one frame old data
    get_query_pool_results(timestamp_pool, timestamp_array.values);
    compute_ns := timestamp_array[Timestamp.COMPUTE_END] - timestamp_array[Timestamp.COMPUTE_START];
    compute_ms := cast(float)compute_ns / 1000_000.0;
    grid_ns    := timestamp_array[Timestamp.GRID_END] - timestamp_array[Timestamp.GRID_START];
    grid_ms    := cast(float)grid_ns / 1000_000.0;
    mesh_ns    := timestamp_array[Timestamp.MESH_END] - timestamp_array[Timestamp.MESH_START];
    mesh_ms    := cast(float)mesh_ns / 1000_000.0;
    ui_ns      := timestamp_array[Timestamp.UI_END] - timestamp_array[Timestamp.UI_START];
    ui_ms      := cast(float)ui_ns / 1000_000.0;

    panel_position: Vector2 = .{300.0, 300.0};
    panel_size:     Vector2 = .{300.0, 600.0};
    panel_start(*ui, panel_position, panel_size, "Panel");
    label(*ui, tprint("GPU COMPUTE ms: %", compute_ms));
    label(*ui, tprint("GPU GRID ms: %", grid_ms));
    label(*ui, tprint("GPU MESH ms: %", mesh_ms));
    label(*ui, tprint("GPU UI ms: %", ui_ms));
    label(*ui, tprint("LMB pressed: %", pressed(mouse_state, .LMB)));
    label(*ui, tprint("LMB just pressed: %", just_pressed(mouse_state, .LMB)));
    label(*ui, tprint("pos: %", camera_position));
    label(*ui, tprint("rot: %", camera_rotation));
    if button(*ui, "Debug") ui.debug = !ui.debug;

    if need_swapchain_recreation {
      if last_swapchain_image_index != NO_LAST_SWAPCHAIN_INDEX
        wait_swapchain_fence(xx last_swapchain_image_index);
      recreate_swapchain();
      recreate_depth_buffer();
    }

    render_command := *render_commands[current_frame_idx];
    defer current_frame_idx = (current_frame_idx + 1) % FRAMES;

    wait_for_cmd(render_command);
    reset_render_command(render_command);

    swapchaine_image_index: u32 = 0;
    while (true) {
      index, need_swapchain_recreation := acquire_next_image(render_command);
      if !need_swapchain_recreation {
        swapchaine_image_index = index;
        break;
      } else {
          if last_swapchain_image_index != NO_LAST_SWAPCHAIN_INDEX
            wait_swapchain_fence(xx last_swapchain_image_index);
          recreate_swapchain();
          recreate_depth_buffer();

          // note(sc): for some reason acquiring the image singles the semaphore even on
          // failure. Maybe there is a way to handle it more reasonably.
          destroy_semaphore(render_command);
          render_command.swapchain_semaphore = create_semaphore(.{});

          last_swapchain_image_index = NO_LAST_SWAPCHAIN_INDEX;
      }
    }
    last_swapchain_image_index = swapchaine_image_index;

    begin_render_command(render_command);
    cmd_reset_query_pool(render_command, timestamp_pool, xx timestamp_array.values.count);

    cmd_transition_swapchain_image(
      render_command,
      swapchaine_image_index,
      .UNDEFINED,
      .GENERAL,
      VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
      VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
      VK_ACCESS_2_NONE,
      VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT,
    );

    {
      cmd_write_timestamp(render_command, timestamp_pool, .TOP_OF_PIPE_BIT, xx Timestamp.COMPUTE_START);
      defer cmd_write_timestamp(render_command, timestamp_pool, .BOTTOM_OF_PIPE_BIT, xx Timestamp.COMPUTE_END);

      cmd_bind_pipeline(render_command, compute_pipeline, .COMPUTE);
      image_descriptors: [2]VkDescriptorImageInfo = .[
        .{
          sampler     = null,
          imageView   = swapchain_image_views[swapchaine_image_index],
          imageLayout = .GENERAL,
        },
        .{
          sampler     = font_sampler,
          imageView   = font_image.view,
          imageLayout = .GENERAL,
        },
      ];
      descriptor_sets: [2]VkWriteDescriptorSet = .[
        .{
          dstSet          = null,
          dstBinding      = 0,
          descriptorCount = 1,
          descriptorType  = .STORAGE_IMAGE,
          pImageInfo      = *image_descriptors[0],
        },
        .{
          dstSet          = null,
          dstBinding      = 1,
          descriptorCount = 1,
          descriptorType  = .COMBINED_IMAGE_SAMPLER,
          pImageInfo      = *image_descriptors[1],
        },
      ];
      cmd_push_descriptors(render_command, compute_pipeline, .COMPUTE, descriptor_sets);
      cmd_push_constants(render_command, compute_pipeline, .COMPUTE_BIT, *v);
      cmd_dispatch(render_command, (window_width + 15) / 16, (window_height + 15) / 16, 1);
    }

    cmd_barrier(
      render_command,
      VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
      VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT ,
      VK_ACCESS_2_MEMORY_WRITE_BIT,
      VK_ACCESS_2_MEMORY_WRITE_BIT,
    );

    {
      cmd_begin_rendering_to_swapchain(render_command, swapchaine_image_index, depth_buffer.view);

      world_rotation_z  := quat_from_axis_angle(.{ z = 1.0 }, camera_rotation.y);
      camera_rotation_x := quat_from_axis_angle(.{ x = -1.0 }, PI - camera_rotation.x);
      camera_to_world_rotation := world_rotation_z * camera_rotation_x;
      world_to_camera_rotation := conjugate(camera_to_world_rotation);

      camera_position += rotate(camera_velocity * 5.0 * (1.0 / 120.0), camera_to_world_rotation);

      view := quat_to_mat4(world_to_camera_rotation);
      translate(*view, rotate(-camera_position, world_to_camera_rotation));

      view_inv := quat_to_mat4(camera_to_world_rotation);
      translate(*view_inv, camera_position);

      projection := perspective(PI / 2.0, cast(float)window_width / cast(float)window_height, 0.1, 10000.0);
      scene := cast(*Scene)scene_buffer.host_mem.data;
      scene.* = .{
        camera_view       = view,
        camera_view_inv   = view_inv,
        camera_projection = projection,
      };

      // mesh
      {
        cmd_write_timestamp(render_command, timestamp_pool, .TOP_OF_PIPE_BIT, xx Timestamp.MESH_START);
        defer cmd_write_timestamp(render_command, timestamp_pool, .BOTTOM_OF_PIPE_BIT, xx Timestamp.MESH_END);

        cmd_bind_pipeline(render_command, mesh_pipeline, .GRAPHICS);
        constant: MeshPushConstant = .{
          mesh_buffer.device_address,
          scene_buffer.device_address,
          xx cube_mesh_info.vertices_buffer_offset,
        };
        cmd_push_constants(render_command, mesh_pipeline, .VERTEX_BIT | .FRAGMENT_BIT, *constant);
        cmd_bind_index_buffer(
          render_command,
          mesh_buffer.buffer,
          cube_mesh_info.indices_buffer_offset,
          .UINT32
        );
        cmd_draw_indexed(render_command, cube_mesh_info.index_count, 1, 0, 0, 0);
      }

      // grid
      {
        cmd_write_timestamp(render_command, timestamp_pool, .TOP_OF_PIPE_BIT, xx Timestamp.GRID_START);
        defer cmd_write_timestamp(render_command, timestamp_pool, .BOTTOM_OF_PIPE_BIT, xx Timestamp.GRID_END);

        cmd_bind_pipeline(render_command, grid_pipeline, .GRAPHICS);
        constant: GridPushConstant = .{
          scene_buffer.device_address
        };
        cmd_push_constants(render_command, grid_pipeline, .VERTEX_BIT | .FRAGMENT_BIT, *constant);
        cmd_draw(render_command, 3, 1, 0, 0);
      }

    }
    cmd_end_rendering(render_command);

    cmd_begin_rendering_to_swapchain(render_command, swapchaine_image_index);
    {
      // ui
      {
        cmd_write_timestamp(render_command, timestamp_pool, .TOP_OF_PIPE_BIT, xx Timestamp.UI_START);
        defer cmd_write_timestamp(render_command, timestamp_pool, .BOTTOM_OF_PIPE_BIT, xx Timestamp.UI_END);

        cmd_bind_pipeline(render_command, text_pipeline, .GRAPHICS);
        image_descriptor: VkDescriptorImageInfo = .{
          sampler     = font_sampler,
          imageView   = font_image.view,
          imageLayout = .GENERAL,
        };
        descriptor_set: VkWriteDescriptorSet = .{
          dstSet          = null,
          dstBinding      = 0,
          descriptorCount = 1,
          descriptorType  = .COMBINED_IMAGE_SAMPLER,
          pImageInfo      = *image_descriptor,
        };
        cmd_push_descriptors(render_command, text_pipeline, .GRAPHICS, .[descriptor_set]);
        constant: TextPushConstant = .{
          quads       = ui_buffers[current_frame_idx].device_address,
          screen_size = .{ xx window_width, xx window_height },
          scaling     = ui.font_size / font.size * font.distance_range,
        };
        cmd_push_constants(render_command, text_pipeline, .VERTEX_BIT | .FRAGMENT_BIT, *constant);
        cmd_draw(render_command, 6, draw_elements(ui), 0, 0);
      }
    }
    cmd_end_rendering(render_command);

    cmd_transition_swapchain_image(
      render_command,
      swapchaine_image_index,
      .GENERAL,
      .PRESENT_SRC_KHR,
      VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
      VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
      VK_ACCESS_2_MEMORY_WRITE_BIT,
      VK_ACCESS_2_MEMORY_READ_BIT,
    );

    end_render_command(render_command);
    graphics_queue_submit(render_command, render_command, render_command, swapchaine_image_index);
    need_swapchain_recreation = present_frame_context(swapchaine_image_index);
  }
}

recreate_depth_buffer :: () {
  free_image_memory(depth_buffer.image, *gpu_memory);
  destroy_image_view(depth_buffer.view);
  destroy_image(depth_buffer.image);
  depth_buffer = create_and_alloc_image(window_width,
                                        window_height,
                                        .D32_SFLOAT,
                                        .DEPTH_STENCIL_ATTACHMENT_BIT,
                                        .DEVICE_LOCAL_BIT,
                                        *gpu_memory);
  imm_command := *render_commands[FRAMES];
  {
    begin_render_command(imm_command);
    defer end_render_command(imm_command);

    transition_image(
      imm_command,
      depth_buffer.image,
      depth_buffer.usage,
      .UNDEFINED,
      .GENERAL,
      VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
      VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT,
      VK_ACCESS_2_NONE,
      VK_ACCESS_2_MEMORY_WRITE_BIT,
    );
  }
  submit_wait_reset(imm_command);
}

GpuMemory :: struct {
  #as memory: VkDeviceMemory;
  size:       u32;
  used:       u32;
  host_mem:   []u8;
};
allocate_gpu_memory :: (size: u32, flags: VkMemoryPropertyFlags) -> GpuMemory {
  index  := find_arena_index(~cast(u32)0, flags);
  memory := allocate_memory(index, size);
  host_mem := ifx flags & .HOST_VISIBLE_BIT map_memory(memory, size);
  return .{ memory, size, 0, host_mem };
}

// note(sc): assume this is the last thing allocated from this arena
free_image_memory :: (image: VkImage, gpu_memory: *GpuMemory) {
  requirements := get_image_memory_requirements(image);
  assert(requirements.size < gpu_memory.used);
  gpu_memory.used -= xx requirements.size;
}

bind_image_memory :: (image: VkImage, props: VkMemoryPropertyFlags, gpu_memory: *GpuMemory) {
  requirements := get_image_memory_requirements(image);

  alignment: u32 = xx requirements.alignment;
  size     : u32 = xx requirements.size;
  start := (gpu_memory.used + alignment) & ~(alignment - 1);
  assert(start < gpu_memory.size);
  end   := start + size;
  assert(end < gpu_memory.size);

  bind_image_memory(image, gpu_memory, start);
  gpu_memory.used = end;
}

bind_buffer_memory :: (buffer: VkBuffer, props: VkMemoryPropertyFlags, gpu_memory: *GpuMemory) -> []u8 {
  requirements := get_buffer_memory_requirements(buffer);

  alignment: u32 = xx requirements.alignment;
  size     : u32 = xx requirements.size;
  start := (gpu_memory.used + alignment) & ~(alignment - 1);
  assert(start < gpu_memory.size);
  end   := start + size;
  assert(end < gpu_memory.size);

  bind_buffer_memory(buffer, gpu_memory, start);
  gpu_memory.used = end;

  host_mem: []u8;
  if gpu_memory.host_mem host_mem = .{ data = gpu_memory.host_mem.data + start, count = size };
  return host_mem;
}

Image :: struct {
  image:  VkImage;
  view:   VkImageView;
  extent: VkExtent3D;
  format: VkFormat;
  usage:  VkImageUsageFlags;
  props:  VkMemoryPropertyFlags;
};
create_and_alloc_image :: (
    width:  u32,
    height: u32,
    format: VkFormat,
    usage:  VkImageUsageFlags,
    props:  VkMemoryPropertyFlags,
    gpu_memory: *GpuMemory,
) -> Image {
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
  bind_image_memory(image, props, gpu_memory);

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

  return .{
    image  = image,
    view   = view,
    extent = extent,
    format = format,
    usage = usage,
    props = props,
  };
}

Buffer :: struct {
  buffer:         VkBuffer;
  device_address: VkDeviceAddress;
  host_mem:       []u8;
}
create_and_alloc_buffer :: (
  size: u32,
  usage: VkBufferUsageFlags,
  props: VkMemoryPropertyFlags,
  gpu_memory: *GpuMemory,
) -> Buffer {
  result: Buffer = .{};
  buffer_create_info: VkBufferCreateInfo = .{
      size        = size,
      usage       = usage,
      sharingMode = .EXCLUSIVE,
  };
  buffer         := create_buffer(buffer_create_info);
  host_mem       := bind_buffer_memory(buffer, props, gpu_memory);
  device_address := ifx usage & .SHADER_DEVICE_ADDRESS_BIT get_buffer_address(buffer);
  return .{ buffer, device_address, host_mem };
}

Pipeline :: struct {
  #as pipeline: VkPipeline;
  #as layout:   VkPipelineLayout;
  dsl:          VkDescriptorSetLayout;
}
create_full_screen_effect_comptue_pipeline :: () -> Pipeline {
  binding_layouts: [2]VkDescriptorSetLayoutBinding = .[
    .{
      binding         = 0,
      descriptorCount = 1,
      descriptorType  = .STORAGE_IMAGE,
      stageFlags      = .COMPUTE_BIT,
    },
    .{
      binding         = 1,
      descriptorCount = 1,
      descriptorType  = .COMBINED_IMAGE_SAMPLER,
      stageFlags      = .COMPUTE_BIT,
    },
  ];
  layout_create_info: VkDescriptorSetLayoutCreateInfo = .{
    flags        = .PUSH_DESCRIPTOR_BIT,
    pBindings    = binding_layouts.data,
    bindingCount = xx binding_layouts.count,
  };
  dsl := create_descriptor_set_layout(layout_create_info);

  compute_push_constants: VkPushConstantRange = .{
    stageFlags = .COMPUTE_BIT,
    offset     = 0,
    size       = size_of(float),
  };
  compute_layout_create_info: VkPipelineLayoutCreateInfo = .{
    pSetLayouts            = *dsl,
    setLayoutCount         = 1,
    pPushConstantRanges    = *compute_push_constants,
    pushConstantRangeCount = 1,
  };
  layout := create_pipeline_layout(compute_layout_create_info);

  shader_path := "shaders_compiled/gradient_comp.spv";
  shader_spirv, ok := platform_read_entire_file(shader_path,, temp);
  assert(ok, "Cannot load shader: %\n", shader_path);

  shader_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx shader_spirv.data,
    codeSize = xx shader_spirv.count,
  };
  shader_stage_create_info: VkPipelineShaderStageCreateInfo = .{
    pNext = *shader_module_create_info,
    stage = .COMPUTE_BIT,
    pName = "main",
  };
  compute_pipeline_create_info: VkComputePipelineCreateInfo = .{
    layout = layout,
    stage  = shader_stage_create_info,
  };
  pipeline := create_compute_pipeline(compute_pipeline_create_info);
  return .{
    pipeline = pipeline,
    layout = layout,
    dsl = dsl,
  };
}

TextPushConstant :: struct {
  quads:       VkDeviceAddress;
  screen_size: Vector2;
  scaling:     float;
} @ShaderType
create_text_pipeline :: () -> Pipeline {
  binging_layout: VkDescriptorSetLayoutBinding = .{
    binding         = 0,
    descriptorCount = 1,
    descriptorType  = .VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    stageFlags      = .FRAGMENT_BIT,
  };
  layout_create_info: VkDescriptorSetLayoutCreateInfo = .{
    flags        = .PUSH_DESCRIPTOR_BIT,
    pBindings    = *binging_layout,
    bindingCount = 1,
  };
  dsl := create_descriptor_set_layout(layout_create_info);

  push_constants: VkPushConstantRange = .{
    stageFlags = .VERTEX_BIT | .FRAGMENT_BIT,
    offset     = 0,
    size       = size_of(TextPushConstant),
  };
  pipeline_layout_create_info: VkPipelineLayoutCreateInfo = .{
    pSetLayouts            = *dsl,
    setLayoutCount         = 1,
    pPushConstantRanges    = *push_constants,
    pushConstantRangeCount = 1,
  };
  layout := create_pipeline_layout(pipeline_layout_create_info);

  text_vert_code := platform_read_entire_file("shaders_compiled/text_vert.spv",, temp);
  text_vert_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx text_vert_code.data,
    codeSize = xx text_vert_code.count,
  };
  text_frag_code := platform_read_entire_file("shaders_compiled/text_frag.spv",, temp);
  text_frag_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx text_frag_code.data,
    codeSize = xx text_frag_code.count,
  };
  stages: []VkPipelineShaderStageCreateInfo = .[
    .{ pNext = *text_vert_module_create_info, stage = .VERTEX_BIT,   pName = "main" },
    .{ pNext = *text_frag_module_create_info, stage = .FRAGMENT_BIT, pName = "main" },
  ];

  input_assembly: VkPipelineInputAssemblyStateCreateInfo = .{ topology = .TRIANGLE_LIST };
  rasterization: VkPipelineRasterizationStateCreateInfo = .{
    polygonMode = .FILL,
    frontFace   = .COUNTER_CLOCKWISE,
    lineWidth   = 1.0,
  };
  multisampling: VkPipelineMultisampleStateCreateInfo = .{ rasterizationSamples = ._1_BIT };
  color_attachment_format: VkFormat = .B8G8R8A8_UNORM;
  rendering: VkPipelineRenderingCreateInfo = .{
    pColorAttachmentFormats = *color_attachment_format,
    colorAttachmentCount    = 1,
    depthAttachmentFormat   = .UNDEFINED,
    stencilAttachmentFormat = .UNDEFINED,
  };
  color_blend_attachment: VkPipelineColorBlendAttachmentState = .{
    blendEnable         = xx true,
    srcColorBlendFactor = .SRC_ALPHA,
    dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
    colorBlendOp        = .ADD,
    srcAlphaBlendFactor = .ONE,
    dstAlphaBlendFactor = .ZERO,
    alphaBlendOp        = .ADD,
    colorWriteMask      = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
  };

  viewport: VkPipelineViewportStateCreateInfo = .{ viewportCount = 1, scissorCount = 1 };

  color_blending: VkPipelineColorBlendStateCreateInfo = .{
    logicOpEnable   = xx false,
    logicOp         = .COPY,
    attachmentCount = 1,
    pAttachments    = *color_blend_attachment,
  };

  vertex_input: VkPipelineVertexInputStateCreateInfo;

  dynamic_states: []VkDynamicState = .[ .VIEWPORT, .SCISSOR ];
  dynamic_state_info: VkPipelineDynamicStateCreateInfo = .{
    pDynamicStates    = dynamic_states.data,
    dynamicStateCount = xx dynamic_states.count,
  };

  create_info: VkGraphicsPipelineCreateInfo = .{
    pNext               = *rendering,
    stageCount          = xx stages.count,
    pStages             = stages.data,
    pVertexInputState   = *vertex_input,
    pInputAssemblyState = *input_assembly,
    pViewportState      = *viewport,
    pRasterizationState = *rasterization,
    pMultisampleState   = *multisampling,
    pColorBlendState    = *color_blending,
    pDynamicState       = *dynamic_state_info,
    layout              = layout,
  };
  pipeline := create_graphics_pipeline(create_info);

  return .{
    pipeline = pipeline,
    layout = layout,
    dsl = dsl,
  };
}

GridPushConstant :: struct {
  scene_buffer:    VkDeviceAddress;
} @ShaderType
create_grid_pipeline :: () -> Pipeline {
  push_constants: VkPushConstantRange = .{
    stageFlags = .VERTEX_BIT | .FRAGMENT_BIT,
    offset     = 0,
    size       = size_of(GridPushConstant),
  };
  pipeline_layout_create_info: VkPipelineLayoutCreateInfo = .{
    pPushConstantRanges    = *push_constants,
    pushConstantRangeCount = 1,
  };
  layout := create_pipeline_layout(pipeline_layout_create_info);

  vert_code := platform_read_entire_file("shaders_compiled/grid_vert.spv",, temp);
  vert_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx vert_code.data,
    codeSize = xx vert_code.count,
  };
  frag_code := platform_read_entire_file("shaders_compiled/grid_frag.spv",, temp);
  frag_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx frag_code.data,
    codeSize = xx frag_code.count,
  };
  stages: []VkPipelineShaderStageCreateInfo = .[
    .{ pNext = *vert_module_create_info, stage = .VERTEX_BIT,   pName = "main" },
    .{ pNext = *frag_module_create_info, stage = .FRAGMENT_BIT, pName = "main" },
  ];

  input_assembly: VkPipelineInputAssemblyStateCreateInfo = .{ topology = .TRIANGLE_LIST };
  rasterization: VkPipelineRasterizationStateCreateInfo = .{
    polygonMode = .FILL,
    frontFace   = .COUNTER_CLOCKWISE,
    lineWidth   = 1.0,
  };
  multisampling: VkPipelineMultisampleStateCreateInfo = .{ rasterizationSamples = ._1_BIT };
  color_attachment_format: VkFormat = .B8G8R8A8_UNORM;
  rendering: VkPipelineRenderingCreateInfo = .{
    pColorAttachmentFormats = *color_attachment_format,
    colorAttachmentCount    = 1,
    depthAttachmentFormat   = .D32_SFLOAT,
    stencilAttachmentFormat = .UNDEFINED,
  };
  color_blend_attachment: VkPipelineColorBlendAttachmentState = .{
    blendEnable         = xx true,
    srcColorBlendFactor = .SRC_ALPHA,
    dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
    colorBlendOp        = .ADD,
    srcAlphaBlendFactor = .ONE,
    dstAlphaBlendFactor = .ZERO,
    alphaBlendOp        = .ADD,
    colorWriteMask      = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
  };

  viewport: VkPipelineViewportStateCreateInfo = .{ viewportCount = 1, scissorCount = 1 };

  depth_stencil_state: VkPipelineDepthStencilStateCreateInfo = .{
    depthTestEnable       = xx true,
    depthWriteEnable      = xx true,
    depthCompareOp        = .GREATER,
    depthBoundsTestEnable = xx false,
    minDepthBounds        = 0,
    maxDepthBounds        = 1.0,
  };

  color_blending: VkPipelineColorBlendStateCreateInfo = .{
    logicOpEnable   = xx false,
    logicOp         = .COPY,
    attachmentCount = 1,
    pAttachments    = *color_blend_attachment,
  };

  vertex_input: VkPipelineVertexInputStateCreateInfo;

  dynamic_states: []VkDynamicState = .[ .VIEWPORT, .SCISSOR ];
  dynamic_state_info: VkPipelineDynamicStateCreateInfo = .{
    pDynamicStates    = dynamic_states.data,
    dynamicStateCount = xx dynamic_states.count,
  };

  create_info: VkGraphicsPipelineCreateInfo = .{
    pNext               = *rendering,
    stageCount          = xx stages.count,
    pStages             = stages.data,
    pVertexInputState   = *vertex_input,
    pInputAssemblyState = *input_assembly,
    pViewportState      = *viewport,
    pRasterizationState = *rasterization,
    pMultisampleState   = *multisampling,
    pDepthStencilState  = *depth_stencil_state,
    pColorBlendState    = *color_blending,
    pDynamicState       = *dynamic_state_info,
    layout              = layout,
  };
  pipeline := create_graphics_pipeline(create_info);

  return .{
    pipeline = pipeline,
    layout = layout,
  };
}

MeshPushConstant :: struct {
  mesh_buffer:     VkDeviceAddress;
  scene_buffer:    VkDeviceAddress;
  vertices_offset: u32;
} @ShaderType
create_mesh_pipeline :: () -> Pipeline {
  push_constants: VkPushConstantRange = .{
    stageFlags = .VERTEX_BIT | .FRAGMENT_BIT,
    offset     = 0,
    size       = size_of(MeshPushConstant),
  };
  pipeline_layout_create_info: VkPipelineLayoutCreateInfo = .{
    pPushConstantRanges    = *push_constants,
    pushConstantRangeCount = 1,
  };
  layout := create_pipeline_layout(pipeline_layout_create_info);

  text_vert_code := platform_read_entire_file("shaders_compiled/mesh_vert.spv",, temp);
  text_vert_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx text_vert_code.data,
    codeSize = xx text_vert_code.count,
  };
  text_frag_code := platform_read_entire_file("shaders_compiled/mesh_frag.spv",, temp);
  text_frag_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx text_frag_code.data,
    codeSize = xx text_frag_code.count,
  };
  stages: []VkPipelineShaderStageCreateInfo = .[
    .{ pNext = *text_vert_module_create_info, stage = .VERTEX_BIT,   pName = "main" },
    .{ pNext = *text_frag_module_create_info, stage = .FRAGMENT_BIT, pName = "main" },
  ];

  input_assembly: VkPipelineInputAssemblyStateCreateInfo = .{ topology = .TRIANGLE_LIST };
  rasterization: VkPipelineRasterizationStateCreateInfo = .{
    polygonMode = .FILL,
    frontFace   = .COUNTER_CLOCKWISE,
    lineWidth   = 1.0,
  };
  multisampling: VkPipelineMultisampleStateCreateInfo = .{ rasterizationSamples = ._1_BIT };
  color_attachment_format: VkFormat = .B8G8R8A8_UNORM;
  rendering: VkPipelineRenderingCreateInfo = .{
    pColorAttachmentFormats = *color_attachment_format,
    colorAttachmentCount    = 1,
    depthAttachmentFormat   = .D32_SFLOAT,
    stencilAttachmentFormat = .UNDEFINED,
  };
  color_blend_attachment: VkPipelineColorBlendAttachmentState = .{
    blendEnable         = xx true,
    srcColorBlendFactor = .SRC_ALPHA,
    dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
    colorBlendOp        = .ADD,
    srcAlphaBlendFactor = .ONE,
    dstAlphaBlendFactor = .ZERO,
    alphaBlendOp        = .ADD,
    colorWriteMask      = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
  };

  viewport: VkPipelineViewportStateCreateInfo = .{ viewportCount = 1, scissorCount = 1 };

  depth_stencil_state: VkPipelineDepthStencilStateCreateInfo = .{
    depthTestEnable       = xx true,
    depthWriteEnable      = xx true,
    depthCompareOp        = .GREATER,
    depthBoundsTestEnable = xx false,
    minDepthBounds        = 0,
    maxDepthBounds        = 1.0,
  };

  color_blending: VkPipelineColorBlendStateCreateInfo = .{
    logicOpEnable   = xx false,
    logicOp         = .COPY,
    attachmentCount = 1,
    pAttachments    = *color_blend_attachment,
  };

  vertex_input: VkPipelineVertexInputStateCreateInfo;

  dynamic_states: []VkDynamicState = .[ .VIEWPORT, .SCISSOR ];
  dynamic_state_info: VkPipelineDynamicStateCreateInfo = .{
    pDynamicStates    = dynamic_states.data,
    dynamicStateCount = xx dynamic_states.count,
  };

  create_info: VkGraphicsPipelineCreateInfo = .{
    pNext               = *rendering,
    stageCount          = xx stages.count,
    pStages             = stages.data,
    pVertexInputState   = *vertex_input,
    pInputAssemblyState = *input_assembly,
    pViewportState      = *viewport,
    pRasterizationState = *rasterization,
    pMultisampleState   = *multisampling,
    pDepthStencilState  = *depth_stencil_state,
    pColorBlendState    = *color_blending,
    pDynamicState       = *dynamic_state_info,
    layout              = layout,
  };
  pipeline := create_graphics_pipeline(create_info);

  return .{
    pipeline = pipeline,
    layout = layout,
  };
}

destroy_pipeline :: (pipeline: Pipeline) {
  if pipeline.dsl destroy_descriptor_set_layout(pipeline.dsl);
  if pipeline.layout destroy_pipeline_layout(pipeline.layout);
  if pipeline.pipeline destroy_pipeline(pipeline.pipeline);
}

rebuild_pipelines_if_needed :: () {
  rebuild_gradient_shader := false;
  rebuild_ui_shader := false;
  rebuild_mesh_shader := false;
  rebuild_grid_shader := false;
  while changed_file := has_event(*file_watcher) {
    log("Found changed file: %", changed_file);
    if changed_file == {
      case "shaders/gradient_comp.glsl";
        rebuild_gradient_shader = true;
      case "shaders/text_frag.glsl"; #through;
      case "shaders/text_vert.glsl";
        rebuild_ui_shader = true;
      case "shaders/mesh_frag.glsl"; #through;
      case "shaders/mesh_vert.glsl";
        rebuild_mesh_shader = true;
      case "shaders/grid_frag.glsl"; #through;
      case "shaders/grid_vert.glsl";
        rebuild_grid_shader = true;
    }
  }
  if rebuild_gradient_shader {
    log("Rebuiding GRADIENT pipeline");
    if compile_shader("shaders/gradient_comp.glsl") {
      device_wait_idle();
      destroy_pipeline(compute_pipeline);
      compute_pipeline = create_full_screen_effect_comptue_pipeline();
    } else log_error("Failed to rebuild GRADIENT pipeline");
  }
  if rebuild_ui_shader {
    log("Rebuiding UI pipeline");
    if compile_shader("shaders/text_frag.glsl") && compile_shader("shaders/text_vert.glsl") {
      device_wait_idle();
      destroy_pipeline(text_pipeline);
      text_pipeline = create_text_pipeline();
    } else log_error("Failed to rebuild UI pipeline");
  }
  if rebuild_mesh_shader {
    log("Rebuiding MESH pipeline");
    if compile_shader("shaders/mesh_frag.glsl") && compile_shader("shaders/mesh_vert.glsl") {
      device_wait_idle();
      destroy_pipeline(mesh_pipeline);
      mesh_pipeline = create_mesh_pipeline();
    } else log_error("Failed to rebuild MESH pipeline");
  }
  if rebuild_grid_shader {
    log("Rebuiding GRID pipeline");
    if compile_shader("shaders/grid_frag.glsl") && compile_shader("shaders/grid_vert.glsl") {
      device_wait_idle();
      destroy_pipeline(grid_pipeline);
      grid_pipeline = create_grid_pipeline();
    } else log_error("Failed to rebuild GRID pipeline");
  }
}

RenderCommand :: struct {
  #as cmd:             VkCommandBuffer;
  #as swapchain_semaphore: VkSemaphore;
  #as render_fence:        VkFence;
};
create_render_command :: () -> RenderCommand {
  allocate_info : VkCommandBufferAllocateInfo = .{
    commandPool = graphics_command_pool,
    level = .PRIMARY,
    commandBufferCount = 1,
  };
  cmd := allocate_command_buffer(allocate_info);

  fence_create_info: VkFenceCreateInfo = .{ flags = .SIGNALED_BIT };
  render_fence := create_fence(fence_create_info);

  swapchain_semaphore := create_semaphore(.{});

  return .{
    cmd = cmd,
    swapchain_semaphore = swapchain_semaphore,
    render_fence = render_fence,
  };
}

reset_render_command :: (cmd: RenderCommand) {
  reset_command_buffer(cmd);
}

begin_render_command :: (cmd: RenderCommand) {
  begin_info: VkCommandBufferBeginInfo = .{ flags = .ONE_TIME_SUBMIT_BIT };
  begin_command_buffer(cmd, begin_info);
}

end_render_command :: (cmd: RenderCommand) {
  end_command_buffer(cmd);
}

submit_wait_reset :: (cmd: RenderCommand) {
  buffer_submit_info: VkCommandBufferSubmitInfo =.{ commandBuffer = cmd };
  submit_info: VkSubmitInfo2 = .{ commandBufferInfoCount = 1, pCommandBufferInfos = *buffer_submit_info };

  reset_fences(.[cmd]);
  queue_submit(submit_info, cmd);
  wait_for_fence(cmd);
  reset_command_buffer(cmd);
}

wait_for_cmd :: (cmd: RenderCommand) {
  wait_for_fence(cmd.render_fence);
  reset_fences(.[cmd.render_fence]);
}

cmd_transition_swapchain_image :: (
    cmd:         RenderCommand,
    image_index: u32,
    src_layout:  VkImageLayout,
    dst_layout:  VkImageLayout,
    src_stage:   VkPipelineStageFlags2,
    dst_stage:   VkPipelineStageFlags2,
    src_access:  VkAccessFlags2,
    dst_access:  VkAccessFlags2,
) {
  transition_image(
    cmd.cmd,
    swapchain_images[image_index],
    0,
    src_layout,
    dst_layout,
    src_stage,
    dst_stage,
    src_access,
    dst_access,
  );
}

Scene :: struct {
  camera_view:       Matrix4;
  camera_view_inv:   Matrix4;
  camera_projection: Matrix4;
} @ShaderType

Vertex :: struct {
  position: Vector3;
  uv_x:     float;
  normal:   Vector3;
  uv_y:     float;
  color:    Vector3;
  _:        float;
} @ShaderType

Mesh :: struct {
  indices:  []u32;
  vertices: []Vertex;
}

GpuMeshInfo :: struct {
  vertices_buffer_offset: u64;
  indices_buffer_offset:  u32;
  index_count:            u32;
  vertex_count:           u32;
}

Cube :: Mesh.{
  indices = u32.[
    1,
    14,
    20,
    1,
    20,
    7,
    10,
    6,
    19,
    10,
    19,
    23,
    21,
    18,
    12,
    21,
    12,
    15,
    16,
    3,
    9,
    16,
    9,
    22,
    5,
    2,
    8,
    5,
    8,
    11,
    17,
    13,
    0,
    17,
    0,
    4,
  ],
  vertices = Vertex.[
    .{
      position = .{ 1.0, 1.0, -1.0 },
      normal = .{ 0.0, 0.0, -1.0 },
      uv_x = 6.25e-1,
      uv_y = 5.0e-1,
      color = .{ 0.0, 0.0, -1.0 },
    },
    .{
      position = .{ 1.0, 1.0, -1.0 },
      normal = .{ 0.0, 1.0, -0.0 },
      uv_x = 6.25e-1,
      uv_y = 5.0e-1,
      color = .{ 0.0, 1.0, -0.0 },
    },
    .{
      position = .{ 1.0, 1.0, -1.0 },
      normal = .{ 1.0, 0.0, -0.0 },
      uv_x = 6.25e-1,
      uv_y = 5.0e-1,
      color = .{ 1.0, 0.0, -0.0 },
    },
    .{
      position = .{ 1.0, -1.0, -1.0 },
      normal = .{ 0.0, -1.0, -0.0 },
      uv_x = 3.75e-1,
      uv_y = 5.0e-1,
      color = .{ 0.0, -1.0, -0.0 },
    },
    .{
      position = .{ 1.0, -1.0, -1.0 },
      normal = .{ 0.0, 0.0, -1.0 },
      uv_x = 3.75e-1,
      uv_y = 5.0e-1,
      color = .{ 0.0, 0.0, -1.0 },
    },
    .{
      position = .{ 1.0, -1.0, -1.0 },
      normal = .{ 1.0, 0.0, -0.0 },
      uv_x = 3.75e-1,
      uv_y = 5.0e-1,
      color = .{ 1.0, 0.0, -0.0 },
    },
    .{
      position = .{ 1.0, 1.0, 1.0 },
      normal = .{ 0.0, 0.0, 1.0 },
      uv_x = 6.25e-1,
      uv_y = 2.5e-1,
      color = .{ 0.0, 0.0, 1.0 },
    },
    .{
      position = .{ 1.0, 1.0, 1.0 },
      normal = .{ 0.0, 1.0, -0.0 },
      uv_x = 6.25e-1,
      uv_y = 2.5e-1,
      color = .{ 0.0, 1.0, -0.0 },
    },
    .{
      position = .{ 1.0, 1.0, 1.0 },
      normal = .{ 1.0, 0.0, -0.0 },
      uv_x = 6.25e-1,
      uv_y = 2.5e-1,
      color = .{ 1.0, 0.0, -0.0 },
    },
    .{
      position = .{ 1.0, -1.0, 1.0 },
      normal = .{ 0.0, -1.0, -0.0 },
      uv_x = 3.75e-1,
      uv_y = 2.5e-1,
      color = .{ 0.0, -1.0, -0.0 },
    },
    .{
      position = .{ 1.0, -1.0, 1.0 },
      normal = .{ 0.0, 0.0, 1.0 },
      uv_x = 3.75e-1,
      uv_y = 2.5e-1,
      color = .{ 0.0, 0.0, 1.0 },
    },
    .{
      position = .{ 1.0, -1.0, 1.0 },
      normal = .{ 1.0, 0.0, -0.0 },
      uv_x = 3.75e-1,
      uv_y = 2.5e-1,
      color = .{ 1.0, 0.0, -0.0 },
    },
    .{
      position = .{ -1.0, 1.0, -1.0 },
      normal = .{ -1.0, 0.0, -0.0 },
      uv_x = 6.25e-1,
      uv_y = 7.5e-1,
      color = .{ -1.0, 0.0, -0.0 },
    },
    .{
      position = .{ -1.0, 1.0, -1.0 },
      normal = .{ 0.0, 0.0, -1.0 },
      uv_x = 6.25e-1,
      uv_y = 7.5e-1,
      color = .{ 0.0, 0.0, -1.0 },
    },
    .{
      position = .{ -1.0, 1.0, -1.0 },
      normal = .{ 0.0, 1.0, -0.0 },
      uv_x = 8.75e-1,
      uv_y = 5.0e-1,
      color = .{ 0.0, 1.0, -0.0 },
    },
    .{
      position = .{ -1.0, -1.0, -1.0 },
      normal = .{ -1.0, 0.0, -0.0 },
      uv_x = 3.75e-1,
      uv_y = 7.5e-1,
      color = .{ -1.0, 0.0, -0.0 },
    },
    .{
      position = .{ -1.0, -1.0, -1.0 },
      normal = .{ 0.0, -1.0, -0.0 },
      uv_x = 1.25e-1,
      uv_y = 5.0e-1,
      color = .{ 0.0, -1.0, -0.0 },
    },
    .{
      position = .{ -1.0, -1.0, -1.0 },
      normal = .{ 0.0, 0.0, -1.0 },
      uv_x = 3.75e-1,
      uv_y = 7.5e-1,
      color = .{ 0.0, 0.0, -1.0 },
    },
    .{
      position = .{ -1.0, 1.0, 1.0 },
      normal = .{ -1.0, 0.0, -0.0 },
      uv_x = 6.25e-1,
      uv_y = 1.0,
      color = .{ -1.0, 0.0, -0.0 },
    },
    .{
      position = .{ -1.0, 1.0, 1.0 },
      normal = .{ 0.0, 0.0, 1.0 },
      uv_x = 6.25e-1,
      uv_y = 0.0,
      color = .{ 0.0, 0.0, 1.0 },
    },
    .{
      position = .{ -1.0, 1.0, 1.0 },
      normal = .{ 0.0, 1.0, -0.0 },
      uv_x = 8.75e-1,
      uv_y = 2.5e-1,
      color = .{ 0.0, 1.0, -0.0 },
    },
    .{
      position = .{ -1.0, -1.0, 1.0 },
      normal = .{ -1.0, 0.0, -0.0 },
      uv_x = 3.75e-1,
      uv_y = 1.0,
      color = .{ -1.0, 0.0, -0.0 },
    },
    .{
      position = .{ -1.0, -1.0, 1.0 },
      normal = .{ 0.0, -1.0, -0.0 },
      uv_x = 1.25e-1,
      uv_y = 2.5e-1,
      color = .{ 0.0, -1.0, -0.0 },
    },
    .{
      position = .{ -1.0, -1.0, 1.0 },
      normal = .{ 0.0, 0.0, 1.0 },
      uv_x = 3.75e-1,
      uv_y = 0.0,
      color = .{ 0.0, 0.0, 1.0 },
    },
  ],
};

#import,file "ui.jai";
#import,file "math.jai";
#import,file "font.jai";
#import,file "vulkan.jai";
#import,file "shaders.jai";
#import,file "platform.jai";
#import,file "file_watch.jai";
#import,file "allocators.jai";
#import,file "enum_array.jai";
#import "Basic";
#import "Vulkan";
#import "cgltf";
