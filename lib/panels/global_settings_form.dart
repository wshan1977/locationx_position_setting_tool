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
        Row(children: [
          Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('전역 Positioning 설정',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('로케이터를 선택하면 개별 설정이 표시됩니다.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const Divider(height: 24),

        _cfgTip(
          '이 위치인식 그룹의 식별자입니다.\n'
          'position 토픽 경로(silabs/aoa/position/<ID>/<태그>)에 그대로 들어갑니다.',
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
        ),
        const SizedBox(height: 12),

        _cfgTip(
          '위치 계산 알고리즘 모드입니다.\n'
          '· THREE_DIM: x·y·z 3차원 추정 (기본)\n'
          '· TWO_DIM: 태그 높이를 고정한 2차원 추정 — 로케이터가 적을 때 안정적\n'
          '· HIGH_ACCURACY: 정확하지만 느림 / FAST_RESPONSE: 빠르지만 노이즈에 민감',
          SafeDropdown(
            label: 'estimationModeLocation',
            value: g.estimationModeLocation,
            options: _estimationModes,
            onChanged: (v) {
              g.estimationModeLocation = v;
              app.globalsEdited();
            },
          ),
        ),
        const SizedBox(height: 12),

        _cfgTip(
          '각도 측정값 검증 강도입니다. 품질이 낮은 angle을 걸러냅니다.\n'
          '· MINIMUM: 검증 최소 — 대부분의 측정을 사용 (기본)\n'
          '· MEDIUM: 중간 수준 검증\n'
          '· FULL: 가장 엄격 — 반사/노이즈 환경에서 유리하지만 위치 갱신이 뜸해질 수 있음',
          SafeDropdown(
            label: 'validationModeLocation',
            value: g.validationModeLocation,
            options: _validationModes,
            onChanged: (v) {
              g.validationModeLocation = v;
              app.globalsEdited();
            },
          ),
        ),
        const SizedBox(height: 12),

        _cfgTip(
          '위치 계산(추정) 주기 (초)입니다. 기본 0.02 = 초당 50회.\n'
          '짧을수록 위치가 자주 갱신되지만 서버 계산량과 MQTT 트래픽이 늘어납니다.',
          NumField(
            label: 'estimationIntervalSec',
            value: g.estimationIntervalSec,
            fractionDigits: 3,
            onChanged: (v) {
              g.estimationIntervalSec = v;
              app.globalsEdited();
            },
          ),
        ),
        const SizedBox(height: 12),

        _cfgTip(
          '위치 필터링(스무딩) 사용 여부입니다.\n'
          '켜면 위치 좌표의 떨림이 줄어 궤적이 부드러워지지만, 태그가 움직일 때 실제 위치를 늦게 따라갑니다.',
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title:
                const Text('locationFiltering', style: TextStyle(fontSize: 13)),
            value: g.locationFiltering,
            onChanged: (v) {
              g.locationFiltering = v;
              app.globalsEdited();
            },
          ),
        ),
        _cfgTip(
          '위치 필터 강도 (0~1)입니다. 기본 0.1.\n'
          '클수록 이전 위치를 많이 유지해 부드러워지지만 이동 반응이 느려집니다.',
          NumField(
            label: 'locationFilteringWeight',
            value: g.locationFilteringWeight,
            onChanged: (v) {
              g.locationFilteringWeight = v;
              app.globalsEdited();
            },
          ),
        ),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(
              child: _cfgTip(
            '추적하는 CTE 시퀀스 ID 개수입니다.\n'
            '여러 로케이터의 angle 측정을 같은 송신 시점끼리 묶는 데 사용합니다. 기본 6.',
            NumField(
              label: 'numberOfSequenceIds',
              value: g.numberOfSequenceIds.toDouble(),
              fractionDigits: 0,
              onChanged: (v) {
                g.numberOfSequenceIds = v.toInt();
                app.globalsEdited();
              },
            ),
          )),
          const SizedBox(width: 6),
          Expanded(
              child: _cfgTip(
            '측정끼리 묶을 때 허용하는 시퀀스 ID 차이의 최대값입니다.\n'
            '크게 하면 수신 시점이 어긋난 측정도 묶이지만 오래된 측정이 섞일 수 있습니다. 기본 20.',
            NumField(
              label: 'maximumSequenceIdDiffs',
              value: g.maximumSequenceIdDiffs.toDouble(),
              fractionDigits: 0,
              onChanged: (v) {
                g.maximumSequenceIdDiffs = v.toInt();
                app.globalsEdited();
              },
            ),
          )),
        ]),
        const Divider(height: 24),

        // ---- 서버 연결 ----
        const Text('서버 카드', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _cfgTip(
          '설정을 전송할 MQTT 서버 카드의 IP입니다.\n'
          '[Locator 검색]으로 서버 카드가 발견되면 자동으로 채워집니다.',
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
        ),
      ],
    );
  }

  /// 설정 항목 설명 툴팁: 마우스를 1초쯤 올리고 있으면 표시된다.
  Widget _cfgTip(String message, Widget child) => Tooltip(
        message: message,
        waitDuration: const Duration(seconds: 1),
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
        child: child,
      );
}
