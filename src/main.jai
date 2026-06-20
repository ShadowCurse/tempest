WATCHED_FILES :: string.[
  "shaders/gradient_comp.glsl",
  "shaders/grid_frag.glsl",
  "shaders/grid_vert.glsl",
  "shaders/mesh_frag.glsl",
  "shaders/mesh_vert.glsl",
  "shaders/ui_frag.glsl",
  "shaders/ui_vert.glsl",
];

file_watcher: FileWatcher;

FRAMES :: 2;
current_frame_idx: u8 = 0;
// note(sc): create one additional command for immediate actions
render_commands: [FRAMES + 1]RenderCommand = ---;
NO_LAST_SWAPCHAIN_INDEX : u32 = ~cast(u32)0;

cpu_to_gpu_buffer_arena: GpuBufferArena;
staging_buffer:          GpuBufferSlice(u8);
ui_buffers:              [FRAMES]GpuBufferSlice(Quad);
scene_buffer:            GpuBufferSlice(SceneInfo);
gizmo_buffers:           [FRAMES]GpuBufferSlice(Matrix4);

gpu_buffer_arena: GpuBufferArena;
mesh_buffer:      GpuBufferSlice(u8);

font_buffer:      GpuBufferSlice(u8);
GpuFontBufferInfo :: struct {
  curves_offset: u32;
  bands_offset: u32;
}
font_buffer_info: GpuFontBufferInfo;

gpu_image_arena: GpuImageArena;
depth_image:     GpuImage;

Timestamp :: enum u8 {
  COMPUTE_START :: 0;
  COMPUTE_END;
  GRID_START;
  GRID_END;
  MESH_START;
  MESH_END;
  UI_START;
  UI_END;
  GIZMO_START;
  GIZMO_END;
};
timestamp_array: EnumArray(Timestamp, u64);
timestamp_pool:  VkQueryPool;

compute_pipeline: Pipeline;
ui_pipeline:      Pipeline;
grid_pipeline:    Pipeline;
mesh_pipeline:    Pipeline;
gizmo_pipeline:   Pipeline;

cube_mesh_idx:      MeshIdx;
sphere_mesh_idx:    MeshIdx;
gizmo_cylinder_idx: MeshIdx;
gizmo_cone_idx:     MeshIdx;
gpu_mesh_infos:     FixedArray(GpuMeshInfo, 8192, MeshIdx);

// rendering settings
visual_aabb:  bool          = false;
polygon_mode: VkPolygonMode = .FILL;

//camera
camera_position:            Vector3 = .{ 0.0, -5.0, 5.0 };
camera_rotation:            Vector2 = .{ 0.78, 0.0 };
camera_view:                Matrix4;
camera_view_inv:            Matrix4;
camera_projection:          Matrix4;
camera_projection_inv:      Matrix4;
camera_mouse_ray_direction: Vector3;

// selection
selection_on:            bool;
selected_scene_node_idx: SceneNodeIdx;
selected_intersection:   TriangleIntersectionResult;
selected_world_position: Vector3;
gizmo_dragging_on:       bool;
selected_gizmo_axis:     enum { NONE; X; Y; Z; } = .NONE;
selection_starting_camera_position:            Vector3;
selection_starting_camera_mouse_ray_direction: Vector3;
gizmo_current_drag_delta: float32;

