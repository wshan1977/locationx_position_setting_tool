import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/discovered_device.dart';
import '../state/app_state.dart';

/// 카드 검색 패널 (위치 설정 탭 왼쪽): 스캔 버튼 + 발견된 디바이스 목록.
/// 로케이터 카드는 캔버스로 드래그할 수 있다.
class RightDevicePanel extends StatelessWidget {
  const RightDevicePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final servers = app.devices.where((d) => d.isServer).toList();
    final locators = app.devices.where((d) => !d.isServer).toList();

    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
        color: Colors.grey.shade50,
      ),
      child: Column(
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
              label: Text(app.scanning ? '검색 중...' : '카드 검색 (UDP)'),
            ),
          ),
          Expanded(
            child: app.devices.isEmpty
                ? Center(
                    child: Text(
                      app.scanning ? '' : '검색된 카드가 없습니다.\n[카드 검색]을 눌러주세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      if (servers.isNotEmpty) ...[
                        _sectionTitle('MQTT 서버'),
                        for (final d in servers) _ServerTile(device: d),
                      ],
                      _sectionTitle('로케이터 (${locators.length})'),
                      if (locators.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('로케이터 카드 없음',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ),
                      for (final d in locators) _LocatorTile(device: d),
                      const SizedBox(height: 8),
                      Text(
                        '로케이터를 캔버스로 드래그해서 배치하세요.',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
      );
}

class _ServerTile extends StatelessWidget {
  final DiscoveredDevice device;
  const _ServerTile({required this.device});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isTarget = app.serverIp == device.ip;
    return Card(
      color: isTarget ? Colors.teal.shade50 : null,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.dns, color: Colors.teal),
        title: Text(device.device,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${device.ip}\nver ${device.ver}'),
        isThreeLine: true,
        trailing: isTarget
            ? const Chip(
                label: Text('대상', style: TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
              )
            : TextButton(
                onPressed: () => app.setServerIp(device.ip),
                child: const Text('선택'),
              ),
      ),
    );
  }
}

class _LocatorTile extends StatelessWidget {
  final DiscoveredDevice device;
  const _LocatorTile({required this.device});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final placed = app.isPlaced(device);
    final placeable = device.hasValidMac && !placed;

    final tile = Card(
      color: placed ? Colors.grey.shade200 : null,
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.settings_input_antenna,
          color: placed
              ? Colors.grey
              : (device.hasValidMac ? Colors.blue : Colors.red),
        ),
        title: Text(device.device),
        subtitle: Text(
          device.hasValidMac
              ? '${device.ip}\n${device.locatorId}'
              : '${device.ip}\nMAC 오류 — 배치 불가',
          style: TextStyle(
              fontSize: 11,
              color: device.hasValidMac ? null : Colors.red),
        ),
        isThreeLine: true,
        trailing: placed
            ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
            : (placeable
                ? const Icon(Icons.drag_indicator, size: 18)
                : const Icon(Icons.error_outline,
                    color: Colors.red, size: 18)),
        onTap: placed ? () => app.selectLocator(device.locatorId) : null,
      ),
    );

    if (!placeable) return tile;

    return Draggable<DiscoveredDevice>(
      data: device,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.8),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.settings_input_antenna,
              color: Colors.white, size: 20),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }
}
