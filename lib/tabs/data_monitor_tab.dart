import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/mqtt_state.dart';
import '../widgets/mqtt_connect_bar.dart';
import '../widgets/tab_guide.dart';

/// 관제 › 데이터 수신 확인.
/// MQTT 브로커에 접속해 silabs/aoa/angle·position 토픽의 수신 현황을
/// 로케이터/태그별로 보여준다. 캔버스에 배치된 로케이터 중 미수신인
/// 카드도 표시한다.
class DataMonitorTab extends StatelessWidget {
  const DataMonitorTab({super.key});

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttState>();
    final app = context.watch<AppState>();
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabGuide(
          icon: Icons.monitor_heart,
          text: '배치를 마친 뒤 수신 점검: 내부망 브로커에 연결하면 로케이터별 angle · '
              '태그별 position 수신 상태가 표시됩니다 — 배치했는데 수신이 없는 카드는 '
              '주황색 경고로 표시됩니다',
        ),
        const MqttConnectBar(),
        const Divider(height: 1),
        Expanded(
          child: !mqtt.isConnected && mqtt.topics.isEmpty
              ? Center(
                  child: Text(
                    'MQTT 브로커에 연결하면 로케이터별 angle / 태그별 position\n수신 현황이 표시됩니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _angleSection(context, mqtt, app, now),
                    const SizedBox(height: 16),
                    _positionSection(context, mqtt, now),
                  ],
                ),
        ),
      ],
    );
  }

  // =========================================================
  // Angle (로케이터별)
  // =========================================================
  Widget _angleSection(
      BuildContext context, MqttState mqtt, AppState app, DateTime now) {
    final byLocator = mqtt.angleByLocator();
    final placedIds = {for (final p in app.placements) p.locatorId};
    final receivingIds = byLocator.keys.toSet();
    final silentPlaced = placedIds.difference(receivingIds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Angle 수신 (silabs/aoa/angle/<로케이터>/<태그>)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (byLocator.isEmpty)
          Text('수신된 angle 데이터가 없습니다.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        for (final entry in (byLocator.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))))
          _locatorCard(context, entry.key, entry.value, placedIds, now),
        if (silentPlaced.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber,
                      color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '캔버스에 배치되었지만 angle 미수신: ${silentPlaced.join(', ')}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _locatorCard(
      BuildContext context,
      String locatorId,
      List<MapEntry<String, TopicStat>> tags,
      Set<String> placedIds,
      DateTime now) {
    final placed = placedIds.contains(locatorId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_input_antenna,
                    size: 16, color: Colors.blue),
                const SizedBox(width: 6),
                Text(locatorId,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 8),
                if (placed)
                  const Chip(
                    label: Text('배치됨', style: TextStyle(fontSize: 10)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (final tag in tags) _statRow(tag.key, tag.value, now),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // Position (태그별)
  // =========================================================
  Widget _positionSection(BuildContext context, MqttState mqtt, DateTime now) {
    final byTag = mqtt.positionByTag();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Position 수신 (silabs/aoa/position/<태그>)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (byTag.isEmpty)
          Text(
            '수신된 position 데이터가 없습니다. '
            '(서버 카드의 aoa-positioning 서비스가 계산해 발행합니다)',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        for (final entry in (byTag.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: _statRow(entry.key, entry.value, now,
                  icon: Icons.my_location),
            ),
          ),
      ],
    );
  }

  // =========================================================
  // 공통 행
  // =========================================================
  Widget _statRow(String label, TopicStat stat, DateTime now,
      {IconData icon = Icons.sell}) {
    final last = stat.lastTs;
    final ageSec =
        last == null ? null : now.difference(last).inMilliseconds / 1000.0;
    final live = ageSec != null && ageSec < 3.0;
    final rate = stat.rateHz(now);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.circle,
              size: 9, color: live ? Colors.green : Colors.red),
          const SizedBox(width: 6),
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          SizedBox(
            width: 210,
            child: Text(label.isEmpty ? '(태그 없음)' : label,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 90,
            child: Text('${rate.toStringAsFixed(1)} msg/s',
                style: const TextStyle(fontSize: 12)),
          ),
          SizedBox(
            width: 80,
            child: Text('총 ${stat.count}',
                style: const TextStyle(fontSize: 12)),
          ),
          SizedBox(
            width: 110,
            child: Text(
              ageSec == null
                  ? '수신 없음'
                  : (ageSec < 60
                      ? '${ageSec.toStringAsFixed(1)}초 전'
                      : '${(ageSec / 60).toStringAsFixed(0)}분 전'),
              style: TextStyle(
                  fontSize: 12,
                  color: live ? Colors.grey.shade700 : Colors.red),
            ),
          ),
          Expanded(
            child: Text(
              stat.lastPayload.replaceAll('\n', ' '),
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
