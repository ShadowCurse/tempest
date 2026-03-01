verbose := false;
bindings := false;

build :: () {
  // The compiler warning does not have \n for some reason, so add it manually.
  print("\n");

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
      case "-v"; #through;
      case "-verbose";
        verbose = true;
      case "-bindings";
        bindings = true;
    }
  }

  workspace_options.use_custom_link_command = true;

  build_file := "src/main.jai";
  if bindings {
    build_file = "sdl3_bindings_gen.jai";
    workspace_options.output_executable_name = "sdl3_bindings_gen";
  } else {
    workspace_options.output_executable_name = "tempest";
  }

  set_build_options(workspace_options, w);

  {
    compiler_begin_intercept(w);
    defer compiler_end_intercept(w);

    add_build_file(tprint("%/%", #filepath, build_file), w);

    message_loop(w);
  }
  set_build_options_dc(.{do_output=false});
}

message_loop :: (w: Workspace) {
  while true {
    message := compiler_wait_for_message();
    if message.kind == {
      case .FILE;
        if verbose {
          message_file := cast(*Message_File) message;
          print("  Loading file '%'.\n", message_file.fully_pathed_filename);
        }
      case .IMPORT;
        if verbose {
          import := cast(*Message_Import) message;
          print("  Importing module '%'.\n", import.module_name);
        }
      case .PHASE;
        phase := cast(*Message_Phase) message;
        if verbose {
          print("--- Entering phase %. ---\n", phase.phase);
          if phase.phase == .POST_WRITE_EXECUTABLE {
              print("\n");
              if phase.executable_write_failed {
                  print("FAILED writing '%'! Linker exit code was %.\n", phase.executable_name, phase.linker_exit_code);
              } else {
                  print("Success writing '%'! Linker exit code was %.\n", phase.executable_name, phase.linker_exit_code);
              }
          }
        }
        if phase.phase == .READY_FOR_CUSTOM_LINK_COMMAND {
          compiler_custom_link_command_is_complete(w);
          run_linux_link_command(w, phase);
        }
      case .TYPECHECKED;
        if verbose {
          typechecked := cast(*Message_Typechecked) message;
          n := typechecked.all.count;
          if n == 1 {
              print("  1 thing has been typechecked.\n");
          } else {
              print("  % things have been typechecked.\n", n);
          }
        }
      case .COMPLETE;
        break;
      case;
        compiler_report(tprint("Unhandled message type %!\n", message.kind));
    }
  }
}

run_linux_link_command :: (w: Workspace, m: *Message_Phase) -> string {
  compiler := "clang";
  linker   := "mold";

  args: [..] string;
  array_add(*args, compiler);
  array_add(*args, tprint("-fuse-ld=%", linker));
  array_add(*args, "-no-pie");

  for m.compiler_generated_object_files array_add(*args, it);
  for m.support_object_files            array_add(*args, it);

  system_libs := string.["c", "SDL3"];
  for system_libs array_add(*args, tprint("-l%", it));

  if bindings array_add(*args, "-lclang");

  options := get_build_options(w);
  output_filename := tprint("%/%", ifx options.output_path else ".", options.output_executable_name);
  array_add(*args, "-o", output_filename);

  log("Running linker: %\n", get_quoted_command_string(args));

  result := run_command(..args);
  if result.exit_code != 0 {
      details: string;
      if result.type == {
          case .FAILED_TO_LAUNCH;
              details = "Could not launch linker.";
          case .SIGNALED;
              details = tprint("Linker caught signal %.", result.signal);
          case;
              details = tprint("Linker exit code %.", result.exit_code);
      }
      log_error("Error: Link step failed! %", details);
      compiler_set_workspace_status(.FAILED, w);
  }

  compiler_custom_link_command_is_complete(w);

  return output_filename;
}

#run build();

#import "Basic";
#import "Process";
#import "Compiler";
