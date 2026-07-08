import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/placement.dart';
import '../state/app_state.dart';
import 'form_widgets.dart';

const _aoxModes = [
  'SL_RTL_AOD_MODE_REAL_TIME_FAST_RESPONSE',
  'SL_RTL_AOD_MODE_REAL_TIME_BASIC',
  'SL_RTL_AOX_MODE_REAL_TIME_BASIC',
  'SL_RTL_AOX_MODE_REAL_HIGH_ACCURACY',
];

const _antennaModes = [
  'SL_RTL_AOX_ARRAY_TYPE_4x4_URA',
  'SL_RTL_AOX_ARRAY_TYPE_3x3_URA',
  'SL_RTL_AOX_ARRAY_TYPE_1x4_ULA',
];

const _cteModes = ['SILABS', 'CONNLESS', 'CONN'];

/// 선택된 로케이터의 설정 폼: 좌표, 자세, AoA config.
class LocatorSettingsForm extends StatelessWidget {
  final PlacedLocator placement;

  const LocatorSettingsForm({super.key, required this.placement});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = placement;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            const Icon(Icons.settings_input_antenna, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.deviceName.isEmpty ? '(이름 없음)' : p.deviceName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  SelectableText(p.locatorId,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                  if (p.ip.isNotEmpty)
                    Text(p.ip,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 24),

        // ---- 좌표 ----
        const Text('좌표 (m)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: NumField(
            label: 'X',
            value: p.coordinate.x,
            onChanged: (v) {
              p.coordinate.x = v;
              app.placementEdited();
            },
          )),
          const SizedBox(width: 6),
          Expanded(
              child: NumField(
            label: 'Y',
            value: p.coordinate.y,
            onChanged: (v) {
              p.coordinate.y = v;
              app.placementEdited();
            },
          )),
          const SizedBox(width: 6),
          Expanded(
              child: NumField(
            label: 'Z (높이)',
            value: p.coordinate.z,
            onChanged: (v) {
              p.coordinate.z = v;
              app.placementEdited();
            },
          )),
        ]),
        const SizedBox(height: 16),

        // ---- 자세 ----
        const Text('자세 (Euler °)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: NumField(
            label: 'X',
            value: p.orientation.x,
            fractionDigits: 0,
            onChanged: (v) {
              p.orientation.x = v;
              app.placementEdited();
            },
          )),
          const SizedBox(width: 6),
          Expanded(
              child: NumField(
            label: 'Y',
            value: p.orientation.y,
            fractionDigits: 0,
            onChanged: (v) {
              p.orientation.y = v;
              app.placementEdited();
            },
          )),
          const SizedBox(width: 6),
          Expanded(
              child: NumField(
            label: 'Z',
            value: p.orientation.z,
            fractionDigits: 0,
            onChanged: (v) {
              p.orientation.z = v;
              app.placementEdited();
            },
          )),
        ]),
        const SizedBox(height: 8),
        Text(
          '천장 설치(안테나가 아래를 향함) 기본값: X=0, Y=180, Z=90',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),

        // ---- AoA config ----
        ExpansionTile(
          title: const Text('AoA 상세 설정',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            SafeDropdown(
              label: 'aoxMode',
              value: p.config['aoxMode']?.toString() ?? _aoxModes.first,
              options: _aoxModes,
              onChanged: (v) => _setConfig(app, 'aoxMode', v),
            ),
            const SizedBox(height: 8),
            SafeDropdown(
              label: 'antennaMode',
              value:
                  p.config['antennaMode']?.toString() ?? _antennaModes.first,
              options: _antennaModes,
              onChanged: (v) => _setConfig(app, 'antennaMode', v),
            ),
            const SizedBox(height: 8),
            SafeDropdown(
              label: 'cteMode',
              value: p.config['cteMode']?.toString() ?? _cteModes.first,
              options: _cteModes,
              onChanged: (v) => _setConfig(app, 'cteMode', v),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('angleFiltering', style: TextStyle(fontSize: 13)),
              value: p.config['angleFiltering'] == true,
              onChanged: (v) => _setConfig(app, 'angleFiltering', v),
            ),
            NumField(
              label: 'angleFilteringWeight',
              value: _num(p.config['angleFilteringWeight'], 0.6),
              onChanged: (v) => _setConfig(app, 'angleFilteringWeight', v),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: NumField(
                label: 'cteLength',
                value: _num(p.config['cteLength'], 160),
                fractionDigits: 0,
                onChanged: (v) =>
                    _setConfig(app, 'cteLength', v.toInt()),
              )),
              const SizedBox(width: 6),
              Expanded(
                  child: NumField(
                label: 'cteSamplingInterval',
                value: _num(p.config['cteSamplingInterval'], 1),
                fractionDigits: 0,
                onChanged: (v) =>
                    _setConfig(app, 'cteSamplingInterval', v.toInt()),
              )),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: NumField(
                label: 'periodSamples',
                value: _num(p.config['periodSamples'], 64),
                fractionDigits: 0,
                onChanged: (v) =>
                    _setConfig(app, 'periodSamples', v.toInt()),
              )),
              const SizedBox(width: 6),
              Expanded(
                  child: NumField(
                label: 'slotDuration',
                value: _num(p.config['slotDuration'], 1),
                fractionDigits: 0,
                onChanged: (v) =>
                    _setConfig(app, 'slotDuration', v.toInt()),
              )),
            ]),
          ],
        ),
        const SizedBox(height: 16),

        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => app.removePlacement(p.locatorId),
          icon: const Icon(Icons.delete_outline),
          label: const Text('캔버스에서 제거'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => app.selectLocator(null),
          child: const Text('선택 해제 (전역 설정 보기)'),
        ),
      ],
    );
  }

  void _setConfig(AppState app, String key, Object? value) {
    placement.config[key] = value;
    app.placementEdited();
  }

  static double _num(Object? v, double fallback) =>
      v is num ? v.toDouble() : fallback;
}
