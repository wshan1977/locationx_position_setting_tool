import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'form_widgets.dart';

const _estimationModes = [
  'SL_RTL_LOC_ESTIMATION_MODE_THREE_DIM_HIGH_ACCURACY',
  'SL_RTL_LOC_ESTIMATION_MODE_THREE_DIM_FAST_RESPONSE',
  'SL_RTL_LOC_ESTIMATION_MODE_TWO_DIM_HIGH_ACCURACY',
  'SL_RTL_LOC_ESTIMATION_MODE_TWO_DIM_FAST_RESPONSE',
];

const _validationModes = [
  'SL_RTL_LOC_MEASUREMENT_VALIDATION_MINIMUM',
  'SL_RTL_LOC_MEASUREMENT_VALIDATION_MEDIUM',
  'SL_RTL_LOC_MEASUREMENT_VALIDATION_FULL',
];

/// 전역 positioning 설정 폼 (로케이터 미선택 시 표시).
class GlobalSettingsForm extends StatelessWidget {
  const GlobalSettingsForm({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final g = app.globals;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Row(children: [
          Icon(Icons.tune, color: Colors.teal),
          SizedBox(width: 8),
          Expanded(
            child: Text('전역 Positioning 설정',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('로케이터를 선택하면 개별 설정이 표시됩니다.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const Divider(height: 24),

        TextFormField(
          initialValue: g.id,
          decoration: const InputDecoration(
            labelText: 'ID (예: positioning-room-a)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) {
            g.id = v.trim();
            app.globalsEdited();
          },
        ),
        const SizedBox(height: 12),

        SafeDropdown(
          label: 'estimationModeLocation',
          value: g.estimationModeLocation,
          options: _estimationModes,
          onChanged: (v) {
            g.estimationModeLocation = v;
            app.globalsEdited();
          },
        ),
        const SizedBox(height: 12),

        SafeDropdown(
          label: 'validationModeLocation',
          value: g.validationModeLocation,
          options: _validationModes,
          onChanged: (v) {
            g.validationModeLocation = v;
            app.globalsEdited();
          },
        ),
        const SizedBox(height: 12),

        NumField(
          label: 'estimationIntervalSec',
          value: g.estimationIntervalSec,
          fractionDigits: 3,
          onChanged: (v) {
            g.estimationIntervalSec = v;
            app.globalsEdited();
          },
        ),
        const SizedBox(height: 12),

        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('locationFiltering', style: TextStyle(fontSize: 13)),
          value: g.locationFiltering,
          onChanged: (v) {
            g.locationFiltering = v;
            app.globalsEdited();
          },
        ),
        NumField(
          label: 'locationFilteringWeight',
          value: g.locationFilteringWeight,
          onChanged: (v) {
            g.locationFilteringWeight = v;
            app.globalsEdited();
          },
        ),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(
              child: NumField(
            label: 'numberOfSequenceIds',
            value: g.numberOfSequenceIds.toDouble(),
            fractionDigits: 0,
            onChanged: (v) {
              g.numberOfSequenceIds = v.toInt();
              app.globalsEdited();
            },
          )),
          const SizedBox(width: 6),
          Expanded(
              child: NumField(
            label: 'maximumSequenceIdDiffs',
            value: g.maximumSequenceIdDiffs.toDouble(),
            fractionDigits: 0,
            onChanged: (v) {
              g.maximumSequenceIdDiffs = v.toInt();
              app.globalsEdited();
            },
          )),
        ]),
        const Divider(height: 24),

        // ---- 서버 연결 ----
        const Text('서버 카드', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey('serverIp:${app.serverIp}'),
          initialValue: app.serverIp,
          decoration: const InputDecoration(
            labelText: '서버 IP (검색으로 자동 설정)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) => app.serverIp = v.trim(),
        ),
      ],
    );
  }
}
