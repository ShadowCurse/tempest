TAU   :: cast(float32) 6.283185;
TAU64 :: 6.28318530717958648;

PI    :: cast(float32) 3.1415927;
PI64  :: 3.141592653589793;

FLOAT16_MAX : float :   65504.0;

FLOAT32_MIN        :: 0h00800000;
FLOAT32_MAX        :: 0h7F7FFFFF;
FLOAT32_INFINITY   :: 0h7F800000;
FLOAT32_NAN        :: 0h7FBFFFFF;

FLOAT64_MIN        :: 0h00100000_00000000;
FLOAT64_MAX        :: 0h7FEFFFFF_FFFFFFFF;
FLOAT64_INFINITY   :: 0h7FF00000_00000000;
FLOAT64_NAN        :: 0h7FF7FFFF_FFFFFFFF;

S8_MIN  :s8:    -128;
S8_MAX  :s8:    127;
U8_MAX  :u8:    255;
S16_MIN :s16:   -32768;
S16_MAX :s16:   32767;
U16_MAX :u16:   0xffff;
S32_MIN :s32:   0x8000_0000;
S32_MAX :s32:   0x7fff_ffff;
U32_MAX :u32:   0xffff_ffff;
S64_MIN :s64:   0x8000_0000_0000_0000;
S64_MAX :s64:   0x7fff_ffff_ffff_ffff;
U64_MAX :u64:   0xffff_ffff_ffff_ffff;

clamp :: inline (pointer: *$T, low: T, high: T) {
  if pointer.* < low  then pointer.* = low;
  if pointer.* > high then pointer.* = high;
} @NoProfile

abs :: inline (x: $T/.[s64, s32, s16, s8]) -> T {
  result := ifx x < 0 then -x else x;
  return result;
} @NoProfile

abs :: inline (x: float32) -> float32 {
  union {
    _float32: float32;
    _u32:     u32;
  }

  _float32 = x;
  _u32 &= 0x7fff_ffff;
  return _float32;
} @NoProfile

Vector2 :: struct {
  x, y: float32;
  #overlay (x) component: [2] float;
}

operator + :: (a: Vector2, b: Vector2) -> Vector2 {
  return .{a.x + b.x, a.y + b.y};
} @NoProfile

operator - :: (a: Vector2, b: Vector2) -> Vector2 {
  return .{a.x - b.x, a.y - b.y};
} @NoProfile

operator - :: (a: Vector2) -> Vector2 {
  return .{-a.x, -a.y};
} @NoProfile

operator * :: (a: Vector2, k: float32) -> Vector2 #symmetric {
  return .{a.x * k, a.y * k};
} @NoProfile

operator * :: (a: Vector2, b: Vector2) -> Vector2 #symmetric {
  return .{a.x * a.x, a.y * a.y};
} @NoProfile

operator / :: (a: Vector2, b: Vector2) -> Vector2 {
  return .{a.x / b.x, a.y / b.y};
} @NoProfile

operator / :: (a: Vector2, k: float32) -> Vector2 {
  denom := 1 / k;
  return .{a.x * denom, a.y * denom};
} @NoProfile

Vector3 :: struct {
  x, y, z: float32;
  #overlay (x) xy: Vector2;
  #overlay (y) yz: Vector2;
  #overlay (x) component: [3] float;
}

operator + :: (a: Vector3, b: Vector3) -> Vector3 {
  return .{a.x + b.x, a.y + b.y, a.z + b.z};
} @NoProfile

operator - :: (a: Vector3, b: Vector3) -> Vector3 {
  return .{a.x - b.x, a.y - b.y, a.z - b.z};
} @NoProfile

operator - :: (a: Vector3) -> Vector3 {
  return .{-a.x, -a.y, -a.z};
} @NoProfile

operator * :: (a: Vector3, k: float32) -> Vector3 #symmetric {
  return .{a.x * k, a.y * k, a.z * k};
} @NoProfile

operator * :: (a: Vector3, b: Vector3) -> Vector3 #symmetric {
  return .{a.x * b.x, a.y * b.y, a.z * b.z};
} @NoProfile

operator / :: (a: Vector3, b: Vector3) -> Vector3 {
  return .{a.x / b.x, a.y / b.y, a.z / b.z};
} @NoProfile

