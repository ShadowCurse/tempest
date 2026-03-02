Binaries :: struct {
  tempest       :: "src/main.jai";
  sdl3_bindings :: "sdl3_bindings_gen.jai";
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

  info_struct : Type_Info_Struct = type_info(Binaries);

  target_options := get_build_options(w);
  args := target_options.compile_time_command_line;
  for arg: args {
    for info_struct.members {
      if arg == it.name {
        if it.offset_into_constant_storage >= 0 {
          path: *string = xx (info_struct.constant_storage.data + it.offset_into_constant_storage);
          compile(it.name, path.*);
        }
      }
    }
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

#run build();

#import "Basic";
#import "POSIX";
#import "String";
#import "Compiler";