main :: () {
  init_prof();
  defer deinit_prof();

  if !platform_init() return;
  defer platform_quit();
  if !vulkan_init(true) return;

  if init(*file_watcher) {
    for WATCHED_FILES {
      if !add_file(*file_watcher, it) log_error("Cannot setup watch for file: %", it);
    }
    log("Watcher: %", file_watcher);
  }

  for *rc: render_commands rc.* = create_render_command();
  cpu_to_gpu_memory := allocate_gpu_memory(64 << 20, .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT);
  init(*cpu_to_gpu_buffer_arena, cpu_to_gpu_memory, .TRANSFER_SRC_BIT | .SHADER_DEVICE_ADDRESS_BIT);
  staging_buffer, ok := push(*cpu_to_gpu_buffer_arena, u8, 16 << 20);
  assert(ok);
  for * ui_buffers {
    it.*, ok = push(*cpu_to_gpu_buffer_arena, Quad, 1 << 15);
    assert(ok);
  }
  scene_buffer, ok = push(*cpu_to_gpu_buffer_arena, SceneInfo);
  assert(ok);
  for * gizmo_buffers {
    it.*, ok = push(*cpu_to_gpu_buffer_arena, Matrix4, 6); // 3 rods, 3 cones
    assert(ok);
  }

  gpu_memory := allocate_gpu_memory(256 << 20, .DEVICE_LOCAL_BIT);
  init(*gpu_buffer_arena, gpu_memory, .TRANSFER_DST_BIT | .INDEX_BUFFER_BIT | .SHADER_DEVICE_ADDRESS_BIT);
  mesh_buffer, ok = push(*gpu_buffer_arena, u8, 128 << 20);
  assert(ok);

  pool_create_info: VkQueryPoolCreateInfo = .{
    queryType  = .TIMESTAMP,
    queryCount = xx timestamp_array.values.count,
  };
  timestamp_pool = create_query_pool(pool_create_info);

  font, tmp_curves, tmp_bands := load_font("NotoSans-Regular");
  font_buffer, ok = push(
    *gpu_buffer_arena,
    u8,
    cast(u32)(tmp_curves.count * size_of(u16) + tmp_bands.count * size_of(u16)),
  );
  assert(ok);

  gpu_image_memory := allocate_gpu_memory(64 << 20, .DEVICE_LOCAL_BIT);
  init(*gpu_image_arena, gpu_image_memory);
  depth_image, ok = push(
    *gpu_image_arena,
    window_width,
    window_height,
    .D32_SFLOAT,
    .DEPTH_STENCIL_ATTACHMENT_BIT,
  );
  assert(ok);

  default_scene: Scene;
  init(*default_scene);
  crystal_idx := load_gltf(*default_scene, "crystal.glb");
  bistro_idx  := load_gltf(*default_scene, "bistro.glb");
  cube_mesh_idx   = add_mesh(*default_scene, create_box(1.0, 1.0, 1.0,, temp));
  sphere_mesh_idx = add_mesh(*default_scene, create_sphere_uv(1.0, 32, 32,,
                                                              allocator(*default_scene.mesh_arena)));
  gizmo_cylinder_idx = add_mesh(*default_scene, create_cylinder(0.2, 32, 4.0,,
                                                              allocator(*default_scene.mesh_arena)));
  gizmo_cone_idx     = add_mesh(*default_scene, create_cone(0.4, 32, 1.0,,
                                                              allocator(*default_scene.mesh_arena)));

  cylinder_mesh_idx := add_mesh(*default_scene, create_cylinder(0.5, 32, 1.0,,
                                                              allocator(*default_scene.mesh_arena)));

  node2_idx,   node2   := add_node(*default_scene, "root");

  node1_c_idx,   node1_c   := add_node(*default_scene, node2_idx, "center");
  node1_c.mesh_idx = cylinder_mesh_idx;
  node1_c.rotation = quat_from_axis_angle(.{y = 1.0}, PI / 2.0);

  node2_c_idx, node2_c := add_node(*default_scene, node2_idx, "ball1");
  node2_c.mesh_idx = sphere_mesh_idx;
  node2_c.translation = .{x = 1.5};

  node3_c_idx, node3_c := add_node(*default_scene, node2_idx, "ball2");
  node3_c.mesh_idx = sphere_mesh_idx;
  node3_c.translation = .{x = -1.5};

  {
    imm_command := *render_commands[FRAMES];
    {
      begin_render_command(imm_command);
      defer submit_wait_reset(imm_command);
      defer end_render_command(imm_command);

      transition_image(
        imm_command,
        depth_image.image,
        depth_image.usage,
        .UNDEFINED,
        .GENERAL,
        VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT,
        VK_ACCESS_2_NONE,
        VK_ACCESS_2_MEMORY_WRITE_BIT,
      );
    }

    staging_buffer_host_mem := host_memory(staging_buffer);
    {
      begin_render_command(imm_command);
      defer submit_wait_reset(imm_command);
      defer end_render_command(imm_command);

      font_buffer_info.curves_offset = 0;
      // In the shader it is an array of u32s, but here the buffer is in u16s
      font_buffer_info.bands_offset  = cast(u32)tmp_curves.count / 2;
      assert(tmp_curves.count % 2 == 0);

      curves_bytes := tmp_curves.count * size_of(u16);
      bands_bytes  := tmp_curves.count * size_of(u16);
      total_bytes  := curves_bytes + bands_bytes;
      memcpy(staging_buffer_host_mem.data, tmp_curves.data, curves_bytes);
      memcpy(staging_buffer_host_mem.data + curves_bytes, tmp_bands.data, bands_bytes);
      cmd_copy_buffer_slice_to_buffer_slice(
        imm_command,
        slice(font_buffer,    0, cast(u32)total_bytes),
        slice(staging_buffer, 0, cast(u32)total_bytes),
      );
    }

    mesh_buffer_offset := 0;
    for *mesh: default_scene.meshes {
      begin_render_command(imm_command);
      defer submit_wait_reset(imm_command);
      defer end_render_command(imm_command);

      mesh_info := array_add(*gpu_mesh_infos);
      if mesh.vertices.count == 0 || mesh.indices.count == 0 then continue;

      vertices_bytes := mesh.vertices.count * size_of(Vertex);
      indices_bytes  := mesh.indices.count  * size_of(u32);
      total_bytes    := vertices_bytes + indices_bytes;
      assert(vertices_bytes + indices_bytes < staging_buffer_host_mem.count);
      memcpy(staging_buffer_host_mem.data, mesh.vertices.data, vertices_bytes);
      memcpy(staging_buffer_host_mem.data + vertices_bytes, mesh.indices.data, indices_bytes);
      mesh_buffer_offset = align_up(mesh_buffer_offset, 4);
      mesh_info.* = .{
        cast(u64)mesh_buffer_offset,
        cast(u32)mesh_buffer_offset + cast(u32)vertices_bytes,
        cast(u32)mesh.indices.count,
        cast(u32)mesh.vertices.count
      };

      cmd_copy_buffer_slice_to_buffer_slice(
        imm_command,
        slice(mesh_buffer,    cast(u32)mesh_buffer_offset, cast(u32)(mesh_buffer_offset + total_bytes)),
        slice(staging_buffer, 0,                           cast(u32)total_bytes)
      );
      mesh_buffer_offset += total_bytes;
    }
  }

  compute_pipeline = create_full_screen_effect_comptue_pipeline();
  ui_pipeline      = create_ui_pipeline();
  grid_pipeline    = create_grid_pipeline();
  mesh_pipeline    = create_mesh_pipeline();
  gizmo_pipeline   = create_gizmo_pipeline();

  ui: Context;
  init(*ui, *font);
  draw_sphere  := false;
  draw_crystal := false;
  draw_bistro  := false;

  v := 0.1;
  need_swapchain_recreation      := false;
  last_swapchain_image_index: u32 = NO_LAST_SWAPCHAIN_INDEX ;
  last_present_time_ns: u64       = 0;
  dt_s: float                     = 0.0;

  while !quit {
    reset_temporary_storage();
    platform_new_frame();
    new_frame(*ui, host_memory(ui_buffers[current_frame_idx]));
    ui.mouse_position     = mouse_position;
    ui.mouse_just_pressed = just_pressed(mouse_state, .LMB);
    ui.mouse_down         = pressed(mouse_state, .LMB);

    prof_draw(*ui);
    prof_new_frame();

    prof_record_thread_start();
    defer prof_record_thread_end();

    rebuild_pipelines_if_needed();

    // note(sc): the caller will get one frame old data
    get_query_pool_results(timestamp_pool, timestamp_array.values);
    compute_ns := timestamp_array[Timestamp.COMPUTE_END] - timestamp_array[Timestamp.COMPUTE_START];
    compute_ms := cast(float)compute_ns / 1000_000.0;
    grid_ns    := timestamp_array[Timestamp.GRID_END] - timestamp_array[Timestamp.GRID_START];
    grid_ms    := cast(float)grid_ns / 1000_000.0;
    mesh_ns    := timestamp_array[Timestamp.MESH_END] - timestamp_array[Timestamp.MESH_START];
    mesh_ms    := cast(float)mesh_ns / 1000_000.0;
    ui_ns      := timestamp_array[Timestamp.UI_END] - timestamp_array[Timestamp.UI_START];
    ui_ms      := cast(float)ui_ns / 1000_000.0;

    for get_past_presentation_timing() {
      if it.reportComplete {
        present_time := it.pPresentStages[0].time;
        dt_s = cast(float)(present_time - last_present_time_ns) / 1000.0 / 1000.0 / 1000.0;
        last_present_time_ns = present_time;
      }
    }

    {
      prof_scope("build_ui");

      {
        panel_start(*ui, "Panel", .{ 300.0, 750.0 }, .{ 1.0, 1.0 });
        defer panel_end(*ui);

        label(*ui, tprint("FPS: %", 1.0 / dt_s));
        label(*ui, tprint("dt s: %", dt_s));
        label(*ui, tprint("GPU COMPUTE ms: %", compute_ms));
        label(*ui, tprint("GPU GRID ms: %", grid_ms));
        label(*ui, tprint("GPU MESH ms: %", mesh_ms));
        label(*ui, tprint("GPU UI ms: %", ui_ms));
        label(*ui, tprint("pos: %", camera_position));
        label(*ui, tprint("rot: %", camera_rotation));
        label(*ui, tprint("pressed_id: %", ui.pressed_id));
        label(*ui, tprint("hover_id: %", ui.hover_id));
        toggle(*ui, "Visualize AABB", *visual_aabb);
        toggle(*ui, "Draw Sphere",    *draw_sphere);
        toggle(*ui, "Draw Crystal",   *draw_crystal);
        toggle(*ui, "Draw Bistro",    *draw_bistro);
        slider(*ui, "Gradient", 0.0, 1.0, *v);
        select(*ui, "Polygon mode2", *polygon_mode, .["FILL", "LINE", "POINT"]);
      }
      finish_widgets(*ui);
    }

    camera_velocity: Vector3;
    if !ui.consumed_keyboard_event {
      if pressed(keyboard_state, .W)       camera_velocity.z += 1.0;
      if pressed(keyboard_state, .S)       camera_velocity.z -= 1.0;
      if pressed(keyboard_state, .A)       camera_velocity.x -= 1.0;
      if pressed(keyboard_state, .D)       camera_velocity.x += 1.0;
      if pressed(keyboard_state, .LCTRL)   camera_velocity.y += 1.0;
      if pressed(keyboard_state, .SPACE)   camera_velocity.y -= 1.0;
      if just_pressed(keyboard_state, .F1) context.prof_enabled = !context.prof_enabled;
    }

    selection_on = false;
    if !ui.consumed_mouse_event {
      if just_pressed(mouse_state, .LMB) && selected_gizmo_axis != .NONE {
        gizmo_dragging_on = true;
      } else if !gizmo_dragging_on {
        if pressed(mouse_state, .LMB) {
          camera_rotation.y -= mouse_movement.x * (1.0 / 120.0);
          camera_rotation.x -= mouse_movement.y * (1.0 / 120.0);
          camera_rotation.x = clamp(camera_rotation.x, 0, PI);
        }
      }
      if just_released(mouse_state, .LMB) {
        gizmo_dragging_on = false;
        gizmo_current_drag_delta = 0.0;
      }
      if just_pressed(mouse_state, .RMB) {
        selection_on = true;
        selected_scene_node_idx = 0;
        selected_intersection = .{};
      }
    }

    if need_swapchain_recreation {
      if last_swapchain_image_index != NO_LAST_SWAPCHAIN_INDEX
        wait_swapchain_fence(xx last_swapchain_image_index);
      recreate_swapchain();
      recreate_depth_image();
    }

    render_command := *render_commands[current_frame_idx];
    defer current_frame_idx = (current_frame_idx + 1) % FRAMES;

    wait_for_cmd(render_command);
    reset_render_command(render_command);

    swapchaine_image_index: u32 = 0;
    while (true) {
      index, need_swapchain_recreation := acquire_next_image(render_command);
      if !need_swapchain_recreation {
        swapchaine_image_index = index;
        break;
      } else {
          if last_swapchain_image_index != NO_LAST_SWAPCHAIN_INDEX
            wait_swapchain_fence(xx last_swapchain_image_index);
          recreate_swapchain();
          recreate_depth_image();

          // note(sc): for some reason acquiring the image singles the semaphore even on
          // failure. Maybe there is a way to handle it more reasonably.
          destroy_semaphore(render_command);
          render_command.swapchain_semaphore = create_semaphore(.{});

          last_swapchain_image_index = NO_LAST_SWAPCHAIN_INDEX;
      }
    }
    last_swapchain_image_index = swapchaine_image_index;

    begin_render_command(render_command);
    cmd_reset_query_pool(render_command, timestamp_pool, xx timestamp_array.values.count);

    cmd_transition_swapchain_image(
      render_command,
      swapchaine_image_index,
      .UNDEFINED,
      .GENERAL,
      VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
      VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
      VK_ACCESS_2_NONE,
      VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT,
    );

    {
      prof_scope("compute_pipeline");

      cmd_write_timestamp(render_command, timestamp_pool, .TOP_OF_PIPE_BIT, xx Timestamp.COMPUTE_START);
      defer cmd_write_timestamp(render_command, timestamp_pool, .BOTTOM_OF_PIPE_BIT, xx Timestamp.COMPUTE_END);

      cmd_bind_pipeline(render_command, compute_pipeline, .COMPUTE);
      image_descriptors: [1]VkDescriptorImageInfo = .[
        .{
          sampler     = null,
          imageView   = swapchain_image_views[swapchaine_image_index],
          imageLayout = .GENERAL,
        },
      ];
      descriptor_sets: [1]VkWriteDescriptorSet = .[
        .{
          dstSet          = null,
          dstBinding      = 0,
          descriptorCount = 1,
          descriptorType  = .STORAGE_IMAGE,
          pImageInfo      = *image_descriptors[0],
        },
      ];
      cmd_push_descriptors(render_command, compute_pipeline, .COMPUTE, descriptor_sets);
      cmd_push_constants(render_command, compute_pipeline, .COMPUTE_BIT, *v);
      cmd_dispatch(render_command, (window_width + 15) / 16, (window_height + 15) / 16, 1);
    }

    cmd_barrier(
      render_command,
      VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
      VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT ,
      VK_ACCESS_2_MEMORY_WRITE_BIT,
      VK_ACCESS_2_MEMORY_WRITE_BIT,
    );

    {
      prof_scope("graphics_pipeline");

      cmd_begin_rendering_to_swapchain(render_command, swapchaine_image_index, depth_image.view);
      defer cmd_end_rendering(render_command);

      world_rotation_z  := quat_from_axis_angle(.{ z = 1.0 }, camera_rotation.y);
      camera_rotation_x := quat_from_axis_angle(.{ x = -1.0 }, PI - camera_rotation.x);
      camera_to_world_rotation := world_rotation_z * camera_rotation_x;
      world_to_camera_rotation := conjugate(camera_to_world_rotation);

      camera_position += rotate(camera_velocity * 5.0 * (1.0 / 120.0), camera_to_world_rotation);

      camera_view = quat_to_mat4(world_to_camera_rotation);
      translate(*camera_view, rotate(-camera_position, world_to_camera_rotation));

      camera_view_inv = quat_to_mat4(camera_to_world_rotation);
      translate(*camera_view_inv, camera_position);

      camera_projection = perspective(PI / 2.0,
                                      cast(float)window_width / cast(float)window_height,
                                      0.1, 10000.0);
      camera_projection_inv = inverse(camera_projection);

      camera_mouse_clip := Vector4.{
        (mouse_position.x / cast(float)window_width  * 2.0) - 1.0,
        ((mouse_position.y / cast(float)window_height * 2.0) - 1.0),
        1.0,
        1.0
      };
      camera_mouse_near_plane := camera_view_inv * camera_projection_inv * camera_mouse_clip;
      camera_mouse_near_plane_world := camera_mouse_near_plane.xyz / camera_mouse_near_plane.w;
      // log("camera_mouse_near_plane_world %", camera_mouse_near_plane_world);
      camera_mouse_ray_direction = normalize(camera_mouse_near_plane_world - camera_position);
      // log("camera_mouse_ray_direction %", camera_mouse_ray_direction);

      scene := scene_buffer.host_ptr;
      scene.* = .{
        camera_view       = camera_view,
        camera_view_inv   = camera_view_inv,
        camera_projection = camera_projection,
      };

      // mesh
      {
        cmd_write_timestamp(render_command, timestamp_pool, .TOP_OF_PIPE_BIT, xx Timestamp.MESH_START);
        defer cmd_write_timestamp(render_command, timestamp_pool, .BOTTOM_OF_PIPE_BIT, xx Timestamp.MESH_END);

        cmd_bind_pipeline(render_command, mesh_pipeline, .GRAPHICS);
        cmd_set_polygon_mode(render_command, polygon_mode);
        if draw_sphere  then draw_node(render_command, default_scene, node2_idx, Matrix4_Identity);
        if draw_crystal then draw_node(render_command, default_scene, crystal_idx, Matrix4_Identity);
        if draw_bistro  then draw_node(render_command, default_scene, bistro_idx, Matrix4_Identity);
      }

      // grid
      {
        cmd_write_timestamp(render_command, timestamp_pool, .TOP_OF_PIPE_BIT, xx Timestamp.GRID_START);
        defer cmd_write_timestamp(render_command, timestamp_pool, .BOTTOM_OF_PIPE_BIT, xx Timestamp.GRID_END);

        cmd_bind_pipeline(render_command, grid_pipeline, .GRAPHICS);
        constant: GridPushConstant = .{
          scene_buffer.device_address
        };
        cmd_push_constants(render_command, grid_pipeline, .VERTEX_BIT | .FRAGMENT_BIT, *constant);
        cmd_draw(render_command, 3, 1, 0, 0);
      }

    }

    {
      prof_scope("ui_pipeline");

      cmd_begin_rendering_to_swapchain(render_command, swapchaine_image_index);
      defer cmd_end_rendering(render_command);

      {
        cmd_write_timestamp(render_command, timestamp_pool, .TOP_OF_PIPE_BIT, xx Timestamp.UI_START);
        defer cmd_write_timestamp(render_command, timestamp_pool, .BOTTOM_OF_PIPE_BIT, xx Timestamp.UI_END);

        cmd_bind_pipeline(render_command, ui_pipeline, .GRAPHICS);
        constant: UiPushConstant = .{
          quads         = ui_buffers[current_frame_idx].device_address,
          screen_size   = .{ xx window_width, xx window_height },
          data_buffer   = font_buffer.device_address,
          curves_offset = font_buffer_info.curves_offset,
          bands_offset  = font_buffer_info.bands_offset,
        };
        cmd_push_constants(render_command, ui_pipeline, .VERTEX_BIT | .FRAGMENT_BIT, *constant);
        cmd_draw(render_command, 6, draw_elements(ui), 0, 0);
      }
    }

    {
      prof_scope("gizmo_pipeline");

      cmd_begin_rendering_to_swapchain(render_command, swapchaine_image_index, depth_image.view);
      defer cmd_end_rendering(render_command);

      {
        cmd_write_timestamp(render_command, timestamp_pool, .TOP_OF_PIPE_BIT, xx Timestamp.GIZMO_START);
        defer cmd_write_timestamp(render_command, timestamp_pool, .BOTTOM_OF_PIPE_BIT, xx Timestamp.GIZMO_END);

        // This if is here because timestamps need to be written all the time for now
        if selected_scene_node_idx {
          selected_position := Vector4.{ xyz = selected_world_position, w = 1.0 };
          selected_in_camera_space := camera_view * selected_position;
          normalize(*selected_in_camera_space);
          selected_in_camera_space *= 10.0;
          selected_in_camera_space.w = 1.0;

          selected_in_world_space := camera_view_inv * selected_in_camera_space;

          current_instance_buffer := *gizmo_buffers[current_frame_idx];
          instance_buffer         := host_memory(current_instance_buffer);

          // rods
          instance_buffer[0] = Matrix4_Identity;
          instance_buffer[0] = rotate(instance_buffer[0], quat_from_axis_angle(.{ y = 1.0 }, PI / 2.0));
          translate(*instance_buffer[0], selected_in_world_space.xyz + .{ x = 1.0 });

          instance_buffer[1] = Matrix4_Identity;
          instance_buffer[1] = rotate(instance_buffer[1], quat_from_axis_angle(.{ x = 1.0 }, -PI / 2.0));
          translate(*instance_buffer[1], selected_in_world_space.xyz + .{ y = 1.0 });

          instance_buffer[2] = Matrix4_Identity;
          translate(*instance_buffer[2], selected_in_world_space.xyz + .{ z = 1.0 });

          // cones
          instance_buffer[3] = instance_buffer[0];
          translate(*instance_buffer[3], .{ x = 2.0 });
          instance_buffer[4] = instance_buffer[1];
          translate(*instance_buffer[4], .{ y = 2.0 });
          instance_buffer[5] = instance_buffer[2];
          translate(*instance_buffer[5], .{ z = 2.0 });

          if just_pressed(mouse_state, .LMB) {
            selected_gizmo_axis = .NONE;
            closest_point: float32 = 100000.0;
            selected_gizmo_part := -1;
            for instance_buffer {
              t := inverse(it);
              ray: Ray = .{
                          (t * Vector4.{ xyz = camera_position,            w = 1.0 }).xyz,
                normalize((t * Vector4.{ xyz = camera_mouse_ray_direction, w = 0.0 }).xyz),
              };
              mesh := ifx it_index < 3 then default_scene.meshes[gizmo_cylinder_idx] else default_scene.meshes[gizmo_cone_idx];
              s, r := mesh_ray_intersection(mesh, ray);
              if s && r.t < closest_point {
                closest_point = r.t;
                selected_gizmo_part = it_index;
              }
            }
            if selected_gizmo_part != -1 {
              selection_starting_camera_position            = camera_position;
              selection_starting_camera_mouse_ray_direction = camera_mouse_ray_direction;
              if selected_gizmo_part == {
                case 0; #through;
                case 3;
                  selected_gizmo_axis = .X;
                case 1; #through;
                case 4;
                  selected_gizmo_axis = .Y;
                case 2; #through;
                case 5;
                  selected_gizmo_axis = .Z;
              }
            }
          }
          if gizmo_dragging_on {
            t := *default_scene.nodes[selected_scene_node_idx];
            if selected_gizmo_axis == {
              case .NONE;
              case .X;
                old_t := selection_starting_camera_position.z / selection_starting_camera_mouse_ray_direction.z;
                new_t := camera_position.z / camera_mouse_ray_direction.z;

                old := selection_starting_camera_position + selection_starting_camera_mouse_ray_direction * old_t;
                new := camera_position + camera_mouse_ray_direction * new_t;

                v := new - old;

                t.translation.x += gizmo_current_drag_delta;
                gizmo_current_drag_delta = dot(v, .{ x = 1.0 });
                t.translation.x -= gizmo_current_drag_delta;
              case .Y;
                old_t := selection_starting_camera_position.z / selection_starting_camera_mouse_ray_direction.z;
                new_t := camera_position.z / camera_mouse_ray_direction.z;

                old := selection_starting_camera_position + selection_starting_camera_mouse_ray_direction * old_t;
                new := camera_position + camera_mouse_ray_direction * new_t;

                v := new - old;

                t.translation.y += gizmo_current_drag_delta;
                gizmo_current_drag_delta = dot(v, .{ y = 1.0 });
                t.translation.y -= gizmo_current_drag_delta;
              case .Z;
                old_t := selection_starting_camera_position.y / selection_starting_camera_mouse_ray_direction.y;
                new_t := camera_position.y / camera_mouse_ray_direction.y;

                old := selection_starting_camera_position + selection_starting_camera_mouse_ray_direction * old_t;
                new := camera_position + camera_mouse_ray_direction * new_t;

                v := new - old;

                t.translation.z += gizmo_current_drag_delta;
                gizmo_current_drag_delta = dot(v, .{ z = 1.0 });
                t.translation.z -= gizmo_current_drag_delta;
            }
          }

          cmd_bind_pipeline(render_command, gizmo_pipeline, .GRAPHICS);
          {
            info := *gpu_mesh_infos[gizmo_cylinder_idx];
            constant: GizmoPushConstant = .{
              scene_buffer.device_address,
              mesh_buffer.device_address,
              current_instance_buffer .device_address,
              xx info.vertices_buffer_offset,
              0,
            };

            cmd_push_constants(render_command, ui_pipeline, .VERTEX_BIT | .FRAGMENT_BIT, *constant);
            cmd_bind_index_buffer(render_command, mesh_buffer.buffer, info.indices_buffer_offset, .UINT32);
            cmd_draw_indexed(render_command, info.index_count, 3, 0, 0, 0);
          }

          {
            info := *gpu_mesh_infos[gizmo_cone_idx];
            constant: GizmoPushConstant = .{
              scene_buffer.device_address,
              mesh_buffer.device_address,
              current_instance_buffer .device_address,
              xx info.vertices_buffer_offset,
              3,
            };

            cmd_push_constants(render_command, ui_pipeline, .VERTEX_BIT | .FRAGMENT_BIT, *constant);
            cmd_bind_index_buffer(render_command, mesh_buffer.buffer, info.indices_buffer_offset, .UINT32);
            cmd_draw_indexed(render_command, info.index_count, 3, 0, 0, 0);
          }
        }
      }
    }

    cmd_transition_swapchain_image(
      render_command,
      swapchaine_image_index,
      .GENERAL,
      .PRESENT_SRC_KHR,
      VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
      VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
      VK_ACCESS_2_MEMORY_WRITE_BIT,
      VK_ACCESS_2_MEMORY_READ_BIT,
    );

    end_render_command(render_command);
    graphics_queue_submit(render_command, render_command, render_command, swapchaine_image_index);
    need_swapchain_recreation = present_frame_context(swapchaine_image_index);
  }
}

