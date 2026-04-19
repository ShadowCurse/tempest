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

create_box :: (size_x: float, size_y: float, size_z: float) -> Mesh {
  indices :=  u32.[
     0,  1,  2,  2,  3,  0, // front
     4,  5,  6,  6,  7,  4, // back
     8,  9, 10, 10, 11,  8, // right
    12, 13, 14, 14, 15, 12, // left
    16, 17, 18, 18, 19, 16, // top
    20, 21, 22, 22, 23, 20, // bottom
  ];

  half_x := size_x / 2.0;
  half_y := size_y / 2.0;
  half_z := size_z / 2.0;

  vertices := Vertex.[
    // Front
    .{ .{-half_x, -half_y,  half_z}, 0.0, .{ 0.0,  0.0,  1.0}, 0.0, .{ 0.0,  0.0,  1.0}, 0.0 },
    .{ .{ half_x, -half_y,  half_z}, 1.0, .{ 0.0,  0.0,  1.0}, 0.0, .{ 0.0,  0.0,  1.0}, 0.0 },
    .{ .{ half_x,  half_y,  half_z}, 1.0, .{ 0.0,  0.0,  1.0}, 1.0, .{ 0.0,  0.0,  1.0}, 0.0 },
    .{ .{-half_x,  half_y,  half_z}, 0.0, .{ 0.0,  0.0,  1.0}, 1.0, .{ 0.0,  0.0,  1.0}, 0.0 },
    // Back
    .{ .{-half_x,  half_y, -half_z}, 1.0, .{ 0.0,  0.0, -1.0}, 0.0, .{ 0.0,  0.0, -1.0}, 0.0 },
    .{ .{ half_x,  half_y, -half_z}, 0.0, .{ 0.0,  0.0, -1.0}, 0.0, .{ 0.0,  0.0, -1.0}, 0.0 },
    .{ .{ half_x, -half_y, -half_z}, 0.0, .{ 0.0,  0.0, -1.0}, 1.0, .{ 0.0,  0.0, -1.0}, 0.0 },
    .{ .{-half_x, -half_y, -half_z}, 1.0, .{ 0.0,  0.0, -1.0}, 1.0, .{ 0.0,  0.0, -1.0}, 0.0 },
    // Right
    .{ .{ half_x, -half_y, -half_z}, 0.0, .{ 1.0,  0.0,  0.0}, 0.0, .{ 1.0,  0.0,  0.0}, 0.0 },
    .{ .{ half_x,  half_y, -half_z}, 1.0, .{ 1.0,  0.0,  0.0}, 0.0, .{ 1.0,  0.0,  0.0}, 0.0 },
    .{ .{ half_x,  half_y,  half_z}, 1.0, .{ 1.0,  0.0,  0.0}, 1.0, .{ 1.0,  0.0,  0.0}, 0.0 },
    .{ .{ half_x, -half_y,  half_z}, 0.0, .{ 1.0,  0.0,  0.0}, 1.0, .{ 1.0,  0.0,  0.0}, 0.0 },
    // Left
    .{ .{-half_x, -half_y,  half_z}, 1.0, .{-1.0,  0.0,  0.0}, 0.0, .{-1.0,  0.0,  0.0}, 0.0 },
    .{ .{-half_x,  half_y,  half_z}, 0.0, .{-1.0,  0.0,  0.0}, 0.0, .{-1.0,  0.0,  0.0}, 0.0 },
    .{ .{-half_x,  half_y, -half_z}, 0.0, .{-1.0,  0.0,  0.0}, 1.0, .{-1.0,  0.0,  0.0}, 0.0 },
    .{ .{-half_x, -half_y, -half_z}, 1.0, .{-1.0,  0.0,  0.0}, 1.0, .{-1.0,  0.0,  0.0}, 0.0 },
    // Top
    .{ .{ half_x,  half_y, -half_z}, 1.0, .{ 0.0,  1.0,  0.0}, 0.0, .{ 0.0,  1.0,  0.0}, 0.0 },
    .{ .{-half_x,  half_y, -half_z}, 0.0, .{ 0.0,  1.0,  0.0}, 0.0, .{ 0.0,  1.0,  0.0}, 0.0 },
    .{ .{-half_x,  half_y,  half_z}, 0.0, .{ 0.0,  1.0,  0.0}, 1.0, .{ 0.0,  1.0,  0.0}, 0.0 },
    .{ .{ half_x,  half_y,  half_z}, 1.0, .{ 0.0,  1.0,  0.0}, 1.0, .{ 0.0,  1.0,  0.0}, 0.0 },
    // Bottom
    .{ .{ half_x, -half_y,  half_z}, 0.0, .{ 0.0, -1.0,  0.0}, 0.0, .{ 0.0, -1.0,  0.0}, 0.0 },
    .{ .{-half_x, -half_y,  half_z}, 1.0, .{ 0.0, -1.0,  0.0}, 0.0, .{ 0.0, -1.0,  0.0}, 0.0 },
    .{ .{-half_x, -half_y, -half_z}, 1.0, .{ 0.0, -1.0,  0.0}, 1.0, .{ 0.0, -1.0,  0.0}, 0.0 },
    .{ .{ half_x, -half_y, -half_z}, 0.0, .{ 0.0, -1.0,  0.0}, 1.0, .{ 0.0, -1.0,  0.0}, 0.0 },
  ];
  return .{ 0, array_copy(indices), array_copy(vertices) };
}

