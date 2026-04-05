Vertex :: struct {
  position: Vector3;
  uv_x:     float;
  normal:   Vector3;
  uv_y:     float;
  color:    Vector3;
  _:        float;
} @ShaderType

MeshIdx :: #type,distinct u32;
Mesh :: struct {
  material_idx: MaterialIdx;
  indices:      []u32;
  vertices:     []Vertex;
}

MaterialIdx :: #type,distinct u32;
Material :: struct {
  albedo:    Vector4;
  metallic:  float;
  roughness: float;
}

SceneNodeIdx :: #type,distinct u32;
SceneNode :: struct {
  name:             [64]u8;// = "NullNode";
  parent_idx:       SceneNodeIdx;
  first_child_idx:  SceneNodeIdx;
  children_count:   u32;
  mesh_idx:         MeshIdx;
  translation:      Vector3;
  rotation:         Quaternion;
  scale:            Vector3 = .{1, 1, 1};
}

root_nodes:    FixedArray(SceneNodeIdx, 8);
nodes:         FixedArray(SceneNode,    8192, SceneNodeIdx);
meshes:        FixedArray(Mesh,         8192, MeshIdx);
materials:     FixedArray(Material,     8192, MaterialIdx);
mesh_arena:    BufferAllocator;

init_scenes :: () {
  buffer := new_array(512 << 20, u8, initialized = false);
  init(*mesh_arena, buffer);

  // Make 0 indexes be usable values
  array_add(*nodes, .{});
  array_add(*meshes, .{});
  array_add(*materials, .{});
}

data: *cgltf_data = ---;
prev_nodes_count: u32;
prev_meshes_count: u32;
prev_materials_count: u32;

load_scene :: (name: string) {
  path := tprint("resources/scenes/%\0", name);
  log("Loading gltf scene from path: %", path);

  options: cgltf_options;
  assert(cgltf_parse_file(*options, path.data, *data) == .success);
  assert(cgltf_load_buffers(*options, data, path.data) == .success);
  defer cgltf_free(data);

  assert(data.scenes_count == 1, "Cannot load %: too many scenes", path);
  scene := data.scenes;

  prev_nodes_count     = nodes.count;
  prev_meshes_count    = meshes.count;
  prev_materials_count = materials.count;

  setup_node :: (scene_node: *SceneNode, node: *cgltf_node, parent_idx: SceneNodeIdx) {
    scene_node.* = .{
      parent_idx      = parent_idx,
      children_count  = ifx cast(u32) node.children_count,
      mesh_idx        = ifx node.mesh then
                            cast(MeshIdx) (prev_meshes_count + node.mesh - data.meshes),
      translation    = (cast(*Vector3)    *node.translation).*,
      rotation       = (cast(*Quaternion) *node.rotation).*,
      scale          = (cast(*Vector3)    *node.scale).*,
    };

    node_name := to_string(node.name);
    memcpy(*scene_node.name, node_name.data, min(node_name.count, scene_node.name.count));
  }

  add_children :: (parent: *cgltf_node, parent_idx: SceneNodeIdx) {
    if parent.children_count {
      scene_parent := *nodes[parent_idx];
      scene_parent.first_child_idx = cast(SceneNodeIdx) nodes.count;

      for 0..parent.children_count - 1 {
        child     := (parent.children + it).*;
        child_idx := scene_parent.first_child_idx + cast(SceneNodeIdx) it;
        node := array_add(*nodes);
        setup_node(node, child, parent_idx);
        log("Scene node: % name: % mesh_idx: % children: %", child_idx, to_string(node.name), node.mesh_idx, node.children_count);
      }
      for 0..parent.children_count - 1 {
        child     := (parent.children + it).*;
        child_idx := scene_parent.first_child_idx + cast(SceneNodeIdx) it;
        add_children(child, child_idx);
      }
    }
  }

  assert(scene.nodes_count != 0, "No nodes in the scene: %", path);
  root_node_idx := cast(SceneNodeIdx) prev_nodes_count;
  array_add(*root_nodes, root_node_idx);
  root_node := array_add(*nodes);
  root_node.first_child_idx = root_node_idx + 1;
  root_node.children_count  = cast(u32) scene.nodes_count;
  log("Scene root node: % name: % mesh_idx: % children: %", root_node_idx, to_string(root_node.name), root_node.mesh_idx, root_node.children_count);

  for 0..scene.nodes_count - 1 {
    child := (scene.nodes + it).*;
    child_idx := root_node.first_child_idx + cast(SceneNodeIdx) it;
    node := array_add(*nodes);
    setup_node(node, child, root_node_idx);
    log("Scene node: % name: % mesh_idx: % children: %", child_idx, to_string(node.name), node.mesh_idx, node.children_count);
  }
  for 0..scene.nodes_count - 1 {
    child := (scene.nodes + it).*;
    child_idx := root_node.first_child_idx + cast(SceneNodeIdx) it;
    add_children(child, child_idx);
  }

  for 0..data.meshes_count - 1 {
    mesh := data.meshes + it;
    add_mesh(mesh);
  }

  for 0..data.materials_count - 1 {
    material := data.materials + it;
    array_add(*materials, .{
      albedo    = .{ component = material.pbr_metallic_roughness.base_color_factor },
      metallic  = material.pbr_metallic_roughness.metallic_factor,
      roughness = material.pbr_metallic_roughness.roughness_factor,
    });
  }
}

