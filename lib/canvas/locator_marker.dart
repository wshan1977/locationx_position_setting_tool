import 'package:flutter/material.dart';

import '../models/placement.dart';

/// 캔버스 위 로케이터 마커. 스크린 크기 고정(줌 무관).
class LocatorMarker extends StatelessWidget {
  static const double size = 34;

  final PlacedLocator placement;
  final bool selected;
  final VoidCallback onTap;
  final void Function(Offset screenDelta) onDragBy;

  const LocatorMarker({
    super.key,
    required this.placement,
    required this.selected,
    required this.onTap,
    required this.onDragBy,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.orange : Colors.blue;
    return GestureDetector(
      onTap: onTap,
      onPanStart: (_) => onTap(),
      onPanUpdate: (d) => onDragBy(d.delta),
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? Colors.deepOrange : Colors.blue.shade900,
                    width: 2),
                boxShadow: const [
                  BoxShadow(blurRadius: 3, color: Colors.black38),
                ],
              ),
              child: const Icon(Icons.settings_input_antenna,
                  size: 18, color: Colors.white),
            ),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                placement.shortId,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color.shade900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
