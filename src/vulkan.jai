VALIDATION_LAYERS_NAMES := *u8.[
    "VK_LAYER_KHRONOS_validation",
];
INSTANCE_EXTENSIONS := *u8.[
    "VK_EXT_debug_utils",
    "VK_EXT_surface_maintenance1",
    "VK_KHR_get_surface_capabilities2",
];
DEVICE_EXTENSIONS := *u8.[
    "VK_KHR_swapchain",
    "VK_KHR_maintenance5",
    "VK_EXT_swapchain_maintenance1",
    "VK_KHR_push_descriptor",
    // "VK_KHR_unified_image_layouts",
];
MINIMAL_API_VERSION := #run api_version(0, 1, 3, 0);

instance:              VkInstance;
instance_version:      ApiVersion;
debug_messanger:       VkDebugUtilsMessengerEXT;
surface:               VkSurfaceKHR;
physical_device:       VkPhysicalDevice;
device:                VkDevice;
graphics_queue_family: u32;
graphics_queue:        VkQueue;
present_queue_family:  u32;
present_queue:         VkQueue;
compute_queue_family:  u32;
compute_queue:         VkQueue;
transfer_queue_family: u32;
transfer_queue:        VkQueue;

swapchain_pool: Flat_Pool;
swapchain: VkSwapchainKHR;
swapchain_images: []VkImage;
swapchain_image_views: []VkImageView;
// NOTE: per swapchain image semaphores are required to safely reuse
// swapchain images. these are used between vkQueueSubmit and vkQueuePresent calls
swapchain_semaphores: []VkSemaphore;
// NOTE: these are for vkQueuePresentKHR. They will be signaled when the resources
// associated with a present operation can be safely destroyed.
swapchain_fences: []VkFence;
swapchain_format: VkFormat = .UNDEFINED;
swapchain_extent: VkExtent2D;

graphics_command_pool: VkCommandPool;

vulkan_init :: (enable_validation: bool) -> success: bool {
  get_proc := platform_vulkan_proc_addr();
  if !load_basic_procs(get_proc) return false;
  init_instance(enable_validation);
  if !instance return false;
  if !load_instance_procs(get_proc) return false;
  if enable_validation debug_messanger = init_debug_messanger();
  platform_create_surface(instance, *surface);
  if !surface return false;
  select_physical_device(enable_validation);
  if !physical_device return false;
  init_device();
  if !device return false;
  init_swapchain(window_width, window_height, null);
  if !swapchain return false;
  graphics_command_pool = init_command_pool(graphics_queue_family);
  return true;
}

create_fence :: (create_info: VkFenceCreateInfo) -> VkFence  {
  result: VkFence = ---;
  assert(!vkCreateFence(device, *create_info, null, *result));
  return result;
}

create_semaphore :: (create_info: VkSemaphoreCreateInfo) -> VkSemaphore  {
  result: VkSemaphore = ---;
  assert(!vkCreateSemaphore(device, *create_info, null, *result));
  return result;
}

create_buffer:: (create_info: VkBufferCreateInfo) -> VkBuffer {
  result: VkBuffer = ---;
  assert(!vkCreateBuffer(device, *create_info, null, *result));
  return result;
}

create_image:: (create_info: VkImageCreateInfo) -> VkImage {
  result: VkImage = ---;
  assert(!vkCreateImage(device, *create_info, null, *result));
  return result;
}

create_image_view :: (create_info: VkImageViewCreateInfo) -> VkImageView {
  result: VkImageView = ---;
  assert(!vkCreateImageView(device, *create_info, null, *result));
  return result;
}

create_descriptor_set_layout :: (create_info: VkDescriptorSetLayoutCreateInfo) -> VkDescriptorSetLayout {
  result: VkDescriptorSetLayout = ---;
  assert(!vkCreateDescriptorSetLayout(device, *create_info, null, *result));
  return result;
}

create_sampler :: (create_info: VkSamplerCreateInfo) -> VkSampler {
  result: VkSampler = ---;
  assert(!vkCreateSampler(device, *create_info, null, *result));
  return result;
}

create_pipeline_layout :: (create_info: VkPipelineLayoutCreateInfo) -> VkPipelineLayout {
  result: VkPipelineLayout = ---;
  assert(!vkCreatePipelineLayout(device, *create_info, null, *result));
  return result;
}

create_compute_pipeline :: (create_info: VkComputePipelineCreateInfo) -> VkPipeline {
  result: VkPipeline = ---;
  assert(!vkCreateComputePipelines(device, null, 1, *create_info, null, *result));
  return result;
}

create_graphics_pipeline :: (create_info: VkGraphicsPipelineCreateInfo) -> VkPipeline {
  result: VkPipeline = ---;
  assert(!vkCreateGraphicsPipelines(device, null, 1, *create_info, null, *result));
  return result;
}

create_query_pool :: (create_info: VkQueryPoolCreateInfo) -> VkQueryPool {
  result: VkQueryPool = ---;
  assert(!vkCreateQueryPool(device, *create_info, null, *result));
  return result;
}

get_query_pool_results :: (pool: VkQueryPool, data: []u64, wait := true) {
  r := vkGetQueryPoolResults(
      device,
      pool,
      0,
      xx data.count,
      xx (data.count * size_of(u64)),
      data.data,
      size_of(u64),
      ._64_BIT | ifx wait VkQueryResultFlags.WAIT_BIT else 0,
  );
  // The very first call to this will fail because query is not reset. This is fine.
  // assert(r == .SUCCESS || r == .NOT_READY);
}

get_buffer_memory_requirements :: (buffer: VkBuffer) -> VkMemoryRequirements {
  result: VkMemoryRequirements = ---;
  vkGetBufferMemoryRequirements(device, buffer, *result);
  return result;
}

get_image_memory_requirements :: (image: VkImage) -> VkMemoryRequirements {
  result: VkMemoryRequirements = ---;
  vkGetImageMemoryRequirements(device, image, *result);
  return result;
}

