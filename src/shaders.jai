SHADER_TARGET_DIR :: "shaders_compiled";
SHADER_EXT :: ".glsl";

compile_shader :: (path: string) -> bool {
  index := find_index_from_right(path, #char "/");
  file_name: string = .{ data = path.data + index, count = path.count - index };
  base_name: string = .{ data = file_name.data,  count = file_name.count - SHADER_EXT.count };

  shader_type := ifx ends_with(base_name, "_frag") "-fshader-stage=fragment" else
                 ifx ends_with(base_name, "_vert") "-fshader-stage=vertex"   else
                 ifx ends_with(base_name, "_comp") "-fshader-stage=compute"  else
                 "invalid";
  if shader_type == "invalid" return false;
  else {
    output_path := tprint("%%.spv", SHADER_TARGET_DIR, base_name);
    log("Running command: glsl % % -o %\n", shader_type, path, output_path);
    cmd := string.["glslc", shader_type, path, "-o", output_path];
    process_result, output_string, error_string := run_command(..cmd,, temp);
    if process_result.exit_code != 0 {
      print("Failet to run: % error type: %\n", cmd, process_result.type);
      return false;
    }
  }
  return true;
}

#scope_file

#import "Basic";
#import "String";
#import "Process";
