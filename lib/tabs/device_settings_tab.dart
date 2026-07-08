import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/discovered_device.dart';
import '../services/udp_control_service.dart';
import '../state/app_state.dart';

/// 탭 1: AOA Locator 장치 설정.
/// 좌측 카드 목록에서 장치를 선택하면 우측에서
/// MQTT 브로커 설정(UDP MQTT_SET) / 서비스 재시작 / 재부팅 / LED 식별을 수행한다.
class DeviceSettingsTab extends StatefulWidget {
  const DeviceSettingsTab({super.key});

  @override
  State<DeviceSettingsTab> createState() => _DeviceSettingsTabState();
}

class _DeviceSettingsTabState extends State<DeviceSettingsTab> {
  final _control = const UdpControlService();
  String? _selectedKey;
  bool _busy = false;

  DiscoveredDevice? _selected(AppState app) =>
      app.devices.where((d) => d.dedupeKey == _selectedKey).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final selected = _selected(app);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 340, child: _deviceList(app)),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? Center(
                  child: Text('좌측에서 장치를 선택하세요.',
                      style: TextStyle(color: Colors.grey.shade600)),
                )
              : _detailPanel(app, selected),
        ),
      ],
    );
  }

  // =========================================================
  // 좌측: 장치 목록
  // =========================================================
  Widget _deviceList(AppState app) {
    final servers = app.devices.where((d) => d.isServer).toList();
    final locators = app.devices.where((d) => !d.isServer).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton.icon(
            onPressed: app.scanning ? null : () => app.scan(),
            icon: app.scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar),
            label: Text(app.scanning ? '검색 중...' : '장치 검색 (UDP)'),
          ),
        ),
        Expanded(
          child: app.devices.isEmpty
              ? Center(
                  child: Text(
                    app.scanning ? '' : '검색된 카드가 없습니다.\n[장치 검색]을 눌러주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    if (servers.isNotEmpty) _sectionTitle('MQTT 서버'),
                    for (final d in servers) _deviceTile(app, d),
                    _sectionTitle('로케이터 (${locators.length})'),
                    for (final d in locators) _deviceTile(app, d),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
      );

  Widget _deviceTile(AppState app, DiscoveredDevice d) {
    final isSelected = d.dedupeKey == _selectedKey;
    final isTargetServer = d.isServer && app.serverIp == d.ip;
    return Card(
      color: isSelected ? Colors.teal.shade50 : null,
      child: ListTile(
        dense: true,
        selected: isSelected,
        leading: Icon(
          d.isServer ? Icons.dns : Icons.settings_input_antenna,
          color: d.isServer
              ? Colors.teal
              : (d.hasValidMac ? Colors.blue : Colors.red),
        ),
        title: Text(d.device,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${d.ip}\nver ${d.ver}'),
        isThreeLine: true,
        trailing: isTargetServer
            ? const Chip(
                label: Text('대상', style: TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
              )
            : null,
        onTap: () => setState(() => _selectedKey = d.dedupeKey),
      ),
    );
  }

  // =========================================================
  // 우측: 선택 장치 상세
  // =========================================================
  Widget _detailPanel(AppState app, DiscoveredDevice d) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(d.isServer ? Icons.dns : Icons.settings_input_antenna,
                    color: d.isServer ? Colors.teal : Colors.blue, size: 28),
                const SizedBox(width: 10),
                Text(d.device,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                Chip(
                  label: Text(d.isServer ? 'MQTT 서버 카드' : '로케이터 카드',
                      style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoCard(d),
            const SizedBox(height: 16),
            if (d.isServer) _serverActions(app, d) else _locatorActions(app, d),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(DiscoveredDevice d) {
    final rows = <(String, String)>[
      ('IP', d.ip),
      ('MAC', d.mac),
      ('모델', d.model),
      ('에이전트 버전', d.ver),
      if (!d.isServer) ('로케이터 ID', d.hasValidMac ? d.locatorId : 'MAC 오류'),
      if (d.mqttHost != null)
        ('현재 MQTT 브로커', '${d.mqttHost}:${d.mqttPort ?? '-'}'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                        width: 130,
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600))),
                    Expanded(
                        child: SelectableText(value,
                            style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 서버 카드 ----
  Widget _serverActions(AppState app, DiscoveredDevice d) {
    final isTarget = app.serverIp == d.ip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('서버 카드 관리', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: isTarget ? null : () => app.setServerIp(d.ip),
              icon: const Icon(Icons.gps_fixed),
              label: Text(isTarget ? '현재 대상 서버' : '대상 서버로 선택'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openUrl('http://${d.ip}:8080'),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('웹 설정 페이지 열기 (:8080)'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '이 카드에서 mosquitto MQTT 브로커(기본 포트 1883)와 positioning 서비스가 구동됩니다.\n'
          '위치 설정은 [위치 설정] 탭에서, MQTT 수신 확인은 [데이터 수신]·[MQTT 뷰어] 탭에서 합니다.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  // ---- 로케이터 카드 ----
  Widget _locatorActions(AppState app, DiscoveredDevice d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MQTT 브로커 설정', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _MqttSetForm(
          key: ValueKey('mqtt-${d.dedupeKey}'),
          initialHost: d.mqttHost ?? app.serverIp,
          initialPort: d.mqttPort ?? 1883,
          busy: _busy,
          onSubmit: (host, port) => _doSetMqtt(d, host, port),
        ),
        const SizedBox(height: 20),
        Text('장치 제어', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _doLedBlink(d),
              icon: const Icon(Icons.lightbulb),
              label: const Text('LED 식별 (8초 점멸)'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _doRestartService(d),
              icon: const Icon(Icons.restart_alt),
              label: const Text('AOA 서비스 재시작'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _doReboot(d),
              icon: const Icon(Icons.power_settings_new),
              label: const Text('재부팅'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'MQTT 브로커 설정을 바꾼 뒤에는 AOA 서비스 재시작(또는 재부팅)을 해야 적용됩니다.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  // =========================================================
  // 동작
  // =========================================================
  Future<void> _doSetMqtt(DiscoveredDevice d, String host, int port) async {
    setState(() => _busy = true);
    try {
      final resp = await _control.setMqtt(
          targetIp: d.ip, brokerHost: host, brokerPort: port);
      if (!mounted) return;
      if (resp['ok'] == true) {
        _snack('MQTT 브로커 설정 저장됨 ($host:$port)');
        final restart = await _confirm(
            'AOA 서비스 재시작', '설정을 적용하려면 AOA 서비스를 재시작해야 합니다.\n지금 재시작할까요?');
        if (restart == true) await _doRestartService(d, quiet: false);
        // 목록의 mqtt 표기 갱신
        if (mounted) context.read<AppState>().scan();
      } else {
        _snack('설정 실패: ${resp['error'] ?? '알 수 없는 오류'}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doRestartService(DiscoveredDevice d, {bool quiet = false}) async {
    setState(() => _busy = true);
    try {
      final resp = await _control.restartService(targetIp: d.ip);
      if (!mounted) return;
      if (resp['ok'] == true) {
        _snack('AOA 서비스 재시작 완료');
      } else {
        _snack('재시작 실패: ${resp['error'] ?? resp['rc'] ?? '알 수 없는 오류'}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doReboot(DiscoveredDevice d) async {
    final ok = await _confirm('재부팅', '${d.device} (${d.ip}) 카드를 재부팅할까요?');
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final resp = await _control.reboot(targetIp: d.ip);
      if (!mounted) return;
      if (resp['ok'] == true) {
        _snack('재부팅 명령 전송됨 — 카드가 다시 켜질 때까지 1~2분 걸립니다');
      } else {
        _snack('재부팅 실패: ${resp['error'] ?? '알 수 없는 오류'}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doLedBlink(DiscoveredDevice d) async {
    await _control.ledBlink(targetIp: d.ip);
    _snack('LED 점멸 전송 — 카드의 LED를 확인하세요');
  }

  void _openUrl(String url) {
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', url]);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool?> _confirm(String title, String body) {
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
}

/// MQTT 브로커 host/port 입력 폼.
class _MqttSetForm extends StatefulWidget {
  final String initialHost;
  final int initialPort;
  final bool busy;
  final void Function(String host, int port) onSubmit;

  const _MqttSetForm({
    super.key,
    required this.initialHost,
    required this.initialPort,
    required this.busy,
    required this.onSubmit,
  });

  @override
  State<_MqttSetForm> createState() => _MqttSetFormState();
}

class _MqttSetFormState extends State<_MqttSetForm> {
  late final TextEditingController _host =
      TextEditingController(text: widget.initialHost);
  late final TextEditingController _port =
      TextEditingController(text: widget.initialPort.toString());

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: '브로커 호스트 (보통 서버 카드 IP)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
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
        FilledButton(
          onPressed: widget.busy
              ? null
              : () {
                  final host = _host.text.trim();
                  final port = int.tryParse(_port.text.trim());
                  if (host.isEmpty || port == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('호스트/포트를 올바르게 입력하세요')));
                    return;
                  }
                  widget.onSubmit(host, port);
                },
          child: const Text('전송'),
        ),
      ],
    );
  }
}
