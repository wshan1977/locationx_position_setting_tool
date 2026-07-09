import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/mqtt_state.dart';
import 'hover_tip.dart';

/// 데이터 수신 / MQTT 뷰어 탭 공용 브로커 연결 바.
/// 하나의 MqttState 연결을 두 탭이 공유한다.
class MqttConnectBar extends StatefulWidget {
  const MqttConnectBar({super.key});

  @override
  State<MqttConnectBar> createState() => _MqttConnectBarState();
}

class _MqttConnectBarState extends State<MqttConnectBar> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '1883');

  @override
  void initState() {
    super.initState();
    final mqtt = context.read<MqttState>();
    if (mqtt.host.isNotEmpty) {
      _host.text = mqtt.host;
      _port.text = mqtt.port.toString();
    } else {
      // 기본값: 대상 서버 카드 (mosquitto 브로커가 서버 카드에서 구동됨)
      _host.text = context.read<AppState>().serverIp;
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttState>();
    final connected = mqtt.isConnected;
    final connecting = mqtt.status == MqttStatus.connecting;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          hoverTip(
            'MQTT 브로커 주소 — 보통 서버 카드 IP\n'
            '(mosquitto 브로커가 서버 카드에서 구동됩니다)\n'
            'broker.hivemq.com 같은 외부 브로커 호스트명도 가능합니다.',
            SizedBox(
              width: 220,
              child: TextField(
                controller: _host,
                enabled: !connected && !connecting,
                decoration: const InputDecoration(
                  labelText: 'MQTT 브로커 (IP/호스트명)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          hoverTip(
            'MQTT 포트 (기본 1883)',
            SizedBox(
              width: 80,
              child: TextField(
                controller: _port,
                enabled: !connected && !connecting,
                decoration: const InputDecoration(
                  labelText: '포트',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (connected)
            hoverTip(
              '브로커 연결을 끊습니다 (수신된 데이터는 유지).',
              FilledButton.icon(
                onPressed: () => mqtt.disconnect(),
                icon: const Icon(Icons.link_off),
                label: const Text('연결 해제'),
              ),
            )
          else
            hoverTip(
              '브로커에 접속해 LocationX 토픽(silabs/#)을 구독합니다.\n'
              '연결 상태는 재시작 시 자동으로 복원됩니다.',
              FilledButton.icon(
                onPressed: connecting
                    ? null
                    : () {
                        final host = _host.text.trim().isEmpty
                            ? context.read<AppState>().serverIp
                            : _host.text.trim();
                        _host.text = host;
                        final port = int.tryParse(_port.text.trim()) ?? 1883;
                        mqtt.connect(host, port);
                      },
                icon: connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.link),
                label: Text(connecting ? '연결 중...' : '연결'),
              ),
            ),
          const SizedBox(width: 12),
          _statusChip(mqtt),
          const Spacer(),
          IconButton(
            tooltip: mqtt.paused ? '수신 재개' : '수신 일시정지',
            onPressed:
                connected ? () => mqtt.setPaused(!mqtt.paused) : null,
            icon: Icon(mqtt.paused ? Icons.play_arrow : Icons.pause),
          ),
          IconButton(
            tooltip: '수신 데이터 지우기',
            onPressed: () => mqtt.clear(),
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(MqttState mqtt) {
    final (color, text) = switch (mqtt.status) {
      MqttStatus.connected => (Colors.green, '연결됨 ${mqtt.host}:${mqtt.port}'),
      MqttStatus.connecting => (Colors.orange, '연결 중'),
      MqttStatus.error => (Colors.red, mqtt.lastError),
      MqttStatus.disconnected => (Colors.grey, '연결 안 됨'),
    };
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