get_buffer_address :: (buffer: VkBuffer) -> VkDeviceAddress {
  result: VkDeviceAddress = ---;
  info: VkBufferDeviceAddressInfo = .{ buffer = buffer };
  result = vkGetBufferDeviceAddress(device, *info);
  return result;
}

bind_buffer_memory :: (buffer: VkBuffer, device_memory: VkDeviceMemory, offset: u32) {
  assert(!vkBindBufferMemory(device, buffer, device_memory, offset));
}

bind_image_memory :: (image: VkImage, device_memory: VkDeviceMemory, offset: u32) {
  assert(!vkBindImageMemory(device, image, device_memory, offset));
}

allocate_command_buffer :: (allocate_info: VkCommandBufferAllocateInfo) -> VkCommandBuffer {
  result: VkCommandBuffer = ---;
  assert(!vkAllocateCommandBuffers(device, *allocate_info, *result));
  return result;
}

reset_command_buffer :: (cmd: VkCommandBuffer) {
  assert(!vkResetCommandBuffer(cmd, 0));
}

device_wait_idle :: () {
  vkDeviceWaitIdle(device);
}

destroy_image :: (image: VkImage) {
  vkDestroyImage(device, image, null);
}

destroy_image_view :: (view: VkImageView) {
  vkDestroyImageView(device, view, null);
}

destroy_semaphore :: (semaphore: VkSemaphore) {
  vkDestroySemaphore(device, semaphore, null);
}

destroy_fence :: (fence: VkFence) {
  vkDestroyFence(device, fence, null);
}

destroy_swapchain :: (swapchain: VkSwapchainKHR) {
  vkDestroySwapchainKHR(device, swapchain, null);
}

destroy_descriptor_set_layout :: (layout: VkDescriptorSetLayout) {
  vkDestroyDescriptorSetLayout(device, layout, null);
}

destroy_pipeline_layout :: (layout: VkPipelineLayout) {
  vkDestroyPipelineLayout(device, layout, null);
}

destroy_pipeline :: (pipeline: VkPipeline) {
  vkDestroyPipeline(device, pipeline, null);
}

begin_command_buffer :: (cmd: VkCommandBuffer, begin_info: VkCommandBufferBeginInfo) {
  assert(!vkBeginCommandBuffer(cmd, *begin_info));
}

end_command_buffer :: (cmd: VkCommandBuffer) {
  assert(!vkEndCommandBuffer(cmd));
}

wait_for_fence :: (fence: VkFence) {
  assert(!vkWaitForFences(device, 1, *fence, xx true, ~0));
}

reset_fences :: (fences: []VkFence) {
  assert(!vkResetFences(device, xx fences.count, fences.data));
}

wait_swapchain_fence :: (index: u32) {
  wait_for_fence(swapchain_fences[index]);
}

cmd_copy_buffer_to_buffer :: (cmd: VkCommandBuffer, dst: VkBuffer, src: VkBuffer, copy: VkBufferCopy) {
  vkCmdCopyBuffer(cmd, src, dst, 1, *copy);
}

cmd_copy_buffer_to_image :: (cmd: VkCommandBuffer, buffer: VkBuffer, image: VkImage, extent: VkExtent3D) {
  copy_region: VkBufferImageCopy = .{
    imageExtent = extent,
    imageSubresource = .{
      layerCount = VK_REMAINING_ARRAY_LAYERS,
      aspectMask = .COLOR_BIT,
    },
  };
  vkCmdCopyBufferToImage(cmd, buffer, image, .GENERAL, 1, *copy_region);
}

cmd_bind_pipeline :: (cmd: VkCommandBuffer, pipeline: VkPipeline, bind_point: VkPipelineBindPoint) {
  vkCmdBindPipeline(cmd, bind_point, pipeline);
}

cmd_bind_index_buffer :: (cmd: VkCommandBuffer, buffer: VkBuffer, offset: u32, index_type: VkIndexType) {
  vkCmdBindIndexBuffer(cmd, buffer, offset, index_type);
}

cmd_push_descriptors :: (
  cmd:             VkCommandBuffer,
  pipeline_layout: VkPipelineLayout,
  bind_point:      VkPipelineBindPoint,
  descriptors:     []VkWriteDescriptorSet,
) {
  vkCmdPushDescriptorSetKHR(cmd, bind_point, pipeline_layout, 0, xx descriptors.count, descriptors.data);
}

cmd_push_constants :: (
  cmd:             VkCommandBuffer,
  pipeline_layout: VkPipelineLayout,
  stage_flags:     VkShaderStageFlags,
  constants:       *$T,
) {
  vkCmdPushConstants(cmd, pipeline_layout, stage_flags, 0, size_of(T), constants);
}

cmd_reset_query_pool :: (cmd: VkCommandBuffer, pool: VkQueryPool, size: u32) {
  vkCmdResetQueryPool(cmd, pool, 0, size);
}

cmd_write_timestamp :: (
  cmd:   VkCommandBuffer,
  pool:  VkQueryPool,
  stage: VkPipelineStageFlags,
  idx:   u32,
) {
  vkCmdWriteTimestamp(cmd, stage, pool, idx);
}

cmd_dispatch :: (cmd: VkCommandBuffer, group_count_x: u32,  group_count_y: u32, group_count_z: u32) {
  vkCmdDispatch(cmd, group_count_x, group_count_y, group_count_z);
}

cmd_draw :: (
  cmd:            VkCommandBuffer,
  vertex_count:   u32,
  instance_count: u32,
  first_vertex:   u32,
  first_instance: u32,
) {
  vkCmdDraw(cmd, vertex_count, instance_count, first_vertex, first_instance);
}

cmd_draw_indexed :: (
  cmd:            VkCommandBuffer,
  index_count:    u32,
  instance_count: u32,
  first_index:    u32,
  vertex_offset:  u32,
  first_instance: u32,
) {
  vkCmdDrawIndexed(cmd, index_count, instance_count, first_index, xx vertex_offset, first_instance);
}

