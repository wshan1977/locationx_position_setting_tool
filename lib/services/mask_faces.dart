import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/vec3.dart';
import 'calibration.dart';

/// 반사면 마스크: 도면 4면(+X/−X/+Y/−Y) 중 벽·반사면이 있는 쪽을 고르면,
/// 로케이터 orientation으로 로케이터 기준 azimuth 범위로 바꿔 카드의
/// locator_config.json azimuthMask에 넣는다 (SDK sl_rtl_aox_add_constraint —
/// "벽·반사면 근처 로케이터의 멀티패스 오검출 배제").
class MaskFaces {
  /// 면 → 도면(월드) 방위각 중심 (°, +X = 0, +Y = 90).
  static const faces = {'+y': 90.0, '-y': -90.0, '+x': 0.0, '-x': 180.0};

  static const labels = {
    '+y': '↑ 위 (+Y)',
    '-y': '↓ 아래 (−Y)',
    '+x': '→ 오른쪽 (+X)',
    '-x': '← 왼쪽 (−X)',
  };

  /// 면 1개가 덮는 반폭 (°). 90이면 반평면 전체 — 양 끝 10°는 벽을 따라
  /// 스치는 방향이라 남겨 둔다.
  static const halfWidth = 80.0;

  /// 변환 기준 앙각: 수평에서 아래로 30° (천장 설치 · 방 안 태그의 전형).
  /// 기울기가 없는 로케이터는 앙각과 무관하게 정확하다.
  static const _belowHorizon = 30.0;

  /// 고른 면들 → 로케이터 기준 azimuth 범위 목록 (min ≤ max, −180..180).
  static List<(double, double)> localRanges(Set<String> selected, Vec3 o) {
    final r = Calib.rotation(o.x, o.y, o.z);
    final covered = List.filled(360, false); // index = az + 180 (1° 칸)
    final dn = _belowHorizon * math.pi / 180;
    for (final f in selected) {
      final c = faces[f];
      if (c == null) continue;
      for (var b = c - halfWidth; b <= c + halfWidth + 1e-9; b += 0.5) {
        final br = b * math.pi / 180;
        final w = [
          math.cos(dn) * math.cos(br),
          math.cos(dn) * math.sin(br),
          -math.sin(dn),
        ];
        // local = Rᵀ·world
        final l = [
          for (var j = 0; j < 3; j++) r[0][j] * w[0] + r[1][j] * w[1] + r[2][j] * w[2],
        ];
        final az = math.atan2(l[1], l[0]) * 180 / math.pi;
        covered[(az.round() + 180) % 360] = true;
      }
    }
    // 연속 구간으로 묶는다 (−180/180 경계에서 갈라지는 구간은 둘로 남김)
    final out = <(double, double)>[];
    int? start;
    for (var i = 0; i <= 360; i++) {
      final on = i < 360 && covered[i];
      if (on && start == null) start = i;
      if (!on && start != null) {
        out.add(((start - 180).toDouble(), (i - 1 - 180).toDouble()));
        start = null;
      }
    }
    return out;
  }

  static String describe(List<(double, double)> ranges) => ranges.isEmpty
      ? '없음'
      : ranges.map((r) => '${r.$1.toStringAsFixed(0)}°~${r.$2.toStringAsFixed(0)}°').join(', ');
}

/// 로케이터 카드 상태 서버(:8080)의 각도 마스크 API (로케이터 v1.0.29+).
class LocatorCardApi {
  final String ip;
  const LocatorCardApi(this.ip);

  Uri _uri(String p) => Uri.parse('http://$ip:8080$p');

  /// 카드에 적용된 azimuthMask (null = 없음).
  Future<List<(double, double)>?> getAzimuthMask() async {
    final res = await http.get(_uri('/api/locator_config')).timeout(const Duration(seconds: 5));
    if (res.statusCode == 404) {
      throw '카드 소프트웨어가 마스크 API를 지원하지 않습니다 (로케이터 v1.0.29 이상 필요)';
    }
    final d = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (d['ok'] != true) throw d['error']?.toString() ?? 'HTTP ${res.statusCode}';
    return _parse(d['azimuthMask']);
  }

  /// azimuthMask 적용 (빈 목록 = 해제). 카드가 aoa-antenna를 재시작한다.
  Future<List<(double, double)>?> setAzimuthMask(List<(double, double)> ranges) async {
    final res = await http
        .post(
          _uri('/api/locator_config'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'azimuthMask': ranges.isEmpty
                ? null
                : [for (final r in ranges) {'min': r.$1, 'max': r.$2}],
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) {
      throw '카드 소프트웨어가 마스크 API를 지원하지 않습니다 (로케이터 v1.0.29 이상 필요)';
    }
    final d = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (d['ok'] != true) throw d['error']?.toString() ?? 'HTTP ${res.statusCode}';
    return _parse(d['azimuthMask']);
  }

  static List<(double, double)>? _parse(dynamic v) => v is List
      ? [
          for (final r in v)
            if (r is Map) ((r['min'] as num).toDouble(), (r['max'] as num).toDouble()),
        ]
      : null;
}