operator / :: (a: Vector3, k: float32) -> Vector3 {
  denom := 1 / k;
  return .{a.x * denom, a.y * denom, a.z * denom};
} @NoProfile

Vector4 :: struct {
  x, y, z, w: float32;
  #overlay (x) xy: Vector2;
  #overlay (y) yz: Vector2;
  #overlay (z) zw: Vector2;
  #overlay (x) xyz: Vector3;
  #overlay (y) yzw: Vector3;
  #overlay (x) component: [4] float32;
}

operator + :: (a: Vector4, b: Vector4) -> Vector4 {
  return .{a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w};
} @NoProfile

operator - :: (a: Vector4, b: Vector4) -> Vector4 {
  return .{a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w};
} @NoProfile

operator - :: (a: Vector4) -> Vector4 {
  return .{-a.x, -a.y, -a.z, -a.w};
} @NoProfile

operator * :: (a: Vector4, k: float32) -> Vector4 #symmetric {
  return .{a.x * k, a.y * k, a.z * k, a.w * k};
} @NoProfile

operator * :: (a: Vector4, b: Vector4) -> Vector4 #symmetric {
  return .{a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w};
} @NoProfile

operator / :: (a: Vector4, b: Vector4) -> Vector4 {
  return .{a.x / b.x, a.y / b.y, a.z / b.z, a.w / b.w};
} @NoProfile

operator / :: (a: Vector4, k: float32) -> Vector4 {
  denom := 1 / k;
  return .{a.x * denom, a.y * denom, a.z * denom, a.w * denom};
} @NoProfile

Quaternion :: struct {
  x, y, z:  float;
  w      := 1.0;
  #overlay (x) xyz: Vector3;
  #overlay (x) component: [4] float;
}

operator + :: (a: Quaternion, b: Quaternion) -> Quaternion {
  return .{a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w};
} @NoProfile

operator * :: (a: Quaternion, k: float32) -> Quaternion  #symmetric {
  return .{a.x * k, a.y * k, a.z * k, a.w * k};
} @NoProfile

operator - :: (a: Quaternion, b: Quaternion) -> Quaternion {
  return .{a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w};
} @NoProfile

operator - :: (a: Quaternion) -> Quaternion {
  return .{-a.x, -a.y, -a.z, -a.w};
} @NoProfile

operator * :: (m: Quaternion, a: Quaternion) -> Quaternion {
  v  := m.xyz;
  av := a.xyz;

  r: Quaternion = ---;
  r.w = m.w * a.w - dot(v, av);

  rv := cross(v, av);

  av *= m.w;
  v  *= a.w;

  rv = rv + av + v;

  r.x = rv.x;
  r.y = rv.y;
  r.z = rv.z;

  return r;
} @NoProfile

conjugate :: (using q: Quaternion) -> Quaternion {
  r: Quaternion = ---;

  r.x = -x;
  r.y = -y;
  r.z = -z;
  r.w = w;

  return r;
} @NoProfile

dot :: (a: Vector2, b: Vector2) -> float32 {
  return a.x * b.x + a.y * b.y;
} @NoProfile

dot :: (a: Vector3, b: Vector3) -> float32 {
  return a.x * b.x + a.y * b.y + a.z * b.z;
} @NoProfile

dot :: (a: Vector4, b: Vector4) -> float32 {
  return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
} @NoProfile

dot :: (a: Quaternion, b: Quaternion) -> float32 {
  return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
} @NoProfile

length :: (a: Vector2) -> float32 {
  return sqrt(a.x * a.x + a.y * a.y);
} @NoProfile

length :: (a: Vector3) -> float32 {
  return sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
} @NoProfile

length :: (a: Vector4) -> float32 {
  return sqrt(a.x * a.x + a.y * a.y + a.z * a.z + a.w * a.w);
} @NoProfile

length :: (a: Quaternion) -> float32 {
  return sqrt(a.x * a.x + a.y * a.y + a.z * a.z + a.w * a.w);
} @NoProfile

length_squared :: inline (a: Vector2) -> float32 {
  return a.x * a.x + a.y * a.y;
} @NoProfile

length_squared :: inline (a: Vector3) -> float32 {
  return a.x * a.x + a.y * a.y + a.z * a.z;
} @NoProfile

length_squared :: inline (a: Vector4) -> float32 {
  return a.x * a.x + a.y * a.y + a.z * a.z + a.w * a.w;
} @NoProfile

