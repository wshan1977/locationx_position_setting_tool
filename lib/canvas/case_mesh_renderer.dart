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
  double scale = 1.0, // 그림 크기 배율 (정점만 · 조명 법선은 그대로)
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
      final px = v[o] * scale, py = v[o + 1] * scale, pz = v[o + 2] * scale;
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
    shades[k] = math.min(1.0, 0.42 + 0.58 * math.max(0.0, diff));
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

/// 2D(위에서 본) 뷰용 "세운 케이스" 그림 — 벽·경사 설치처럼 사진(앞/뒷면)으로는
/// 세운 모양이 안 보이는 자세용. 위에서 정사영하면 세운 케이스는 몇 픽셀짜리
/// 막대라 마커에 가려지므로, 화면 크기 고정([widthPx])으로 비스듬히 위에서 본
/// 미니 3D 그림을 [lift]px 위로 띄워 그리고, 바라보는 방향 화살표는 도면상
/// 실제 위치·방향으로 그린다. [toScreen]: 그 뷰의 world(m) → 화면 (위치설정
/// 도면·관제 뷰 공용 · 도면은 회전 없이 x 오른쪽 / y 위쪽이라고 가정).
void drawCaseMeshIcon2d(
  Canvas canvas,
  CaseMesh mesh, {
  required List<double> rot, // 설정 자세 — 바라보는 방향 화살표용
  required List<double> meshRot, // 그림용 자세 (CaseMesh.drawRotation)
  required double cx,
  required double cy,
  required Offset Function(Offset world) toScreen,
  required Color color,
  double widthPx = 64,
  double lift = 0,
}) {
  final o = toScreen(Offset(cx, cy));
  Offset unit(Offset v) => v.distance < 1e-9 ? v : v / v.distance;
  final xh = unit(toScreen(Offset(cx + 1, cy)) - o);
  final yh = unit(toScreen(Offset(cx, cy + 1)) - o);

  // 그림은 항상 안테나면(앞면)이 보이게: 바라보는 방향이 카메라 쪽(-y)이
  // 되도록 수평으로 돌린다 (방향은 아래 화살표가 도면상 실제로 표시).
  final m = meshRot;
  final fx = m[2], fy = m[5];
  var r3 = m;
  if (math.sqrt(fx * fx + fy * fy) >= 0.3) {
    final th = -math.pi / 2 - math.atan2(fy, fx);
    final ch = math.cos(th), sh = math.sin(th);
    r3 = [
      ch * m[0] - sh * m[3], ch * m[1] - sh * m[4], ch * m[2] - sh * m[5], //
      sh * m[0] + ch * m[3], sh * m[1] + ch * m[4], sh * m[2] + ch * m[5], //
      m[6], m[7], m[8],
    ];
  }

  // 메시 실제 폭(m) → 화면 widthPx
  var r = 0.0;
  final v = mesh.vertices;
  for (var i = 0; i < v.length; i += 3) {
    final d = math.sqrt(v[i] * v[i] + v[i + 1] * v[i + 1] + v[i + 2] * v[i + 2]);
    if (d > r) r = d;
  }
  final k = widthPx / (2 * (r <= 0 ? 0.2 : r));

  // 비스듬히(앙각 t) 아래쪽(-y)에서 내려다보는 정사영:
  //   화면 = o' + k·(x̂·x + ŷ·y·sin t) + 위쪽·z·cos t
  //   깊이(클수록 카메라 쪽) = -y·cos t + z·sin t
  const t = 0.85; // rad ≈ 49°
  final st = math.sin(t), ct = math.cos(t);
  final c = Offset(o.dx, o.dy - lift);
  final cam = Float64List(16);
  cam[0] = k * xh.dx;
  cam[1] = k * xh.dy;
  cam[4] = k * yh.dx * st;
  cam[5] = k * yh.dy * st;
  cam[8] = 0;
  cam[9] = -k * ct;
  cam[2] = 0;
  cam[6] = -ct;
  cam[10] = st;
  cam[12] = c.dx;
  cam[13] = c.dy;
  cam[15] = 1;

  // 그림 받침(그림자 원) + 위치 연결선
  if (lift > 0) {
    canvas.drawLine(o, c, Paint()
      ..color = const Color(0x803949AB)
      ..strokeWidth = 1);
  }
  canvas.drawOval(
      Rect.fromCenter(center: c + Offset(0, widthPx * 0.18), width: widthPx * 0.9, height: widthPx * 0.22),
      Paint()..color = const Color(0x22000000));
  drawCaseMesh(canvas, mesh, rot: r3, cx: 0, cy: 0, cz: 0, cam: cam, color: color);

  // 바라보는 방향(보드 법선의 수평 성분) 화살표 — 도면상 실제 위치에서
  final nx = rot[2], ny = rot[5];
  final len = math.sqrt(nx * nx + ny * ny);
  if (len < 0.3) return; // 거의 위/아래를 보면 생략
  final dir = unit(xh * (nx / len) + yh * (ny / len));
  final tip = o + dir * math.max(14.0, widthPx * 0.6); // 그림 크기에 비례
  final paint = Paint()
    ..color = const Color(0xFF3949AB)
    ..strokeWidth = 2.4
    ..style = PaintingStyle.stroke;
  canvas.drawLine(o, tip, paint);
  final side = Offset(-dir.dy, dir.dx);
  canvas.drawLine(tip, tip - dir * 9 + side * 5, paint);
  canvas.drawLine(tip, tip - dir * 9 - side * 5, paint);
}
