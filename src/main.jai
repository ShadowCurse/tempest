main :: () {
  if !platform_init() return;
  defer platform_quit();
  if !vulkan_init(true) return;
}

#import,file "platform.jai";
#import,file "vulkan.jai";