abs :: inline (using v: Vector2) -> Vector2 {
  return .{abs(x), abs(y)};
} @NoProfile

abs :: inline (using v: Vector3) -> Vector3 {
  return .{abs(x), abs(y), abs(z)};
} @NoProfile

abs :: inline (using v: Vector4) -> Vector4 {
  return .{abs(x), abs(y), abs(z), abs(w)};
} @NoProfile

min :: inline (v1: Vector2, v2: Vector2) -> Vector2 {
  return .{min(v1.x, v2.x), min(v1.y, v2.y)};
} @NoProfile

min :: inline (v1: Vector3, v2: Vector3) -> Vector3 {
  return .{min(v1.x, v2.x), min(v1.y, v2.y), min(v1.z, v2.z)};
} @NoProfile

min :: inline (v1: Vector4, v2: Vector4) -> Vector4 {
  return .{min(v1.x, v2.x), min(v1.y, v2.y), min(v1.z, v2.z), min(v1.w, v2.w)};
} @NoProfile

max :: inline (v1: Vector2, v2: Vector2) -> Vector2 {
  return .{max(v1.x, v2.x), max(v1.y, v2.y)};
} @NoProfile

max :: inline (v1: Vector3, v2: Vector3) -> Vector3 {
  return .{max(v1.x, v2.x), max(v1.y, v2.y), max(v1.z, v2.z)};
} @NoProfile

max :: inline (v1: Vector4, v2: Vector4) -> Vector4 {
  return .{max(v1.x, v2.x), max(v1.y, v2.y), max(v1.z, v2.z), max(v1.w, v2.w)};
} @NoProfile

lerp :: inline (a: float32, b: float32, t: float32) -> float32 {
  return a + (b - a) * t;
} @NoProfile

lerp :: inline (a: float64, b: float64, t: float64) -> float64 {
  return a + (b - a) * t;
} @NoProfile

lerp :: (a: $T, b: T, t: float32) -> T
#modify {
  return (T == Vector2) || (T == Vector3) || (T == Vector4) || (T == Quaternion);
} {
  return a + (b - a) * t;
} @NoProfile

lerp :: (a: Quaternion, b: Quaternion, t: float32) -> Quaternion {
  r: Quaternion = ---;

  r.x = a.x + t * (b.x - a.x);
  r.y = a.y + t * (b.y - a.y);
  r.z = a.z + t * (b.z - a.z);
  r.w = a.w + t * (b.w - a.w);

  return r;
} @NoProfile

lerp :: (a: Vector2, b: Vector2, t: float32) -> Vector2 {
  r: Vector2 = ---;

  r.x = a.x + t * (b.x - a.x);
  r.y = a.y + t * (b.y - a.y);

  return r;
} @NoProfile

lerp :: (a: Vector3, b: Vector3, t: float32) -> Vector3 {
  r: Vector3 = ---;

  r.x = a.x + t * (b.x - a.x);
  r.y = a.y + t * (b.y - a.y);
  r.z = a.z + t * (b.z - a.z);

  return r;
} @NoProfile

lerp :: (a: Vector4, b: Vector4, t: float32) -> Vector4 {
  r: Vector4 = ---;

  r.x = a.x + t * (b.x - a.x);
  r.y = a.y + t * (b.y - a.y);
  r.z = a.z + t * (b.z - a.z);
  r.w = a.w + t * (b.w - a.w);

  return r;
} @NoProfile

normalize :: (v: *$T, $epsilon := 0.0001) -> float32
#modify {
  return (T == Vector2) || (T == Vector3) || (T == Vector4) || (T == Quaternion);
} {
  sq := length(v);
  if sq <= epsilon {
      v.* = .{};
      return sq;
  }

  factor := 1 / sq;
  v.* *= factor;
  return sq;
} @NoProfile

normalize :: (v: $T, $epsilon := 0.0001) -> T
#modify {
  return (T == Vector2) || (T == Vector3) || (T == Vector4) || (T == Quaternion);
} {
  w := v;
  inline normalize(*w, epsilon);
  return w;
} @NoProfile

cross :: (a: Vector3, b: Vector3) -> Vector3 {
  n: Vector3 = ---;

  n.x = a.y * b.z - a.z * b.y;
  n.y = a.z * b.x - a.x * b.z;
  n.z = a.x * b.y - a.y * b.x;

  return n;
} @NoProfile

