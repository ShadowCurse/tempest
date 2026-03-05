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
WANTED_API_VERSION := #run api_version(0, 1, 4, 0);


instance: VkInstance;
debug_messanger: VkDebugUtilsMessengerEXT;
surface: VkSurfaceKHR;
physical_device: VkPhysicalDevice;
// device: Device,
// swapchain: Swapchain,

vulkan_init :: (enable_validation: bool) -> success: bool {
  get_proc := platform_vulkan_proc_addr();
  if !load_basic_procs(get_proc) return false;
  ok := init_instance(enable_validation);
  if !ok return false;
  if !load_instance_procs(get_proc) return false;
  if enable_validation debug_messanger = init_debug_messanger();
  ok = platform_create_surface(instance, *surface);
  queue_families := select_physical_device(enable_validation);
  if !physical_device return false;
  return true;
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
    data = NewArray(count, VkExtensionProperties, initialized = false,, temp);
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
  data = NewArray(count, VkLayerProperties, initialized = false,, temp);
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

init_instance :: (enable_validation: bool) -> bool {
  current_version, ok := get_api_version();
  if !ok return false;

  log("Supported vulkan version: %.%.%",
      api_version_major(current_version),
      api_version_minor(current_version),
      api_version_patch(current_version),
  );
  log(
      "Wanted vulkan version: %.%.%",
      api_version_major(WANTED_API_VERSION),
      api_version_minor(WANTED_API_VERSION),
      api_version_patch(WANTED_API_VERSION),
  );
  if current_version < WANTED_API_VERSION {
      log_error("Wanted vulkan api version is above the supported version");
      return false;
  }

  extensions, err := get_instance_extensions();
  if err return false;
  platform_extensions := platform_vulkan_extensions();

  if !contains_all_extensions("Instance", extensions, .[platform_extensions, INSTANCE_EXTENSIONS]) {
    return false;
  }

  total_extensions_count := platform_extensions.count + INSTANCE_EXTENSIONS.count;
  enabled_extensions: []*u8 = NewArray(total_extensions_count, *u8, initialized = false,, temp);
  if !enabled_extensions return false;
  {
    i: u32 = 0;
    for platform_extensions { enabled_extensions[i] = it; i += 1; }
    for INSTANCE_EXTENSIONS { enabled_extensions[i] = it; i += 1; }
  }

  enabled_layers: []*u8;
  if enable_validation {
      layers, err := get_instance_layers();
      if err return false;
      if !contains_all_layers("Instance", layers, VALIDATION_LAYERS_NAMES) return false;
      enabled_layers = VALIDATION_LAYERS_NAMES;
  }

  app_info := VkApplicationInfo.{
      pApplicationName   = "shiver",
      applicationVersion = xx api_version(0, 0, 0, 1),
      pEngineName        = "tempest",
      engineVersion      = xx api_version(0, 0, 0, 1),
      apiVersion         = xx WANTED_API_VERSION,
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

  if vkCreateInstance(*instance_create_info, null, *instance) != .VK_SUCCESS return false;
  return true;
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
  data = NewArray(count, VkPhysicalDevice, initialized = false,, temp);
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
  data = NewArray(count, VkExtensionProperties, initialized = false,, temp);
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
  data = NewArray(count, VkLayerProperties, initialized = false,, temp);
  result = vkEnumerateDeviceLayerProperties(physical_device, *count, data.data);
  return data, result;
}

get_physical_device_queue_families :: (physical_device: VkPhysicalDevice) -> []VkQueueFamilyProperties {
  count: u32 = ---;
  data: []VkQueueFamilyProperties = ---;
  vkGetPhysicalDeviceQueueFamilyProperties(physical_device, *count, null);
  if count == 0 return .[];
  data = NewArray(count, VkQueueFamilyProperties, initialized = false,, temp);
  vkGetPhysicalDeviceQueueFamilyProperties(physical_device, *count, data.data);
  return data;
}

get_physical_device_memory_properties :: (physical_device: VkPhysicalDevice) -> VkPhysicalDeviceMemoryProperties {
    result: VkPhysicalDeviceMemoryProperties;
    vkGetPhysicalDeviceMemoryProperties(physical_device, *result);
    return result;
}

SelectedQueueFamilies :: struct {
    graphics_queue_family: u32 = 0;
    present_queue_family:  u32 = 0;
    compute_queue_family:  u32 = 0;
    transfer_queue_family: u32 = 0;
};

select_physical_device :: (enable_validation: bool) -> SelectedQueueFamilies {
    physical_devices, err := get_physical_devices();
    if err return .{};

    selected_queue_families: SelectedQueueFamilies;
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
            layers, err := get_physical_device_layers(pd);
            if err continue;
            if !contains_all_layers(device_name, layers, VALIDATION_LAYERS_NAMES)
              continue;
        }
        extensions, err := get_physical_device_exensions(pd);
        if err continue;
        if !contains_all_extensions(device_name, extensions, .[DEVICE_EXTENSIONS])
          continue;

        queue_families := get_physical_device_queue_families(pd);
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

        if properties.deviceType == .DISCRETE_GPU &&
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
            selected_queue_families = .{
                graphics_queue_family = xx graphics_queue_family,
                present_queue_family  = xx present_queue_family,
                compute_queue_family  = xx compute_queue_family,
                transfer_queue_family = xx transfer_queue_family,
            };
        }
    }
    return selected_queue_families;
}

