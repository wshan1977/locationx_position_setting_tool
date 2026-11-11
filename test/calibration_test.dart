import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:locationx_position_setting_tool/models/vec3.dart';
import 'package:locationx_position_setting_tool/models/positioning_config.dart';
import 'package:locationx_position_setting_tool/services/calibration.dart';

/// [o]로 설치된 로케이터가 [target]을 볼 때 보고할 (azimuth, elevation).
(double, double) simulate(Vec3 loc, Vec3 o, Vec3 target) {
  final w = Calib.trueDir(loc, target);
  final r = Calib.rotation(o.x, o.y, o.z);
  // local = Rᵀ·world
  final l = [
    for (var j = 0; j < 3; j++) r[0][j] * w[0] + r[1][j] * w[1] + r[2][j] * w[2],
  ];
  return (
    math.atan2(l[1], l[0]) * 180 / math.pi,
    math.asin(l[2].clamp(-1.0, 1.0)) * 180 / math.pi,
  );
}

void main() {
  test('matches the field analysis (tag under 7ACD, 2026-11-11 capture)', () {
    // 현장 20초 캡처의 로케이터별 평균 각도 · Python 분석 결과와 같은 오차여야 한다
    final tag = Vec3(x: 2.5, y: -4.3, z: 0);
    final cases = {
      'D71E': (Vec3(x: 0, y: 0.06, z: 3), Vec3(x: 0, y: 180, z: 180), 68.1, 33.684, 7.3),
      '7924': (Vec3(x: 0, y: -4.3, z: 2.3), Vec3(x: 0, y: 180, z: 180), 37.954, 51.438, 27.0),
      '792E': (Vec3(x: 3, y: 0, z: 3), Vec3(x: 0, y: 180, z: 0), -103.524, 23.408, 20.9),
      '7ACD': (Vec3(x: 2.5, y: -4.3, z: 3), Vec3(x: 0, y: 180, z: 0), -106.94, 71.052, 18.9),
    };
    cases.forEach((k, c) {
      final (loc, o, az, el, expected) = c;
      final e = Calib.error(o, Calib.localDir(az, el), Calib.trueDir(loc, tag));
      expect(e, closeTo(expected, 0.15), reason: k);
    });
  });

  test('rotation order matches RTL expected direction (correction messages)', () {
    // 2026-11-11 실측: positioning이 D71E에 보낸 correction 기대 각도와 같은
    // sequence의 위치 · 당시 orientation (-3.1, 170, 172.6). 183건 평균 잔차
    // az 0.4° · el 0.4° (Rx·Ry·Rz 순서면 크게 어긋남).
    final loc = Vec3(x: 0, y: 0.06, z: 3);
    final o = Vec3(x: -3.1, y: 170, z: 172.6);
    const samples = [
      (2.1659, -6.3986, 0.2960, 60.347, 20.900),
      (1.8640, -6.6149, 0.0183, 62.862, 21.350),
      (2.1588, -6.4302, 0.1569, 60.292, 20.668),
      (2.1213, -6.7819, 0.3043, 61.818, 18.627),
      (1.7079, -6.2839, 0.2806, 63.533, 21.083),
      (1.6936, -6.2627, 0.3034, 63.647, 21.458),
      (2.1365, -6.6293, 0.0346, 60.907, 21.000),
      (2.1260, -6.8714, 0.1871, 61.897, 20.473),
    ];
    for (final (x, y, z, az, el) in samples) {
      final (a, e) = simulate(loc, o, Vec3(x: x, y: y, z: z));
      expect(a, closeTo(az, 2.5));
      expect(e, closeTo(el, 2.5));
    }
  });

  test('recovers a tilted install from several reference points', () {
    final loc = Vec3(x: 2.5, y: -4.3, z: 3);
    final actual = Vec3(x: 15, y: 186, z: 8); // 설치 기울기·회전
    final points = [
      Vec3(x: 2.5, y: -4.3, z: 0),
      Vec3(x: 0, y: -4.3, z: 0),
      Vec3(x: 3, y: 0, z: 0),
      Vec3(x: 0.5, y: -1, z: 0.8),
    ];
    final pairs = [
      for (final p in points)
        (
          Calib.localDir(simulate(loc, actual, p).$1, simulate(loc, actual, p).$2),
          Calib.trueDir(loc, p),
        ),
    ];
    final fit = Calib.fit(Vec3(x: 0, y: 180, z: 0), pairs);
    expect(fit.errorBefore, greaterThan(10));
    expect(fit.errorAfter, lessThan(0.2));
    expect(fit.orientation.x, closeTo(15, 0.3));
    expect(fit.orientation.y, closeTo(186, 0.3));
    expect(fit.orientation.z, closeTo(8, 0.3));
  });

  test('targetHeight round-trips and is omitted when not set', () {
    final c = PositioningConfig.fromJson({'targetHeight': 1.2, 'foo': 1});
    expect(c.targetHeight, 1.2);
    expect(c.extras.containsKey('targetHeight'), isFalse);
    expect(c.toJson()['targetHeight'], 1.2);
    c.targetHeight = null;
    expect(c.toJson().containsKey('targetHeight'), isFalse);
    expect(c.toJson()['foo'], 1);
  });
}
