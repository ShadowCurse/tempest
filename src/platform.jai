window: *SDL_Window;
window_width  : u32 = 1600;
window_height : u32 = 800;

platform_init :: () -> success: bool {
  SDL_Init(SDL_INIT_AUDIO);
  window = SDL_CreateWindow(
      "tempest",
      xx window_width,
      xx window_height,
      SDL_WINDOW_VULKAN, // | SDL_WINDOW_RESIZABLE,
  );
  if !window {
    log_error("Cannot create SDL window: %\n", SDL_GetError());
    return false;
  }
  if !SDL_ShowWindow(window) {
      log_error("Cannot show a window: %", SDL_GetError());
      return false;
  }
  return true;
}

platform_quit :: () {
  SDL_DestroyWindow(window);
  SDL_Quit();
}

platform_vulkan_proc_addr :: () -> vk.PFN_vkGetInstanceProcAddr  {
  return xx SDL_Vulkan_GetVkGetInstanceProcAddr();
}

platform_vulkan_extensions :: () -> []*u8 {
  count: u32 = ---;
  data := SDL_Vulkan_GetInstanceExtensions(*count);
  slice: []*u8 = ---;
  slice.data = data;
  slice.count = count;
  return slice;
}

platform_create_surface :: (instance: vk.VkInstance, surface: *vk.VkSurfaceKHR) {
  if !SDL_Vulkan_CreateSurface(window, xx instance, null, xx surface)
    log_error("Cannot create Vulkan surface. Error: %", SDL_GetError());
}

platform_new_frame :: () {
    if !SDL_GetWindowSize(window, xx *window_width, xx *window_height)
        log_error("Cannot get window size. Error: %\n", to_string(SDL_GetError()));
    // _ = SDL_GetMouseState(&mouse_position.x, &mouse_position.y);
}

platform_read_entire_file :: (path: string) -> string, bool {
  data, ok := read_entire_file(path);
  return data, ok;
}

platform_wants_to_exit :: () -> bool {
    events: [64]SDL_Event = ---;
    SDL_FlushEvents(xx SDL_EventType.FIRST, xx SDL_EventType.LAST);
    SDL_PumpEvents();
    n_events := SDL_PeepEvents(events.data, events.count, .PEEKEVENT, xx SDL_EventType.FIRST, xx SDL_EventType.LAST);
    for 0..n_events -1 if events[it].type == xx SDL_EventType.QUIT return true;
    return false;
}

#scope_file

#import "SDL3";
#import "Basic";
#import "File";
vk :: #import "Vulkan";

SDL_WINDOW_FULLSCREEN           :: 0x0000000000000001; //window is in fullscreen mode
SDL_WINDOW_OPENGL               :: 0x0000000000000002; //window usable with OpenGL context
SDL_WINDOW_OCCLUDED             :: 0x0000000000000004; //window is occluded
SDL_WINDOW_HIDDEN               :: 0x0000000000000008; //window is neither mapped onto the desktop nor shown in the taskbar/dock/window list; SDL_ShowWindow() is required for it to become visible
SDL_WINDOW_BORDERLESS           :: 0x0000000000000010; //no window decoration
SDL_WINDOW_RESIZABLE            :: 0x0000000000000020; //window can be resized
SDL_WINDOW_MINIMIZED            :: 0x0000000000000040; //window is minimized
SDL_WINDOW_MAXIMIZED            :: 0x0000000000000080; //window is maximized
SDL_WINDOW_MOUSE_GRABBED        :: 0x0000000000000100; //window has grabbed mouse input
SDL_WINDOW_INPUT_FOCUS          :: 0x0000000000000200; //window has input focus
SDL_WINDOW_MOUSE_FOCUS          :: 0x0000000000000400; //window has mouse focus
SDL_WINDOW_EXTERNAL             :: 0x0000000000000800; //window not created by SDL
SDL_WINDOW_MODAL                :: 0x0000000000001000; //window is modal
SDL_WINDOW_HIGH_PIXEL_DENSITY   :: 0x0000000000002000; //window uses high pixel density back buffer if possible
SDL_WINDOW_MOUSE_CAPTURE        :: 0x0000000000004000; //window has mouse captured (unrelated to MOUSE_GRABBED)
SDL_WINDOW_MOUSE_RELATIVE_MODE  :: 0x0000000000008000; //window has relative mode enabled
SDL_WINDOW_ALWAYS_ON_TOP        :: 0x0000000000010000; //window should always be above others
SDL_WINDOW_UTILITY              :: 0x0000000000020000; //window should be treated as a utility window, not showing in the task bar and window list
SDL_WINDOW_TOOLTIP              :: 0x0000000000040000; //window should be treated as a tooltip and does not get mouse or keyboard focus, requires a parent window
SDL_WINDOW_POPUP_MENU           :: 0x0000000000080000; //window should be treated as a popup menu, requires a parent window
SDL_WINDOW_KEYBOARD_GRABBED     :: 0x0000000000100000; //window has grabbed keyboard input
SDL_WINDOW_FILL_DOCUMENT        :: 0x0000000000200000; //window is in fill-document mode (Emscripten only), since SDL 3.4.0
SDL_WINDOW_VULKAN               :: 0x0000000010000000; //window usable for Vulkan surface
SDL_WINDOW_METAL                :: 0x0000000020000000; //window usable for Metal view
SDL_WINDOW_TRANSPARENT          :: 0x0000000040000000; //window with transparent buffer
SDL_WINDOW_NOT_FOCUSABLE        :: 0x0000000080000000; //window should not be focusable
