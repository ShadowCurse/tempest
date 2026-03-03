main :: ()  {
  opts: Generate_Bindings_Options;

  ld_lib_path := getenv("LD_LIBRARY_PATH");
  if ld_lib_path {
    s := to_string(ld_lib_path);
    log("found LD_LIBRARY_PATH: %\n", s);
    for split(s, ":") array_add(*opts.system_library_search_paths, it);
  }

  // Put libc headers into system include path so they will not
  // be converted into bindings
  libc_include_path := getenv("LIBC_INCLUDE_PATH");
  if libc_include_path  {
    s := to_string(libc_include_path );
    log("found LIBC_INCLUDE_PATH : %\n", s);
    for split(s, ":") array_add(*opts.system_include_paths, it);
  }

  sdl3_include_path := getenv("SDL3_INCLUDE_PATH");
  if sdl3_include_path {
    s := to_string(sdl3_include_path);
    log("found SDL3_INCLUDE_PATH  : %\n", s);
    for split(s, ":") array_add(*opts.include_paths, it);
  }
  // Cannot used this since there are functions with arguments names
  // same as the function types, but without SDL_ prefix.
  // array_add(*opts.strip_prefixes, "SDL");

  array_add(*opts.source_files, "SDL3/SDL.h");
  array_add(*opts.source_files, "SDL3/SDL_vulkan.h");
  array_add(*opts.system_libraries, .{ filename = "libSDL3.so" });

  opts.generate_compile_time_struct_checks = false;
  s := generate_bindings(opts, "modules/SDL3.jai");
  log("Done: %\n", s);
}

#import "Basic";
#import "POSIX";
#import "String";
#import "Bindings_Generator";