recreate_depth_image :: () {
  pop(*gpu_image_arena, depth_image);
  new_depth_image, ok := push(
    *gpu_image_arena,
    window_width,
    window_height,
    .D32_SFLOAT,
    .DEPTH_STENCIL_ATTACHMENT_BIT,
  );
  assert(ok);
  depth_image = new_depth_image;
  imm_command := *render_commands[FRAMES];
  {
    begin_render_command(imm_command);
    defer end_render_command(imm_command);

    transition_image(
      imm_command,
      depth_image.image,
      depth_image.usage,
      .UNDEFINED,
      .GENERAL,
      VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
      VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT,
      VK_ACCESS_2_NONE,
      VK_ACCESS_2_MEMORY_WRITE_BIT,
    );
  }
  submit_wait_reset(imm_command);
}

draw_aabb :: (cmd: RenderCommand, aabb: AABB, transform: Matrix4) {
  cmd_set_polygon_mode(cmd, .LINE);
  defer cmd_set_polygon_mode(cmd, polygon_mode);

  cube_mesh_info := gpu_mesh_infos[cube_mesh_idx];

  m := transform;
  s, t := aabb_to_scale_and_translation(aabb);
  scale(*m, s);
  // the multiplication expect matrices to be row-major, but we only believe in
  // a column-major matrices in this town, so transpose for a temporary fix
  tt := transform * Vector4.{t.x, t.y, t.z, 0.0};
  translate(*m, tt.xyz);
  constant: MeshPushConstant = .{
    m,
    adjugate(m),
    mesh_buffer.device_address,
    scene_buffer.device_address,
    xx cube_mesh_info.vertices_buffer_offset,
  };
  cmd_push_constants(cmd, mesh_pipeline, .VERTEX_BIT | .FRAGMENT_BIT, *constant);
  cmd_bind_index_buffer(
    cmd,
    mesh_buffer.buffer,
    cube_mesh_info.indices_buffer_offset,
    .UINT32
  );
  cmd_draw_indexed(cmd, cube_mesh_info.index_count, 1, 0, 0, 0);
}