create_sphere_uv :: (radius: float, sectors: u32, stacks: u32) -> Mesh {
  length_inv  := 1.0 / radius;
  sector_step := 2.0 * PI / cast(float)sectors;

  assert(2 < stacks);
  // sacks include the top and bottom points, so sub 2 here
  inner_stacks := stacks - 2;
  stack_step  := PI / cast(float)(stacks - 1);

  total_vertices := sectors * inner_stacks + 2; // 2 for top and bottom
  total_indices  := sectors * 3 * 2 + (sectors * (inner_stacks - 1)) * 2 * 3;
  vertices := new_array(total_vertices, Vertex, initialized = false);
  indices  := new_array(total_indices,  u32,    initialized = false);

  vv := fixed_slice(vertices);

  push(*vv, .{.{0.0, 0.0, radius}, 0.0, .{0.0, 0.0, 1.0}, 0.0, .{0.0, 0.0, 1.0}, 0.0});
  for i: 1..inner_stacks {
    stack_angle := PI / 2.0 - stack_step * i;
    xy := cos(stack_angle) * radius;
    z  := sin(stack_angle) * radius;
    for j: 1..sectors {
      sector_angle := sector_step * j;
      x := cos(sector_angle) * xy;
      y := sin(sector_angle) * xy;
      position := Vector3.{x, y, z};
      normal   := Vector3.{x * length_inv, y * length_inv, z * length_inv};
      uv_x     := cast(float)j / cast(float)sectors;
      uv_y     := cast(float)i / cast(float)stacks;
      push(*vv, .{ position, uv_x, normal, uv_y, normal, 0 });
    }
  }
  push(*vv, .{.{0.0, 0.0, -radius}, 0.0, .{0.0, 0.0, -1.0}, 0.0, .{0.0, 0.0, -1.0}, 0.0});
  assert(vv.count == total_vertices, "% != %", vv.count, total_vertices);

  ii := fixed_slice(indices);
  for i: 0..sectors - 1 {
    push(*ii, 0);
    push(*ii, i + 1);
    if i != sectors - 1 {
      push(*ii, i + 2);
    } else {
      push(*ii, 1);
    }
  }
  //  k1--k1+1
  //  |  / |
  //  | /  |
  //  k2--k2+1
  // only add triangles if there are at lest 2 inner_stacks, otherwise there is nothing
  // to connect
  for i: 0..inner_stacks - 2 {
    k1 := 1 + i * sectors;
    k2 := 1 + (i + 1) * sectors;
    for j: 0..sectors - 1 {
      if j != sectors - 1 {
        push(*ii, k1);
        push(*ii, k2);
        push(*ii, k1 + 1);

        push(*ii, k1 + 1);
        push(*ii, k2);
        push(*ii, k2 + 1);
      } else {
        push(*ii, k1);
        push(*ii, k2);
        push(*ii, 1 + i * sectors);

        push(*ii, 1 + i * sectors);
        push(*ii, k2);
        push(*ii, 1 + (i + 1) * sectors);
      }
      k1 += 1;
      k2 += 1;
    }
  }
  for i: 0..sectors - 1 {
    push(*ii, total_vertices - 1);
    push(*ii, total_vertices - 1 - sectors + i);
    if i != sectors - 1 {
      push(*ii, total_vertices - 1 - sectors + i + 1);
    } else {
      push(*ii, total_vertices - 1 - sectors);
    }
  }
  assert(ii.count == total_indices, "% != %", ii.count, total_indices);
  return .{ 0, indices, vertices };
}


