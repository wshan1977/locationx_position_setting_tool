import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dart:math' as math;

import '../models/discovered_device.dart';
import '../models/placement.dart';
import '../services/case_mesh.dart';
import '../services/locator_images.dart';
import '../services/mask_faces.dart';
import '../state/app_state.dart';
import 'case_mesh_renderer.dart';
import 'grid_painter.dart';
import 'locator_marker.dart';
import 'world_transform.dart' show canvasBackground;

/// 중앙 캔버스: 도면 + 그리드 + 마커. 휠 줌 / 빈 공간 드래그 팬 /
/// 오른쪽 리스트에서 드롭 / 보정·원점 클릭 모드.
class FloorCanvas extends StatelessWidget {
  const FloorCanvas({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.transform;

    return LayoutBuilder(builder: (context, constraints) {
      final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

      return DragTarget<DiscoveredDevice>(
        onWillAcceptWithDetails: (details) =>
            details.data.hasValidMac &&
            !details.data.isServer &&
            !app.isPlaced(details.data),
        onAcceptWithDetails: (details) {
          final box = context.findRenderObject() as RenderBox;
          final local = box.globalToLocal(details.offset);
          app.placeDevice(details.data, t.screenToWorld(local));
        },
        builder: (context, candidates, rejected) {
          return Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                if (app.canvasMode == CanvasMode.adjustImage) {
                  // 도면 조정 모드: 뷰가 아니라 도면 이미지 크기를 조정
                  final factor = event.scrollDelta.dy > 0 ? 1 / 1.05 : 1.05;
                  app.scaleImage(event.localPosition, factor);
                } else {
                  final factor = event.scrollDelta.dy > 0 ? 1 / 1.15 : 1.15;
                  app.setTransform(
                      t.zoomAt(event.localPosition, t.zoom * factor));
                }
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (app.canvasMode != CanvasMode.normal) {
                  final imagePx = t.screenToImage(details.localPosition);
                  final needDistance = app.handleCalibrationClick(imagePx);
                  if (needDistance) _askCalibrationDistance(context);
                } else {
                  app.selectLocator(null);
                }
              },
              onPanUpdate: (details) {
                if (app.canvasMode == CanvasMode.adjustImage) {
                  app.nudgeImage(details.delta);
                } else {
                  app.setTransform(t.copyWith(panPx: t.panPx + details.delta));
                }
              },
              child: MouseRegion(
                cursor: switch (app.canvasMode) {
                  CanvasMode.normal => SystemMouseCursors.basic,
                  CanvasMode.adjustImage => SystemMouseCursors.move,
                  _ => SystemMouseCursors.precise,
                },
                child: Container(
                  color: candidates.isNotEmpty
                      ? Colors.blue.withValues(alpha: 0.06)
                      : canvasBackground,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      // 도면 + 그리드 + 축 + 보정선
                      Positioned.fill(
                        child: CustomPaint(
                          painter: FloorPainter(
                            image: app.floorImage,
                            t: t,
                            calibP1: app.calibP1,
                            calibP2: app.calibP2,
                          ),
                        ),
                      ),
                      // 실물 사진 레이어 (마커 아래 · 월드 스케일 · 회전 반영)
                      if (app.showLocatorPhoto && LocatorImages.loaded)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _LocatorPhotoPainter(app: app),
                            ),
                          ),
                        ),
                      // 반사면 마스크 부채꼴 (마커 아래)
                      if (app.placements.any((p) => p.maskFaces.isNotEmpty))
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _MaskFacePainter(app: app),
                            ),
                          ),
                        ),
                      // 로케이터 마커
                      for (final p in app.placements)
                        _positionedMarker(context, app, p),
                      // 모드 안내 배너
                      if (app.canvasMode != CanvasMode.normal)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _modeBanner(context, app),
                        ),
                      // 좌하단 상태 표시
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: _scaleInfo(app),
                      ),
                      // 우하단 fit 버튼
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: FloatingActionButton.small(
                          heroTag: 'fit',
                          tooltip: '도면 맞춤',
                          onPressed: () => app.fitImage(canvasSize),
                          child: const Icon(Icons.fit_screen),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _positionedMarker(
      BuildContext context, AppState app, PlacedLocator placement) {
    final t = app.transform;
    final screen = t.worldToScreen(
        Offset(placement.coordinate.x, placement.coordinate.y));
    return Positioned(
      left: screen.dx - LocatorMarker.size / 2,
      top: screen.dy - LocatorMarker.size / 2,
      child: LocatorMarker(
        placement: placement,
        selected: app.selectedLocatorId == placement.locatorId,
        onTap: () => app.selectLocator(placement.locatorId),
        onDragBy: (screenDelta) {
          final current = t.worldToScreen(
              Offset(placement.coordinate.x, placement.coordinate.y));
          app.moveLocator(
              placement.locatorId, t.screenToWorld(current + screenDelta));
        },
      ),
    );
  }

  Widget _modeBanner(BuildContext context, AppState app) {
    final text = switch (app.canvasMode) {
      CanvasMode.calibrateP1 => '스케일 보정: 첫 번째 점을 클릭하세요',
      CanvasMode.calibrateP2 => '스케일 보정: 두 번째 점을 클릭하세요',
      CanvasMode.setOrigin => '원점(0,0)으로 사용할 위치를 클릭하세요',
      CanvasMode.adjustImage => '도면 조정: 드래그=도면 이동 · 휠=도면 크기 (배치는 고정)',
      CanvasMode.normal => '',
    };
    return Material(
      color: Colors.orange.shade100,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app, size: 16),
            const SizedBox(width: 6),
            Text(text),
            const SizedBox(width: 10),
            InkWell(
              onTap: () => app.setCanvasMode(CanvasMode.normal),
              child: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scaleInfo(AppState app) {
    final mpp = app.transform.metersPerPixel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '스케일: ${mpp.toStringAsFixed(4)} m/px   '
        '배치: ${app.placements.length}개',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Future<void> _askCalibrationDistance(BuildContext context) async {
    final app = context.read<AppState>();
    final controller = TextEditingController(
        text: app.calibDistanceM?.toString() ?? '');
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('두 점 사이의 실제 거리'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '거리 (m)',
            hintText: '예: 5.0',
          ),
          onSubmitted: (v) =>
              Navigator.of(context).pop(double.tryParse(v.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context)
                .pop(double.tryParse(controller.text.trim())),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    if (result != null && result > 0) {
      app.applyCalibration(result);
    }
  }
}

/// Top 뷰의 실물 사진 레이어 — 배치된 로케이터 자리에 사진을
/// 월드 스케일(0.5m)·설치 회전 반영으로 그린다 (마커 아래 · 입력 무시).
/// 천장 설치(아래를 봄) = 뒷면(back) · 바닥 설치(위를 봄) = 앞면(front).
class _LocatorPhotoPainter extends CustomPainter {
  final AppState app;

  _LocatorPhotoPainter({required this.app});

  @override
  void paint(Canvas canvas, Size size) {
    final t = app.transform;
    for (final p in app.placements) {
      final rot = _euler(p.orientation.x, p.orientation.y, p.orientation.z);
      // 법선 z (R * (0,0,1)) — 아래를 보면 back, 위를 보면 front
      final nz = rot[8];
      // 벽·경사 설치: 사진으로는 세운 모양이 안 보여 세운 케이스 그림으로
      final mesh = CaseMesh.instance;
      if (nz.abs() < 0.7 && mesh != null) {
        drawCaseMeshIcon2d(canvas, mesh,
            rot: rot,
            meshRot: CaseMesh.drawRotation(
              p.orientation.x, p.orientation.y, p.orientation.z,
              flip: p.imageFlip),
            cx: p.coordinate.x,
            cy: p.coordinate.y,
            toScreen: t.worldToScreen,
            color: const Color(0xFFB9C3CD),
            // 사진과 같은 월드 크기(0.5 m) — 줌에 따라 도면과 함께 커지고 작아짐
            widthPx: 0.5 / t.metersPerPixel * t.zoom,
            lift: 17 + 0.25 / t.metersPerPixel * t.zoom); // 마커(34px) 위로
        continue;
      }
      final img = nz < 0 ? LocatorImages.back : LocatorImages.front;
      if (img == null) continue;

      final center =
          t.worldToScreen(Offset(p.coordinate.x, p.coordinate.y));
      // 보드 +x (R * (1,0,0))의 화면 방향각
      final xw = Offset(rot[0], rot[3]);
      final tip = t.worldToScreen(
          Offset(p.coordinate.x + xw.dx, p.coordinate.y + xw.dy));
      final ang = math.atan2(tip.dy - center.dy, tip.dx - center.dx);

      final sizePx = 0.5 / t.metersPerPixel * t.zoom;
      LocatorImages.drawRotated(
          canvas, img, center, sizePx, ang + (p.imageFlip ? math.pi : 0));
    }
  }

  /// Rz·Ry·Rx (도) — placement_3d_view의 _rotEulerDeg와 동일 규약.
  static List<double> _euler(double xDeg, double yDeg, double zDeg) {
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

  @override
  bool shouldRepaint(covariant _LocatorPhotoPainter old) => true;
}

/// 반사면 마스크로 고른 면(도면 방향 ±80°)을 로케이터 주변에 빨간 부채꼴로 그린다.
class _MaskFacePainter extends CustomPainter {
  final AppState app;
  _MaskFacePainter({required this.app});

  @override
  void paint(Canvas canvas, Size size) {
    final t = app.transform;
    final fill = Paint()..color = Colors.red.withValues(alpha: 0.16);
    final edge = Paint()
      ..color = Colors.red.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final p in app.placements) {
      if (p.maskFaces.isEmpty) continue;
      final c = Offset(p.coordinate.x, p.coordinate.y);
      final cs = t.worldToScreen(c);
      final radius = (1.2 / t.metersPerPixel * t.zoom).clamp(28.0, 140.0);
      for (final f in p.maskFaces) {
        final mid = MaskFaces.faces[f];
        if (mid == null) continue;
        // 월드 방위 → 화면 각도 (화면 y축은 도면 변환에 따라 뒤집힐 수 있음)
        double screenAngle(double worldDeg) {
          final r = worldDeg * math.pi / 180;
          final s = t.worldToScreen(c + Offset(math.cos(r), math.sin(r)));
          return math.atan2(s.dy - cs.dy, s.dx - cs.dx);
        }

        final a0 = screenAngle(mid - MaskFaces.halfWidth);
        final a1 = screenAngle(mid + MaskFaces.halfWidth);
        // a0 → a1 호 중 중앙 방향(am)을 지나는 쪽으로 그린다
        double norm(double a) => (a + 3 * math.pi) % (2 * math.pi) - math.pi;
        final am = screenAngle(mid);
        var sweep = norm(a1 - a0);
        final d = norm(am - a0);
        final onArc = sweep >= 0 ? (d >= 0 && d <= sweep) : (d <= 0 && d >= sweep);
        if (!onArc) sweep = sweep >= 0 ? sweep - 2 * math.pi : sweep + 2 * math.pi;
        final rect = Rect.fromCircle(center: cs, radius: radius);
        final path = Path()
          ..moveTo(cs.dx, cs.dy)
          ..arcTo(rect, a0, sweep, false)
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, edge);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaskFacePainter old) => true;
}