draw_node :: (
  cmd:              RenderCommand,
  scene:            Scene,
  node_idx:         SceneNodeIdx,
  parent_transform: Matrix4,
) {
  node := *scene.nodes[node_idx];
  transform := mat4_from_trs(node.translation, node.rotation, node.scale);
  final_transform := parent_transform * transform;
  if node.mesh_idx {
    info := *gpu_mesh_infos[node.mesh_idx];
    constant: MeshPushConstant = .{
      final_transform,
      adjugate(final_transform),
      mesh_buffer.device_address,
      scene_buffer.device_address,
      xx info.vertices_buffer_offset,
    };
    cmd_push_constants(cmd, mesh_pipeline, .VERTEX_BIT | .FRAGMENT_BIT, *constant);
    cmd_bind_index_buffer(cmd, mesh_buffer.buffer, info.indices_buffer_offset, .UINT32);
    cmd_draw_indexed(cmd, info.index_count, 1, 0, 0, 0);

    if node_idx == selected_scene_node_idx {
      selected_world_position = translation(final_transform);
    }

    if visual_aabb || node_idx == selected_scene_node_idx {
      draw_aabb(cmd, scene.meshes[node.mesh_idx].aabb, final_transform);
    }

    if selection_on {
      t := inverse(final_transform);
      ray: Ray = .{
                  (t * Vector4.{ xyz = camera_position,            w = 1.0 }).xyz,
        normalize((t * Vector4.{ xyz = camera_mouse_ray_direction, w = 0.0 }).xyz),
      };
      s, r := mesh_ray_intersection(scene.meshes[node.mesh_idx], ray);
      if s && r.t < selected_intersection.t {
        log("intersects: % at t: % previous t: %", to_string(node.name), r.t, selected_intersection.t);
        selected_scene_node_idx = node_idx;
        selected_intersection = r;
      }
    }
  }

  if node.first_child_idx {
    draw_node(cmd, scene, node.first_child_idx, final_transform);
  }
  if node.next_sibling {
    draw_node(cmd, scene, node.next_sibling, parent_transform);
  }
}