rotate :: (v: Vector3, q: Quaternion) -> Vector3 {
  t := cross(q.xyz, v) * 2.0;
  return v + t * q.w + cross(q.xyz, t);
} @NoProfile

rotate :: (v: *Vector3, q: Quaternion) {
  t := cross(q.xyz, v.*) * 2.0;
  vv := v.* + t * q.w + cross(q.xyz, t);
  v.* = vv;
} @NoProfile

Matrix3 :: struct {
  i: Vector3;
  j: Vector3;
  k: Vector3;
  #overlay (i) floats: [9]    float32;
  #overlay (i) coef:   [3][3] float32;
}

Matrix3_Identity :: Matrix3.{i = .{x = 1.0}, j = .{y = 1.0}, k = .{z = 1.0 }};

operator * :: (m: Matrix3, v: Vector3) -> Vector3 {
  result: Vector3 = ---;

  result.x = m.i.x * v.x + m.j.x * v.y + m.k.x * v.z;
  result.y = m.i.y * v.x + m.j.y * v.y + m.k.y * v.z;
  result.z = m.i.z * v.x + m.j.z * v.y + m.k.z * v.z;

  return result;
} @NoProfile

operator * :: (m: Matrix3, n: Matrix3) -> Matrix3 {
  result: Matrix3 = ---;

  result.i = m * n.i;
  result.j = m * n.j;
  result.k = m * n.k;

  return result;
} @NoProfile

transpose :: (m: Matrix3) -> Matrix3 {
  r: Matrix3 = ---;
  for i: 0..2 for j: 0..2 {
    r.coef[i][j] = m.coef[j][i];
  }
  return r;
} @NoProfile

rotate :: (m: Matrix3, q: Quaternion) -> Matrix3 {
  r := mat3_from_mat4(quat_to_mat4(q));
  return r * m;
} @NoProfile

Matrix4 :: struct {
  i: Vector4;
  j: Vector4;
  k: Vector4;
  t: Vector4;
  #overlay (i) floats: [16]   float32;
  #overlay (i) coef:   [4][4] float32;
}

Matrix4_Identity :: Matrix4.{i = .{x = 1.0}, j = .{y = 1.0}, k = .{z = 1.0}, t = .{w = 1.0 }};

operator * :: (m: Matrix4, v: Vector4) -> Vector4 {
  result: Vector4 = ---;

  result.x = m.i.x * v.x + m.j.x * v.y + m.k.x * v.z + m.t.x * v.w;
  result.y = m.i.y * v.x + m.j.y * v.y + m.k.y * v.z + m.t.y * v.w;
  result.z = m.i.z * v.x + m.j.z * v.y + m.k.z * v.z + m.t.z * v.w;
  result.w = m.i.w * v.x + m.j.w * v.y + m.k.w * v.z + m.t.w * v.w;

  return result;
} @NoProfile

operator * :: (m: Matrix4, n: Matrix4) -> Matrix4 {
  result: Matrix4 = ---;

  result.i = m * n.i;
  result.j = m * n.j;
  result.k = m * n.k;
  result.t = m * n.t;

  return result;
} @NoProfile

transpose :: (m: Matrix4) -> Matrix4 {
  r: Matrix4 = ---;
  for i: 0..3 for j: 0..3 {
    r.coef[i][j] = m.coef[j][i];
  }
  return r;
} @NoProfile

rotate :: (m: Matrix4, q: Quaternion) -> Matrix4 {
  r := quat_to_mat4(q);
  return r * m;
} @NoProfile

inverse :: (m: Matrix4, epsilon := 0.0001) -> (success: bool, result: Matrix4) {
  a := m.i.xyz;
  b := m.j.xyz;
  c := m.k.xyz;
  d := m.t.xyz;

  x := m.i.w;
  y := m.j.w;
  z := m.k.w;
  w := m.t.w;

  s := cross(a, b);
  t := cross(c, d);
  u := a * y - b * x;
  v := c * w - d * z;

  det := dot(s, v) + dot(t, u);

  if abs(det) < epsilon {
      return false, Matrix4_Identity;
  }

  inv_det := 1.0 / det;
  s *= inv_det;
  t *= inv_det;
  u *= inv_det;
  v *= inv_det;

  r0 := cross(b, v) + t * y;
  r1 := cross(v, a) - t * x;
  r2 := cross(d, u) + s * w;
  r3 := cross(u, c) - s * z;

  result := Matrix4.{
    .{ r0.x,      r1.x,       r2.x,      r3.x     },
    .{ r0.y,      r1.y,       r2.y,      r3.y     },
    .{ r0.z,      r1.z,       r2.z,      r3.z     },
    .{-dot(b, t), dot(a, t), -dot(d, s), dot(c, s)},
  };
  return true, result;
}

