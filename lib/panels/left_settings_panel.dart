import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'global_settings_form.dart';
import 'locator_settings_form.dart';

/// 설정 패널 (위치 설정 탭 오른쪽): 로케이터 선택 시 로케이터 설정, 아니면 전역 설정.
class LeftSettingsPanel extends StatelessWidget {
  const LeftSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final selected = app.selectedPlacement;

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
        color: Colors.grey.shade50,
      ),
      child: selected != null
          ? LocatorSettingsForm(
              key: ValueKey(selected.locatorId), placement: selected)
          : const GlobalSettingsForm(),
    );
  }
}
