import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../services/case_mesh.dart';

/// 실물 케이스 메시를 3D 뷰에 그린다 — 위치 설정·위치 확인 3D 페인터 공용.
///
/// 두 뷰 모두 같은 카메라 행렬 구성을 쓰며(translate→perspective→rotX→rotZ→
/// scale→translate), 그 행렬의 z-row 값은 **클수록 카메라에 가깝다**(수치 검증).
/// 이를 근거로:
///  - 뒷면 컬링: world 법선 · z-row 방향 ≤ 0 이면 스킵
///  - 페인터 정렬: z-row 값 오름차순(먼 것부터) 정렬 후 한 번의
///    drawVertices 호출로 그린다 (삼각형 1.1만 개 × 로케이터 수)
void drawCaseMesh(
  Canvas canvas,
  CaseMesh mesh, {
  required List<double> rot, // 3x3 row-major · 보드 로컬 → world 회전
  required double cx,
  required double cy,
  required double cz, // 보드 world 위치 (m)
  required Float64List cam, // Matrix4.storage (column-major 16)
  required Color color,
}) {
  final n = mesh.triangleCount;
  final v = mesh.vertices;
  final nm = mesh.normals;

  final m0 = cam[0], m4 = cam[4], m8 = cam[8], m12 = cam[12];
  final m1 = cam[1], m5 = cam[5], m9 = cam[9], m13 = cam[13];
  final m3 = cam[3], m7 = cam[7], m11 = cam[11], m15 = cam[15];
  final zx = cam[2], zy = cam[6], zz = cam[10];

  // 광원: world 고정 방향 (위 + 약간 측면) — 플랫 셰이딩
  const lx = 0.32, ly = 0.24, lz = 0.92;

  final depths = Float64List(n);
  final screen = Float32List(n * 6);
  final shades = Float64List(n);
  final kept = Uint32List(n);
  var k = 0;

  for (var i = 0; i < n; i++) {
    // world 법선 (회전만)
    final a = nm[i * 3], b = nm[i * 3 + 1], c = nm[i * 3 + 2];
    final nwx = rot[0] * a + rot[1] * b + rot[2] * c;
    final nwy = rot[3] * a + rot[4] * b + rot[5] * c;
    final nwz = rot[6] * a + rot[7] * b + rot[8] * c;

    // 뒷면 컬링: 카메라 쪽(z-row 증가 방향)을 보지 않으면 스킵
    if (nwx * zx + nwy * zy + nwz * zz <= 0) continue;

    var depth = 0.0;
    var ok = true;
    for (var j = 0; j < 3; j++) {
      final o = i * 9 + j * 3;
      final px = v[o], py = v[o + 1], pz = v[o + 2];
      final wx = cx + rot[0] * px + rot[1] * py + rot[2] * pz;
      final wy = cy + rot[3] * px + rot[4] * py + rot[5] * pz;
      final wz = cz + rot[6] * px + rot[7] * py + rot[8] * pz;
      final w = m3 * wx + m7 * wy + m11 * wz + m15;
      if (w.abs() < 1e-6) {
        ok = false;
        break;
      }
      screen[k * 6 + j * 2] = (m0 * wx + m4 * wy + m8 * wz + m12) / w;
      screen[k * 6 + j * 2 + 1] = (m1 * wx + m5 * wy + m9 * wz + m13) / w;
      depth += zx * wx + zy * wy + zz * wz;
    }
    if (!ok) continue;

    final diff = nwx * lx + nwy * ly + nwz * lz;
    shades[k] = 0.42 + 0.58 * math.max(0.0, diff);
    depths[k] = depth;
    kept[k] = k;
    k++;
  }
  if (k == 0) return;

  // 먼 것부터 (z-row 작은 것부터) — 페인터 알고리즘
  final order = kept.sublist(0, k)..sort((a, b) => depths[a].compareTo(depths[b]));

  final positions = Float32List(k * 6);
  final colors = Int32List(k * 3);
  final baseR = (color.r * 255).round();
  final baseG = (color.g * 255).round();
  final baseB = (color.b * 255).round();
  for (var oi = 0; oi < k; oi++) {
    final i = order[oi];
    for (var j = 0; j < 6; j++) {
      positions[oi * 6 + j] = screen[i * 6 + j];
    }
    final s = shades[i];
    final argb = 0xFF000000 |
        ((baseR * s).round() << 16) |
        ((baseG * s).round() << 8) |
        (baseB * s).round();
    colors[oi * 3] = argb;
    colors[oi * 3 + 1] = argb;
    colors[oi * 3 + 2] = argb;
  }

  canvas.drawVertices(
    Vertices.raw(VertexMode.triangles, positions, colors: colors),
    BlendMode.dst, // 정점 색만 사용
    Paint(),
  );
}
