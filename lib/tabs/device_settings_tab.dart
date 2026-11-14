import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/discovered_device.dart';
import '../services/config_api_client.dart';
import '../services/deploy_service.dart';
import '../services/udp_control_service.dart';
import '../widgets/cloud_config_form.dart';
import '../widgets/update_flow.dart';
import '../widgets/hover_tip.dart';
import '../widgets/locator_avatar.dart';
import '../widgets/password_gate.dart';
import '../widgets/tab_guide.dart';
import '../widgets/topic_root_section.dart';
import '../state/app_state.dart';

/// 설정 › ① Locator 설정.
/// 좌측 카드 목록에서 Locator를 선택하면 우측에서
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabGuide(
          icon: Icons.tune,
          text:
              '작업 순서: ① [Locator 검색]으로 카드 찾기 → ② 왼쪽 목록에서 카드 선택 → '
              '③ 브로커 설정·서비스 재시작·재부팅·LED 식별·소프트웨어 업데이트 — '
              '서버 카드는 내부망/외부망 브로커를 각각 설정합니다',
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 340, child: _deviceList(app)),
              const VerticalDivider(width: 1),
              Expanded(
                child:
                    selected == null
                        ? Center(
                          child: Text(
                            '좌측에서 Locator를 선택하세요.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                        : _detailPanel(app, selected),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // 좌측: Locator 목록
  // =========================================================
  Widget _deviceList(AppState app) {
    final servers = app.devices.where((d) => d.isServer).toList();
    final locators = app.devices.where((d) => !d.isServer).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: hoverTip(
            'UDP 브로드캐스트(포트 40010)로 LAN의 서버/로케이터 카드를 검색합니다.',
            FilledButton.icon(
              onPressed: app.scanning ? null : () => app.scan(),
              icon:
                  app.scanning
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.radar),
              label: Text(app.scanning ? '검색 중...' : 'Locator 검색 (UDP)'),
            ),
          ),
        ),
        Expanded(
          child:
              app.devices.isEmpty
                  ? Center(
                    child: Text(
                      app.scanning ? '' : '검색된 카드가 없습니다.\n[Locator 검색]을 눌러주세요.',
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
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.grey,
      ),
    ),
  );

  Widget _deviceTile(AppState app, DiscoveredDevice d) {
    final isSelected = d.dedupeKey == _selectedKey;
    final isTargetServer = d.isServer && app.serverIp == d.ip;
    return Card(
      color: isSelected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
          : null,
      child: ListTile(
        dense: true,
        selected: isSelected,
        // 로케이터는 실물 프론트 사진으로 (MAC 오류 카드는 빨간 아이콘 유지)
        leading: d.isServer
            ? const Icon(Icons.dns, color: Colors.teal)
            : (d.hasValidMac
                ? const LocatorAvatar(size: 36)
                : const Icon(Icons.settings_input_antenna,
                    color: Colors.red)),
        title: Text(
          d.device,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${d.ip}\nver ${d.ver}'),
        isThreeLine: true,
        trailing:
            isTargetServer
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
  // 우측: 선택 Locator 상세
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
                if (d.isServer)
                  const Icon(Icons.dns, color: Colors.teal, size: 28)
                else
                  const LocatorAvatar(size: 34),
                const SizedBox(width: 10),
                Text(
                  d.device,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                Chip(
                  label: Text(
                    d.isServer ? 'MQTT 서버 카드' : '로케이터 카드',
                    style: const TextStyle(fontSize: 11),
                  ),
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
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        value,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 섹션을 카드로 묶어 시각적으로 구분한다 (제목 + 한 줄 설명 + 내용).
  Widget _sectionCard(
    IconData icon,
    String title,
    String? subtitle,
    Widget child,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 10),
            child,
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
        hoverTip(
          '이 카드를 설정 전송·MQTT 연결의 대상 서버로 지정합니다.',
          FilledButton.icon(
            onPressed: isTarget ? null : () => app.setServerIp(d.ip),
            icon: const Icon(Icons.gps_fixed),
            label: Text(isTarget ? '현재 대상 서버' : '대상 서버로 선택'),
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          Icons.lan,
          '내부망 MQTT 브로커 (positioning 서비스)',
          '로케이터 angle 수신·position 계산에 쓰는 현장 브로커 — 보통 localhost(이 카드)',
          _ServerMqttSection(
            key: ValueKey('server-mqtt-${d.dedupeKey}'),
            serverIp: d.ip,
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          Icons.topic,
          '고객용 토픽 이름',
          '고객 시스템이 구독하는 토픽의 맨 앞 이름 — 업체·데모마다 다르게 (기본 controlbit)',
          TopicRootSection(
            key: ValueKey('server-topic-${d.dedupeKey}'),
            serverIp: d.ip,
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          Icons.cloud_sync,
          '외부망 MQTT 브로커 (중계 · cloud-agent)',
          '계산된 position·Locator 상태를 인터넷 브로커로 중계 — [관제 › 외부망]에서 사용',
          CloudConfigForm(
            key: ValueKey('server-cloud-${d.dedupeKey}'),
            serverIp: d.ip,
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          Icons.settings,
          '서버 카드 제어',
          null,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              hoverTip(
                '서버 카드의 상태 확인 웹(포트 8080)을 브라우저로 엽니다.\n'
                '읽기 전용 뷰어 — 설정 변경은 이 도구에서 합니다.',
                OutlinedButton.icon(
                  onPressed: () => _openUrl('http://${d.ip}:8080'),
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: const Text('상태 페이지 열기 (:8080)'),
                ),
              ),
              hoverTip(
                'positioning 서비스(aoa-positioning)를 재시작합니다.\n'
                '수 초간 angle 수신·position 발행이 중단됩니다.\n'
                '서버 카드 소프트웨어 v2.1.1 이상 필요.',
                OutlinedButton.icon(
                  onPressed:
                      _busy
                          ? null
                          : () => _doServerService(
                            d,
                            'aoa-positioning',
                            'positioning 서비스 재시작',
                          ),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('positioning 재시작'),
                ),
              ),
              hoverTip(
                'mosquitto(내부망 MQTT 브로커)를 재시작합니다.\n'
                '로케이터·이 도구의 MQTT 연결이 잠시 끊겼다가 자동 복구됩니다.',
                OutlinedButton.icon(
                  onPressed:
                      _busy
                          ? null
                          : () => _doServerService(
                            d,
                            'mosquitto',
                            '내부망 MQTT 브로커 재시작',
                            confirmBody:
                                'mosquitto(내부망 MQTT 브로커)를 재시작할까요?\n'
                                '모든 클라이언트(로케이터·이 도구) 연결이 잠시 끊겼다가 '
                                '자동 복구됩니다.',
                          ),
                  icon: const Icon(Icons.hub_outlined),
                  label: const Text('내부망 MQTT 브로커 재시작'),
                ),
              ),
              hoverTip(
                '외부망 중계 에이전트(locationx-cloud-agent)를 재시작합니다.\n'
                '외부 브로커 연결이 잠시 끊겼다가 자동 복구됩니다.\n'
                '서버 카드 소프트웨어 v2.2.0 이상 필요.',
                OutlinedButton.icon(
                  onPressed:
                      _busy
                          ? null
                          : () => _doServerService(
                            d,
                            'locationx-cloud-agent',
                            '외부망 MQTT 브로커 재시작',
                            confirmBody:
                                '외부망 중계(cloud-agent)를 재시작할까요?\n'
                                '외부 브로커 쪽 위치·상태 발행이 잠시 끊겼다가 '
                                '자동 복구됩니다 (내부망 동작에는 영향 없음).',
                          ),
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: const Text('외부망 MQTT 브로커 재시작'),
                ),
              ),
              hoverTip(
                'PC의 배포 저장소(${DeployService.serverRepo})의 최신 버전과\n'
                '카드 버전을 비교해, 다르면 재배포(provision.sh)로 업데이트합니다.\n'
                '수 분 걸릴 수 있으며 이 PC의 SSH 키가 카드에 등록돼 있어야 합니다.',
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _doUpdate(d),
                  icon: const Icon(Icons.system_update_alt),
                  label: const Text('소프트웨어 업데이트'),
                ),
              ),
              hoverTip(
                '서버 카드를 재부팅합니다. 다시 켜질 때까지 1~2분 걸리며\n'
                '그동안 브로커·위치 계산이 모두 중단됩니다.',
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _doServerReboot(d),
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('재부팅'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '이 카드에서 mosquitto MQTT 브로커(기본 포트 1883)와 positioning 서비스가 구동됩니다.\n'
          'positioning 서비스는 내부망 브로커에서 angle을 수신하고 position을 발행하며, '
          '외부망 중계(cloud-agent)는 그 결과만 인터넷 브로커로 내보냅니다.\n'
          '위치 설정은 [설정 › ③ 위치 설정]에서, 수신 확인은 [관제 › 데이터 수신]·[관제 › MQTT 뷰어]에서 합니다.',
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
        _sectionCard(
          Icons.lan,
          'MQTT 브로커 설정',
          '이 로케이터가 angle을 발행할 내부망 브로커 — 보통 서버 카드 IP',
          _MqttSetForm(
            key: ValueKey('mqtt-${d.dedupeKey}'),
            initialHost: d.mqttHost ?? app.serverIp,
            initialPort: d.mqttPort ?? 1883,
            busy: _busy,
            onSubmit: (host, port) => _doSetMqtt(d, host, port),
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          Icons.settings,
          'Locator 제어',
          null,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              hoverTip(
                '카드의 상태 확인 웹(포트 8080)을 브라우저로 엽니다.\n'
                '안테나 UART 수신 · CPU 온도 · MQTT 연결 상태를 실시간으로 보여줍니다.',
                OutlinedButton.icon(
                  onPressed: () => _openUrl('http://${d.ip}:8080'),
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: const Text('상태 페이지 열기 (:8080)'),
                ),
              ),
              hoverTip(
                '카드의 LED를 8초간 점멸시켜 현장에서 어떤 Locator인지 확인합니다.\n'
                '(카드 동작에는 영향 없음)',
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _doLedBlink(d),
                  icon: const Icon(Icons.lightbulb),
                  label: const Text('LED 식별 (8초 점멸)'),
                ),
              ),
              hoverTip(
                '카드의 AOA 서비스를 재시작합니다.\n'
                'MQTT 브로커 설정 변경 후 적용에 필요하며, 약 10초간 angle 송신이 중단됩니다.',
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _doRestartService(d),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('AOA 서비스 재시작'),
                ),
              ),
              hoverTip(
                'PC의 배포 저장소(${DeployService.locatorRepo})의 최신 버전과\n'
                '카드 버전을 비교해, 다르면 재배포(provision.sh)로 업데이트합니다.\n'
                '수 분 걸릴 수 있으며 이 PC의 SSH 키가 카드에 등록돼 있어야 합니다.',
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _doUpdate(d),
                  icon: const Icon(Icons.system_update_alt),
                  label: const Text('소프트웨어 업데이트'),
                ),
              ),
              hoverTip(
                '카드를 재부팅합니다. 다시 켜질 때까지 1~2분 걸립니다.',
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _doReboot(d),
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('재부팅'),
                ),
              ),
            ],
          ),
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
    final ok = await confirmSettingsPassword(context, 'MQTT 브로커 설정 변경');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final resp = await _control.setMqtt(
        targetIp: d.ip,
        brokerHost: host,
        brokerPort: port,
      );
      if (!mounted) return;
      if (resp['ok'] == true) {
        _snack('MQTT 브로커 설정 저장됨 ($host:$port)');
        final restart = await _confirm(
          'AOA 서비스 재시작',
          '설정을 적용하려면 AOA 서비스를 재시작해야 합니다.\n지금 재시작할까요?',
        );
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

  Future<void> _doRestartService(
    DiscoveredDevice d, {
    bool quiet = false,
  }) async {
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

  // 서버 카드 제어 — config 서버(:8080) /api/service·/api/reboot 사용
  // (로케이터와 달리 서버 discover 에이전트는 UDP 제어가 없음).
  Future<void> _doServerService(
    DiscoveredDevice d,
    String name,
    String label, {
    String? confirmBody,
  }) async {
    if (confirmBody != null) {
      final ok = await _confirm(label, confirmBody);
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await ConfigApiClient(d.ip).restartService(name);
      _snack('$label 완료');
    } on Exception catch (e) {
      _snack('$label 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doServerReboot(DiscoveredDevice d) async {
    final ok = await _confirm(
      '재부팅',
      '${d.device} (${d.ip}) 서버 카드를 재부팅할까요?\n'
          '1~2분 동안 MQTT 브로커·위치 계산이 중단됩니다.',
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ConfigApiClient(d.ip).reboot();
      _snack('재부팅 명령 전송됨 — 카드가 다시 켜질 때까지 1~2분 걸립니다');
    } on Exception catch (e) {
      _snack('재부팅 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 소프트웨어 업데이트 — PC 배포 저장소의 최신 태그와 카드 버전을 비교해
  // 다르면 Git Bash로 provision.sh <IP>를 실행해 재배포한다 (서버/로케이터 공통).
  Future<void> _doUpdate(DiscoveredDevice d) async {
    setState(() => _busy = true);
    try {
      final updated = await runCardUpdateFlow(
        context,
        deviceLabel: d.device,
        ip: d.ip,
        isServer: d.isServer,
        currentVer: d.ver,
      );
      if (updated && mounted) {
        _snack('업데이트 완료 — Locator 목록을 다시 검색합니다');
        context.read<AppState>().scan(); // 목록의 ver 표기 갱신
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
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('확인'),
              ),
            ],
          ),
    );
  }
}

/// 서버 카드의 MQTT 브로커 설정 섹션.
/// config 서버(:8080)의 /api/mqtt에서 현재 값을 읽어 폼으로 보여주고,
/// 전송 시 스테이징 저장 → 적용(+aoa-positioning 재시작)까지 수행한다.
class _ServerMqttSection extends StatefulWidget {
  final String serverIp;

  const _ServerMqttSection({super.key, required this.serverIp});

  @override
  State<_ServerMqttSection> createState() => _ServerMqttSectionState();
}

class _ServerMqttSectionState extends State<_ServerMqttSection> {
  late final ConfigApiClient _client = ConfigApiClient(widget.serverIp);
  late Future<ServerMqttSettings> _future = _client.fetchMqtt();
  bool _busy = false;

  void _reload() => setState(() => _future = _client.fetchMqtt());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ServerMqttSettings>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('브로커 설정 조회 중...', style: TextStyle(fontSize: 12)),
              ],
            ),
          );
        }
        if (snap.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '브로커 설정을 가져오지 못했습니다: ${snap.error}\n'
                '서버 카드 소프트웨어가 구버전(v2 미만)이면 저장소 배포로 업데이트하세요.',
                style: TextStyle(fontSize: 12, color: Colors.red.shade700),
              ),
              TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('다시 시도'),
              ),
            ],
          );
        }

        final s = snap.data!;
        final pending =
            s.stagedHost != s.appliedHost || s.stagedPort != s.appliedPort;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MqttSetForm(
              key: ValueKey('server-mqtt-form-${widget.serverIp}'),
              initialHost: s.stagedHost,
              initialPort: s.stagedPort,
              busy: _busy,
              hostLabel: '브로커 호스트 (localhost = 이 카드)',
              submitTip:
                  'positioning 서비스가 접속할 MQTT 브로커를 설정합니다.\n'
                  '적용 시 aoa-positioning 서비스가 재시작되며 비밀번호 확인이 뜹니다.',
              onSubmit: _submit,
            ),
            const SizedBox(height: 6),
            Text(
              '현재 반영: ${s.appliedHost}:${s.appliedPort}'
              '${pending ? ' · 스테이징 ${s.stagedHost}:${s.stagedPort} 미적용' : ''}'
              ' — localhost는 이 카드의 mosquitto입니다.',
              style: TextStyle(
                fontSize: 12,
                color: pending ? Colors.orange.shade800 : Colors.grey.shade600,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submit(String host, int port) async {
    final ok = await confirmSettingsPassword(context, '서버 MQTT 브로커 설정 변경');
    if (!ok || !mounted) return;

    final apply = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('브로커 설정 적용'),
            content: Text(
              'positioning 서비스의 MQTT 브로커를 $host:$port(으)로 변경합니다.\n'
              '적용을 위해 aoa-positioning 서비스가 재시작됩니다(수 초간 위치 계산 중단).\n'
              '계속할까요?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('적용'),
              ),
            ],
          ),
    );
    if (apply != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _client.pushMqtt(host, port);
      final result = await _client.apply(restart: true);
      if (!mounted) return;
      if (result.restarted) {
        _snack('브로커 설정 적용 완료 ($host:$port) — 서비스 재시작됨');
      } else {
        _snack(
          '브로커 설정 저장됨 — 서비스 재시작 실패'
          '${result.restartError.isEmpty ? '' : ': ${result.restartError}'}. '
          'Pi에서 직접: sudo systemctl restart aoa-positioning',
        );
      }
    } on Exception catch (e) {
      if (mounted) _snack('설정 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// MQTT 브로커 host/port 입력 폼.
class _MqttSetForm extends StatefulWidget {
  final String initialHost;
  final int initialPort;
  final bool busy;
  final String hostLabel;
  final String submitTip;
  final void Function(String host, int port) onSubmit;

  const _MqttSetForm({
    super.key,
    required this.initialHost,
    required this.initialPort,
    required this.busy,
    required this.onSubmit,
    this.hostLabel = '브로커 호스트 (보통 서버 카드 IP)',
    this.submitTip =
        '이 카드가 접속할 MQTT 브로커 주소를 UDP로 설정합니다.\n'
            '전송 후 AOA 서비스 재시작이 필요하며 비밀번호 확인이 뜹니다.',
  });

  @override
  State<_MqttSetForm> createState() => _MqttSetFormState();
}

class _MqttSetFormState extends State<_MqttSetForm> {
  late final TextEditingController _host = TextEditingController(
    text: widget.initialHost,
  );
  late final TextEditingController _port = TextEditingController(
    text: widget.initialPort.toString(),
  );

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
            decoration: InputDecoration(
              labelText: widget.hostLabel,
              isDense: true,
              border: const OutlineInputBorder(),
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
        hoverTip(
          widget.submitTip,
          FilledButton(
            onPressed:
                widget.busy
                    ? null
                    : () {
                      final host = _host.text.trim();
                      final port = int.tryParse(_port.text.trim());
                      if (host.isEmpty || port == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('호스트/포트를 올바르게 입력하세요')),
                        );
                        return;
                      }
                      widget.onSubmit(host, port);
                    },
            child: const Text('전송'),
          ),
        ),
      ],
    );
  }
}
