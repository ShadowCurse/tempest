Targets :: struct {
  tempest         :: "src/main.jai";
  sdl3_bindings   :: "sdl3_bindings_gen.jai";
  vulkan_bindings :: "vulkan_bindings_gen.jai";
}

build :: () {
  // The compiler warning does not have \n for some reason, so add it manually.
  print("\n");

  ld_lib_path := getenv("LD_LIBRARY_PATH");
  if ld_lib_path {
    s := to_string(ld_lib_path);
    for split(s, ":") {
      print("Adding library search path: %\n", it);
      compiler_add_library_search_directory(it);
    }
  }

  w := compiler_create_workspace("Tempest workspace");
  if !w {
    print("Workspace creation failed.\n");
    return;
  }

  targets : Type_Info_Struct = type_info(Targets);

  target_options := get_build_options(w);
  args := target_options.compile_time_command_line;
  for arg: args {
    for targets.members {
      if arg == it.name {
        if it.offset_into_constant_storage >= 0 {
          path: *string = xx (targets.constant_storage.data + it.offset_into_constant_storage);
          compile(it.name, path.*);
        }
      }
    }
    if arg == "shaders" compile_shaders();
  }

  set_build_options_dc(.{do_output=false});
}

compile :: (binary_name: string, path: string) {
  workspace_name := tprint("Workspace: name: % path: %", binary_name, path);
  w := compiler_create_workspace(workspace_name);
  if !w {
    print(tprint("Failed: %\n", workspace_name));
    return;
  }

  workspace_options := get_build_options();
  workspace_options.output_executable_name = binary_name;
  set_build_options(workspace_options, w);

  add_build_file(tprint("%/%", #filepath, path), w);
}

compile_shaders :: () {
  EXT :: ".glsl";
  TARGET_DIR :: "shaders_compiled";

  if !make_directory_if_it_does_not_exist(TARGET_DIR) {
    print("Cannot create \"%\" directroy\n", TARGET_DIR);
    return;
  }
  for file_list("./shaders") {
    if ends_with(it, EXT) {
      index := find_index_from_right(it, #char "/");
      file_name: string = .{ data = it.data + index, count = it.count - index };
      base_name: string = .{ data = file_name.data,  count = file_name.count - EXT.count };

      shader_type := ifx ends_with(base_name, "_frag") "-fshader-stage=fragment" else
                     ifx ends_with(base_name, "_vert") "-fshader-stage=vertex"   else
                     ifx ends_with(base_name, "_comp") "-fshader-stage=compute"  else
                     "invalid";
      if shader_type == "invalid" continue;

      output_path_bulider : String_Builder;
      print_to_builder(*output_path_bulider, "%%.spv", TARGET_DIR, base_name);
      output_path := builder_to_string(*output_path_bulider);
      print("Running command: glsl % % -o %\n", shader_type, it, output_path);
      cmd := string.["glslc", shader_type, it, "-o", output_path];
      process_result, output_string, error_string := run_command(..cmd);
      if process_result.exit_code != 0 print("Failet to run: % error type: %\n", cmd, process_result.type);
    }
  }
}

#run build();

#import "File";
#import "Basic";
#import "POSIX";
#import "String";
#import "Process";
#import "Compiler";
#import "File_Utilities";