load_procs :: ($instance: bool, $names: []string) -> success: bool #expand {
  gen_code :: ($instance: bool, $names: []string) -> string {
TEMPLATE :: #string DONE
%1 = xx `get_proc(%2, "%1");
if !%1 `return false;
DONE
    builder: String_Builder;
    if instance for names print_to_builder(*builder, TEMPLATE, it, "`instance");
    else        for names print_to_builder(*builder, TEMPLATE, it, "null");
    return builder_to_string(*builder);
  }
  #insert #run gen_code(instance, names);
}

vkCreateInstance:                       PFN_vkCreateInstance                       = ---;
vkEnumerateInstanceExtensionProperties: PFN_vkEnumerateInstanceExtensionProperties = ---;
vkEnumerateInstanceLayerProperties:     PFN_vkEnumerateInstanceLayerProperties     = ---;
vkEnumerateInstanceVersion:             PFN_vkEnumerateInstanceVersion             = ---;

load_basic_procs :: (get_proc: PFN_vkGetInstanceProcAddr) -> success: bool {
  load_procs(false, .[
    "vkCreateInstance",
    "vkEnumerateInstanceExtensionProperties",
    "vkEnumerateInstanceLayerProperties",
    "vkEnumerateInstanceVersion",
  ]);
  return true;
}