Pipeline :: struct {
  #as pipeline: VkPipeline;
  #as layout:   VkPipelineLayout;
  dsl:          VkDescriptorSetLayout;
}
create_full_screen_effect_comptue_pipeline :: () -> Pipeline {
  binding_layouts: [1]VkDescriptorSetLayoutBinding = .[
    .{
      binding         = 0,
      descriptorCount = 1,
      descriptorType  = .STORAGE_IMAGE,
      stageFlags      = .COMPUTE_BIT,
    },
  ];
  layout_create_info: VkDescriptorSetLayoutCreateInfo = .{
    flags        = .PUSH_DESCRIPTOR_BIT,
    pBindings    = binding_layouts.data,
    bindingCount = xx binding_layouts.count,
  };
  dsl := create_descriptor_set_layout(layout_create_info);

  compute_push_constants: VkPushConstantRange = .{
    stageFlags = .COMPUTE_BIT,
    offset     = 0,
    size       = size_of(float),
  };
  compute_layout_create_info: VkPipelineLayoutCreateInfo = .{
    pSetLayouts            = *dsl,
    setLayoutCount         = 1,
    pPushConstantRanges    = *compute_push_constants,
    pushConstantRangeCount = 1,
  };
  layout := create_pipeline_layout(compute_layout_create_info);

  shader_path := "shaders_compiled/gradient_comp.spv";
  shader_spirv, ok := platform_read_entire_file(shader_path,, temp);
  assert(ok, "Cannot load shader: %\n", shader_path);

  shader_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx shader_spirv.data,
    codeSize = xx shader_spirv.count,
  };
  shader_stage_create_info: VkPipelineShaderStageCreateInfo = .{
    pNext = *shader_module_create_info,
    stage = .COMPUTE_BIT,
    pName = "main",
  };
  compute_pipeline_create_info: VkComputePipelineCreateInfo = .{
    layout = layout,
    stage  = shader_stage_create_info,
  };
  pipeline := create_compute_pipeline(compute_pipeline_create_info);
  return .{
    pipeline = pipeline,
    layout = layout,
    dsl = dsl,
  };
}

UiPushConstant :: struct {
  quads:         VkDeviceAddress;
  screen_size:   Vector2;
  data_buffer:  VkDeviceAddress;
  curves_offset: u32;
  bands_offset:  u32;
} @ShaderType
create_ui_pipeline :: () -> Pipeline {
  layout_create_info: VkDescriptorSetLayoutCreateInfo = .{
    flags        = .PUSH_DESCRIPTOR_BIT,
  };
  dsl := create_descriptor_set_layout(layout_create_info);

  push_constants: VkPushConstantRange = .{
    stageFlags = .VERTEX_BIT | .FRAGMENT_BIT,
    offset     = 0,
    size       = size_of(UiPushConstant),
  };
  pipeline_layout_create_info: VkPipelineLayoutCreateInfo = .{
    pSetLayouts            = *dsl,
    setLayoutCount         = 1,
    pPushConstantRanges    = *push_constants,
    pushConstantRangeCount = 1,
  };
  layout := create_pipeline_layout(pipeline_layout_create_info);

  vert_code := platform_read_entire_file("shaders_compiled/ui_vert.spv",, temp);
  vert_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx vert_code.data,
    codeSize = xx vert_code.count,
  };
  frag_code := platform_read_entire_file("shaders_compiled/ui_frag.spv",, temp);
  frag_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx frag_code.data,
    codeSize = xx frag_code.count,
  };
  stages: []VkPipelineShaderStageCreateInfo = .[
    .{ pNext = *vert_module_create_info, stage = .VERTEX_BIT,   pName = "main" },
    .{ pNext = *frag_module_create_info, stage = .FRAGMENT_BIT, pName = "main" },
  ];

  input_assembly: VkPipelineInputAssemblyStateCreateInfo = .{ topology = .TRIANGLE_LIST };
  rasterization: VkPipelineRasterizationStateCreateInfo = .{
    polygonMode = .FILL,
    frontFace   = .COUNTER_CLOCKWISE,
    lineWidth   = 1.0,
  };
  multisampling: VkPipelineMultisampleStateCreateInfo = .{ rasterizationSamples = ._1_BIT };
  color_attachment_format: VkFormat = .B8G8R8A8_UNORM;
  rendering: VkPipelineRenderingCreateInfo = .{
    pColorAttachmentFormats = *color_attachment_format,
    colorAttachmentCount    = 1,
    depthAttachmentFormat   = .UNDEFINED,
    stencilAttachmentFormat = .UNDEFINED,
  };
  color_blend_attachment: VkPipelineColorBlendAttachmentState = .{
    blendEnable         = xx true,
    srcColorBlendFactor = .SRC_ALPHA,
    dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
    colorBlendOp        = .ADD,
    srcAlphaBlendFactor = .ONE,
    dstAlphaBlendFactor = .ZERO,
    alphaBlendOp        = .ADD,
    colorWriteMask      = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
  };

  viewport: VkPipelineViewportStateCreateInfo = .{ viewportCount = 1, scissorCount = 1 };

  color_blending: VkPipelineColorBlendStateCreateInfo = .{
    logicOpEnable   = xx false,
    logicOp         = .COPY,
    attachmentCount = 1,
    pAttachments    = *color_blend_attachment,
  };

  vertex_input: VkPipelineVertexInputStateCreateInfo;

  dynamic_states: []VkDynamicState = .[ .VIEWPORT, .SCISSOR ];
  dynamic_state_info: VkPipelineDynamicStateCreateInfo = .{
    pDynamicStates    = dynamic_states.data,
    dynamicStateCount = xx dynamic_states.count,
  };

  create_info: VkGraphicsPipelineCreateInfo = .{
    pNext               = *rendering,
    stageCount          = xx stages.count,
    pStages             = stages.data,
    pVertexInputState   = *vertex_input,
    pInputAssemblyState = *input_assembly,
    pViewportState      = *viewport,
    pRasterizationState = *rasterization,
    pMultisampleState   = *multisampling,
    pColorBlendState    = *color_blending,
    pDynamicState       = *dynamic_state_info,
    layout              = layout,
  };
  pipeline := create_graphics_pipeline(create_info);

  return .{
    pipeline = pipeline,
    layout = layout,
    dsl = dsl,
  };
}

