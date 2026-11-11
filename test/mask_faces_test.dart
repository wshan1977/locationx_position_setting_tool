import 'package:flutter_test/flutter_test.dart';
import 'package:locationx_position_setting_tool/models/vec3.dart';
import 'package:locationx_position_setting_tool/services/mask_faces.dart';

void main() {
  test('level locators map the +Y face to the expected local azimuths', () {
    // 천장 설치(y=180)·z=180 (D71E): local az = −world az → +Y(10~170°)는 −170~−10
    final d71e = MaskFaces.localRanges({'+y'}, Vec3(x: 0, y: 180, z: 180));
    expect(d71e, hasLength(1));
    expect(d71e.single.$1, closeTo(-170, 1));
    expect(d71e.single.$2, closeTo(-10, 1));

    // z=0 (792E): local az = 180 − world az → +Y는 10~170
    final e792 = MaskFaces.localRanges({'+y'}, Vec3(x: 0, y: 180, z: 0));
    expect(e792.single.$1, closeTo(10, 1));
    expect(e792.single.$2, closeTo(170, 1));
  });

  test('faces across ±180 split into two ranges; none selected is empty', () {
    final r = MaskFaces.localRanges({'+x'}, Vec3(x: 0, y: 180, z: 0));
    // +X(−80~80) → local 100~180 와 −180~−100
    expect(r, hasLength(2));
    expect(r.first.$1, closeTo(-180, 1));
    expect(r.last.$2, closeTo(180, 1));
    expect(MaskFaces.localRanges({}, Vec3(x: 0, y: 180, z: 0)), isEmpty);
  });
}