adjugate :: (m: Matrix4) -> Matrix4 {
  a := m.i.xyz;
  b := m.j.xyz;
  c := m.k.xyz;
  d := m.t.xyz;

  x := m.i.w;
  y := m.j.w;
  z := m.k.w;
  w := m.t.w;

  s := cross(a, b);
  t := cross(c, d);
  u := a * y - b * x;
  v := c * w - d * z;

  r0 := cross(b, v) + t * y;
  r1 := cross(v, a) - t * x;
  r2 := cross(d, u) + s * w;
  r3 := cross(u, c) - s * z;

  result := Matrix4.{
    .{ r0.x,      r1.x,       r2.x,      r3.x     },
    .{ r0.y,      r1.y,       r2.y,      r3.y     },
    .{ r0.z,      r1.z,       r2.z,      r3.z     },
    .{-dot(b, t), dot(a, t), -dot(d, s), dot(c, s)},
  };
  return result;
}

// The world space is right handed Z up
//   z
//   |
//   |___ y
//  /
// x
//
// The camera space is right handed Z into the screen (same as default Vulkan NDC)
//      z
//    /
//   |---- x
//   |
//   y
//
// Default camera orientation is looking down the -Z

look_at :: (position: Vector3, target: Vector3, up: Vector3) -> Matrix4 {
  forward := normalize(target - position);
  right   := normalize(cross(forward, up));
  new_up  := cross(right, forward);

  return .{
    .{xyz = right,   w = 0.0},
    .{xyz = new_up,  w = 0.0},
    .{xyz = forward, w = 0.0},
    .{               w = 1.0},
 };
}

translate :: (m: *Matrix4, position: Vector3) {
  m.t.xyz += position;
}

translation :: (m: Matrix4) -> Vector3 {
  return m.t.xyz;
}

scale :: (m: *Matrix4, v: Vector3) {
  m.i *= v.x;
  m.j *= v.y;
  m.k *= v.z;
}

scale :: (m: Matrix4) -> Vector3 {
  return .{
    length(Vector4.{m.i.x, m.j.x, m.k.x, m.t.x }),
    length(Vector4.{m.i.y, m.j.y, m.k.y, m.t.y }),
    length(Vector4.{m.i.z, m.j.z, m.k.z, m.t.z }),
 };
}

perspective :: (fovy: float, aspect: float, near: float, far: float) -> Matrix4 {
  g := 1.0 / tan(fovy / 2.0);
  k := near / (near - far);
  return .{
    .{g / aspect, 0.0,      0.0, 0.0},
    .{0.0,          g,      0.0, 0.0},
    .{0.0,        0.0,        k, 1.0},
    .{0.0,        0.0, -far * k, 0.0},
 };
}

mat3_from_mat4 :: (m: Matrix4) -> Matrix3 {
  return .{m.i.xyz, m.j.xyz, m.k.xyz};
}

mat4_from_trs :: (
  translation: Vector3 = .{},
  rotation: Quaternion = .{},
  scale: Vector3 = .{1.0, 1.0, 1.0}
) -> Matrix4 {
  qx := rotation.x;
  qy := rotation.y;
  qz := rotation.z;
  qw := rotation.w;

  sx := scale.x;
  sy := scale.y;
  sz := scale.z;

  result: Matrix4 = ---;

  result.i.x = (1 - 2 * qy * qy - 2 * qz * qz) * sx;
  result.i.y = (2 * qx * qy + 2 * qz * qw)     * sx;
  result.i.z = (2 * qx * qz - 2 * qy * qw)     * sx;
  result.i.w = 0.0;

  result.j.x = (2 * qx * qy - 2 * qz * qw)     * sy;
  result.j.y = (1 - 2 * qx * qx - 2 * qz * qz) * sy;
  result.j.z = (2 * qy * qz + 2 * qx * qw)     * sy;
  result.j.w = 0.0;

  result.k.x = (2 * qx * qz + 2 * qy * qw)     * sz;
  result.k.y = (2 * qy * qz - 2 * qx * qw)     * sz;
  result.k.z = (1 - 2 * qx * qx - 2 * qy * qy) * sz;
  result.k.w = 0.0;

  result.t.x = translation.x;
  result.t.y = translation.y;
  result.t.z = translation.z;
  result.t.w = 1.0;

  return result;
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
    .{1.0 - 2.0 * (y2 + z2), 2.0 * (xy + wz),       2.0 * (xz - wy),       0.0},
    .{2.0 * (xy - wz),       1.0 - 2.0 * (x2 + z2), 2.0 * (yz + wx),       0.0},
    .{2.0 * (xz + wy),       2.0 * (yz - wx),       1.0 - 2.0 * (x2 + y2), 0.0},
    .{0.0,                   0.0,                   0.0,                   1.0},
 };
}