GridPushConstant :: struct {
  scene_buffer:    VkDeviceAddress;
} @ShaderType
create_grid_pipeline :: () -> Pipeline {
  push_constants: VkPushConstantRange = .{
    stageFlags = .VERTEX_BIT | .FRAGMENT_BIT,
    offset     = 0,
    size       = size_of(GridPushConstant),
  };
  pipeline_layout_create_info: VkPipelineLayoutCreateInfo = .{
    pPushConstantRanges    = *push_constants,
    pushConstantRangeCount = 1,
  };
  layout := create_pipeline_layout(pipeline_layout_create_info);

  vert_code := platform_read_entire_file("shaders_compiled/grid_vert.spv",, temp);
  vert_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx vert_code.data,
    codeSize = xx vert_code.count,
  };
  frag_code := platform_read_entire_file("shaders_compiled/grid_frag.spv",, temp);
  frag_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx frag_code.data,
    codeSize = xx frag_code.count,
  };
  stages: []VkPipelineShaderStageCreateInfo = .[
    .{ pNext = *vert_module_create_info, stage = .VERTEX_BIT,   pName = "main" },
    .{ pNext = *frag_module_create_info, stage = .FRAGMENT_BIT, pName = "main" },
  ];

  input_assembly: VkPipelineInputAssemblyStateCreateInfo = .{ topology = .TRIANGLE_LIST };
  rasterization: VkPipelineRasterizationStateCreateInfo = .{
    polygonMode = .FILL,
    frontFace   = .COUNTER_CLOCKWISE,
    lineWidth   = 1.0,
  };
  multisampling: VkPipelineMultisampleStateCreateInfo = .{ rasterizationSamples = ._1_BIT };
  color_attachment_format: VkFormat = .B8G8R8A8_UNORM;
  rendering: VkPipelineRenderingCreateInfo = .{
    pColorAttachmentFormats = *color_attachment_format,
    colorAttachmentCount    = 1,
    depthAttachmentFormat   = .D32_SFLOAT,
    stencilAttachmentFormat = .UNDEFINED,
  };
  color_blend_attachment: VkPipelineColorBlendAttachmentState = .{
    blendEnable         = xx true,
    srcColorBlendFactor = .SRC_ALPHA,
    dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
    colorBlendOp        = .ADD,
    srcAlphaBlendFactor = .ONE,
    dstAlphaBlendFactor = .ZERO,
    alphaBlendOp        = .ADD,
    colorWriteMask      = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
  };

  viewport: VkPipelineViewportStateCreateInfo = .{ viewportCount = 1, scissorCount = 1 };

  depth_stencil_state: VkPipelineDepthStencilStateCreateInfo = .{
    depthTestEnable       = xx true,
    depthWriteEnable      = xx true,
    depthCompareOp        = .GREATER,
    depthBoundsTestEnable = xx false,
    minDepthBounds        = 0,
    maxDepthBounds        = 1.0,
  };

  color_blending: VkPipelineColorBlendStateCreateInfo = .{
    logicOpEnable   = xx false,
    logicOp         = .COPY,
    attachmentCount = 1,
    pAttachments    = *color_blend_attachment,
  };

  vertex_input: VkPipelineVertexInputStateCreateInfo;

  dynamic_states: []VkDynamicState = .[ .VIEWPORT, .SCISSOR ];
  dynamic_state_info: VkPipelineDynamicStateCreateInfo = .{
    pDynamicStates    = dynamic_states.data,
    dynamicStateCount = xx dynamic_states.count,
  };

  create_info: VkGraphicsPipelineCreateInfo = .{
    pNext               = *rendering,
    stageCount          = xx stages.count,
    pStages             = stages.data,
    pVertexInputState   = *vertex_input,
    pInputAssemblyState = *input_assembly,
    pViewportState      = *viewport,
    pRasterizationState = *rasterization,
    pMultisampleState   = *multisampling,
    pDepthStencilState  = *depth_stencil_state,
    pColorBlendState    = *color_blending,
    pDynamicState       = *dynamic_state_info,
    layout              = layout,
  };
  pipeline := create_graphics_pipeline(create_info);

  return .{
    pipeline = pipeline,
    layout = layout,
  };
}

MeshPushConstant :: struct {
  transform:       Matrix4;
  transform_inv:   Matrix4;
  mesh_buffer:     VkDeviceAddress;
  scene_buffer:    VkDeviceAddress;
  vertices_offset: u32;
} @ShaderType
create_mesh_pipeline :: () -> Pipeline {
  push_constants: VkPushConstantRange = .{
    stageFlags = .VERTEX_BIT | .FRAGMENT_BIT,
    offset     = 0,
    size       = size_of(MeshPushConstant),
  };
  pipeline_layout_create_info: VkPipelineLayoutCreateInfo = .{
    pPushConstantRanges    = *push_constants,
    pushConstantRangeCount = 1,
  };
  layout := create_pipeline_layout(pipeline_layout_create_info);

  vert_code := platform_read_entire_file("shaders_compiled/mesh_vert.spv",, temp);
  vert_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx vert_code.data,
    codeSize = xx vert_code.count,
  };
  frag_code := platform_read_entire_file("shaders_compiled/mesh_frag.spv",, temp);
  frag_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx frag_code.data,
    codeSize = xx frag_code.count,
  };
  stages: []VkPipelineShaderStageCreateInfo = .[
    .{ pNext = *vert_module_create_info, stage = .VERTEX_BIT,   pName = "main" },
    .{ pNext = *frag_module_create_info, stage = .FRAGMENT_BIT, pName = "main" },
  ];

  input_assembly: VkPipelineInputAssemblyStateCreateInfo = .{ topology = .TRIANGLE_LIST };
  rasterization: VkPipelineRasterizationStateCreateInfo = .{
    polygonMode = .FILL,
    // cullMode    = .BACK_BIT,
    frontFace   = .COUNTER_CLOCKWISE,
    lineWidth   = 1.0,
  };
  multisampling: VkPipelineMultisampleStateCreateInfo = .{ rasterizationSamples = ._1_BIT };
  color_attachment_format: VkFormat = .B8G8R8A8_UNORM;
  rendering: VkPipelineRenderingCreateInfo = .{
    pColorAttachmentFormats = *color_attachment_format,
    colorAttachmentCount    = 1,
    depthAttachmentFormat   = .D32_SFLOAT,
    stencilAttachmentFormat = .UNDEFINED,
  };
  color_blend_attachment: VkPipelineColorBlendAttachmentState = .{
    blendEnable         = xx true,
    srcColorBlendFactor = .SRC_ALPHA,
    dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
    colorBlendOp        = .ADD,
    srcAlphaBlendFactor = .ONE,
    dstAlphaBlendFactor = .ZERO,
    alphaBlendOp        = .ADD,
    colorWriteMask      = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
  };

  viewport: VkPipelineViewportStateCreateInfo = .{ viewportCount = 1, scissorCount = 1 };

  depth_stencil_state: VkPipelineDepthStencilStateCreateInfo = .{
    depthTestEnable       = xx true,
    depthWriteEnable      = xx true,
    depthCompareOp        = .GREATER,
    depthBoundsTestEnable = xx false,
    minDepthBounds        = 0,
    maxDepthBounds        = 1.0,
  };

  color_blending: VkPipelineColorBlendStateCreateInfo = .{
    logicOpEnable   = xx false,
    logicOp         = .COPY,
    attachmentCount = 1,
    pAttachments    = *color_blend_attachment,
  };

  vertex_input: VkPipelineVertexInputStateCreateInfo;

  dynamic_states: []VkDynamicState = .[ .VIEWPORT, .SCISSOR, .POLYGON_MODE_EXT ];
  dynamic_state_info: VkPipelineDynamicStateCreateInfo = .{
    pDynamicStates    = dynamic_states.data,
    dynamicStateCount = xx dynamic_states.count,
  };

  create_info: VkGraphicsPipelineCreateInfo = .{
    pNext               = *rendering,
    stageCount          = xx stages.count,
    pStages             = stages.data,
    pVertexInputState   = *vertex_input,
    pInputAssemblyState = *input_assembly,
    pViewportState      = *viewport,
    pRasterizationState = *rasterization,
    pMultisampleState   = *multisampling,
    pDepthStencilState  = *depth_stencil_state,
    pColorBlendState    = *color_blending,
    pDynamicState       = *dynamic_state_info,
    layout              = layout,
  };
  pipeline := create_graphics_pipeline(create_info);

  return .{
    pipeline = pipeline,
    layout = layout,
  };
}