cmd_begin_rendering_to_swapchain :: (
  cmd: VkCommandBuffer,
  image_index: u32,
  depth_image_view: VkImageView = null
) {
  sc_view := swapchain_image_views[image_index];

  color_attachment: VkRenderingAttachmentInfo = .{
    imageView          = sc_view,
    imageLayout        = .GENERAL,
    resolveImageLayout = .UNDEFINED,
    loadOp             = .LOAD,
    clearValue         = .{ color = .{ _float32 = .[ 0.0, 0.0, 0.0, 0.0 ] } },
    storeOp            = .STORE,
  };

  depth_attachment: VkRenderingAttachmentInfo;
  if depth_image_view {
    depth_attachment = .{
      imageView   = depth_image_view,
      imageLayout = .GENERAL,
      loadOp      = .CLEAR,
      storeOp     = .STORE,
      clearValue  = .{ depthStencil = .{ depth = 0.0 } },
    };
  }

  render_info: VkRenderingInfo = .{
    pColorAttachments    = *color_attachment,
    colorAttachmentCount = 1,
    pDepthAttachment     = ifx depth_image_view then *depth_attachment,
    renderArea           = .{ extent = swapchain_extent },
    layerCount           = 1,
  };
  vkCmdBeginRendering(cmd, *render_info);

  viewport: VkViewport = .{
    x        = 0.0,
    y        = 0.0,
    width    = xx swapchain_extent.width,
    height   = xx swapchain_extent.height,
    minDepth = 0.0,
    maxDepth = 1.0,
  };
  vkCmdSetViewport(cmd, 0, 1, *viewport);
  scissor: VkRect2D = .{ offset = .{ 0, 0 }, extent = swapchain_extent };
  vkCmdSetScissor(cmd, 0, 1, *scissor);
}

cmd_end_rendering :: (cmd: VkCommandBuffer) {
  vkCmdEndRendering(cmd);
}

cmd_barrier :: (
  cmd: VkCommandBuffer,
  src_stage:  VkPipelineStageFlags2,
  dst_stage:  VkPipelineStageFlags2,
  src_access: VkAccessFlags2,
  dst_access: VkAccessFlags2,
) {
  barrier: VkMemoryBarrier2  = .{
    srcStageMask     = src_stage,
    srcAccessMask    = src_access,
    dstStageMask     = dst_stage,
    dstAccessMask    = dst_access,
  };
  dependency: VkDependencyInfo = .{
    pMemoryBarriers    = *barrier,
    memoryBarrierCount = 1,
  };
  vkCmdPipelineBarrier2(cmd, *dependency);
}

transition_image :: (
  cmd:        VkCommandBuffer,
  image:      VkImage,
  usage:      VkImageUsageFlags,
  src_layout: VkImageLayout,
  dst_layout: VkImageLayout,
  src_stage:  VkPipelineStageFlags2,
  dst_stage:  VkPipelineStageFlags2,
  src_access: VkAccessFlags2,
  dst_access: VkAccessFlags2,
) {
  assert(image != null, "Trying to transition null VkImage");

  subresource: VkImageSubresourceRange = .{
    aspectMask     = ifx usage & .DEPTH_STENCIL_ATTACHMENT_BIT then .DEPTH_BIT else .COLOR_BIT,
    baseMipLevel   = 0,
    levelCount     = VK_REMAINING_MIP_LEVELS,
    baseArrayLayer = 0,
    layerCount     = VK_REMAINING_ARRAY_LAYERS,
  };
  barrier: VkImageMemoryBarrier2 = .{
    srcStageMask     = src_stage,
    srcAccessMask    = src_access,
    dstStageMask     = dst_stage,
    dstAccessMask    = dst_access,
    oldLayout        = src_layout,
    newLayout        = dst_layout,
    subresourceRange = subresource,
    image            = image,
  };
  dependency: VkDependencyInfo = .{
    pImageMemoryBarriers    = *barrier,
    imageMemoryBarrierCount = 1,
  };
  vkCmdPipelineBarrier2(cmd, *dependency);
}

queue_submit :: (submit_info: VkSubmitInfo2, fence: VkFence) {
  assert(!vkQueueSubmit2(graphics_queue, 1, *submit_info, fence));
}

find_arena_index :: (type_bits: u32, properties: VkMemoryPropertyFlags) -> u32 {
  result: u32;
  mp := get_physical_device_memory_properties(physical_device);
  for 0..mp.memoryTypeCount -1 {
    if (1 << it & type_bits) != 0 &&
       mp.memoryTypes[it].propertyFlags & properties == properties {
      result = xx it;
      break;
    }
  }
  return result;
}

allocate_memory :: (memory_type_idx: u32, size: u64) -> VkDeviceMemory {
  // note(sc): this should be fine to enable all the time if the
  // VkPhysicalDeviceBufferDeviceAddressFeatures.bufferDeviceAddress is set
  // which is required.
  allocate_flags: VkMemoryAllocateFlagsInfo = .{ flags = .DEVICE_ADDRESS_BIT };
  memory_allocate_info: VkMemoryAllocateInfo = .{
      pNext = *allocate_flags,
      allocationSize = size,
      memoryTypeIndex = memory_type_idx,
  };
  result: VkDeviceMemory = ---;
  assert(!vkAllocateMemory(device, *memory_allocate_info, null, *result));
  return result;
}

map_memory :: (device_memory: VkDeviceMemory, size: u32) -> []u8 {
  result: []u8;
  assert(!vkMapMemory(device, device_memory, 0, size, 0, xx *result.data));
  result.count = size;
  return result;
}

acquire_next_image :: (smaphore: VkSemaphore) -> next_image: u32, need_swapchain_recreation: bool {
  result: u32 = ---;
  r := vkAcquireNextImageKHR(device, swapchain, ~0, smaphore, null, *result);
  if r == .VK_SUBOPTIMAL_KHR || r == .VK_ERROR_OUT_OF_DATE_KHR return result, true;

  assert(!r, "Cannot acquire next image: %", r);

  fence := swapchain_fences[result];
  wait_for_fence(fence);
  reset_fences(.[fence]);
  return result, false;
}