RGBA :: #type,distinct u32;

WHITE   :: cast(RGBA)0xffffffff;
RED     :: cast(RGBA)0xff0000ff;
GREEN   :: cast(RGBA)0x00ff00ff;
BLUE    :: cast(RGBA)0x0000ffff;
MAGENTA :: cast(RGBA)0xff00ffff;

rgba :: (r: u8, g: u8, b: u8, a: u8) -> RGBA {
  return (cast(RGBA)r) << 24 | (cast(RGBA)g) << 16 | (cast(RGBA)b) << 8 | cast(RGBA)a;
}

rgb_to_vector3 :: (hex: u32) -> Vector3 {
  return .{
    cast(float)(hex >> 16 & 0xff) / 255.0,
    cast(float)(hex >> 8  & 0xff) / 255.0,
    cast(float)(hex >> 0  & 0xff) / 255.0,
 };
}

max :: (v: Vector3) -> float {
  return max(max(v.x, v.y), max(v.y, v.z));
}

min :: (v: Vector3) -> float {
  return min(min(v.x, v.y), min(v.y, v.z));
}

AABB :: struct {
  min: Vector3;
  max: Vector3;
};

// Scale and translation to apply to unit cube to convert it to AABB
aabb_to_scale_and_translation :: (aabb: AABB) -> Vector3, Vector3 {
  dim := aabb.max - aabb.min;
  center := (aabb.max + aabb.min) / 2.0;
  return dim, center;
}

Ray :: struct {
  origin:    Vector3;
  direction: Vector3;
}

aabb_ray_intersection :: (aabb: AABB, ray: Ray) -> bool {
  low  := (aabb.min - ray.origin) / ray.direction;
  high := (aabb.max - ray.origin) / ray.direction;

  close := min(low, high);
  far   := max(low, high);

  t_close := max(close);
  t_far   := min(far);

  return t_close < t_far;
}

triangle_winding_ccw :: (p0: Vector3, p1: Vector3, p2: Vector3, direction: Vector3) -> bool {
  p1p0 := p1 - p0;
  p1p2 := p2 - p0;
  n    := cross(p1p0, p1p2);
  d    := dot(n, direction);
  return 0.0 < d;
}

TriangleIntersectionResult :: struct {
  u, v: float;
  t:    float = FLOAT32_MAX;
  n:    Vector3;
}
triangle_ray_intersection :: (
  p0: Vector3, p1: Vector3, p2: Vector3,
  ray: Ray,
  $only_ccw: bool = true,
) -> (success: bool, result: TriangleIntersectionResult) {
  e1 := p1 - p0;
  e2 := p2 - p0;
  n  := cross(e1, e2);
  d  := dot(n, ray.direction);

  if abs(d) < 1.0e-6 return false, .{};

  #if only_ccw {
    if (d < 0.0) return false, .{};
  }

  inv_d := 1.0 / d;
  ao    := p0 - ray.origin;
  dao   := cross(ao, ray.direction);
  u     :=  dot(e2, dao) * inv_d;
  v     := -dot(e1, dao) * inv_d;
  t     :=  dot(ao, n)   * inv_d;
  if 0.0 <= t && 0.0 <= u && 0.0 <= v && (u + v) <= 1.0 {
    return true, .{u, v, t, n};
  } else {
    return false, .{};
  }
}

using,only(sin, cos, tan, ctan, log, sqrt) math :: #import "Math";
