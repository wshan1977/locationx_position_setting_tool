import 'package:flutter/material.dart';

/// 탭 상단의 한 줄 작업 안내 배너.
/// 현장 작업자가 각 탭에서 무엇을 어떤 순서로 하는지 바로 알 수 있게
/// 모든 탭이 같은 톤(아이콘 + 옅은 배경 + 작은 글씨)으로 표시한다.
class TabGuide extends StatelessWidget {
  final IconData icon;
  final String text;

  const TabGuide({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.primaryContainer.withValues(alpha: 0.30),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