graphics_queue_submit :: (cmd: VkCommandBuffer, semaphore: VkSemaphore, fence: VkFence, image_idx: u32) {
  buffer_submit_info: VkCommandBufferSubmitInfo = .{ commandBuffer = cmd, deviceMask = 0 };
  wait_semaphore_info: VkSemaphoreSubmitInfo = .{
    semaphore = semaphore,
    stageMask = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
  };
  signal_semaphore_info: VkSemaphoreSubmitInfo = .{
    semaphore = swapchain_semaphores[image_idx],
    stageMask = VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
  };
  submit_info: VkSubmitInfo2 = .{
    pWaitSemaphoreInfos      = *wait_semaphore_info,
    waitSemaphoreInfoCount   = 1,
    pSignalSemaphoreInfos    = *signal_semaphore_info,
    signalSemaphoreInfoCount = 1,
    pCommandBufferInfos      = *buffer_submit_info,
    commandBufferInfoCount   = 1,
  };
  queue_submit(submit_info, fence);
}

present_frame_context :: (image_idx: u32) -> need_swapchain_recreation: bool {
  fence := *swapchain_fences[image_idx];
  present_info_fence: VkSwapchainPresentFenceInfoKHR = .{ swapchainCount = 1, pFences = fence };
  present_info: VkPresentInfoKHR = .{
    pNext              = *present_info_fence,
    pSwapchains        = *swapchain,
    swapchainCount     = 1,
    pWaitSemaphores    = *swapchain_semaphores[image_idx],
    waitSemaphoreCount = 1,
    pImageIndices      = *image_idx,
  };
  r := vkQueuePresentKHR(graphics_queue, *present_info);
  if r != .VK_SUCCESS && r != .VK_SUBOPTIMAL_KHR {
    log_error("Cannot present to graphics queue: %", r);
  }
  // note(sc): the windowing system might not tell the driver about the window resizing
  // so do the check manually
  need_swapchain_recreation := r == .VK_SUBOPTIMAL_KHR ||
                               swapchain_extent.width  != window_width ||
                               swapchain_extent.height != window_height;
  return need_swapchain_recreation;
}

recreate_swapchain :: () {
  for swapchain_image_views destroy_image_view(it);
  for swapchain_semaphores  destroy_semaphore(it);
  for swapchain_fences      destroy_fence(it);
  old_swapchain := swapchain;
  init_swapchain(window_width, window_height, old_swapchain);
  destroy_swapchain(old_swapchain);
}

#scope_file

ApiVersion :: #type,distinct u32;
api_version :: (variant: u32, major: u32, minor: u32, patch: u32) -> ApiVersion {
  return xx ((variant & ((1 <<  3) - 1)) << 29) |
            ((major   & ((1 <<  7) - 1)) << 22) |
            ((minor   & ((1 << 10) - 1)) << 12) |
            ((patch   & ((1 << 12) - 1)));
}
api_version_patch :: (version: ApiVersion) -> u32 {
  v: u32 = xx version;
  MASK: u32 = (1 << 12) - 1;
  return v & MASK;
}
api_version_minor :: (version: ApiVersion) -> u32 {
  v: u32 = xx version;
  MASK: u32 = (1 << 10) - 1;
  SHIFT: u32 = 12;
  return (v >> SHIFT) & MASK;
}
api_version_major :: (version: ApiVersion) -> u32 {
  v: u32 = xx version;
  MASK: u32 = (1 << 7) - 1;
  SHIFT: u32 = 22;
  return (v >> SHIFT) & MASK;
}
api_version_variant :: (version: ApiVersion) -> u32 {
  v: u32 = xx version;
  MASK: u32 = (1 << 3) - 1;
  SHIFT: u32 = 29;
  return (v >> SHIFT) & MASK;
}

get_api_version :: () -> ApiVersion, bool {
    version: ApiVersion = ---;
    result := vkEnumerateInstanceVersion(*version) == .VK_SUCCESS;
    return version, result;
}

get_instance_extensions :: () -> []VkExtensionProperties, VkResult {
    count: u32 = ---;
    data: []VkExtensionProperties = ---;
    result: VkResult = ---;
    result = vkEnumerateInstanceExtensionProperties(null, *count, null);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkExtensionProperties, initialized = false);
    result = vkEnumerateInstanceExtensionProperties(null, *count, data.data);
    return data, result;
}

get_instance_layers :: () ->[]VkLayerProperties, VkResult {
  count: u32 = ---;
  data: []VkLayerProperties = ---;
  result: VkResult = ---;
  result = vkEnumerateInstanceLayerProperties(*count, null);
  if result return .[], result;
  if count == 0 return .[], .SUCCESS;
  data = NewArray(count, VkLayerProperties, initialized = false);
  result = vkEnumerateInstanceLayerProperties(*count, data.data);
  return data, result;
}

contains_all_extensions :: (prefix: string, extensions: []VkExtensionProperties, to_find_slices: [][]*u8) -> bool {
  found_extensions        := 0;
  searched_for_extensions := 0;
  bitfind                 := 0;
  for to_find_slices searched_for_extensions += it.count;

  for e: extensions {
    for to_find, i: to_find_slices {
      for tf, j: to_find {
        extension_name    := to_string(e.extensionName);
        tf_extension_name := to_string(tf);
        bit := 1 << (i * to_find_slices.count + j);
        if extension_name == tf_extension_name && (bitfind & bit == 0) {
          log("found: %", extension_name);
          found_extensions += 1;
          bitfind |= bit;
        }
      }
    }
  }
  found_all := found_extensions == searched_for_extensions;
  if (!found_all) {
    for to_find, i: to_find_slices {
      for tf, j: to_find {
        bit := 1 << (i * to_find_slices.count + j);
        if bitfind & bit == 0 log_error("[%]: Missing extension: %", prefix, tf);
      }
    }
  }
  return found_all;
}

