import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/discovered_device.dart';
import '../models/placement.dart';
import '../state/app_state.dart';
import 'grid_painter.dart';
import 'locator_marker.dart';

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
                final factor = event.scrollDelta.dy > 0 ? 1 / 1.15 : 1.15;
                app.setTransform(
                    t.zoomAt(event.localPosition, t.zoom * factor));
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
                app.setTransform(t.copyWith(panPx: t.panPx + details.delta));
              },
              child: MouseRegion(
                cursor: app.canvasMode == CanvasMode.normal
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.precise,
                child: Container(
                  color: candidates.isNotEmpty
                      ? Colors.blue.withValues(alpha: 0.06)
                      : const Color(0xFFF4F6F8),
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
