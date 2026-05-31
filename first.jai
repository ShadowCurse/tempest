Targets :: struct {
  tempest         :: "src/main.jai";
  sdl3_bindings   :: "sdl3_bindings_gen.jai";
  vulkan_bindings :: "vulkan_bindings_gen.jai";
  cgltf_bindings  :: "cgltf_bindings_gen.jai";
  cslug_bindings  :: "cslug_bindings_gen.jai";
}

need_to_compile_shaders := false;
need_to_instrument      := false;

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
  compiler_add_library_search_directory("modules");

  w := compiler_create_workspace("Tempest workspace");
  if !w {
    print("Workspace creation failed.\n");
    return;
  }

  targets : Type_Info_Struct = type_info(Targets);

  target_options := get_build_options(w);
  args := target_options.compile_time_command_line;

  to_compile: [..]struct { name: string; path: *string; };
  for arg: args {
    for targets.members {
      if arg == it.name {
        if 0 <= it.offset_into_constant_storage {
          path: *string = xx (targets.constant_storage.data + it.offset_into_constant_storage);
          array_add(*to_compile, .{ it.name, path });
          // compile(it.name, path.*);
        }
      }
    }
    if arg == "shaders"   need_to_compile_shaders = true;
    if arg == "with_prof" need_to_instrument = true;
  }
  for to_compile compile(it.name, it.path.*);
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

  intercept_flags: Intercept_Flags = .SKIP_EXPRESSIONS_WITHOUT_NOTES;
  if need_to_instrument then intercept_flags = 0;

  compiler_begin_intercept(w, intercept_flags);
  add_build_file(tprint("%/%", #filepath, path), w);
  message_loop(w);
  compiler_end_intercept(w);

  write_shader_structs();
}

compile_shaders :: () {
  if !make_directory_if_it_does_not_exist(SHADER_TARGET_DIR) {
    print("Cannot create \"%\" directroy\n", SHADER_TARGET_DIR);
    return;
  }
  for file_list("./shaders") if ends_with(it, SHADER_EXT) compile_shader(it);
}

message_loop :: (w: Workspace) {
  while true {
    message := compiler_wait_for_message();
    if message.kind == .COMPLETE break;
    capture_shader_structs(message);
    instrument_prof_functions(message);
  }
}

has_note :: (s: *Code_Declaration, note: string) -> bool {
  if s.notes for s.notes if it.text == note return true;
  return false;
}

has_note :: (s: *Code_Procedure_Header, note: string) -> bool {
  if s.notes for s.notes if it.text == note return true;
  return false;
}

ShaderStruct :: struct {
  name: string;
  code: *Code_Struct;
}
shader_structs: [..]ShaderStruct;

capture_shader_structs :: (message: *Message) {
  if message.kind == {
    case .TYPECHECKED;
      typechecked := cast(*Message_Typechecked)message;
      for typechecked.declarations {
        decl := it.expression;
        if !decl continue;
        expr := decl.expression;
        if !expr continue;
        if expr.kind == .STRUCT && has_note(decl, "ShaderType") {
          s := array_add(*shader_structs);
          s.name = decl.name;
          s.code = cast(*Code_Struct)expr;
        }
      }
  }
}

write_shader_structs :: () {
  builder: String_Builder;
  print_to_builder(
    *builder,
#string DONE
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#define VkDeviceAddress uint64_t

DONE
  );
#import "Sort";
  quick_sort(
    shader_structs,
    (a: ShaderStruct, b: ShaderStruct) -> s32 {
      c := 0;
      while c < min(a.name.count, b.name.count) {
             if a.name[c] < b.name[c] then return -1;
        else if b.name[c] < a.name[c] then return  1;
        c += 1;
      }
      return 1;
    }
  );
  for shader_structs print_struct(*builder, it);
  code := builder_to_string(*builder);

  file_name := "shaders/types.glsl";
  file, success := file_open(file_name , true, false, true);
  assert(success, "[glsl gen]: Unable to open '%' for writing\n", file_name);
  defer file_close(*file);

  success = file_write(*file, code);
  assert(success, "[glsl gen]: Unable to write output into '%'\n", file_name);
}

print_struct :: (builder: *String_Builder, s: ShaderStruct) {
  c := s.code;
  if c.textual_flags & .UNION {
    assert(false, "[glsl gen]: Cannot convert union: %", s.name);
    return;
  }

  Field :: struct { type: string; name: string; };
  fields: [..]Field;
  Alias :: struct { from: string; to: string; };
  aliases: [..]Alias;

  if c.block {
    for c.block.statements {
      if it.node_flags & .CREATED_BY_DESUGARING continue;
      if it.kind == it.kind.DECLARATION {
        decl := cast(*Code_Declaration)it;
        type: string;
        if decl.type_inst {
          if decl.type_inst.type_valued_expression.kind == .IDENT {
            ident := cast(*Code_Ident)decl.type_inst.type_valued_expression;
            if decl.notes{
              type = ident.name;
              glsl_type := type_to_glsl_type(decl.notes[0].text);
              array_add(*aliases, .{ ident.name, glsl_type });
            } else {
              type = type_to_glsl_type(ident.name);
            }
          }
        }
        if type array_add(*fields, .{ type, decl.name });
      }
    }
  }
  for aliases print_to_builder(builder, "#define % %\n", it.from, it.to);
  print_to_builder(builder, "struct % {\n", s.name);
  for fields print_to_builder(builder, "    % %;\n", it.type, it.name);
  print_to_builder(builder, "};\n\n");
}

type_to_glsl_type :: (type: string) -> string {
  if type == {
    case "u32";             return "uint";
    case "u64";             return "uint64_t";//#through;
    // case "VkDeviceAddress"; return "uint64_t";
    case "VkDeviceAddress"; return "VkDeviceAddress";
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

// This is the copy of the struct in the src/profiler.jai
ZoneInfo :: struct {
  name: string;
  line: u64;
}
zone_infos: [..]ZoneInfo;
prof_scope_message: *Message;
injected_final_profiling_code := false;

PROF_BLOCK_ZONE :: #string DONE
context.Prof_Module.prof_zone(%1);
DONE;

insert_instrumentation_into_scope :: (block: *Code_Block, zone_index: s64, location: Code_Node.Location) {
  literal_start := New(Code_Literal);
  literal_start.kind = .LITERAL;
  literal_start.value_type = .STRING;
  literal_start.values._string = tprint(PROF_BLOCK_ZONE, zone_index);
  insert_start := New(Code_Directive_Insert);
  insert_start.kind = .DIRECTIVE_INSERT;
  insert_start.expression = literal_start;
  insert_start.location = location;

  new_statements := NewArray(block.statements.count + 1, *Code_Node, initialized = false);
  memcpy(new_statements.data + 1, block.statements.data, block.statements.count * size_of(*Code_Node));
  new_statements[0] = insert_start;
  block.statements = new_statements;
}

instrument_prof_scopes :: (block: *Code_Block) -> bool {
  found := false;
  idx := 0;
  len := block.statements.count;
  while idx < len {
    defer idx += 1;

    it := block.statements[idx];
    if it.kind == {
      case .PROCEDURE_CALL;
        pc := cast(*Code_Procedure_Call)it;
        if pc.procedure_expression.kind == .IDENT {
          i := cast(*Code_Ident)pc.procedure_expression;
          if i.name == "prof_scope" {
            found = true;

            name       := pc.arguments_unsorted[0].expression.(*Code_Literal)._string;
            zone_index := zone_infos.count;
            info := array_add(*zone_infos);
            info.name = name;
            info.line = cast(u64)it.location.l0;
            // log("found: % at %/%", name, idx, len);

            insert_instrumentation_into_scope(block, zone_index, it.location);
            idx += 1;
            len += 1;
          }
        }
      case .WHILE; found |= instrument_prof_scopes((it.(*Code_While)).block);
      case .BLOCK; found |= instrument_prof_scopes(it.(*Code_Block));
    }
  }
  return found;
}

instrument_prof_functions :: (message: *Message) {
    if injected_final_profiling_code  return;

    if message.kind == .FILE {
      m := message.(*Message_File);
      if ends_with(m.fully_pathed_filename, "Profiler.jai") {
        prof_scope_message = message;
        return;
      }
    }
    if message.kind == .PHASE {
        phase_message := cast (*Message_Phase) message;
        phase := phase_message.phase;
        if phase == .TYPECHECKED_ALL_WE_CAN {
          if !injected_final_profiling_code {
            injected_final_profiling_code = true;

            add_build_string(tprint("PROF_ZONES_COUNT :: %;", zone_infos.count),
                             message.workspace, prof_scope_message);

            builder: String_Builder;
            print_to_builder(*builder, "PROF_ZONES_INFOS :: ZoneInfo.[\n");
            for zone_infos print_to_builder(*builder, ".{ \"%\", % },\n", it.name, it.line);
            print_to_builder(*builder, "];\n");
            s := builder_to_string(*builder);

            add_build_string(s, message.workspace, prof_scope_message);
          }
        }
        return;
    }
    if !need_to_instrument return;

    if message.kind != .TYPECHECKED return;

    m := message.(*Message_Typechecked);
    for * tc: m.procedure_bodies {
      body := tc.expression;
      if body.body_flags & .ALREADY_MODIFIED continue;

      h := body.header;
      if h.procedure_flags &
        (h.procedure_flags.POLYMORPHIC        |
                          .COMPILER_GENERATED |
                          .COMPILE_TIME_ONLY  |
                          .QUICK              |
                          .TYPE_ONLY          |
                          .MACRO)
        continue;

      need_to_modify_procedure := instrument_prof_scopes (body.block);
      defer if need_to_modify_procedure compiler_modify_procedure(message.workspace, body);

      is_entry_point := (h.procedure_flags & .ENTRY_POINT) != 0;
      if is_entry_point continue;

      type := h.type.(*Type_Info_Procedure);
      if type.procedure_flags & .HAS_NO_CONTEXT continue;

      file := body.enclosing_load;
      if file && file.enclosing_import {
          import := file.enclosing_import;

          if import.module_type == .PRELOAD continue;
          if import.module_type == .RUNTIME_SUPPORT continue;
          if import.module_type != .MAIN_PROGRAM continue;
      }
      if has_note(h, "NoProfile") continue;

      zone_index := zone_infos.count;
      info := array_add(*zone_infos);
      info.name = h.name;
      info.line = cast(u64)h.l0;

      insert_instrumentation_into_scope(body.block, zone_index, body.location);
      need_to_modify_procedure = true;
    }
}

#run build();

#load "src/shaders.jai";
#import "File";
#import "Basic";
#import "POSIX";
#import "String";
#import "Process";
#import "Compiler";
#import "File_Utilities";
