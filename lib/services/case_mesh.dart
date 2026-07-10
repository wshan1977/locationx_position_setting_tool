import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// 로케이터 실물 케이스(LocatorXCase) 3D 메시 — 보드 로컬 좌표(m).
///
/// 좌표 매핑 (실물 3D 뷰 대조로 확정):
///  - 안테나면 = 모델 -Z → 보드 로컬 +z (바라보는 방향) ·
///    전면(모델 z 최소) 중심을 원점으로 → 케이스 몸통은 z ≤ 0 (보드 뒤쪽)
///    (최초 +Z 가정은 실물 확인 결과 위아래가 뒤집혀 -Z로 수정)
///  - 케이블 커넥터 방향(방위 0° · 빨간 노치) = 모델 -X → 보드 +x
///    (STEP 분석: -X 측 정점 밀도가 +X의 2.2배 = 포트·디테일 면)
///  - 보드 +y = z × x = 모델 +Y (커넥터 기준 우측 = +90°)
///  - 단위: 모델 mm → m (÷1000)
/// 방향이 실물과 다르면 [yawOffsetDeg]만 바꾸면 된다.
class CaseMesh {
  /// 커넥터 방향 매핑이 틀렸을 때 90° 단위로 돌려 보정 (0/90/180/270).
  static const yawOffsetDeg = 0;

  /// 3D 뷰 표시 배율 — 실측(18cm)은 룸 스케일 화면에서 너무 작아
  /// 작업자 시인성을 위해 키워 그린다 (사용자 요청 1.5배).
  static const displayScale = 1.5;

  /// 삼각형 소업: [x,y,z] × 3정점 × triangleCount (보드 로컬, m)
  final Float32List vertices;

  /// 삼각형당 법선 1개: [x,y,z] × triangleCount (보드 로컬)
  final Float32List normals;

  final int triangleCount;

  CaseMesh._(this.vertices, this.normals, this.triangleCount);

  static CaseMesh? instance;
  static bool _loading = false;

  /// 앱 시작 시 1회 호출 — 실패(에셋 없음 등)하면 instance는 null로 남고
  /// 3D 뷰는 기존 보드 사각형 표시를 그대로 쓴다.
  static Future<void> ensureLoaded() async {
    if (instance != null || _loading) return;
    _loading = true;
    try {
      final data = await rootBundle.load('assets/models/locator_case.stl');
      instance = _parse(
          data.buffer.asByteData(data.offsetInBytes, data.lengthInBytes));
    } catch (_) {
      // 에셋이 빠진 빌드에서도 앱은 정상 동작해야 한다
    } finally {
      _loading = false;
    }
  }

  /// binary STL: 80B 헤더 + uint32 count + {normal 3f, v0 3f, v1 3f, v2 3f, u16}*n
  static CaseMesh _parse(ByteData b) {
    final n = b.getUint32(80, Endian.little);

    // 1차: 전면(z 최소) 판 — 원점을 전면 중심에 맞추기 위해
    var zMin = double.infinity;
    for (var i = 0; i < n; i++) {
      final base = 84 + i * 50 + 12;
      for (var v = 0; v < 3; v++) {
        final z = b.getFloat32(base + v * 12 + 8, Endian.little);
        if (z < zMin) zMin = z;
      }
    }

    final yaw = CaseMesh.yawOffsetDeg * math.pi / 180.0;
    final c = math.cos(yaw), s = math.sin(yaw);

    final verts = Float32List(n * 9);
    final norms = Float32List(n * 3);
    for (var i = 0; i < n; i++) {
      final base = 84 + i * 50;
      // 법선: 모델 (nx,ny,nz) → 보드 (-nx, ny, -nz) → yaw 보정
      final nx = -b.getFloat32(base, Endian.little);
      final ny = b.getFloat32(base + 4, Endian.little);
      final nz = -b.getFloat32(base + 8, Endian.little);
      norms[i * 3] = nx * c - ny * s;
      norms[i * 3 + 1] = nx * s + ny * c;
      norms[i * 3 + 2] = nz;
      for (var v = 0; v < 3; v++) {
        final o = base + 12 + v * 12;
        const k = displayScale / 1000.0; // mm→m + 표시 배율
        final x = -b.getFloat32(o, Endian.little) * k;
        final y = b.getFloat32(o + 4, Endian.little) * k;
        final z = (zMin - b.getFloat32(o + 8, Endian.little)) * k;
        final j = i * 9 + v * 3;
        verts[j] = x * c - y * s;
        verts[j + 1] = x * s + y * c;
        verts[j + 2] = z;
      }
    }
    return CaseMesh._(verts, norms, n);
  }
}
