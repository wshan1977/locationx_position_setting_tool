import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'world_transform.dart';

/// 도면 이미지 + 미터 그리드 + 원점 축 + 보정점을 한 번에 그린다.
class FloorPainter extends CustomPainter {
  final ui.Image? image;
  final WorldTransform t;
  final Offset? calibP1; // 이미지 px
  final Offset? calibP2;

  FloorPainter({
    required this.image,
    required this.t,
    this.calibP1,
    this.calibP2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // 도면 이미지
    final img = image;
    if (img != null) {
      final topLeft = t.imageToScreen(Offset.zero);
      final bottomRight = t.imageToScreen(
          Offset(img.width.toDouble(), img.height.toDouble()));
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromPoints(topLeft, bottomRight),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    _drawGrid(canvas, size);
    _drawAxes(canvas, size);
    _drawCalibration(canvas);

    canvas.restore();
  }

  /// 화면상 그리드 간격이 40px 이상이 되도록 1/2/5/10... m 스텝을 고른다.
  double _gridStepMeters() {
    final pxPerMeter = t.zoom / t.metersPerPixel;
    double step = 1.0;
    const factors = [1.0, 2.0, 5.0];
    var scale = 1.0;
    while (true) {
      for (final f in factors) {
        step = f * scale;
        if (step * pxPerMeter >= 40) return step;
      }
      scale *= 10;
      if (scale > 1e6) return step;
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.25)
      ..strokeWidth = 1;

    final step = _gridStepMeters();
    final wTopLeft = t.screenToWorld(Offset.zero);
    final wBottomRight = t.screenToWorld(Offset(size.width, size.height));

    final xMin = (math.min(wTopLeft.dx, wBottomRight.dx) / step).floor() * step;
    final xMax = math.max(wTopLeft.dx, wBottomRight.dx);
    final yMin = (math.min(wTopLeft.dy, wBottomRight.dy) / step).floor() * step;
    final yMax = math.max(wTopLeft.dy, wBottomRight.dy);

    final labelStyle = TextStyle(
        color: Colors.blueGrey.withValues(alpha: 0.7), fontSize: 10);

    for (var x = xMin; x <= xMax; x += step) {
      final s1 = t.worldToScreen(Offset(x, wTopLeft.dy));
      final s2 = t.worldToScreen(Offset(x, wBottomRight.dy));
      canvas.drawLine(Offset(s1.dx, 0), Offset(s2.dx, size.height), paint);
      _label(canvas, '${_fmt(x)}m', Offset(s1.dx + 2, size.height - 14),
          labelStyle);
    }
    for (var y = yMin; y <= yMax; y += step) {
      final s = t.worldToScreen(Offset(0, y));
      canvas.drawLine(Offset(0, s.dy), Offset(size.width, s.dy), paint);
      _label(canvas, '${_fmt(y)}m', Offset(2, s.dy + 2), labelStyle);
    }
  }

  void _drawAxes(Canvas canvas, Size size) {
    final origin = t.worldToScreen(Offset.zero);
    final xAxis = Paint()
      ..color = Colors.red.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    final yAxis = Paint()
      ..color = Colors.green.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    canvas.drawLine(origin, origin + const Offset(40, 0), xAxis);
    canvas.drawLine(origin, origin + const Offset(0, -40), yAxis);
    canvas.drawCircle(origin, 4, Paint()..color = Colors.red);
    _label(canvas, '(0,0)', origin + const Offset(6, 6),
        const TextStyle(color: Colors.red, fontSize: 11));
  }

  void _drawCalibration(Canvas canvas) {
    final p1 = calibP1, p2 = calibP2;
    final pin = Paint()..color = Colors.orange;
    if (p1 != null) {
      canvas.drawCircle(t.imageToScreen(p1), 5, pin);
    }
    if (p1 != null && p2 != null) {
      final s1 = t.imageToScreen(p1);
      final s2 = t.imageToScreen(p2);
      canvas.drawCircle(s2, 5, pin);
      canvas.drawLine(
          s1,
          s2,
          Paint()
            ..color = Colors.orange
            ..strokeWidth = 2);
    }
  }

  void _label(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  static String _fmt(double v) {
    final r = (v * 100).round() / 100;
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }

  @override
  bool shouldRepaint(FloorPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.t != t ||
      oldDelegate.calibP1 != calibP1 ||
      oldDelegate.calibP2 != calibP2;
}
