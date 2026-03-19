main :: ()  {
  opts: Generate_Bindings_Options;

  CGLTF_C_PATH :: "thirdparty/cgltf/cgltf.c";
  CGLTF_OBJ_PATH :: ".build/cgltf.o";
  CGLTF_STATIC_LIB_PATH :: "./modules/libcgltf.a";
  if !run_cmd(.["gcc", "-fPIC", "-c", CGLTF_C_PATH, "-o", CGLTF_OBJ_PATH]) return;
  if !run_cmd(.["ar", "rcs", CGLTF_STATIC_LIB_PATH, CGLTF_OBJ_PATH]) return;

  ld_lib_path := getenv("LD_LIBRARY_PATH");
  if ld_lib_path {
    s := to_string(ld_lib_path);
    log("found LD_LIBRARY_PATH: %\n", s);
    for split(s, ":") array_add(*opts.system_library_search_paths, it);
  }
  array_add(*opts.system_library_search_paths, "modules");

  // Put libc headers into system include path so they will not
  // be converted into bindings
  libc_include_path := getenv("LIBC_INCLUDE_PATH");
  if libc_include_path  {
    s := to_string(libc_include_path );
    log("found LIBC_INCLUDE_PATH : %\n", s);
    for split(s, ":") array_add(*opts.system_include_paths, it);
  }
  array_add(*opts.include_paths, "thirdparty/cgltf");

  array_add(*opts.source_files, "cgltf.h");
  array_add(*opts.system_libraries, .{ filename = "libcgltf" });

  opts.generate_compile_time_struct_checks = false;
  s := generate_bindings(opts, "modules/cgltf.jai");
  log("Done: %\n", s);
}

run_cmd :: (cmd: []string) -> bool {
  log("Running command: %", cmd);
  process_result := run_command(..cmd);
  if process_result.exit_code != 0 {
    print("Failet to run: % error type: %\n", cmd, process_result.type);
    return false;
  }
  return true;
}

#import "Basic";
#import "POSIX";
#import "String";
#import "Process";
#import "Bindings_Generator";

