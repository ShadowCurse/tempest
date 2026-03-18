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

  need_to_compile_shaders := false;
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
    if arg == "shaders" need_to_compile_shaders = true;
  }
  // note(sc): need to do shaders step after main compile, since it may update shader
  // types
  if need_to_compile_shaders compile_shaders();;

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

  compiler_begin_intercept(w, .SKIP_EXPRESSIONS_WITHOUT_NOTES);
  add_build_file(tprint("%/%", #filepath, path), w);
  structs := capture_shader_structs();
  compiler_end_intercept(w);

  write_shader_structs(structs);
}

compile_shaders :: () {
  if !make_directory_if_it_does_not_exist(SHADER_TARGET_DIR) {
    print("Cannot create \"%\" directroy\n", SHADER_TARGET_DIR);
    return;
  }
  for file_list("./shaders") if ends_with(it, SHADER_EXT) compile_shader(it);
}

Struct :: struct {
  name: string;
  code: *Code_Struct;
}
capture_shader_structs :: () -> [..]Struct {
  structs: [..]Struct;

  has_note :: (s: *Code_Declaration, note: string) -> bool {
    for s.notes if it.text == note return true;
    return false;
  }

  while true {
    message := compiler_wait_for_message();
    if message.kind == {
      case .TYPECHECKED;
        typechecked := cast(*Message_Typechecked)message;
        for typechecked.declarations {
          decl := it.expression;
          expr := decl.expression;
          if expr.kind == .STRUCT && has_note(decl, "ShaderType") {
            s := array_add(*structs);
            s.name = decl.name;
            s.code = cast(*Code_Struct)expr;
          }
        }
      case .COMPLETE;
        break;
    }
  }
  return structs;
}

write_shader_structs :: (structs: []Struct) {
  builder: String_Builder;
  print_to_builder(
    *builder,
    "#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require\n\n"
  );
  for structs print_struct(*builder, it);
  code := builder_to_string(*builder);

  file_name := "shaders/types.glsl";
  file, success := file_open(file_name , true, false, true);
  assert(success, "[glsl gen]: Unable to open '%' for writing\n", file_name);
  defer file_close(*file);

  success = file_write(*file, code);
  assert(success, "[glsl gen]: Unable to write output into '%'\n", file_name);
}

print_struct :: (builder: *String_Builder, s: Struct) {
  c := s.code;
  if c.textual_flags & .UNION {
    assert(false, "[glsl gen]: Cannot convert union: %", s.name);
    return;
  }

  print_to_builder(builder, "struct % {\n", s.name);
  if c.block {
    for c.block.statements {
      if it.node_flags & .CREATED_BY_DESUGARING continue;
      if it.kind == it.kind.DECLARATION {
        decl := cast(*Code_Declaration)it;
        found_type: string;
        if decl.notes {
          found_type = decl.notes[0].text;
        } else {
          if decl.type_inst {
            if decl.type_inst.type_valued_expression.kind == .IDENT {
              ident := cast(*Code_Ident)decl.type_inst.type_valued_expression;
              found_type = ident.name;
            }
          }
        }
        if found_type {
          glsl_type := type_to_glsl_type(found_type);
          print_to_builder(builder, "    % %;\n", glsl_type, decl.name);
        }
      }
    }
  }
  print_to_builder(builder, "};\n\n");
}

type_to_glsl_type :: (type: string) -> string {
  if type == {
    case "u32";             return "uint";
    case "u64";             #through;
    case "VkDeviceAddress"; return "uint64_t";
    case "float";           #through;
    case "float32";         return "float";
    case "Vector2";         return "vec2";
    case "Vector3";         return "vec3";
    case "Vector4";         return "vec4";
    case "Matrix3";         return "mat3";
    case "Matrix4";         return "mat4";
  }
  assert(false, "[glsl gen]: Cannot convert type: % to glsl type", type);
  return {};
}

#run build();

#import,file "src/shaders.jai";
#import "File";
#import "Basic";
#import "POSIX";
#import "String";
#import "Process";
#import "Compiler";
#import "File_Utilities";
