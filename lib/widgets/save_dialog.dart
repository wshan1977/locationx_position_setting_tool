import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/positioning_config.dart';
import '../services/config_api_client.dart';
import '../state/app_state.dart';

/// 서버 전송 플로우:
/// 상태 확인 → 현재 config 조회 → 병합/diff 요약 → 저장 → (선택) 적용+재시작
Future<void> showPushToServerDialog(BuildContext context) async {
  final app = context.read<AppState>();

  if (app.serverIp.isEmpty) {
    _snack(context, '서버 IP가 없습니다. 장치 검색을 하거나 전역 설정에서 IP를 입력하세요.');
    return;
  }
  if (app.placements.isEmpty) {
    final proceed = await _confirm(context, '배치된 로케이터가 없습니다',
        '빈 locators 목록으로 서버 설정을 덮어씁니다. 계속할까요?');
    if (proceed != true) return;
  }

  final client = ConfigApiClient(app.serverIp);

  // 1) 연결 확인 + 2) 현재 설정 조회
  final PositioningConfig fetched;
  try {
    await client.status();
    fetched = await client.fetchPositioning();
  } on Exception catch (e) {
    if (context.mounted) {
      _snack(context, '서버 연결 실패 (${app.serverIp}:8080): $e');
    }
    return;
  }

  // 3) 병합 + diff 요약
  final merged = app.mergeForPush(fetched);
  final oldIds = {for (final l in fetched.locators) l.id};
  final newIds = {for (final l in merged.locators) l.id};
  final added = newIds.difference(oldIds);
  final removed = oldIds.difference(newIds);
  final kept = newIds.intersection(oldIds);

  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('서버로 전송'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('대상: http://${app.serverIp}:8080'),
            const SizedBox(height: 12),
            _diffLine(Icons.add_circle, Colors.green, '추가', added),
            _diffLine(Icons.sync, Colors.blue, '갱신', kept),
            _diffLine(Icons.remove_circle, Colors.red, '삭제', removed),
            const SizedBox(height: 12),
            const Text(
              '캔버스의 배치가 서버 locators 전체를 대체합니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('전송')),
      ],
    ),
  );
  if (confirmed != true) return;

  // 4) 스테이징 저장
  try {
    final count = await client.pushPositioning(merged);
    if (context.mounted) {
      _snack(context, '스테이징 저장 완료 (로케이터 $count개)');
    }
  } on Exception catch (e) {
    if (context.mounted) _snack(context, '저장 실패: $e');
    return;
  }

  // 5) 적용 여부
  if (!context.mounted) return;
  var restart = true;
  final applyNow = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('서비스에 적용'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('스테이징 파일을 백업 후 서비스 경로에 복사합니다.'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('aoa-positioning 서비스 재시작'),
              value: restart,
              onChanged: (v) => setState(() => restart = v ?? true),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('나중에')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('지금 적용')),
        ],
      ),
    ),
  );
  if (applyNow != true) return;

  try {
    final result = await client.apply(restart: restart);
    if (!context.mounted) return;
    if (restart && !result.restarted) {
      _snack(
          context,
          '적용 완료 (백업: ${result.backupStamp}) — 서비스 재시작 실패. '
          'Pi에서 직접 실행하세요: sudo systemctl restart aoa-positioning');
    } else {
      _snack(context,
          '적용 완료 (백업: ${result.backupStamp}${result.restarted ? ', 서비스 재시작됨' : ''})');
    }
  } on Exception catch (e) {
    if (context.mounted) _snack(context, '적용 실패: $e');
  }
}

Widget _diffLine(IconData icon, Color color, String label, Set<String> ids) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label ${ids.length}개${ids.isEmpty ? '' : ': ${ids.join(', ')}'}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

Future<bool?> _confirm(BuildContext context, String title, String body) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('계속')),
      ],
    ),
  );
}