get_scene_node_by_name :: (name: string) -> SceneNodeIdx, *SceneNode {
  for * nodes if to_string(it.name) == name then return cast(SceneNodeIdx) it_index, it;
  return 0, *nodes[0];
}

#scope_file

add_mesh :: (mesh: *cgltf_mesh) {
  assert(mesh.primitives_count == 1, "Cannot load the scene: mesh has too many primitives");
  assert(mesh.primitives_count == 1);
  primitive      := *mesh.primitives[0];
  indices_count  := primitive.indices[0].count;
  vertices_count := primitive.attributes[0].data[0].count;

  material_idx := cast(MaterialIdx) (prev_materials_count + primitive.material - data.materials);

  total_bytes := indices_count * size_of(u32) + vertices_count * size_of(Vertex);
  model_memory := new_array(xx total_bytes, u8, initialized = false,, allocator(*mesh_arena));

  indices: []u32 = {
    data  = cast(*u32)(model_memory.data + vertices_count * size_of(Vertex)),
    count = xx indices_count
  };
  for i: 0..indices_count - 1 indices[i] = xx cgltf_accessor_read_index(primitive.indices, i);

  vertices: []Vertex = { data = cast(*Vertex)model_memory.data, count = xx vertices_count };
  // log("Mesh primitive type: %", primitive.type);
  for i: 0..primitive.attributes_count - 1 {
    attr := *primitive.attributes[i];
    // log("Mesh primitive attr name: %, type: %, index: %, data type: %, data count: %",
    //     to_string(attr.name),
    //     attr.type,
    //     attr.index,
    //     attr.data[0].type,
    //     attr.data[0].count,
    // );
    floats_count := cgltf_accessor_unpack_floats(attr.data, null, 0);
    floats := new_array(xx floats_count, float,, temp);
    _ = cgltf_accessor_unpack_floats(attr.data, floats.data, floats_count);

    if attr.type == {
      case .cgltf_attribute_type_position;
        num_components := cgltf_num_components(attr.data[0].type);
        // log("Position has % components", num_components);
        assert(num_components == 3);

        positions: []Vector3 = ---;
        positions.data  = cast(*Vector3)floats.data;
        positions.count = floats.count / 3;
        for i: 0..vertices_count - 1 vertices[i].position = positions[i];
      case .cgltf_attribute_type_normal;
        num_components := cgltf_num_components(attr.data[0].type);
        // log("Normal has % components", num_components);
        assert(num_components == 3);

        normals: []Vector3 = ---;
        normals.data  = cast(*Vector3)floats.data;
        normals.count = floats.count / 3;
        for i: 0..vertices_count - 1 vertices[i].normal = normals[i];
      case .cgltf_attribute_type_texcoord;
        num_components := cgltf_num_components(attr.data[0].type);
        // log("Texture coord has % components", num_components);
        assert(num_components == 2);

        uvs: []Vector2 = ---;
        uvs.data  = cast(*Vector2)floats.data;
        uvs.count = floats.count / 2;
        for i: 0..vertices_count - 1 {
          vertices[i].uv_x = uvs[i].x;
          vertices[i].uv_y = uvs[i].y;
        }
      case;
        // log_error("Unknown attribute type: {}. Skipping", attr.type);
    }
  }
  // For debugging use normals as colors
  for * vertices it.color = abs(it.normal);

  // mesh_idx := prev_meshes_count + mesh - data.meshes;
  // mesh_name := to_string(mesh.name);
  // log("Mesh %: % vertices: % indices: %", mesh_idx, mesh_name, vertices.count, indices.count);
  array_add(*meshes, Mesh.{ material_idx, indices, vertices });
}

#import,file "math.jai";
#import,file "allocators.jai";
#import,file "fixed_array.jai";
#import "cgltf";
#import "Basic";