contains_all_layers :: (prefix: string, layers: []VkLayerProperties, to_find: []*u8) -> bool {
  found_layers := 0;
  bitfind      := 0;
  for l: layers {
    for tf, i: to_find {
      layer_name    := to_string(l.layerName);
      tf_layer_name := to_string(tf);
      bit := 1 << i;
      if layer_name == tf_layer_name && (bitfind & bit == 0) {
        found_layers += 1;
        bitfind |= bit;
      }
    }
  }
  found_all := found_layers == to_find.count;
  if !found_all {
    for tf, i: to_find {
      tf_layer_name := to_string(tf);
      bit := 1 << i;
      if bitfind & bit == 0 log("[%]: Missing layer: %", prefix, tf_layer_name);
    }
  }
  return found_all;
}

init_instance :: (enable_validation: bool) {
  current_version, ok := get_api_version();
  if !ok return;

  log("Supported vulkan version: %.%.%",
      api_version_major(current_version),
      api_version_minor(current_version),
      api_version_patch(current_version),
  );
  log(
      "Wanted vulkan version: %.%.%",
      api_version_major(MINIMAL_API_VERSION),
      api_version_minor(MINIMAL_API_VERSION),
      api_version_patch(MINIMAL_API_VERSION),
  );
  if current_version < MINIMAL_API_VERSION {
      log_error("Wanted vulkan api version is above the supported version");
      return;
  }

  extensions, err := get_instance_extensions(,, temp);
  if err return;
  platform_extensions := platform_vulkan_extensions();

  if !contains_all_extensions("Instance", extensions, .[platform_extensions, INSTANCE_EXTENSIONS]) {
    return;
  }

  total_extensions_count := platform_extensions.count + INSTANCE_EXTENSIONS.count;
  enabled_extensions: []*u8 = NewArray(total_extensions_count, *u8, initialized = false,, temp);
  if !enabled_extensions return;
  {
    i: u32 = 0;
    for platform_extensions { enabled_extensions[i] = it; i += 1; }
    for INSTANCE_EXTENSIONS { enabled_extensions[i] = it; i += 1; }
  }

  enabled_layers: []*u8;
  if enable_validation {
      layers, err := get_instance_layers(,, temp);
      if err return;
      if !contains_all_layers("Instance", layers, VALIDATION_LAYERS_NAMES) return;
      enabled_layers = VALIDATION_LAYERS_NAMES;
  }

  instance_version = current_version;
  app_info := VkApplicationInfo.{
      pApplicationName   = "shiver",
      applicationVersion = xx api_version(0, 0, 0, 1),
      pEngineName        = "tempest",
      engineVersion      = xx api_version(0, 0, 0, 1),
      apiVersion         = xx current_version,
  };
  instance_create_info := VkInstanceCreateInfo.{
      pApplicationInfo        = *app_info,
      ppEnabledExtensionNames = enabled_extensions.data,
      enabledExtensionCount   = xx enabled_extensions.count,
      ppEnabledLayerNames     = enabled_layers.data,
      enabledLayerCount       = xx enabled_layers.count,
  };
  for enabled_extensions log("Instance: enabling extension: %", to_string(it));
  for enabled_layers     log("Instance: enabling layer: %",     to_string(it));

  r := vkCreateInstance(*instance_create_info, null, *instance);
  if r != .VK_SUCCESS {
    log_error("Failed to create instance: %\n", r);
  }
}

init_debug_messanger :: () -> VkDebugUtilsMessengerEXT {
  result: VkDebugUtilsMessengerEXT;
  if vkCreateDebugUtilsMessengerEXT {
    create_info := VkDebugUtilsMessengerCreateInfoEXT.{
      messageSeverity = .VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT |
                        .VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                        .VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
      messageType = .VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                    .VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                    .VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
      pfnUserCallback = debug_messanger_callback,
    };
    vkCreateDebugUtilsMessengerEXT(instance, *create_info, null, *result);
  }
  return result;
}

debug_messanger_callback :: (
  severity: VkDebugUtilsMessageSeverityFlagBitsEXT,
  msg_type: VkDebugUtilsMessageTypeFlagsEXT,
  data: *VkDebugUtilsMessengerCallbackDataEXT,
  _: *void
) -> VkBool32 #c_call {
  msg_type_str := "unknown";
  if      msg_type & .VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT     msg_type_str = "general";
  else if msg_type & .VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT  msg_type_str = "validation";
  else if msg_type & .VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT msg_type_str = "performance";

  msg_str := ifx data then to_string(data.pMessage) else "empty";
  push_context {
    if severity & .VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT
      log("[%]: %", msg_type_str, msg_str, flags = .ERROR);
    else if severity & .VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT
      log("[%]: %", msg_type_str, msg_str, flags = .WARNING);
    else if severity & .VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT
      log("[%]: %", msg_type_str, msg_str, flags = .VERBOSE_ONLY);
  }
  return xx true;
}

get_physical_devices :: () -> []VkPhysicalDevice, VkResult {
  count: u32 = ---;
  data: []VkPhysicalDevice = ---;
  result: VkResult = ---;
  result = vkEnumeratePhysicalDevices(instance, *count, null);
  if result return .[], result;
  if count == 0 return .[], .SUCCESS;
  data = NewArray(count, VkPhysicalDevice, initialized = false);
  result = vkEnumeratePhysicalDevices(instance, *count, data.data);
  return data, result;
}

get_physical_device_exensions :: (physical_device: VkPhysicalDevice) -> []VkExtensionProperties, VkResult {
  count: u32 = ---;
  data: []VkExtensionProperties = ---;
  result: VkResult = ---;
  result = vkEnumerateDeviceExtensionProperties(physical_device, null, *count, null);
  if result return .[], result;
  if count == 0 return .[], .SUCCESS;
  data = NewArray(count, VkExtensionProperties, initialized = false);
  result = vkEnumerateDeviceExtensionProperties(physical_device, null, *count, data.data);
  return data, result;
}

get_physical_device_layers :: (physical_device: VkPhysicalDevice) -> []VkLayerProperties, VkResult {
  count: u32 = ---;
  data: []VkLayerProperties = ---;
  result: VkResult = ---;
  result = vkEnumerateDeviceLayerProperties(physical_device, *count, null);
  if result return .[], result;
  if count == 0 return .[], .SUCCESS;
  data = NewArray(count, VkLayerProperties, initialized = false);
  result = vkEnumerateDeviceLayerProperties(physical_device, *count, data.data);
  return data, result;
}

