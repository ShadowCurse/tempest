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
    log("found LIBC_INCLUDE_PATH: %\n", s);
    for split(s, ":") array_add(*opts.system_include_paths, it);
  }

  vulkan_include_path := getenv("VULKAN_INCLUDE_PATH");
  if vulkan_include_path  {
    s := to_string(vulkan_include_path );
    log("found VULKAN_INCLUDE_PATH: %\n", s);
    for split(s, ":") array_add(*opts.include_paths, it);
  }

  array_add(*opts.source_files, "vulkan/vulkan.h");
  // No actulal functions are generated. Use PNF_* typedefs
  // as function types. Actulal functions will be loaded
  // at runtime
  array_add(*opts.strip_prefixes, "PFN_vk");

  opts.generate_compile_time_struct_checks = false;
  opts.generate_library_declarations = true;
  opts.log_stripped_declarations = false;
  opts.visitor = vulkan_visitor;
  s := generate_bindings(opts, "modules/Vulkan.jai");
  log("Done: %", s);
}

struct_type_decl: *Enum;
available_flag_bits: Table(string, *Enum);

vulkan_visitor :: (decl: *Declaration, parent_decl: *Declaration) -> Declaration_Visit_Result {
  // Omit header definitions (ex: VULKAN_H_)
  if decl.kind == .MACRO_DEFINITION && ends_with(decl.name, "_H_") {
    print("MACRO_DEFINITION removed: %\n", decl.name);
    decl.decl_flags |= .OMIT_FROM_OUTPUT;
    return .STOP;
  }

  OMIT_LIST :: string.[
    // These are defined manually:
    "VK_NULL_HANDLE",
    "VK_TRUE",
    "VK_FALSE",
    "VK_WHOLE_SIZE",
    "VK_ATTACHMENT_UNUSED",
    "VK_QUEUE_FAMILY_IGNORED",
    "VK_REMAINING_ARRAY_LAYERS",
    "VK_REMAINING_MIP_LEVELS",
    "VK_SUBPASS_EXTERNAL",
    "VK_MAX_PHYSICAL_DEVICE_NAME_SIZE",
    "VK_UUID_SIZE",
    "VK_MAX_MEMORY_TYPES",
    "VK_MAX_MEMORY_HEAPS",
    "VK_MAX_EXTENSION_NAME_SIZE",
    "VK_MAX_DESCRIPTION_SIZE",
    // Vulkan 1.3 functions that exist on Linux but are not part of our Windows version:
    "vkGetPhysicalDeviceSurfaceCapabilities2KHR",
    "vkGetPhysicalDeviceSurfaceFormats2KHR",
  ];

  // Omit our OMIT_LIST
  if !parent_decl && array_find(OMIT_LIST, decl.name) {
    print("OMIT_LIST: %\n", decl.name);
    decl.decl_flags |= .OMIT_FROM_OUTPUT;
    return .STOP;
  }

  if decl.kind == .ENUM {
    en := cast(*Enum)decl;
    if en.name == "VkStructureType" {
      struct_type_decl = en; // Save for later
    }

    // Almost all enums should be unsigned
    if en.type && decl.name != "VkResult" {
      if en.type.size == {
        case 1;
            en.type = context.generator.type_def_u8;
        case 2;
            en.type = context.generator.type_def_u16;
        case 4;
            en.type = context.generator.type_def_u32;
        case 8;
            en.type = context.generator.type_def_u64;
      }
    }

    if contains(decl.name, "FlagBits") {
      en.flags |= .IS_ENUM_FLAGS;
      en.flags |= .VALUES_IN_HEX;

      // Remember this so we can replace the generic VkFlags aliases with the actual
      // enum_flag's type below. :VkFlags
      table_add(*available_flag_bits, decl.name, en);
    }
  }

  // Replace typedef which has "VkFlags" as value. :VkFlags
  // VkAccessFlags :: VkFlags   ->   VkAccessFlags :: VkAccessFlagBits;
  // We don't change the name of the FlagBits enum directly because both
  // the ...FlagBits and the ...Flags aliases are used in declarations.
  if decl.kind == .TYPEDEF && decl.type.type_of_typedef &&  decl.type.type_of_typedef.name == "VkFlags" {
    flags_name := replace(decl.name, "Flags", "FlagBits");
    found, enum_decl := table_find(*available_flag_bits, flags_name);
    if found {
      type := New(CType);
      type.type_of_enum = enum_decl;
      type.size = enum_decl.type.size;
      decl.type = type;
    }
  }

  // Set the default value for sType.
  if parent_decl && parent_decl.kind == .STRUCT &&
     parent_decl.name != "VkBaseInStructure" &&
     parent_decl.name != "VkBaseOutStructure" &&
     decl.kind == .DECLARATION &&
     decl.name == "sType" {
    enum_value_name := get_stype_from_struct_name(parent_decl.name);
    enum_value: *Declaration;
    for struct_type_decl.enumerates {
      if it.output_name == enum_value_name {
        enum_value = it;
        break;
      }
    }

    if enum_value {
      literal := New(Literal);
      literal.literal_kind = .ENUM;
      literal.enum_type = struct_type_decl;
      literal.enum_value = enum_value;
      decl.expression = literal;
    } else {
      log_error(
        "Could not find VkStructType enum value for %, the enum value name we tried was %",
        parent_decl.name, enum_value_name
      );
    }
  }

  return .RECURSE;
}