GizmoPushConstant :: struct {
  scene_buffer:           VkDeviceAddress;
  mesh_buffer:            VkDeviceAddress;
  instance_buffer:        VkDeviceAddress;
  vertices_offset:        u32;
  instance_buffer_offset: u32;
} @ShaderType
// This one is essentially same as mesh pipeline with only a change to the
// push constant and shaders
create_gizmo_pipeline :: () -> Pipeline {
  push_constants: VkPushConstantRange = .{
    stageFlags = .VERTEX_BIT | .FRAGMENT_BIT,
    offset     = 0,
    size       = size_of(GizmoPushConstant),
  };
  pipeline_layout_create_info: VkPipelineLayoutCreateInfo = .{
    pPushConstantRanges    = *push_constants,
    pushConstantRangeCount = 1,
  };
  layout := create_pipeline_layout(pipeline_layout_create_info);

  vert_code, ok := platform_read_entire_file("shaders_compiled/gizmo_vert.spv",, temp);
  assert(ok);
  vert_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx vert_code.data,
    codeSize = xx vert_code.count,
  };
  frag_code: , ok = platform_read_entire_file("shaders_compiled/gizmo_frag.spv",, temp);
  assert(ok);
  frag_module_create_info: VkShaderModuleCreateInfo = .{
    pCode    = xx frag_code.data,
    codeSize = xx frag_code.count,
  };
  stages: []VkPipelineShaderStageCreateInfo = .[
    .{ pNext = *vert_module_create_info, stage = .VERTEX_BIT,   pName = "main" },
    .{ pNext = *frag_module_create_info, stage = .FRAGMENT_BIT, pName = "main" },
  ];

  input_assembly: VkPipelineInputAssemblyStateCreateInfo = .{ topology = .TRIANGLE_LIST };
  rasterization: VkPipelineRasterizationStateCreateInfo = .{
    polygonMode = .FILL,
    // cullMode    = .BACK_BIT,
    frontFace   = .COUNTER_CLOCKWISE,
    lineWidth   = 1.0,
  };
  multisampling: VkPipelineMultisampleStateCreateInfo = .{ rasterizationSamples = ._1_BIT };
  color_attachment_format: VkFormat = .B8G8R8A8_UNORM;
  rendering: VkPipelineRenderingCreateInfo = .{
    pColorAttachmentFormats = *color_attachment_format,
    colorAttachmentCount    = 1,
    depthAttachmentFormat   = .D32_SFLOAT,
    stencilAttachmentFormat = .UNDEFINED,
  };
  color_blend_attachment: VkPipelineColorBlendAttachmentState = .{
    blendEnable         = xx true,
    srcColorBlendFactor = .SRC_ALPHA,
    dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
    colorBlendOp        = .ADD,
    srcAlphaBlendFactor = .ONE,
    dstAlphaBlendFactor = .ZERO,
    alphaBlendOp        = .ADD,
    colorWriteMask      = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
  };

  viewport: VkPipelineViewportStateCreateInfo = .{ viewportCount = 1, scissorCount = 1 };

  depth_stencil_state: VkPipelineDepthStencilStateCreateInfo = .{
    depthTestEnable       = xx true,
    depthWriteEnable      = xx true,
    depthCompareOp        = .GREATER,
    depthBoundsTestEnable = xx false,
    minDepthBounds        = 0,
    maxDepthBounds        = 1.0,
  };

  color_blending: VkPipelineColorBlendStateCreateInfo = .{
    logicOpEnable   = xx false,
    logicOp         = .COPY,
    attachmentCount = 1,
    pAttachments    = *color_blend_attachment,
  };

  vertex_input: VkPipelineVertexInputStateCreateInfo;

  dynamic_states: []VkDynamicState = .[ .VIEWPORT, .SCISSOR ];
  dynamic_state_info: VkPipelineDynamicStateCreateInfo = .{
    pDynamicStates    = dynamic_states.data,
    dynamicStateCount = xx dynamic_states.count,
  };

  create_info: VkGraphicsPipelineCreateInfo = .{
    pNext               = *rendering,
    stageCount          = xx stages.count,
    pStages             = stages.data,
    pVertexInputState   = *vertex_input,
    pInputAssemblyState = *input_assembly,
    pViewportState      = *viewport,
    pRasterizationState = *rasterization,
    pMultisampleState   = *multisampling,
    pDepthStencilState  = *depth_stencil_state,
    pColorBlendState    = *color_blending,
    pDynamicState       = *dynamic_state_info,
    layout              = layout,
  };
  pipeline := create_graphics_pipeline(create_info);

  return .{
    pipeline = pipeline,
    layout = layout,
  };
}

destroy_pipeline :: (pipeline: Pipeline) {
  if pipeline.dsl destroy_descriptor_set_layout(pipeline.dsl);
  if pipeline.layout destroy_pipeline_layout(pipeline.layout);
  if pipeline.pipeline destroy_pipeline(pipeline.pipeline);
}

rebuild_pipelines_if_needed :: () {
  rebuild_gradient_shader := false;
  rebuild_ui_shader := false;
  rebuild_mesh_shader := false;
  rebuild_grid_shader := false;
  while changed_file := has_event(*file_watcher) {
    log("Found changed file: %", changed_file);
    if changed_file == {
      case "shaders/gradient_comp.glsl";
        rebuild_gradient_shader = true;
      case "shaders/ui_frag.glsl"; #through;
      case "shaders/ui_vert.glsl";
        rebuild_ui_shader = true;
      case "shaders/mesh_frag.glsl"; #through;
      case "shaders/mesh_vert.glsl";
        rebuild_mesh_shader = true;
      case "shaders/grid_frag.glsl"; #through;
      case "shaders/grid_vert.glsl";
        rebuild_grid_shader = true;
    }
  }
  if rebuild_gradient_shader {
    log("Rebuiding GRADIENT pipeline");
    if compile_shader("shaders/gradient_comp.glsl") {
      device_wait_idle();
      destroy_pipeline(compute_pipeline);
      compute_pipeline = create_full_screen_effect_comptue_pipeline();
    } else log_error("Failed to rebuild GRADIENT pipeline");
  }
  if rebuild_ui_shader {
    log("Rebuiding UI pipeline");
    if compile_shader("shaders/ui_frag.glsl") && compile_shader("shaders/ui_vert.glsl") {
      device_wait_idle();
      destroy_pipeline(ui_pipeline);
      ui_pipeline = create_ui_pipeline();
    } else log_error("Failed to rebuild UI pipeline");
  }
  if rebuild_mesh_shader {
    log("Rebuiding MESH pipeline");
    if compile_shader("shaders/mesh_frag.glsl") && compile_shader("shaders/mesh_vert.glsl") {
      device_wait_idle();
      destroy_pipeline(mesh_pipeline);
      mesh_pipeline = create_mesh_pipeline();
    } else log_error("Failed to rebuild MESH pipeline");
  }
  if rebuild_grid_shader {
    log("Rebuiding GRID pipeline");
    if compile_shader("shaders/grid_frag.glsl") && compile_shader("shaders/grid_vert.glsl") {
      device_wait_idle();
      destroy_pipeline(grid_pipeline);
      grid_pipeline = create_grid_pipeline();
    } else log_error("Failed to rebuild GRID pipeline");
  }
}