get_physical_device_queue_families :: (physical_device: VkPhysicalDevice) -> []VkQueueFamilyProperties {
  count: u32 = ---;
  data: []VkQueueFamilyProperties = ---;
  vkGetPhysicalDeviceQueueFamilyProperties(physical_device, *count, null);
  if count == 0 return .[];
  data = NewArray(count, VkQueueFamilyProperties, initialized = false);
  vkGetPhysicalDeviceQueueFamilyProperties(physical_device, *count, data.data);
  return data;
}

get_physical_device_memory_properties :: (physical_device: VkPhysicalDevice) -> VkPhysicalDeviceMemoryProperties {
    result: VkPhysicalDeviceMemoryProperties;
    vkGetPhysicalDeviceMemoryProperties(physical_device, *result);
    return result;
}

select_physical_device :: (enable_validation: bool) {
    physical_devices, err := get_physical_devices(,, temp);
    if err return;

    for pd: physical_devices {
        properties: VkPhysicalDeviceProperties = ---;
        features:   VkPhysicalDeviceFeatures   = ---;
        vkGetPhysicalDeviceProperties(pd, *properties);
        vkGetPhysicalDeviceFeatures(pd, *features);

        device_name := to_string(properties.deviceName);
        log(#string DONE
Physical device:
   Name: %
   API version: %.%.%
   Driver version: %.%.%
   Vendor ID: %
   Device Id: %
   Device type: %
DONE
        ,
            device_name,
            api_version_major(xx properties.apiVersion),
            api_version_minor(xx properties.apiVersion),
            api_version_patch(xx properties.apiVersion),
            api_version_major(xx properties.driverVersion),
            api_version_minor(xx properties.driverVersion),
            api_version_patch(xx properties.driverVersion),
            properties.vendorID,
            properties.deviceID,
            properties.deviceType,
        );
        mp := get_physical_device_memory_properties(pd);
        log("Memory properties:\n    Types:\n");
        for 0..mp.memoryTypeCount
          log(
            "         heapIndex: % propertyFlags: %\n",
            mp.memoryTypes[it].heapIndex,
            mp.memoryTypes[it].propertyFlags
          );
        log("    Heaps:\n");
        for 0..mp.memoryHeapCount
          log(
            "        size: % flags: %\n",
            mp.memoryHeaps[it].size,
            mp.memoryHeaps[it].flags
          );

        if enable_validation {
            layers, err := get_physical_device_layers(pd,, temp);
            if err continue;
            if !contains_all_layers(device_name, layers, VALIDATION_LAYERS_NAMES)
              continue;
        }
        extensions, err := get_physical_device_exensions(pd,, temp);
        if err continue;
        if !contains_all_extensions(device_name, extensions, .[DEVICE_EXTENSIONS])
          continue;

        queue_families := get_physical_device_queue_families(pd,, temp);
        graphics_queue_family := -1;
        present_queue_family  := -1;
        compute_queue_family  := -1;
        transfer_queue_family := -1;

        for qf, i: queue_families {
            if graphics_queue_family == -1 && qf.queueFlags & .GRAPHICS_BIT graphics_queue_family = i;
            if compute_queue_family == -1 && qf.queueFlags & .COMPUTE_BIT compute_queue_family = i;
            if transfer_queue_family == -1 && qf.queueFlags & .TRANSFER_BIT transfer_queue_family = i;
            if present_queue_family == -1 {
                supported: VkBool32 = 0;
                _ = vkGetPhysicalDeviceSurfaceSupportKHR(
                    pd,
                    xx i,
                    surface,
                    *supported,
                );
                if supported present_queue_family = i;
            }
        }

        if (properties.deviceType == .DISCRETE_GPU || properties.deviceType == .INTEGRATED_GPU) &&
            graphics_queue_family != -1 &&
            present_queue_family != -1 &&
            compute_queue_family != -1 &&
            transfer_queue_family != -1
        {
            log(#string DONE
Selected device % with queues:
  Graphics queue family: %
  Present queue family: %
  Compute queue family: %
  Transfer queue family: %
DONE
            ,
                device_name,
                graphics_queue_family,
                present_queue_family,
                compute_queue_family,
                transfer_queue_family,
            );

            physical_device = pd;
            graphics_queue_family = xx graphics_queue_family;
            present_queue_family  = xx present_queue_family;
            compute_queue_family  = xx compute_queue_family;
            transfer_queue_family = xx transfer_queue_family;
        }
    }
}

