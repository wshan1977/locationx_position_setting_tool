import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/placement.dart';
import '../services/udp_control_service.dart';
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
        const SizedBox(height: 8),

        // ---- 설정 그룹: MQTT 브로커 (좌표/자세/AoA와 같은 "설정" 성격) ----
        _MqttBrokerSection(
          key: ValueKey('mqtt-${p.locatorId}'),
          placement: p,
        ),

        // ---- 제어 그룹: 카드에 즉시 실행되는 명령 (설정과 구분) ----
        const Divider(height: 28),
        Row(
          children: [
            Icon(Icons.gamepad_outlined, size: 16, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            const Text('장치 제어', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text('카드에 즉시 실행되는 명령입니다 (저장/전송과 무관).',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        _DeviceControlButtons(
          key: ValueKey('ctrl-${p.locatorId}'),
          placement: p,
        ),

        const Divider(height: 28),
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

/// 검색 결과 우선, 없으면 배치에 저장된 IP.
String _resolvePlacementIp(AppState app, PlacedLocator placement) {
  final live = app.devices
      .where((d) =>
          !d.isServer && d.hasValidMac && d.locatorId == placement.locatorId)
      .firstOrNull;
  return live?.ip ?? placement.ip;
}

Widget _noIpHint() => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '카드 IP를 알 수 없습니다. [카드 검색]으로 이 로케이터가 검색되면 사용할 수 있습니다.',
        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
      ),
    );

void _controlSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool?> _controlConfirm(BuildContext context, String title, String body) {
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
            child: const Text('확인')),
      ],
    ),
  );
}

Future<void> _restartAoaService(
    BuildContext context, UdpControlService control, String ip) async {
  final resp = await control.restartService(targetIp: ip);
  if (!context.mounted) return;
  _controlSnack(
      context,
      resp['ok'] == true
          ? 'AOA 서비스 재시작 완료'
          : '재시작 실패: ${resp['error'] ?? resp['rc'] ?? '알 수 없는 오류'}');
}

/// 설정 그룹: 카드의 MQTT 브로커 설정 (UDP MQTT_SET).
class _MqttBrokerSection extends StatefulWidget {
  final PlacedLocator placement;

  const _MqttBrokerSection({super.key, required this.placement});

  @override
  State<_MqttBrokerSection> createState() => _MqttBrokerSectionState();
}

class _MqttBrokerSectionState extends State<_MqttBrokerSection> {
  final _control = const UdpControlService();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '1883');
  bool _busy = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ip = _resolvePlacementIp(app, widget.placement);

    if (!_prefilled) {
      _prefilled = true;
      final live = app.devices
          .where((d) => d.locatorId == widget.placement.locatorId)
          .firstOrNull;
      _host.text = live?.mqttHost ?? app.serverIp;
      if (live?.mqttPort != null) _port.text = live!.mqttPort.toString();
    }

    return ExpansionTile(
      title: const Text('MQTT 브로커 설정',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        if (ip.isEmpty)
          _noIpHint()
        else ...[
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: '브로커 호스트 (보통 서버 카드 IP)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
              width: 90,
              child: TextField(
                controller: _port,
                decoration: const InputDecoration(
                  labelText: '포트',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _doSetMqtt(ip),
                icon: const Icon(Icons.send, size: 16),
                label: const Text('카드에 전송'),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text('전송 후 AOA 서비스 재시작(또는 재부팅)해야 적용됩니다.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ],
    );
  }

  Future<void> _doSetMqtt(String ip) async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null) {
      _controlSnack(context, '호스트/포트를 올바르게 입력하세요');
      return;
    }
    setState(() => _busy = true);
    try {
      final resp = await _control.setMqtt(
          targetIp: ip, brokerHost: host, brokerPort: port);
      if (!mounted) return;
      if (resp['ok'] == true) {
        _controlSnack(context, 'MQTT 브로커 설정 저장됨 ($host:$port)');
        final restart = await _controlConfirm(context, 'AOA 서비스 재시작',
            '설정을 적용하려면 AOA 서비스를 재시작해야 합니다.\n지금 재시작할까요?');
        if (restart == true && mounted) {
          await _restartAoaService(context, _control, ip);
        }
      } else {
        _controlSnack(context, '설정 실패: ${resp['error'] ?? '알 수 없는 오류'}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// 제어 그룹: 카드에 즉시 실행되는 명령 (LED 식별 / 서비스 재시작 / 재부팅).
class _DeviceControlButtons extends StatefulWidget {
  final PlacedLocator placement;

  const _DeviceControlButtons({super.key, required this.placement});

  @override
  State<_DeviceControlButtons> createState() => _DeviceControlButtonsState();
}

class _DeviceControlButtonsState extends State<_DeviceControlButtons> {
  final _control = const UdpControlService();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ip = _resolvePlacementIp(app, widget.placement);
    if (ip.isEmpty) return _noIpHint();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _doLed(ip),
          icon: const Icon(Icons.lightbulb, size: 16),
          label: const Text('LED 식별', style: TextStyle(fontSize: 12)),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _doRestart(ip),
          icon: const Icon(Icons.restart_alt, size: 16),
          label: const Text('AOA 서비스 재시작', style: TextStyle(fontSize: 12)),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _doReboot(ip),
          icon: const Icon(Icons.power_settings_new, size: 16),
          label: const Text('재부팅', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Future<void> _doRestart(String ip) async {
    setState(() => _busy = true);
    try {
      await _restartAoaService(context, _control, ip);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doReboot(String ip) async {
    final ok = await _controlConfirm(
        context, '재부팅', '${widget.placement.locatorId} ($ip) 카드를 재부팅할까요?');
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final resp = await _control.reboot(targetIp: ip);
      if (!mounted) return;
      _controlSnack(
          context,
          resp['ok'] == true
              ? '재부팅 명령 전송됨 — 카드가 다시 켜질 때까지 1~2분 걸립니다'
              : '재부팅 실패: ${resp['error'] ?? '알 수 없는 오류'}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doLed(String ip) async {
    await _control.ledBlink(targetIp: ip);
    if (mounted) _controlSnack(context, 'LED 점멸 전송 — 카드의 LED를 확인하세요');
  }
}
