build :: () {
  w := compiler_create_workspace("Target Program");
  if !w {
    print("Workspace creation failed.\n");
    return;
  }
  target_options := get_build_options(w);
  target_options.output_executable_name = "tempest";
  set_build_options(target_options, w);

  add_build_file(tprint("%/src/main.jai", #filepath), w);

  set_build_options_dc(.{do_output=false});
}

#run build();

#import "Basic";
#import "Compiler";