init_device :: () {
  unique_count := 0;
  ui := s32.[-1, -1, -1, -1];
  unique_indexes : []s32 = ui;
  for qf : u32.[graphics_queue_family, present_queue_family, compute_queue_family, transfer_queue_family] {
    for unique_indexes if it == xx qf continue qf;
    unique_indexes[unique_count] = xx qf;
    unique_count += 1;
  }
  unique_indexes.count = unique_count;

  qci: [4]VkDeviceQueueCreateInfo = ---;
  queue_create_infos: []VkDeviceQueueCreateInfo  = .{data = qci.data, count = unique_count };

  queue_priority: float = 1.0;
  for 0..unique_count - 1 {
    queue_create_infos[it] = .{
      queueFamilyIndex = xx ui[it],
      queueCount       = 1,
      pQueuePriorities = *queue_priority,
    };
  }

  unified_image_layouts: VkPhysicalDeviceUnifiedImageLayoutsFeaturesKHR;
  physical_device_features_1_4: VkPhysicalDeviceVulkan14Features;
  maintenance5: VkPhysicalDeviceMaintenance5Features;

  swapchain_maintenance1: VkPhysicalDeviceSwapchainMaintenance1FeaturesKHR = .{
    swapchainMaintenance1 = xx true,
  };
  physical_device_features_1_3: VkPhysicalDeviceVulkan13Features = .{
    dynamicRendering = xx true,
    synchronization2 = xx true,
  };
  if api_version(0, 1, 4, 0) <= instance_version {
    unified_image_layouts = .{
      pNext               = *swapchain_maintenance1,
      unifiedImageLayouts = xx true,
    };
    physical_device_features_1_4 = .{
      pNext          = *unified_image_layouts,
      maintenance5   = xx true,
      pushDescriptor = xx true,
    };
    physical_device_features_1_3.pNext = *physical_device_features_1_4;
  } else {
    maintenance5 = .{
      pNext        = *swapchain_maintenance1,
      maintenance5 = xx true,
    };
    physical_device_features_1_3.pNext = *maintenance5;
  }
  physical_device_features_1_2: VkPhysicalDeviceVulkan12Features = .{
    pNext               = *physical_device_features_1_3,
    bufferDeviceAddress = xx true,
    descriptorIndexing  = xx true,
  };
  physical_device_features: VkPhysicalDeviceFeatures = .{
    shaderInt64 = xx true,
  };

  create_info: VkDeviceCreateInfo = .{
    pNext                   = *physical_device_features_1_2,
    queueCreateInfoCount    = xx queue_create_infos.count,
    pQueueCreateInfos       = queue_create_infos.data,
    ppEnabledExtensionNames = DEVICE_EXTENSIONS.data,
    enabledExtensionCount   = DEVICE_EXTENSIONS.count,
    pEnabledFeatures        = *physical_device_features,
  };

  for DEVICE_EXTENSIONS log("(Device) Enabled extension: %\n", to_string(it));

  r := vkCreateDevice(physical_device, *create_info, null, *device);
  if r != .SUCCESS {
    log_error("Cannot create device: %\n", r);
    return;
  }
  vkGetDeviceQueue(device, present_queue_family,  0, *present_queue);
  vkGetDeviceQueue(device, graphics_queue_family, 0, *graphics_queue);
  vkGetDeviceQueue(device, compute_queue_family,  0, *compute_queue);
  vkGetDeviceQueue(device, transfer_queue_family, 0, *transfer_queue);
}

get_swapchain_formats :: () -> []VkSurfaceFormatKHR {
  count: u32 = ---;
  data: []VkSurfaceFormatKHR  = ---;
  err: VkResult = ---;
  err = vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, *count, null);
  assert(!err);
  if count == 0 return .[];
  data = NewArray(count, VkSurfaceFormatKHR, initialized = false);
  err = vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, *count, data.data);
  assert(!err);
  return data;
}

get_swapchain_images :: () -> []VkImage {
  count: u32 = ---;
  data: []VkImage   = ---;
  err: VkResult = ---;
  err = vkGetSwapchainImagesKHR(device, swapchain, *count, null);
  assert(!err);
  if count == 0 return .[];
  data = NewArray(count, VkImage, initialized = false);
  err = vkGetSwapchainImagesKHR(device, swapchain, *count, data.data);
  assert(!err);
  return data;
}

init_swapchain :: (width: u32, height: u32, old_swapchain: VkSwapchainKHR) {
  surface_capabilities: VkSurfaceCapabilitiesKHR = ---;
  assert(!vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, *surface_capabilities));

  log(#string DONE
Surface capabilities:
  Min image count: %
  Max image count: %
  Current extent: w: % h: %
  Min extent: w: % h: %
  Max extent: w: % h: %
DONE
  ,
    surface_capabilities.minImageCount,
    surface_capabilities.maxImageCount,
    surface_capabilities.currentExtent.width,
    surface_capabilities.currentExtent.height,
    surface_capabilities.minImageExtent.width,
    surface_capabilities.minImageExtent.height,
    surface_capabilities.maxImageExtent.width,
    surface_capabilities.maxImageExtent.height,
  );

  surface_formats := get_swapchain_formats(,, temp);
  surface_format_found := false;
  surface_format: VkSurfaceFormatKHR;
  for surface_formats {
      if it.format == .B8G8R8A8_UNORM && it.colorSpace == .COLOR_SPACE_SRGB_NONLINEAR_KHR {
          surface_format = it;
          surface_format_found = true;
          break;
      }
  }

  if surface_format_found {
    swapchain_format = surface_format.format;
    swapchain_extent = surface_capabilities.currentExtent;
    if swapchain_extent.width == 0xffff_ffff {
      swapchain_extent.width = min(
          max(width, surface_capabilities.minImageExtent.width),
          surface_capabilities.maxImageExtent.width,
      );
      swapchain_extent.height = min(
          max(height, surface_capabilities.minImageExtent.height),
          surface_capabilities.maxImageExtent.height,
      );
    }

    create_info: VkSwapchainCreateInfoKHR = .{
      surface          = surface,
      minImageCount    = surface_capabilities.minImageCount,
      imageFormat      = surface_format.format,
      imageColorSpace  = surface_format.colorSpace,
      imageExtent      = swapchain_extent,
      imageArrayLayers = 1,
      imageUsage       = .COLOR_ATTACHMENT_BIT | .TRANSFER_DST_BIT | .STORAGE_BIT,
      imageSharingMode = .VK_SHARING_MODE_EXCLUSIVE,
      preTransform     = surface_capabilities.currentTransform,
      compositeAlpha   = .OPAQUE_BIT_KHR,
      presentMode      = .FIFO_KHR,
      clipped          = xx true,
      oldSwapchain     = old_swapchain,
    };

    err := vkCreateSwapchainKHR(device, *create_info, null, *swapchain);
    if err {
      log_error("Cannot create swapchain: %\n", err);
      return;
    }

    reset(*swapchain_pool);
    new_context := context;
    new_context.allocator.proc = flat_pool_allocator_proc;
    new_context.allocator.data = *swapchain_pool;
    push_context new_context {
      swapchain_images      = get_swapchain_images();
      swapchain_image_views = NewArray(swapchain_images.count, VkImageView, initialized = false);
      swapchain_semaphores  = NewArray(swapchain_images.count, VkSemaphore, initialized = false);
      swapchain_fences      = NewArray(swapchain_images.count, VkFence,     initialized = false);
      for 0..swapchain_images.count - 1 {
        view_create_info: VkImageViewCreateInfo = .{
          image            = swapchain_images[it],
          viewType         = ._2D,
          format           = surface_format.format,
          components       = .{ .IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY },
          subresourceRange = .{
              aspectMask     = .COLOR_BIT,
              baseMipLevel   = 0,
              levelCount     = 1,
              baseArrayLayer = 0,
              layerCount     = 1,
          },
        };
        swapchain_image_views[it] = create_image_view(view_create_info);
        assert(xx swapchain_image_views[it], "Cannot create image view for the swapchain image");

        semaphore_create_info :VkSemaphoreCreateInfo;
        vkCreateSemaphore(device, *semaphore_create_info, null, *swapchain_semaphores[it]);
        assert(xx swapchain_semaphores[it], "Cannot create semaphore for the swapchain image");

        fence_create_info: VkFenceCreateInfo = .{ flags = .SIGNALED_BIT };
        vkCreateFence(device, *fence_create_info, null, *swapchain_fences[it]);
        assert(xx swapchain_fences[it], "Cannot create fence for the swapchain image");
      }
      log("Created swapchain: images: % extent: w: % h: %\n",
          swapchain_images.count, swapchain_extent.width, swapchain_extent.height);
    }
  }
}

