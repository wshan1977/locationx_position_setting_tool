import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/external_state.dart';
import '../state/mqtt_state.dart';
import '../widgets/cloud_config_form.dart';
import '../widgets/hover_tip.dart';
import '../widgets/locator_avatar.dart';
import '../widgets/tab_guide.dart';
import 'mqtt_viewer_tab.dart' show MqttTopicExplorer;
import 'position_live_view.dart';

/// 탭 5: 외부망 테스트.
/// 서버 카드의 cloud-agent가 외부 브로커(broker.hivemq.com 등)로 중계한
/// `locationx/<siteId>/#` 토픽에 접속해:
/// - 장치 목록: 전 장치 상태(온도·서비스·연결) + 리부트/서비스 재시작/LED 식별
/// - 토픽 뷰어: 중계 토픽 탐색기 (프리픽스가 벗겨진 토픽으로 표시 · 발행 시 자동 전치)
/// - 위치 확인: 중계된 position으로 2D/3D 라이브 뷰 (내부망 MQTT 뷰어와 동일 화면)
class ExternalTestTab extends StatefulWidget {
  const ExternalTestTab({super.key});

  @override
  State<ExternalTestTab> createState() => _ExternalTestTabState();
}

class _ExternalTestTabState extends State<ExternalTestTab>
    with SingleTickerProviderStateMixin {
  late final TabController _subTabs;

  @override
  void initState() {
    super.initState();
    _subTabs = TabController(length: 3, vsync: this);
    _subTabs.addListener(() {
      if (!_subTabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _subTabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.watch<ExternalState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabGuide(
          icon: Icons.cloud_sync,
          text: '외부망(인터넷) 확인: ① [서버 중계 설정]에서 중계 활성화 → ② siteId 확인 '
              '→ ③ 외부 브로커에 연결 — 현장 밖 어디서든 장치 상태·제어·위치를 봅니다 '
              '(angle은 중계되지 않음)',
        ),
        const _ExtConnectBar(),
        const Divider(height: 1),
        Row(
          children: [
            SizedBox(
              width: 420,
              child: TabBar(
                controller: _subTabs,
                onTap: (_) => setState(() {}),
                labelStyle: const TextStyle(fontSize: 12.5),
                tabs: const [
                  Tab(height: 36, text: '장치 목록'),
                  Tab(height: 36, text: '토픽 뷰어'),
                  Tab(height: 36, text: '위치 확인'),
                ],
              ),
            ),
            const Expanded(child: Divider(height: 1)),
          ],
        ),
        Expanded(
          // 중첩 Provider로 외부 연결의 MqttState를 주입 —
          // 토픽 뷰어·PositionLiveView는 루트 MqttState 대신 이것을 보고,
          // AppState(배치·도면)는 루트 것을 그대로 쓴다.
          child: ChangeNotifierProvider<MqttState>.value(
            value: ext.mqtt,
            child: IndexedStack(
              index: _subTabs.index,
              children: const [
                _DeviceListBody(),
                MqttTopicExplorer(),
                // 외부망은 position만 중계되므로 angle 점선 UI는 숨긴다
                PositionLiveView(supportsAngle: false),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =========================================================
// 연결 바: 외부 브로커 + siteId + 서버 카드 중계 설정
// =========================================================
class _ExtConnectBar extends StatefulWidget {
  const _ExtConnectBar();

  @override
  State<_ExtConnectBar> createState() => _ExtConnectBarState();
}

class _ExtConnectBarState extends State<_ExtConnectBar> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _site;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final ext = context.read<ExternalState>();
    _host = TextEditingController(text: ext.brokerHost);
    _port = TextEditingController(text: '${ext.brokerPort}');
    _site = TextEditingController(text: ext.siteId);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _site.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final ext = context.read<ExternalState>();
    if (ext.isConnected) {
      await ext.disconnect();
      return;
    }
    final site = _site.text.trim();
    if (site.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('siteId를 입력하세요 — 서버 카드의 중계 설정(우측 버튼)에서 확인')));
      return;
    }
    setState(() => _busy = true);
    ext.brokerHost = _host.text.trim();
    ext.brokerPort = int.tryParse(_port.text.trim()) ?? 1883;
    ext.siteId = site;
    await ext.connect();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.watch<ExternalState>();
    final status = ext.mqtt.status;
    final (statusText, statusColor) = switch (status) {
      MqttStatus.connected => ('연결됨', Colors.green),
      MqttStatus.connecting => ('연결 중...', Colors.orange),
      MqttStatus.error => ('오류: ${ext.mqtt.lastError}', Colors.red),
      MqttStatus.disconnected => ('연결 안 됨', Colors.grey),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _host,
              enabled: !ext.isConnected,
              decoration: const InputDecoration(
                labelText: '외부 브로커',
                hintText: 'broker.hivemq.com',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: TextField(
              controller: _port,
              enabled: !ext.isConnected,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '포트',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 170,
            child: hoverTip(
              '서버 카드 cloud-agent가 쓰는 토픽 프리픽스(locationx/<siteId>/...)의\n'
              'siteId. 공개 브로커에서 이 값이 유일한 접근 장벽이므로 외부에 노출하지 마세요.',
              TextField(
                controller: _site,
                enabled: !ext.isConnected,
                decoration: const InputDecoration(
                  labelText: 'siteId',
                  hintText: 'lx-xxxxxxxx',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy ? null : _toggle,
            child: Text(ext.isConnected ? '연결 해제' : '연결'),
          ),
          const SizedBox(width: 12),
          Icon(Icons.circle, size: 10, color: statusColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text(statusText,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: statusColor)),
          ),
          hoverTip(
            '서버 카드(내부망 연결 필요)의 cloud-agent 중계 설정을 조회/변경합니다.\n'
            '외부 브로커 주소·siteId·활성화 여부를 서버에 저장하고 적용합니다.',
            OutlinedButton.icon(
              icon: const Icon(Icons.cloud_sync, size: 16),
              label: const Text('서버 중계 설정', style: TextStyle(fontSize: 12)),
              onPressed: () async {
                final applied = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => const _CloudConfigDialog(),
                );
                // 다이얼로그가 적용된 siteId를 돌려주면 연결란에 반영
                final site = applied?['site_id']?.toString() ?? '';
                if (site.isNotEmpty && mounted && !ext.isConnected) {
                  _site.text = site;
                  final host = applied?['broker_host']?.toString() ?? '';
                  if (host.isNotEmpty) _host.text = host;
                  final port = (applied?['broker_port'] as num?)?.toInt();
                  if (port != null) _port.text = '$port';
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// 장치 목록
// =========================================================
class _DeviceListBody extends StatelessWidget {
  const _DeviceListBody();

  @override
  Widget build(BuildContext context) {
    final ext = context.watch<ExternalState>();
    if (!ext.isConnected && ext.devices.isEmpty) {
      return const Center(
        child: Text('외부 브로커에 연결하면 중계된 장치 상태가 표시됩니다',
            style: TextStyle(color: Colors.grey)),
      );
    }
    final devices = ext.deviceList;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _agentBanner(ext),
        Expanded(
          child: devices.isEmpty
              ? const Center(
                  child: Text('장치 상태 수신 대기 중... (retained 메시지는 연결 즉시 도착)',
                      style: TextStyle(color: Colors.grey, fontSize: 13)))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: devices.length,
                  itemBuilder: (context, i) =>
                      _DeviceCard(device: devices[i]),
                ),
        ),
      ],
    );
  }

  Widget _agentBanner(ExternalState ext) {
    final online = ext.agentOnline;
    if (online == null) return const SizedBox.shrink();
    final color = online ? Colors.green : Colors.red;
    return Container(
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(online ? Icons.cloud_done : Icons.cloud_off,
              size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            online
                ? '클라우드 에이전트 온라인 (v${ext.agentVer})'
                : '클라우드 에이전트 오프라인 — 아래 상태는 마지막 수신값 (제어 불가)',
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatefulWidget {
  final ExternalDevice device;
  const _DeviceCard({required this.device});

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  bool _busy = false;

  Future<void> _run(String label, Future<CmdResult> Function() action,
      {String? confirm}) async {
    if (confirm != null) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(label),
          content: Text(confirm),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('실행')),
          ],
        ),
      );
      if (yes != true) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${widget.device.deviceId} · $label: ${result.message}'),
      backgroundColor: result.ok ? null : Colors.red.shade700,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final ext = context.read<ExternalState>();
    final tempColor = d.cpuTempC == null
        ? Colors.grey
        : d.cpuTempC! < 60
            ? Colors.green
            : (d.cpuTempC! < 75 ? Colors.orange : Colors.red);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d.isServer)
              Icon(Icons.dns,
                  size: 30,
                  color: d.online
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey)
            else
              LocatorAvatar(size: 36, dimmed: !d.online),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(d.deviceId,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      _chip(d.isServer ? '서버' : '로케이터', Colors.blueGrey),
                      const SizedBox(width: 4),
                      _chip(d.online ? '온라인' : '오프라인',
                          d.online ? Colors.green : Colors.red),
                      if (d.mqttConnected == false) ...[
                        const SizedBox(width: 4),
                        _chip('MQTT 끊김', Colors.orange),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 14,
                    runSpacing: 2,
                    children: [
                      _info('IP', d.ip.isEmpty ? '-' : d.ip),
                      _info('버전', d.ver.isEmpty ? '-' : d.ver),
                      if (d.uptimeText != null)
                        _info('가동시간',
                            '${d.uptimeText} (부팅 ${d.bootTimeText ?? "?"})'),
                      if (d.locatorId != null && d.locatorId!.isNotEmpty)
                        _info('로케이터 ID', d.locatorId!),
                      if (d.uartRxRateBps != null)
                        _info('UART', '${d.uartRxRateBps} B/s'),
                      _info('상태 수신', _age(d.lastRx)),
                    ],
                  ),
                  if (d.services.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final e in d.services.entries)
                          _chip('${e.key}: ${e.value}',
                              e.value == 'active' ? Colors.green : Colors.red),
                      ],
                    ),
                  ],
                  if (d.throttled.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('스로틀링: ${d.throttled.join(", ")}',
                        style:
                            TextStyle(fontSize: 11, color: Colors.red.shade700)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  d.cpuTempC == null ? '온도 -' : '${d.cpuTempC}°C',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: tempColor),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!d.isServer)
                      _actionBtn(
                        icon: Icons.lightbulb_outline,
                        label: 'LED',
                        tip: '로케이터 LED를 깜빡여 현장에서 카드를 식별합니다',
                        onPressed: () => _run(
                            'LED 식별',
                            () => ext.sendCommand(d.deviceId, 'LED_BLINK')),
                      ),
                    _serviceRestartBtn(ext, d),
                    _actionBtn(
                      icon: Icons.restart_alt,
                      label: '리부트',
                      tip: '카드를 재부팅합니다 (1~2분 중단)',
                      danger: true,
                      onPressed: () => _run(
                        '리부트',
                        () => ext.sendCommand(d.deviceId, 'REBOOT'),
                        confirm: '${d.deviceId} 카드를 재부팅할까요?\n'
                            '1~2분 동안 해당 카드의 기능이 중단됩니다.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 서비스 재시작: 장치가 보고한 서비스 목록에서 선택 (화이트리스트는 카드가 최종 차단).
  Widget _serviceRestartBtn(ExternalState ext, ExternalDevice d) {
    final services = d.services.keys.toList();
    if (services.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      enabled: !_busy,
      tooltip: '서비스 재시작',
      itemBuilder: (context) => [
        for (final s in services)
          PopupMenuItem(value: s, child: Text('$s 재시작')),
      ],
      onSelected: (s) => _run(
        '$s 재시작',
        () => ext.sendCommand(d.deviceId, 'SERVICE_RESTART', service: s),
        confirm: '${d.deviceId}의 $s 서비스를 재시작할까요?',
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_backup_restore,
                size: 16, color: Colors.blueGrey.shade700),
            const SizedBox(width: 3),
            Text('서비스',
                style:
                    TextStyle(fontSize: 12, color: Colors.blueGrey.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required String tip,
    required VoidCallback onPressed,
    bool danger = false,
  }) {
    final color = danger ? Colors.red.shade700 : Colors.blueGrey.shade700;
    return hoverTip(
      tip,
      TextButton.icon(
        onPressed: _busy ? null : onPressed,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label, style: TextStyle(fontSize: 12, color: color)),
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero),
      ),
    );
  }

  Widget _chip(String text, MaterialColor color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.shade200),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 10.5, color: color.shade800)),
      );

  Widget _info(String label, String value) => Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '$label ',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          TextSpan(
              text: value,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w500)),
        ]),
      );

  static String _age(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds}초 전';
    if (d.inMinutes < 60) return '${d.inMinutes}분 전';
    return '${d.inHours}시간 전';
  }
}

// =========================================================
// 서버 카드 cloud-agent 설정 다이얼로그 (내부망 필요)
// =========================================================
class _CloudConfigDialog extends StatefulWidget {
  const _CloudConfigDialog();

  @override
  State<_CloudConfigDialog> createState() => _CloudConfigDialogState();
}

class _CloudConfigDialogState extends State<_CloudConfigDialog> {
  Map<String, dynamic>? _applied;

  @override
  Widget build(BuildContext context) {
    final serverIp = context.read<AppState>().serverIp.trim();
    return AlertDialog(
      title: const Text('서버 카드 외부망 중계 설정', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: serverIp.isEmpty
            ? const Text('서버 카드 IP가 없습니다 — 위치 설정 탭에서 장치를 먼저 검색하세요',
                style: TextStyle(fontSize: 13))
            : SingleChildScrollView(
                child: CloudConfigForm(
                  serverIp: serverIp,
                  onApplied: (applied) => _applied = applied,
                ),
              ),
      ),
      actions: [
        FilledButton(
          // 적용된 설정(siteId 포함)을 연결 바에 넘긴다
          onPressed: () => Navigator.pop(context, _applied),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}
