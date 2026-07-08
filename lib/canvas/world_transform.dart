import 'dart:ui';

/// 3개 좌표계 간 순수 변환.
/// - world: 미터 단위, y-up. positioning_config.json에 저장되는 값.
/// - image px: 도면 이미지 픽셀, y-down.
/// - screen px: 캔버스 위젯 픽셀 (팬/줌 적용 후).
class WorldTransform {
  /// 이미지 1px 당 미터
  final double metersPerPixel;

  /// world 원점의 이미지 px 위치
  final Offset originPx;

  /// 이미지 px → 스크린 px 배율
  final double zoom;

  /// 스크린 팬 오프셋
  final Offset panPx;

  const WorldTransform({
    this.metersPerPixel = 0.05,
    this.originPx = Offset.zero,
    this.zoom = 1.0,
    this.panPx = Offset.zero,
  });

  WorldTransform copyWith({
    double? metersPerPixel,
    Offset? originPx,
    double? zoom,
    Offset? panPx,
  }) =>
      WorldTransform(
        metersPerPixel: metersPerPixel ?? this.metersPerPixel,
        originPx: originPx ?? this.originPx,
        zoom: zoom ?? this.zoom,
        panPx: panPx ?? this.panPx,
      );

  Offset worldToImage(Offset world) => Offset(
        originPx.dx + world.dx / metersPerPixel,
        originPx.dy - world.dy / metersPerPixel,
      );

  Offset imageToWorld(Offset imagePx) => Offset(
        (imagePx.dx - originPx.dx) * metersPerPixel,
        -(imagePx.dy - originPx.dy) * metersPerPixel,
      );

  Offset imageToScreen(Offset imagePx) => imagePx * zoom + panPx;

  Offset screenToImage(Offset screenPx) => (screenPx - panPx) / zoom;

  Offset worldToScreen(Offset world) => imageToScreen(worldToImage(world));

  Offset screenToWorld(Offset screenPx) => imageToWorld(screenToImage(screenPx));

  /// 커서 위치를 고정한 채 줌 배율을 바꾼 새 변환.
  WorldTransform zoomAt(Offset screenFocus, double newZoom) {
    final clamped = newZoom.clamp(0.02, 50.0);
    final imageFocus = screenToImage(screenFocus);
    return copyWith(
      zoom: clamped,
      panPx: screenFocus - imageFocus * clamped,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WorldTransform &&
      other.metersPerPixel == metersPerPixel &&
      other.originPx == originPx &&
      other.zoom == zoom &&
      other.panPx == panPx;

  @override
  int get hashCode => Object.hash(metersPerPixel, originPx, zoom, panPx);
}
