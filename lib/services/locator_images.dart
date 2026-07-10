import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// 로케이터 실물 사진 (2D 뷰 오버레이용).
/// - front: 안테나면(로고면) — 바닥 설치(위를 봄)일 때 위에서 보이는 면
/// - back : 브라켓면 — 천장 설치(아래를 봄)일 때 위에서 보이는 면
/// [imageRotOffsetDeg]: 사진 위쪽과 커넥터(보드 +x · 방위 0°)의 관계 보정 —
/// 실물 대조 결과 최초 가정에서 180° 돌아가 있어 180으로 확정.
class LocatorImages {
  static const imageRotOffsetDeg = 180;

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

  /// 사진을 [center] 기준 [sizePx] 정사각으로, 사진 위쪽이 화면상
  /// [screenAngleRad] 방향(보드 +x의 화면 각도)을 향하게 회전해 그린다.
  /// [imageRotOffsetDeg] 보정 포함 — 2D 뷰들이 공용.
  static void drawRotated(ui.Canvas canvas, ui.Image img, ui.Offset center,
      double sizePx, double screenAngleRad) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(screenAngleRad +
        math.pi / 2 +
        imageRotOffsetDeg * math.pi / 180);
    canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      ui.Rect.fromCenter(center: ui.Offset.zero, width: sizePx, height: sizePx),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();
  }
}
