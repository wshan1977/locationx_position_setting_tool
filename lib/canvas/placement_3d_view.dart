import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/placement.dart';
import '../services/case_mesh.dart';
import '../state/app_state.dart';
import 'case_mesh_renderer.dart';
import 'world_transform.dart' show canvasBackground;

/// 위치 설정 탭의 3D 편집 뷰.
///
/// - 빈 공간 드래그: 시점 회전 · 휠: 줌
/// - 로케이터 드래그: X/Y 이동 (바닥 평면 기준)
/// - Shift + 로케이터 드래그: Z(설치 높이) 조절
/// - 클릭: 선택 (왼쪽 패널에서 세부 편집)
///
/// 로케이터는 orientation을 반영한 보드로 그려져 천장/벽 설치 자세와
/// 회전 방향(x/y 노치)을 눈으로 확인하며 배치할 수 있다.
class Placement3dView extends StatefulWidget {
  const Placement3dView({super.key});

  @override
  State<Placement3dView> createState() => _Placement3dViewState();
}

class _Placement3dViewState extends State<Placement3dView> {
  double _yaw = -0.6;
  double _pitch = 1.0;
  double? _scale;
  Offset _pan = Offset.zero;

  String? _draggingId;
  bool _rotating = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final cam = _Cam(
        app: app,
        size: size,
        yaw: _yaw,
        pitch: _pitch,
        scale: _scale ??= _fitScale(app, size),
        pan: _pan,
      );

      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            setState(() {
              final factor = e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
              _scale = (_scale! * factor).clamp(2.0, 2000.0);
            });
          }
        },
        // 가운데 버튼 드래그 = 화면 이동 (좌클릭 회전/편집과 별개)
        onPointerMove: (e) {
          if (e.buttons & kMiddleMouseButton != 0) {
            setState(() => _pan += e.delta);
          }
        },
        child: GestureDetector(
          onTapUp: (d) {
            final hit = _hitTest(app, cam, d.localPosition);
            context.read<AppState>().selectLocator(hit?.locatorId);
          },
          onPanStart: (d) {
            final hit = _hitTest(app, cam, d.localPosition);
            _draggingId = hit?.locatorId;
            _rotating = hit == null;
            if (hit != null) {
              context.read<AppState>().selectLocator(hit.locatorId);
            }
          },
          onPanUpdate: (d) {
            if (_rotating) {
              setState(() {
                _yaw += d.delta.dx * 0.008;
                _pitch = (_pitch + d.delta.dy * 0.008).clamp(0.15, 1.52);
              });
              return;
            }
            final id = _draggingId;
            if (id == null) return;
            final appState = context.read<AppState>();
            final p = appState.placements
                .where((e) => e.locatorId == id)
                .firstOrNull;
            if (p == null) return;

            final shift = HardwareKeyboard.instance.logicalKeysPressed.any(
                (k) =>
                    k == LogicalKeyboardKey.shiftLeft ||
                    k == LogicalKeyboardKey.shiftRight ||
                    k == LogicalKeyboardKey.shift);

            if (shift) {
              // 높이(z) 조절: 화면상 z축 방향으로의 이동량을 역산
              final base = cam.project(
                  p.coordinate.x, p.coordinate.y, p.coordinate.z);
              final up = cam.project(
                  p.coordinate.x, p.coordinate.y, p.coordinate.z + 1);
              final axis = up - base;
              final len2 = axis.dx * axis.dx + axis.dy * axis.dy;
              if (len2 < 1e-6) return;
              final dz =
                  (d.delta.dx * axis.dx + d.delta.dy * axis.dy) / len2;
              p.coordinate.z =
                  ((p.coordinate.z + dz).clamp(0.0, 30.0) * 100).round() / 100;
              appState.placementEdited();
            } else {
              // 바닥 평면 X/Y 이동: 화면 이동량 → world 이동량 2x2 역산
              final o = cam.project(
                  p.coordinate.x, p.coordinate.y, p.coordinate.z);
              final ex = cam.project(
                      p.coordinate.x + 1, p.coordinate.y, p.coordinate.z) -
                  o;
              final ey = cam.project(
                      p.coordinate.x, p.coordinate.y + 1, p.coordinate.z) -
                  o;
              final det = ex.dx * ey.dy - ex.dy * ey.dx;
              if (det.abs() < 1e-6) return;
              final wx =
                  (d.delta.dx * ey.dy - d.delta.dy * ey.dx) / det;
              final wy =
                  (-d.delta.dx * ex.dy + d.delta.dy * ex.dx) / det;
              appState.moveLocator(
                  id,
                  Offset(
                      p.coordinate.x + wx, p.coordinate.y + wy));
            }
          },
          onPanEnd: (_) {
            _draggingId = null;
            _rotating = false;
          },
          child: ClipRect(
            child: Stack(
              children: [
                CustomPaint(
                  size: size,
                  painter: _Placement3dPainter(app: app, cam: cam),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Text(
                    '드래그: 회전 · 로케이터 드래그: X/Y 이동 · Shift+드래그: 높이(Z) · 휠: 줌 · 가운데 버튼: 이동',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  double _fitScale(AppState app, Size canvas) {
    final b = _Cam.sceneBounds(app);
    final extent = math.max(b.width, b.height).clamp(2.0, double.infinity);
    return math.min(canvas.width, canvas.height) / extent * 0.7;
  }

  PlacedLocator? _hitTest(AppState app, _Cam cam, Offset pos) {
    PlacedLocator? best;
    var bestD = 16.0;
    for (final p in app.placements) {
      final s = cam.project(p.coordinate.x, p.coordinate.y, p.coordinate.z);
      final d = (s - pos).distance;
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }
}

/// 3D 카메라: 장면 중심 기준 yaw/pitch 궤도 + 원근 투영.
class _Cam {
  final Matrix4 m;

  _Cam._(this.m);

  factory _Cam({
    required AppState app,
    required Size size,
    required double yaw,
    required double pitch,
    required double scale,
    Offset pan = Offset.zero,
  }) {
    final b = sceneBounds(app);
    final m = Matrix4.identity()
      ..translate(size.width / 2 + pan.dx, size.height * 0.55 + pan.dy)
      ..setEntry(3, 2, -0.0009)
      ..rotateX(math.pi / 2 - pitch)
      ..rotateZ(yaw)
      ..scale(scale, -scale, scale)
      ..translate(-b.center.dx, -b.center.dy, 0);
    return _Cam._(m);
  }

  Offset project(double x, double y, double z) {
    final s = m.storage;
    final tx = s[0] * x + s[4] * y + s[8] * z + s[12];
    final ty = s[1] * x + s[5] * y + s[9] * z + s[13];
    final tw = s[3] * x + s[7] * y + s[11] * z + s[15];
    return Offset(tx / tw, ty / tw);
  }

  static Rect sceneBounds(AppState app) {
    final img = app.floorImage;
    if (img != null) {
      final t = app.transform;
      final a = t.imageToWorld(Offset.zero);
      final b =
          t.imageToWorld(Offset(img.width.toDouble(), img.height.toDouble()));
      return Rect.fromPoints(a, b);
    }
    final pts = [
      for (final p in app.placements) Offset(p.coordinate.x, p.coordinate.y),
    ];
    if (pts.isEmpty) return const Rect.fromLTWH(-5, -5, 10, 10);
    var r = Rect.fromPoints(pts.first, pts.first);
    for (final p in pts) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r.inflate(2);
  }
}

/// 오일러 각(도) → 3x3 회전. R = Rz·Ry·Rx.
List<double> _rotEulerDeg(double xDeg, double yDeg, double zDeg) {
  final a = xDeg * math.pi / 180;
  final b = yDeg * math.pi / 180;
  final c = zDeg * math.pi / 180;
  final ca = math.cos(a), sa = math.sin(a);
  final cb = math.cos(b), sb = math.sin(b);
  final cc = math.cos(c), sc = math.sin(c);
  return [
    cc * cb, cc * sb * sa - sc * ca, cc * sb * ca + sc * sa, //
    sc * cb, sc * sb * sa + cc * ca, sc * sb * ca - cc * sa, //
    -sb, cb * sa, cb * ca,
  ];
}

({double x, double y, double z}) _rotApply(
        List<double> r, double x, double y, double z) =>
    (
      x: r[0] * x + r[1] * y + r[2] * z,
      y: r[3] * x + r[4] * y + r[5] * z,
      z: r[6] * x + r[7] * y + r[8] * z,
    );

class _Placement3dPainter extends CustomPainter {
  final AppState app;
  final _Cam cam;

  _Placement3dPainter({required this.app, required this.cam});

  Offset _p(double x, double y, double z) => cam.project(x, y, z);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = canvasBackground);

    final b = _Cam.sceneBounds(app);
    _drawFloor(canvas);
    _drawGrid(canvas, b);
    _drawAxes(canvas, b);

    for (final p in app.placements) {
      _drawBoard(canvas, p, p.locatorId == app.selectedLocatorId);
    }
  }

  void _drawFloor(Canvas canvas) {
    final img = app.floorImage;
    if (img == null) return;
    final t = app.transform;
    final worldFromImage = Matrix4.identity()
      ..scale(t.metersPerPixel, -t.metersPerPixel, 1.0)
      ..translate(-t.originPx.dx, -t.originPx.dy, 0.0);

    canvas.save();
    canvas.transform((cam.m.clone()..multiply(worldFromImage)).storage);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Rect b) {
    final extent = math.max(b.width, b.height);
    final step = extent > 40 ? 10.0 : (extent > 15 ? 5.0 : 1.0);
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.25)
      ..strokeWidth = 0.7;
    for (var x = (b.left / step).floor() * step; x <= b.right; x += step) {
      canvas.drawLine(_p(x, b.top, 0), _p(x, b.bottom, 0), gridPaint);
    }
    for (var y = (b.top / step).floor() * step; y <= b.bottom; y += step) {
      canvas.drawLine(_p(b.left, y, 0), _p(b.right, y, 0), gridPaint);
    }
  }

  void _drawAxes(Canvas canvas, Rect b) {
    final len = (math.max(b.width, b.height) * 0.12).clamp(0.5, 5.0);
    final o = _p(0, 0, 0);
    void axis(double x, double y, double z, Color c, String name) {
      final e = _p(x, y, z);
      canvas.drawLine(
          o,
          e,
          Paint()
            ..color = c
            ..strokeWidth = 1.6);
      final tp = TextPainter(
        text: TextSpan(
            text: name,
            style: TextStyle(
                fontSize: 10, color: c, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, e + const Offset(3, -3));
    }

    axis(len, 0, 0, Colors.red.shade700, 'x');
    axis(0, len, 0, Colors.green.shade700, 'y');
    axis(0, 0, len, Colors.blue.shade700, 'z');
  }

  void _drawBoard(Canvas canvas, PlacedLocator p, bool selected) {
    final rot =
        _rotEulerDeg(p.orientation.x, p.orientation.y, p.orientation.z);
    final cx = p.coordinate.x, cy = p.coordinate.y, cz = p.coordinate.z;

    Offset world(double lx, double ly, double lz) {
      final w = _rotApply(rot, lx, ly, lz);
      return _p(cx + w.x, cy + w.y, cz + w.z);
    }

    final n = _rotApply(rot, 0, 0, 1);
    final mountLabel = n.z < -0.7
        ? '천장 · 아래를 봄 ✓'
        : (n.z > 0.7 ? '바닥 · 위를 봄' : '벽/경사');
    final mountColor = n.z < -0.7
        ? Colors.teal
        : (n.z > 0.7 ? Colors.orange : Colors.indigo);

    // 바닥 보조선
    final foot = _p(cx, cy, 0);
    final center = _p(cx, cy, cz);
    canvas.drawLine(
        foot,
        center,
        Paint()
          ..color = Colors.blueGrey.withValues(alpha: 0.4)
          ..strokeWidth = 1);
    canvas.drawCircle(
        foot, 2.5, Paint()..color = Colors.blueGrey.withValues(alpha: 0.5));

    // 실물 케이스 메시가 로드돼 있으면 케이스를, 아니면 추상 보드 판을 그린다.
    // 노치·화살표·라벨은 케이스 위에도 그려 설치 회전 확인 기준을 유지한다.
    const h = 0.25;
    final body = selected ? Colors.deepOrange : Colors.blue;
    final mesh = app.showLocatorPhoto ? CaseMesh.instance : null;
    if (mesh != null) {
      drawCaseMesh(canvas, mesh,
          rot: rot,
          cx: cx,
          cy: cy,
          cz: cz,
          cam: cam.m.storage,
          color: selected
              ? Colors.deepOrange.shade300
              : const Color(0xFFB9C3CD));
    } else {
      final c1 = world(-h, -h, 0);
      final c2 = world(h, -h, 0);
      final c3 = world(h, h, 0);
      final c4 = world(-h, h, 0);
      final plate = Path()
        ..moveTo(c1.dx, c1.dy)
        ..lineTo(c2.dx, c2.dy)
        ..lineTo(c3.dx, c3.dy)
        ..lineTo(c4.dx, c4.dy)
        ..close();
      canvas.drawPath(plate, Paint()..color = body.withValues(alpha: 0.35));
      canvas.drawPath(
          plate,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 2.6 : 1.6
            ..color = body);
    }

    // x(0°)/y(90°) 노치
    canvas.drawLine(
        world(h, 0, 0),
        world(h * 1.9, 0, 0),
        Paint()
          ..color = Colors.red
          ..strokeWidth = 2.4);
    canvas.drawLine(
        world(0, h, 0),
        world(0, h * 1.9, 0),
        Paint()
          ..color = Colors.green.shade600
          ..strokeWidth = 2.4);

    // 바라보는 방향 화살표
    final tip = world(0, 0, 0.9);
    canvas.drawLine(
        center,
        tip,
        Paint()
          ..color = body
          ..strokeWidth = 2.2);
    canvas.drawLine(tip, world(0.07, 0, 0.72),
        Paint()..color = body..strokeWidth = 2);
    canvas.drawLine(tip, world(-0.07, 0, 0.72),
        Paint()..color = body..strokeWidth = 2);

    // 라벨
    void label(Offset pos, String text, Color color, double size) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            color: color,
            fontWeight: FontWeight.w600,
            shadows: const [
              Shadow(color: Colors.white, blurRadius: 3),
              Shadow(color: Colors.white, blurRadius: 3),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos);
    }

    label(
        center + const Offset(12, -28),
        '${p.shortId} (${cx.toStringAsFixed(2)}, ${cy.toStringAsFixed(2)}, '
        '${cz.toStringAsFixed(2)})',
        selected ? Colors.deepOrange.shade900 : Colors.blue.shade900,
        11);
    label(center + const Offset(12, -14), mountLabel, mountColor, 10);
  }

  @override
  bool shouldRepaint(covariant _Placement3dPainter old) => true;
}
