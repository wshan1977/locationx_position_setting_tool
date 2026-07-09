import 'package:flutter/material.dart';

/// 설정 변경 전 확인용 비밀번호 (보안이 아니라 경각심 용도).
const String settingsPassword = '1234';

/// 설정 변경 확인 다이얼로그: 비밀번호가 맞으면 true를 반환한다.
/// [action]은 어떤 작업인지 표시용 (예: '서버로 전송').
Future<bool> confirmSettingsPassword(
    BuildContext context, String action) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      String? error;
      return StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            if (controller.text == settingsPassword) {
              Navigator.pop(context, true);
            } else {
              setState(() => error = '비밀번호가 올바르지 않습니다');
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                const Text('설정 변경 확인'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('[$action] 작업은 운영 중인 시스템 동작에 영향을 줍니다.\n'
                    '계속하려면 비밀번호를 입력하세요.'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(onPressed: submit, child: const Text('확인')),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return ok == true;
}
