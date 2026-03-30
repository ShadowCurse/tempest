// The world space is right handed Z up
//   ^ z
//   |
//   |---> y
// /
// x
//
// The camera space is right handed Z into the screen (same as default Vulkan NDC)
//      z
//    /
//   |---> x
//   |
//   y
//
// Default camera orientation is looking down the -Z

look_at :: (position: Vector3, target: Vector3, up: Vector3) -> Matrix4 {
  forward := normalize(target - position);
  right   := normalize(cross(forward, up));
  new_up  := cross(right, forward);

  return .{
    _11 = right.x,   _12 = right.y,   _13 = right.z,   _14 = 0.0,
    _21 = new_up.x,  _22 = new_up.y,  _23 = new_up.z,  _24 = 0.0,
    _31 = forward.x, _32 = forward.y, _33 = forward.z, _34 = 0.0,
    _41 = 0.0,       _42 = 0.0,       _43 = 0.0,       _44 = 1.0,
  };
}

translate :: (m: *Matrix4, position: Vector3) {
  m._41 = position.x;
  m._42 = position.y;
  m._43 = position.z;
}

perspective :: (fovy: float, aspect: float, near: float, far: float) -> Matrix4 {
  g := 1.0 / tan(fovy / 2.0);
  k := near / (near - far);
  return .{
    _11 = g / aspect, _12 = 0.0, _13 = 0.0,      _14 = 0.0,
    _21 = 0.0,        _22 = g,   _23 = 0.0,      _24 = 0.0,
    _31 = 0.0,        _32 = 0.0, _33 = k,        _34 = 1.0,
    _41 = 0.0,        _42 = 0.0, _43 = -far * k, _44 = 0.0,
  };
}

quat_from_axis_angle :: (axis: Vector3, angle: float) -> Quaternion {
  s := sin(angle / 2.0);
  c := cos(angle / 2.0);
  return .{
    x = axis.x * s,
    y = axis.y * s,
    z = axis.z * s,
    w = c,
  };
}

quat_from_rotation_axis :: (x_axis: Vector3, y_axis: Vector3, z_axis: Vector3) -> Quaternion {
  m00 := x_axis.x;
  m01 := x_axis.y;
  m02 := x_axis.z;

  m10 := y_axis.x;
  m11 := y_axis.y;
  m12 := y_axis.z;

  m20 := z_axis.x;
  m21 := z_axis.y;
  m22 := z_axis.z;

  if m22 <= 0.0 {
    d := m11 - m00;
    n := 1.0 - m22;
    if d <= 0.0 {
      f   := n - d;
      inv := 0.5 / sqrt(f);
      return .{
        x = f * inv,
        y = (m01 + m10) * inv,
        z = (m02 + m20) * inv,
        w = (m12 - m21) * inv,
      };
    } else {
      f   := n + d;
      inv := 0.5 / sqrt(f);
      return .{
        x = (m01 + m10) * inv,
        y = f * inv,
        z = (m12 + m21) * inv,
        w = (m20 - m02) * inv,
      };
    }
  } else {
    d := m11 + m00;
    n := 1.0 + m22;
    if d <= 0.0 {
      f   := n - d;
      inv := 0.5 / sqrt(f);
      return .{
        x = (m02 + m20) * inv,
        y = (m12 + m21) * inv,
        z = f * inv,
        w = (m01 - m10) * inv,
      };
    } else {
      f   := n + d;
      inv := 0.5 / sqrt(f);
      return .{
        z = (m12 - m21) * inv,
        w = (m20 - m02) * inv,
        x = (m01 - m10) * inv,
        y = f * inv,
      };
    }
  }
}

quat_to_mat4 :: (quat: Quaternion) -> Matrix4 {
  x2 := quat.x * quat.x;
  y2 := quat.y * quat.y;
  z2 := quat.z * quat.z;
  xy := quat.x * quat.y;
  xz := quat.x * quat.z;
  yz := quat.y * quat.z;
  wx := quat.w * quat.x;
  wy := quat.w * quat.y;
  wz := quat.w * quat.z;
  return .{
    _11 = 1.0 - 2.0 * (y2 + z2), _12 = 2.0 * (xy + wz),       _13 = 2.0 * (xz - wy),       _14 = 0.0,
    _21 = 2.0 * (xy - wz),       _22 = 1.0 - 2.0 * (x2 + z2), _23 = 2.0 * (yz + wx),       _24 = 0.0,
    _31 = 2.0 * (xz + wy),       _32 = 2.0 * (yz - wx),       _33 = 1.0 - 2.0 * (x2 + y2), _34 = 0.0,
    _41 = 0.0,                   _42 = 0.0,                   _43 = 0.0,                   _44 = 1.0,
  };
}

rgb_to_vector3 :: (hex: u32) -> Vector3 {
  return .{
    cast(float)(hex >> 16 & 0xff) / 255.0,
    cast(float)(hex >> 8  & 0xff) / 255.0,
    cast(float)(hex >> 0  & 0xff) / 255.0,
  };
}

using,except(translate) #import "Math";
