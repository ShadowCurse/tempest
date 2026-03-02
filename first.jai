bindings := false;

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

  workspace_options := get_build_options();
  target_options := get_build_options(w);
  args := target_options.compile_time_command_line;

  for arg: args {
    if arg == {
      case "-bindings";
        bindings = true;
    }
  }

  build_file := "src/main.jai";
  if bindings {
    build_file = "sdl3_bindings_gen.jai";
    workspace_options.output_executable_name = "sdl3_bindings_gen";
  } else {
    workspace_options.output_executable_name = "tempest";
  }
  set_build_options(workspace_options, w);
  add_build_file(tprint("%/%", #filepath, build_file), w);
  set_build_options_dc(.{do_output=false});
}

#run build();

#import "Basic";
#import "POSIX";
#import "String";
#import "Compiler";