create_cylinder :: (radius: float, sectors: u32, heigth: float) -> Mesh {
  half_h := heigth / 2.0;
  sector_step   := 2.0 * PI / cast(float)sectors;
  points := new_array(sectors, Vector3,,temp);
  pp := fixed_slice(points);
  for i: 0..sectors - 1 {
    angle := sector_step * i;
    push(*pp, .{cos(angle), sin(angle), 0});
  }

  total_vertices := sectors * 2 + 2; // for 2 centers
  total_indices  := sectors * 2 * 3 * 2;
  vertices := new_array(total_vertices, Vertex, initialized = false);
  indices  := new_array(total_indices,  u32,    initialized = false);

  vv := fixed_slice(vertices);
  push(*vv, .{.{0.0, 0.0, half_h}, 0.0, .{0.0, 0.0, 1.0}, 0.0, .{0.0, 0.0, 1.0}, 0.0});
  for < i: 0..1 {
    h := -half_h + heigth * i;
    uv_y := cast(float)(1 - i);

    for j: 0..sectors - 1 {
      p := points[j];
      position := Vector3.{p.x * radius, p.y * radius, h};
      normal   := p;
      uv_x     := cast(float)j / cast(float)sectors;
      push(*vv, .{ position, uv_x, normal, uv_y, normal, 0 });
    }
  }
  push(*vv, .{.{0.0, 0.0, -half_h}, 0.0, .{0.0, 0.0, -1.0}, 0.0, .{0.0, 0.0, -1.0}, 0.0});
  assert(vv.count == total_vertices, "% != %", vv.count, total_vertices);

  // note(sc): this logic is basically same as for sphere
  ii := fixed_slice(indices);
  for i: 0..sectors - 1 {
    push(*ii, 0);
    push(*ii, i + 1);
    if i != sectors - 1 {
      push(*ii, i + 2);
    } else {
      push(*ii, 1);
    }
  }
  //  k1--k1+1
  //  |  / |
  //  | /  |
  //  k2--k2+1
  {
    k1: u32 = 1;
    k2: u32 = 1 + sectors;
    for j: 0..sectors - 1 {
      if j != sectors - 1 {
        push(*ii, k1);
        push(*ii, k2);
        push(*ii, k1 + 1);

        push(*ii, k1 + 1);
        push(*ii, k2);
        push(*ii, k2 + 1);
      } else {
        push(*ii, k1);
        push(*ii, k2);
        push(*ii, 1);

        push(*ii, 1);
        push(*ii, k2);
        push(*ii, 1 + sectors);
      }
      k1 += 1;
      k2 += 1;
    }
  }
  for i: 0..sectors - 1 {
    push(*ii, total_vertices - 1);
    push(*ii, total_vertices - 1 - sectors + i);
    if i != sectors - 1 {
      push(*ii, total_vertices - 1 - sectors + i + 1);
    } else {
      push(*ii, total_vertices - 1 - sectors);
    }
  }
  assert(ii.count == total_indices, "% != %", ii.count, total_indices);
  return .{ 0, indices, vertices };
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
#import,file "fixed_slice.jai";
#import "cgltf";
#import "Basic";
