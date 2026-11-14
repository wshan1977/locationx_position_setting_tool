import 'dart:math' as math;

import '../models/vec3.dart';

/// 로케이터 설치 오차(기울기·회전) 보정 계산.
///
/// 태그를 위치를 아는 기준점에 두고 각 로케이터가 보고한 각도(azimuth,
/// elevation)를 모은 뒤, "로케이터 좌표 → 기준점" 실제 방향과 가장 잘 맞는
/// orientation(x, y, z)을 로케이터별로 찾는다.
///
/// 각도 → 방향 규칙 (2026-11-11 현장 실측으로 결정):
///   elevation은 안테나 판 평면 기준(0° = 수평, 90° = 판 정면/바로 아래)
///   v_local = (cos el·cos az, cos el·sin az, sin el)
///   v_world = Rz(oz)·Ry(oy)·Rx(ox) · v_local
/// 회전 순서는 positioning(RTL)이 보낸 correction(기대 각도) 267건을
/// 같은 시점 위치·orientation으로 역산해 확인했다 (D71E 잔차 0.4°). 처음 쓴
/// Rx·Ry·Rz는 기울기 0일 때만 같아서 보정 후 오차가 오히려 커졌었다.
/// 적용 후에는 실제 positioning 결과로 검증한다 (보정 화면의 [검증]).
class Calib {
  static double _rad(double d) => d * math.pi / 180;
  static double _deg(double r) => r * 180 / math.pi;

  /// 각도 → 로케이터 기준 단위 벡터.
  static List<double> localDir(double azDeg, double elDeg) {
    final a = _rad(azDeg), e = _rad(elDeg);
    return [math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)];
  }

  static List<double> _mul(List<List<double>> m, List<double> v) => [
        for (final r in m) r[0] * v[0] + r[1] * v[1] + r[2] * v[2],
      ];

  static List<List<double>> _mm(List<List<double>> a, List<List<double>> b) => [
        for (var i = 0; i < 3; i++)
          [
            for (var j = 0; j < 3; j++)
              a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j],
          ],
      ];

  static List<List<double>> rotation(double ox, double oy, double oz) {
    final cx = math.cos(_rad(ox)), sx = math.sin(_rad(ox));
    final cy = math.cos(_rad(oy)), sy = math.sin(_rad(oy));
    final cz = math.cos(_rad(oz)), sz = math.sin(_rad(oz));
    final rx = [
      [1.0, 0.0, 0.0],
      [0.0, cx, -sx],
      [0.0, sx, cx],
    ];
    final ry = [
      [cy, 0.0, sy],
      [0.0, 1.0, 0.0],
      [-sy, 0.0, cy],
    ];
    final rz = [
      [cz, -sz, 0.0],
      [sz, cz, 0.0],
      [0.0, 0.0, 1.0],
    ];
    return _mm(_mm(rz, ry), rx);
  }

  static List<double> _norm(List<double> v) {
    final n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return n == 0 ? v : [v[0] / n, v[1] / n, v[2] / n];
  }

  static double angleBetween(List<double> a, List<double> b) {
    final d = (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]).clamp(-1.0, 1.0);
    return _deg(math.acos(d));
  }

  /// 여러 각도 샘플의 평균 방향 (로케이터 기준).
  static List<double> meanLocalDir(List<(double, double)> azEl) {
    var s = [0.0, 0.0, 0.0];
    for (final (az, el) in azEl) {
      final v = localDir(az, el);
      s = [s[0] + v[0], s[1] + v[1], s[2] + v[2]];
    }
    return _norm(s);
  }

  /// 로케이터 좌표 → 기준점 실제 방향 (월드).
  static List<double> trueDir(Vec3 locator, Vec3 target) => _norm([
        target.x - locator.x,
        target.y - locator.y,
        target.z - locator.z,
      ]);

  /// orientation [o]일 때 측정 방향을 월드로 돌린 결과와 실제 방향의 각도 오차.
  static double error(Vec3 o, List<double> local, List<double> truth) =>
      angleBetween(_mul(rotation(o.x, o.y, o.z), local), truth);

  /// 기준점별 (측정 방향, 실제 방향) 쌍으로 orientation을 맞춘다.
  /// [start]에서 출발하는 Nelder–Mead (오차 제곱 평균 최소화).
  static CalibFit fit(Vec3 start, List<(List<double>, List<double>)> pairs) {
    double cost(List<double> p) {
      final o = Vec3(x: p[0], y: p[1], z: p[2]);
      var s = 0.0;
      for (final (local, truth) in pairs) {
        final e = error(o, local, truth);
        s += e * e;
      }
      return s / pairs.length;
    }

    final best = _nelderMead(cost, [start.x, start.y, start.z], 5.0);
    final o = Vec3(x: _round1(best[0]), y: _round1(best[1]), z: _round1(best[2]));
    double meanErr(Vec3 v) =>
        pairs.map((p) => error(v, p.$1, p.$2)).reduce((a, b) => a + b) /
        pairs.length;
    return CalibFit(
      orientation: o,
      errorBefore: meanErr(start),
      errorAfter: meanErr(o),
    );
  }

  static double _round1(double v) => (v * 10).roundToDouble() / 10;

  static List<double> _nelderMead(
      double Function(List<double>) f, List<double> x0, double step) {
    final n = x0.length;
    var simplex = <List<double>>[
      x0,
      for (var i = 0; i < n; i++) [for (var j = 0; j < n; j++) x0[j] + (i == j ? step : 0)],
    ];
    var values = simplex.map(f).toList();
    for (var iter = 0; iter < 2000; iter++) {
      final order = List.generate(n + 1, (i) => i)
        ..sort((a, b) => values[a].compareTo(values[b]));
      simplex = [for (final i in order) simplex[i]];
      values = [for (final i in order) values[i]];
      if ((values[n] - values[0]).abs() < 1e-9) break;
      final centroid = List.filled(n, 0.0);
      for (var i = 0; i < n; i++) {
        for (var j = 0; j < n; j++) {
          centroid[j] += simplex[i][j] / n;
        }
      }
      List<double> along(double t) =>
          [for (var j = 0; j < n; j++) centroid[j] + t * (simplex[n][j] - centroid[j])];
      final xr = along(-1), fr = f(xr);
      if (fr < values[0]) {
        final xe = along(-2), fe = f(xe);
        simplex[n] = fe < fr ? xe : xr;
        values[n] = fe < fr ? fe : fr;
      } else if (fr < values[n - 1]) {
        simplex[n] = xr;
        values[n] = fr;
      } else {
        final xc = along(0.5), fc = f(xc);
        if (fc < values[n]) {
          simplex[n] = xc;
          values[n] = fc;
        } else {
          for (var i = 1; i <= n; i++) {
            simplex[i] = [
              for (var j = 0; j < n; j++) simplex[0][j] + 0.5 * (simplex[i][j] - simplex[0][j]),
            ];
            values[i] = f(simplex[i]);
          }
        }
      }
    }
    final iBest = List.generate(n + 1, (i) => i)
        .reduce((a, b) => values[a] <= values[b] ? a : b);
    return simplex[iBest];
  }
}

/// 로케이터 1대 보정 결과.
class CalibFit {
  final Vec3 orientation;
  final double errorBefore; // 기준점 평균 각도 오차(°), 현재 orientation
  final double errorAfter; // 보정 orientation
  const CalibFit({
    required this.orientation,
    required this.errorBefore,
    required this.errorAfter,
  });
}
