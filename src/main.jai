FRAMES :: 2;
current_frame_idx: u8 = 0;
render_commands: [FRAMES]RenderCommand = ---;

main :: () {
  if !platform_init() return;
  defer platform_quit();
  if !vulkan_init(true) return;

  pipeline := create_full_screen_effect_comptue_pipeline();
  for *rc: render_commands rc.* = create_render_command();

  v := 1.0;
  while (!platform_wants_to_exit()) {
    render_command := *render_commands[current_frame_idx];
    defer current_frame_idx = (current_frame_idx + 1) % FRAMES;

    wait_for_cmd(render_command);
    reset_render_command(render_command);
    swapchaine_image_index, need_swapchain_recreation := acquire_next_image(render_command.swapchain_semaphore);
    begin_render_command(render_command);
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

    cmd_bind_pipeline(render_command, pipeline, .COMPUTE);
    image_descriptor: VkDescriptorImageInfo = .{
      sampler     = null,
      imageView   = swapchain_image_views[swapchaine_image_index],
      imageLayout = .GENERAL,
    };
    descriptor_set: VkWriteDescriptorSet = .{
      dstSet          = null,
      dstBinding      = 0,
      descriptorCount = 1,
      descriptorType  = .STORAGE_IMAGE,
      pImageInfo      = *image_descriptor,
    };
    cmd_push_descriptors(render_command, pipeline, .COMPUTE, .[descriptor_set]);
    cmd_push_constants(render_command, pipeline, .COMPUTE_BIT, *v);
    cmd_dispatch(render_command, (window_width + 15) / 16, (window_height + 15) / 16, 1);

    cmd_transition_swapchain_image(
      render_command,
      swapchaine_image_index,
      .GENERAL,
      .PRESENT_SRC_KHR,
      VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
      VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
      VK_ACCESS_2_MEMORY_WRITE_BIT,
      VK_ACCESS_2_MEMORY_READ_BIT,
    );

    end_render_command(render_command);
    graphics_queue_submit(render_command, render_command, render_command, swapchaine_image_index);
    need_swapchain_recreation = present_frame_context(swapchaine_image_index);
  }
}

Pipeline :: struct {
  #as pipeline: VkPipeline;
  #as layout:   VkPipelineLayout;
  dsl:          VkDescriptorSetLayout;
}
create_full_screen_effect_comptue_pipeline :: () -> Pipeline {
  binging_layout: VkDescriptorSetLayoutBinding = .{
    binding         = 0,
    descriptorCount = 1,
    descriptorType  = .STORAGE_IMAGE,
    stageFlags      = .COMPUTE_BIT,
  };
  layout_create_info: VkDescriptorSetLayoutCreateInfo = .{
    flags        = .PUSH_DESCRIPTOR_BIT,
    pBindings    = *binging_layout,
    bindingCount = 1,
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

#import,file "platform.jai";
#import,file "vulkan.jai";
#import "Basic";
#import "Vulkan";