RenderCommand :: struct {
  #as cmd:             VkCommandBuffer;
  #as swapchain_semaphore: VkSemaphore;
  #as render_fence:        VkFence;
};
create_render_command :: () -> RenderCommand {
  allocate_info : VkCommandBufferAllocateInfo = .{
    commandPool = graphics_command_pool,
    level = .PRIMARY,
    commandBufferCount = 1,
  };
  cmd := allocate_command_buffer(allocate_info);

  fence_create_info: VkFenceCreateInfo = .{ flags = .SIGNALED_BIT };
  render_fence := create_fence(fence_create_info);

  swapchain_semaphore := create_semaphore(.{});

  return .{
    cmd = cmd,
    swapchain_semaphore = swapchain_semaphore,
    render_fence = render_fence,
  };
}

reset_render_command :: (cmd: RenderCommand) {
  reset_command_buffer(cmd);
}

begin_render_command :: (cmd: RenderCommand) {
  begin_info: VkCommandBufferBeginInfo = .{ flags = .ONE_TIME_SUBMIT_BIT };
  begin_command_buffer(cmd, begin_info);
}

end_render_command :: (cmd: RenderCommand) {
  end_command_buffer(cmd);
}

submit_wait_reset :: (cmd: RenderCommand) {
  buffer_submit_info: VkCommandBufferSubmitInfo =.{ commandBuffer = cmd };
  submit_info: VkSubmitInfo2 = .{ commandBufferInfoCount = 1, pCommandBufferInfos = *buffer_submit_info };

  reset_fences(.[cmd]);
  queue_submit(submit_info, cmd);
  wait_for_fence(cmd);
  reset_command_buffer(cmd);
}

wait_for_cmd :: (cmd: RenderCommand) {
  wait_for_fence(cmd.render_fence);
  reset_fences(.[cmd.render_fence]);
}

cmd_transition_swapchain_image :: (
    cmd:         RenderCommand,
    image_index: u32,
    src_layout:  VkImageLayout,
    dst_layout:  VkImageLayout,
    src_stage:   VkPipelineStageFlags2,
    dst_stage:   VkPipelineStageFlags2,
    src_access:  VkAccessFlags2,
    dst_access:  VkAccessFlags2,
) {
  transition_image(
    cmd.cmd,
    swapchain_images[image_index],
    0,
    src_layout,
    dst_layout,
    src_stage,
    dst_stage,
    src_access,
    dst_access,
  );
}

SceneInfo :: struct {
  camera_view:       Matrix4;
  camera_view_inv:   Matrix4;
  camera_projection: Matrix4;
} @ShaderType

GpuMeshInfo :: struct {
  vertices_buffer_offset: u64;
  indices_buffer_offset:  u32;
  index_count:            u32;
  vertex_count:           u32;
}

prof_selected_bound := -1;
prof_drawn_nodes := 0;
prof_draw :: (ui: *Context) {
  #if !context.Prof_Module.PROF_ZONES_COUNT return;

  size:     Vector2 = .{ 1000, 600 };
  position: Vector2 = .{ (window_width - size.x) / 2.0, (window_height - size.y) / 2.0 };
  padding := 10.0;
  panel_start(ui, "Prof", size, position);
  defer panel_end(ui);

  box_width  := (size.x - padding * 2.0 - cast(float32)FRAMES_TO_CAPTURE * 2.0) /
                cast(float32)FRAMES_TO_CAPTURE;
  box_height := 100.0;
  current_frame_bound := context.prof_current_frame;

  if just_pressed(mouse_state, .LMB) then prof_selected_bound = -1;

  // The nodes buffer might be too small to hold all frames. Only last PROF_TREE_NODES of frames are valid
  diff_sum: u32 = 0;
  for 0..FRAMES_TO_CAPTURE - 1 {
    end := context.prof_tree.frame_bound[current_frame_bound];
    prev_frame_start_bound_idx := ifx current_frame_bound then current_frame_bound - 1
                                  else cast(u32)context.prof_tree.frame_bound.count - 1;
    defer current_frame_bound = prev_frame_start_bound_idx;

    start := context.prof_tree.frame_bound[prev_frame_start_bound_idx];
    diff := (end - start) & (PROF_TREE_NODES - 1);
    diff_sum += diff;
    p: Vector2 = .{ x = padding + (box_width + 2.0) * current_frame_bound, y = padding };
    s: Vector2 = .{ box_width, box_height };
    color: ColorType = .BACKGROUND2;
    if diff_sum < PROF_TREE_NODES                        then color = .BLUE;
    if current_frame_bound == prof_selected_bound        then color = .RED;
    if current_frame_bound == context.prof_current_frame then color = .GREEN;
    pressed, hovered := button(
      ui,
      tprint("prof_frame_%", current_frame_bound),
      .FIXED_POSITION_X | .FIXED_POSITION_Y | .FIXED_SIZE_X | .FIXED_SIZE_Y | .DRAW_BACKGROUND,
      p,
      s,
      Colors[color],
    );
    if pressed then prof_selected_bound = current_frame_bound;
    if hovered then label(
      ui,
      tprint("%", current_frame_bound),
      .DRAW_TEXT | .DRAW_CENTERED | .FIXED_POSITION_X | .FIXED_POSITION_Y,
      p + .{ box_width / 2.0, box_height + 5.0 },
      .{},
    );
  }

  frame_start_bound_idx := ifx prof_selected_bound == -1 then context.prof_current_frame
                           else prof_selected_bound;
  frame_start_node_idx := context.prof_tree.frame_bound[frame_start_bound_idx];

  // start from the first child to walk the top level functions following `next` chain
  first_child := context.prof_tree.nodes[frame_start_node_idx].first_child;

  top_level_ns: u64 = 0;
  current_node_idx := first_child;
  while current_node_idx {
    current := *context.prof_tree.nodes[current_node_idx];
    top_level_ns += current.dt;
    current_node_idx = current.next;
  }
  ns_to_px := (size.x - padding * 2.0) / cast(float32)top_level_ns;

  draw_node :: (
    ui: *Context,
    current_node_idx: u32,
    ns_to_px: float32,
    position: Vector2,
    depth: u32
  ) {
    prof_drawn_nodes += 1;
    if 200 < depth return;

    current := *context.prof_tree.nodes[current_node_idx];
    current_width := cast(float32)current.dt * ns_to_px;
    if 2.0 < current_width {
      bg := rgba(255, 180 + cast(u8)position.x, 180 + cast(u8)position.y * 2, 255);
      size: Vector2 = .{ current_width, 10.0 };
      _, hovered := button(
        ui,
        tprint("%_%", context.Prof_Module.PROF_ZONES_INFOS[current.zone_index].name, prof_drawn_nodes),
        .FIXED_POSITION_X | .FIXED_POSITION_Y | .FIXED_SIZE_X | .FIXED_SIZE_Y | .DRAW_BACKGROUND,
        position,
        size,
        bg,
      );
      if hovered then label(
        ui,
        context.Prof_Module.PROF_ZONES_INFOS[current.zone_index].name,
        .DRAW_TEXT | .DRAW_CENTERED | .FIXED_POSITION_X | .FIXED_POSITION_Y,
        position + .{ x = size.x / 2.0, y = -15.0 },
        .{},
      );

      if current.first_child {
        new_position := position + .{ y = 20.0 };
        draw_node(ui, current.first_child, ns_to_px, new_position, depth + 1);
      }
    }
    if current.next {
      new_position := position + .{ x = current_width };
      draw_node(ui, current.next, ns_to_px, new_position, depth + 1);
    }
  }
  prof_drawn_nodes = 0;
  draw_node(ui, first_child, ns_to_px, .{ padding, padding + 300.0 }, 0);
}

#load "ui.jai";
#load "math.jai";
#load "font.jai";
#load "utils.jai";
#load "scene.jai";
#load "vulkan.jai";
#load "shaders.jai";
#load "platform.jai";
#load "file_watch.jai";
#load "allocators.jai";
#load "enum_array.jai";
#load "fixed_array.jai";
#load "fixed_slice.jai";
#load "static_bitset.jai";


#import "Json";
#import "cgltf";
#import "cslug";
#import "Vulkan";
#import "Profiler";

#import "File";
#import "Linux";
#import "POSIX";
#import "Basic";
#import "String";
#import "Process";
#import "Flat_Pool";