get_stype_from_struct_name :: (name: string) -> string {
    assert(name.count >= 3);
    // For the Vulkan version 1 headers this script was originally written this procedure handled all cases.
    // (For the core stuff anyway, the windows platform types still had issues with Win32, D3D12).
    // If you try run this on later versions there are types that we fail on.
    // Rather than fussing with this procedure when probably generating from c headers isn't the
    // best option anyway, here are just a list of exceptions for v1.2.198.
    Exception :: struct {
        struct_name, enum_name: string;
    }

    STRUCT_NAME_TO_STYPE_EXCEPTIONS :: Exception.[
        .{"VkPhysicalDeviceVulkan11Features",                     "PHYSICAL_DEVICE_VULKAN_1_1_FEATURES"},
        .{"VkPhysicalDeviceVulkan11Properties",                   "PHYSICAL_DEVICE_VULKAN_1_1_PROPERTIES"},
        .{"VkPhysicalDeviceVulkan12Features",                     "PHYSICAL_DEVICE_VULKAN_1_2_FEATURES"},
        .{"VkPhysicalDeviceVulkan12Properties",                   "PHYSICAL_DEVICE_VULKAN_1_2_PROPERTIES"},
        .{"VkPhysicalDeviceVulkan13Features",                     "PHYSICAL_DEVICE_VULKAN_1_3_FEATURES"},
        .{"VkPhysicalDeviceVulkan13Properties",                   "PHYSICAL_DEVICE_VULKAN_1_3_PROPERTIES"},
        .{"VkPhysicalDeviceVulkan14Features",                     "PHYSICAL_DEVICE_VULKAN_1_4_FEATURES"},
        .{"VkPhysicalDeviceVulkan14Properties",                   "PHYSICAL_DEVICE_VULKAN_1_4_PROPERTIES"},
        .{"VkPhysicalDeviceShaderAtomicInt64Features",            "PHYSICAL_DEVICE_SHADER_ATOMIC_INT64_FEATURES"},
        .{"VkPhysicalDeviceShaderFloat16Int8Features",            "PHYSICAL_DEVICE_SHADER_FLOAT16_INT8_FEATURES"},
        .{"VkPhysicalDeviceTextureCompressionASTCHDRFeaturesEXT", "PHYSICAL_DEVICE_TEXTURE_COMPRESSION_ASTC_HDR_FEATURES_EXT"},
        .{"VkPhysicalDeviceShaderImageAtomicInt64FeaturesEXT",    "PHYSICAL_DEVICE_SHADER_IMAGE_ATOMIC_INT64_FEATURES_EXT"},
        .{"VkPhysicalDeviceIndexTypeUint8FeaturesEXT",            "PHYSICAL_DEVICE_INDEX_TYPE_UINT8_FEATURES_EXT"},
        .{"VkPhysicalDeviceRGBA10X6FormatsFeaturesEXT",           "PHYSICAL_DEVICE_RGBA10X6_FORMATS_FEATURES_EXT"},
    ];

    is_upper :: (byte: u8) -> bool {
        if byte >= #char "A" && byte <= #char "Z" return true;
        return false;
    }

    is_num :: (byte: u8) -> bool {
        if byte >= #char "0" && byte <= #char "9" return true;
        return false;
    }

    for STRUCT_NAME_TO_STYPE_EXCEPTIONS {
        if it.struct_name == name {
            return it.enum_name;
        }
    }

    builder: String_Builder;
    append(*builder, name[2]);
    for i:3..name.count-1 {
        if is_upper(name[i]) {
            is_first_uppercase := !is_upper(name[i-1]);
            is_end_of_uppercase_word := (i != name.count-1 && !is_upper(name[i+1]));
            is_bit_count := is_num(name[i-1]) && slice(name, i, 3) == "Bit";
            if (is_first_uppercase || is_end_of_uppercase_word) && !is_bit_count {
                append(*builder, #char "_");
            } else if (i >= 4 && slice(name, i-4, 4) == "AABB") { // Special case hack for names involing AABB
                append(*builder, #char "_");
            }
            append(*builder, name[i]);
        } else if is_num(name[i]) {
            if !is_num(name[i-1]) {
                append(*builder, #char "_");
            }
            append(*builder, name[i]);
        } else {
            append(*builder, to_upper(name[i]));
        }
    }

    return builder_to_string(*builder);
}

#import "File";
#import "Basic";
#import "POSIX";
#import "String";
#import "Hash_Table";
#import "Bindings_Generator";
