import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// 로케이터 실물 사진 (2D 뷰 오버레이용).
/// - front: 안테나면(로고면) — 바닥 설치(위를 봄)일 때 위에서 보이는 면
/// - back : 브라켓면 — 천장 설치(아래를 봄)일 때 위에서 보이는 면
/// 이미지 위쪽 = 커넥터 방향(보드 +x · 방위 0°) 가정 — 다르면
/// [imageRotOffsetDeg]로 90° 단위 보정.
class LocatorImages {
  static const imageRotOffsetDeg = 0;

  static ui.Image? front;
  static ui.Image? back;
  static bool _loading = false;

  static bool get loaded => front != null && back != null;

  static Future<void> ensureLoaded() async {
    if (loaded || _loading) return;
    _loading = true;
    try {
      front = await _load('assets/images/locator_front.png');
      back = await _load('assets/images/locator_back.png');
    } catch (_) {
      // 에셋이 없으면 기존 보드 사각형 표시 유지
    } finally {
      _loading = false;
    }
  }

  static Future<ui.Image> _load(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    return (await codec.getNextFrame()).image;
  }
}