vkDestroyInstance:                         PFN_vkDestroyInstance                         = ---;
vkCreateDebugUtilsMessengerEXT:            PFN_vkCreateDebugUtilsMessengerEXT            = ---;
vkDestroyDebugUtilsMessengerEXT:           PFN_vkDestroyDebugUtilsMessengerEXT           = ---;
vkEnumeratePhysicalDevices:                PFN_vkEnumeratePhysicalDevices                = ---;
vkGetPhysicalDeviceProperties:             PFN_vkGetPhysicalDeviceProperties             = ---;
vkGetPhysicalDeviceFeatures:               PFN_vkGetPhysicalDeviceFeatures               = ---;
vkGetPhysicalDeviceMemoryProperties:       PFN_vkGetPhysicalDeviceMemoryProperties       = ---;
vkEnumerateDeviceLayerProperties:          PFN_vkEnumerateDeviceLayerProperties          = ---;
vkEnumerateDeviceExtensionProperties:      PFN_vkEnumerateDeviceExtensionProperties      = ---;
vkGetPhysicalDeviceQueueFamilyProperties:  PFN_vkGetPhysicalDeviceQueueFamilyProperties  = ---;
vkGetPhysicalDeviceSurfaceSupportKHR:      PFN_vkGetPhysicalDeviceSurfaceSupportKHR      = ---;
vkCreateDevice:                            PFN_vkCreateDevice                            = ---;
vkDestroyDevice:                           PFN_vkDestroyDevice                           = ---;
vkGetDeviceQueue:                          PFN_vkGetDeviceQueue                          = ---;
vkGetPhysicalDeviceSurfaceCapabilitiesKHR: PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR = ---;
vkGetPhysicalDeviceSurfaceFormatsKHR:      PFN_vkGetPhysicalDeviceSurfaceFormatsKHR      = ---;
vkCreateSwapchainKHR:                      PFN_vkCreateSwapchainKHR                      = ---;
vkDestroySwapchainKHR:                     PFN_vkDestroySwapchainKHR                     = ---;
vkGetSwapchainImagesKHR:                   PFN_vkGetSwapchainImagesKHR                   = ---;
vkCreateImageView:                         PFN_vkCreateImageView                         = ---;
vkDestroyImageView:                        PFN_vkDestroyImageView                        = ---;
vkCreateCommandPool:                       PFN_vkCreateCommandPool                       = ---;
vkDestroyCommandPool:                      PFN_vkDestroyCommandPool                      = ---;
vkAllocateCommandBuffers:                  PFN_vkAllocateCommandBuffers                  = ---;
vkResetCommandBuffer:                      PFN_vkResetCommandBuffer                      = ---;
vkBeginCommandBuffer:                      PFN_vkBeginCommandBuffer                      = ---;
vkEndCommandBuffer:                        PFN_vkEndCommandBuffer                        = ---;
vkCreateFence:                             PFN_vkCreateFence                             = ---;
vkWaitForFences:                           PFN_vkWaitForFences                           = ---;
vkResetFences:                             PFN_vkResetFences                             = ---;
vkDestroyFence:                            PFN_vkDestroyFence                            = ---;
vkCreateSemaphore:                         PFN_vkCreateSemaphore                         = ---;
vkDestroySemaphore:                        PFN_vkDestroySemaphore                        = ---;
vkCmdPipelineBarrier2:                     PFN_vkCmdPipelineBarrier2                     = ---;
vkCmdBeginRendering:                       PFN_vkCmdBeginRendering                       = ---;
vkCmdEndRendering:                         PFN_vkCmdEndRendering                         = ---;
vkCmdSetViewport:                          PFN_vkCmdSetViewport                          = ---;
vkCmdSetScissor:                           PFN_vkCmdSetScissor                           = ---;
vkQueueSubmit2:                            PFN_vkQueueSubmit2                            = ---;
vkQueuePresentKHR:                         PFN_vkQueuePresentKHR                         = ---;
vkAcquireNextImageKHR:                     PFN_vkAcquireNextImageKHR                     = ---;
vkCreatePipelineLayout:                    PFN_vkCreatePipelineLayout                    = ---;
vkCreateComputePipelines:                  PFN_vkCreateComputePipelines                  = ---;
vkCreateGraphicsPipelines:                 PFN_vkCreateGraphicsPipelines                 = ---;
vkCmdBindPipeline:                         PFN_vkCmdBindPipeline                         = ---;
vkCmdDispatch:                             PFN_vkCmdDispatch                             = ---;
vkCmdPushDescriptorSet:                    PFN_vkCmdPushDescriptorSet                    = ---;
vkCmdPushConstants:                        PFN_vkCmdPushConstants                        = ---;
vkCreateDescriptorSetLayout:               PFN_vkCreateDescriptorSetLayout               = ---;
vkCreateBuffer:                            PFN_vkCreateBuffer                            = ---;
vkBindBufferMemory:                        PFN_vkBindBufferMemory                        = ---;
vkGetBufferMemoryRequirements:             PFN_vkGetBufferMemoryRequirements             = ---;
vkGetBufferDeviceAddress:                  PFN_vkGetBufferDeviceAddress                  = ---;
vkCreateImage:                             PFN_vkCreateImage                             = ---;
vkCreateSampler:                           PFN_vkCreateSampler                           = ---;
vkBindImageMemory:                         PFN_vkBindImageMemory                         = ---;
vkGetImageMemoryRequirements:              PFN_vkGetImageMemoryRequirements              = ---;
vkAllocateMemory:                          PFN_vkAllocateMemory                          = ---;
vkMapMemory:                               PFN_vkMapMemory                               = ---;
vkCmdCopyBufferToImage:                    PFN_vkCmdCopyBufferToImage                    = ---;
vkCmdCopyBuffer:                           PFN_vkCmdCopyBuffer                           = ---;
vkCmdDraw:                                 PFN_vkCmdDraw                                 = ---;
vkCreateQueryPool:                         PFN_vkCreateQueryPool                         = ---;
vkGetQueryPoolResults:                     PFN_vkGetQueryPoolResults                     = ---;
vkCmdResetQueryPool:                       PFN_vkCmdResetQueryPool                       = ---;
vkCmdWriteTimestamp:                       PFN_vkCmdWriteTimestamp                       = ---;

load_instance_procs :: (get_proc: PFN_vkGetInstanceProcAddr) -> bool {
  load_procs(true, .[
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
    "vkCreateDevice",
    "vkDestroyDevice",
    "vkGetDeviceQueue",
    "vkGetPhysicalDeviceSurfaceCapabilitiesKHR",
    "vkGetPhysicalDeviceSurfaceFormatsKHR",
    "vkCreateSwapchainKHR",
    "vkDestroySwapchainKHR",
    "vkGetSwapchainImagesKHR",
    "vkCreateImageView",
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
    "vkCreateComputePipelines",
    "vkCreateGraphicsPipelines",
    "vkCmdBindPipeline",
    "vkCmdDispatch",
    "vkCmdPushDescriptorSet",
    "vkCmdPushConstants",
    "vkCreateDescriptorSetLayout",
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
    "vkCreateQueryPool",
    "vkGetQueryPoolResults",
    "vkCmdResetQueryPool",
    "vkCmdWriteTimestamp",
  ]);
  return true;
}

#import "Basic";
#import "Vulkan";
using,only(
  platform_vulkan_proc_addr,
  platform_vulkan_extensions,
  platform_create_surface
) platform :: #import,file "platform.jai";
