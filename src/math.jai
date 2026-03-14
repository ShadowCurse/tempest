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
    _21 = 0.0,        _22 = -g,   _23 = 0.0,      _24 = 0.0,
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

using,except(translate) #import "Math";
