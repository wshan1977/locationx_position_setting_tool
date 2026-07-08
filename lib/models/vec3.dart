class Vec3 {
  double x;
  double y;
  double z;

  Vec3({this.x = 0, this.y = 0, this.z = 0});

  factory Vec3.fromJson(Map<String, dynamic>? json) {
    if (json == null) return Vec3();
    return Vec3(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      z: (json['z'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};

  Vec3 copy() => Vec3(x: x, y: y, z: z);
}
