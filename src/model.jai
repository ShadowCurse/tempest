Vertex :: struct {
  position: Vector3;
  uv_x:     float;
  normal:   Vector3;
  uv_y:     float;
  color:    Vector3;
  _:        float;
} @ShaderType

Mesh :: struct {
  indices:  []u32;
  vertices: []Vertex;
}

Material :: struct {
  albedo:    Vector4;
  metallic:  float;
  roughness: float;
}

Model :: struct {
  mesh:     Mesh;
  material: Material;
}

load_model :: (name: string) -> Model, bool {
  path := tprint("resources/models/%.glb\0", name);
  log("Loading gltf model from path: %", name);

  options: cgltf_options;
  data: *cgltf_data = ---;
  assert(cgltf_parse_file(*options, path.data, *data) == .success);
  assert(cgltf_load_buffers(*options, data, path.data) == .success);
  defer cgltf_free(data);

  if data.meshes_count != 1 {
    log_error("Cannot load %: too many meshes", path);
    return {}, false;
  }

  mesh := *data.meshes[0];

  if mesh.primitives_count != 1 {
    log_error("Cannot load %: too many primitives", path);
    return {}, false;
  }

  if data.materials_count != 1 {
    log_error("Cannot load %: too many materials", path);
    return {}, false;
  }

  pbr_material := *data.materials[0];
  material: Material = .{
    albedo    = .{ component = pbr_material.pbr_metallic_roughness.base_color_factor },
    metallic  = pbr_material.pbr_metallic_roughness.metallic_factor,
    roughness = pbr_material.pbr_metallic_roughness.roughness_factor,
  };

  mesh_name := to_string(mesh.name);
  log("Mesh name: %", mesh_name);

  primitive      := *mesh.primitives[0];
  indices_count  := primitive.indices[0].count;
  vertices_count := primitive.attributes[0].data[0].count;

  total_bytes := indices_count * size_of(u32) + vertices_count * size_of(Vertex);
  model_memory := new_array(xx total_bytes, u8, initialized = false);

  indices: []u32 = {
    data  = cast(*u32)(model_memory.data + vertices_count * size_of(Vertex)),
    count = xx indices_count
  };
  for i: 0..indices_count - 1 indices[i] = xx cgltf_accessor_read_index(primitive.indices, i);

  vertices: []Vertex = { data = cast(*Vertex)model_memory.data, count = xx vertices_count };
  log("Mesh primitive type: %", primitive.type);
  for i: 0..primitive.attributes_count - 1 {
    attr := *primitive.attributes[i];
    log("Mesh primitive attr name: %, type: %, index: %, data type: %, data count: %",
        to_string(attr.name),
        attr.type,
        attr.index,
        attr.data[0].type,
        attr.data[0].count,
    );
    floats_count := cgltf_accessor_unpack_floats(attr.data, null, 0);
    floats := new_array(xx floats_count, float,, temp);
    _ = cgltf_accessor_unpack_floats(attr.data, floats.data, floats_count);

    if attr.type == {
      case .cgltf_attribute_type_position;
        num_components := cgltf_num_components(attr.data[0].type);
        log("Position has % components", num_components);
        assert(num_components == 3);

        positions: []Vector3 = ---;
        positions.data  = cast(*Vector3)floats.data;
        positions.count = floats.count / 3;
        for i: 0..vertices_count - 1 vertices[i].position = positions[i];
      case .cgltf_attribute_type_normal;
        num_components := cgltf_num_components(attr.data[0].type);
        log("Normal has % components", num_components);
        assert(num_components == 3);

        normals: []Vector3 = ---;
        normals.data  = cast(*Vector3)floats.data;
        normals.count = floats.count / 3;
        for i: 0..vertices_count - 1 vertices[i].normal = normals[i];
      case .cgltf_attribute_type_texcoord;
        num_components := cgltf_num_components(attr.data[0].type);
        log("Texture coord has % components", num_components);
        assert(num_components == 2);

        uvs: []Vector2 = ---;
        uvs.data  = cast(*Vector2)floats.data;
        uvs.count = floats.count / 2;
        for i: 0..vertices_count - 1 {
          vertices[i].uv_x = uvs[i].x;
          vertices[i].uv_y = uvs[i].y;
        }
      case;
        log_error("Unknown attribute type: {}. Skipping", attr.type);
    }
  }
  // For debugging use normals as colors
  for * vertices it.color = abs(it.normal);

  return .{ .{ indices, vertices }, material }, true;
}

#scope_file

#import,file "math.jai";
#import,file "allocators.jai";
#import "cgltf";
#import "Basic";