init_command_pool :: (queue_family_index: u32) -> VkCommandPool {
    pool_create_info : VkCommandPoolCreateInfo = .{
        flags = .RESET_COMMAND_BUFFER_BIT,
        queueFamilyIndex = queue_family_index,
    };
    result: VkCommandPool = ---;
    assert(!vkCreateCommandPool(device, *pool_create_info, null, *result));
    return result;
}

load_procs :: (proc_name: string, $instance: bool, $names: []string) -> string #expand {
TEMPLATE :: #string,\% DONE
  %1 = xx get_proc(%2, "%1");
  if !%1 {
    log_error("Failed to load \% proc", "%1");
    return false;
  }
DONE
  builder: String_Builder;
  for names print_to_builder(*builder, "%1: PFN_%1 = ---;\n", it);

  print_to_builder(*builder, "% :: (get_proc: PFN_vkGetInstanceProcAddr) -> bool {\n", proc_name);
  if instance for names print_to_builder(*builder, TEMPLATE, it, "instance");
  else        for names print_to_builder(*builder, TEMPLATE, it, "null");
  print_to_builder(*builder, "  return true;\n}\n");
  return builder_to_string(*builder);
}

#insert #run load_procs("load_basic_procs", false, .[
  "vkCreateInstance",
  "vkEnumerateInstanceExtensionProperties",
  "vkEnumerateInstanceLayerProperties",
  "vkEnumerateInstanceVersion",
]);

#insert #run load_procs("load_instance_procs" , true, .[
  "vkDestroyInstance",
  "vkCreateDebugUtilsMessengerEXT",
  "vkDestroyDebugUtilsMessengerEXT",
  "vkEnumeratePhysicalDevices",
  "vkGetPhysicalDeviceProperties",
  "vkGetPhysicalDeviceFeatures",
  "vkGetPhysicalDeviceMemoryProperties",
  "vkEnumerateDeviceLayerProperties",
  "vkEnumerateDeviceExtensionProperties",
  "vkGetPhysicalDeviceQueueFamilyProperties",
  "vkGetPhysicalDeviceSurfaceSupportKHR",
  "vkDeviceWaitIdle",
  "vkCreateDevice",
  "vkDestroyDevice",
  "vkGetDeviceQueue",
  "vkGetPhysicalDeviceSurfaceCapabilitiesKHR",
  "vkGetPhysicalDeviceSurfaceFormatsKHR",
  "vkCreateSwapchainKHR",
  "vkDestroySwapchainKHR",
  "vkGetSwapchainImagesKHR",
  "vkCreateImageView",
  "vkDestroyImage",
  "vkDestroyImageView",
  "vkCreateCommandPool",
  "vkDestroyCommandPool",
  "vkAllocateCommandBuffers",
  "vkResetCommandBuffer",
  "vkBeginCommandBuffer",
  "vkEndCommandBuffer",
  "vkCreateFence",
  "vkWaitForFences",
  "vkResetFences",
  "vkDestroyFence",
  "vkCreateSemaphore",
  "vkDestroySemaphore",
  "vkCmdPipelineBarrier2",
  "vkCmdBeginRendering",
  "vkCmdEndRendering",
  "vkCmdSetViewport",
  "vkCmdSetScissor",
  "vkQueueSubmit2",
  "vkQueuePresentKHR",
  "vkAcquireNextImageKHR",
  "vkCreatePipelineLayout",
  "vkDestroyPipelineLayout",
  "vkCreateComputePipelines",
  "vkCreateGraphicsPipelines",
  "vkDestroyPipeline",
  "vkCmdBindPipeline",
  "vkCmdBindIndexBuffer",
  "vkCmdDispatch",
  "vkCmdPushDescriptorSetKHR",
  "vkCmdPushConstants",
  "vkCreateDescriptorSetLayout",
  "vkDestroyDescriptorSetLayout",
  "vkCreateBuffer",
  "vkBindBufferMemory",
  "vkGetBufferMemoryRequirements",
  "vkGetBufferDeviceAddress",
  "vkCreateImage",
  "vkCreateSampler",
  "vkBindImageMemory",
  "vkGetImageMemoryRequirements",
  "vkAllocateMemory",
  "vkMapMemory",
  "vkCmdCopyBufferToImage",
  "vkCmdCopyBuffer",
  "vkCmdDraw",
  "vkCmdDrawIndexed",
  "vkCreateQueryPool",
  "vkGetQueryPoolResults",
  "vkCmdResetQueryPool",
  "vkCmdWriteTimestamp",
]);

VK_REMAINING_MIP_LEVELS   :: 4294967295;
VK_REMAINING_ARRAY_LAYERS :: 4294967295;

#import "Basic";
#import "Vulkan";
#import "Flat_Pool";
using,only(
  platform_vulkan_proc_addr,
  platform_vulkan_extensions,
  platform_create_surface,
  window_width,
  window_height,
) platform :: #import,file "platform.jai";
