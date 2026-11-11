import 'package:flutter/material.dart';

/// 로케이터 실물 프론트 이미지 아바타 — Locator 목록·상세 헤더 공용.
/// 에셋이 없는 빌드에서는 기존 안테나 아이콘으로 폴백한다.
class LocatorAvatar extends StatelessWidget {
  final double size;
  final Color? fallbackColor;

  /// 흐리게(배치됨·오프라인 등 비활성 표시).
  final bool dimmed;

  const LocatorAvatar(
      {super.key, this.size = 34, this.fallbackColor, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      'assets/images/locator_front.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.settings_input_antenna,
          size: size * 0.8, color: fallbackColor ?? Colors.blue),
    );
    return dimmed ? Opacity(opacity: 0.35, child: img) : img;
  }
}
