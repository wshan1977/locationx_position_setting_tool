import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/discovered_device.dart';
import '../models/placement.dart';
import '../state/app_state.dart';
import '../widgets/hover_tip.dart';

/// 장치 검색 패널 (위치 설정 탭 왼쪽): 스캔 버튼 + 발견된 디바이스 목록.
/// 로케이터 카드는 캔버스로 드래그할 수 있다.
class RightDevicePanel extends StatelessWidget {
  const RightDevicePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final servers = app.devices.where((d) => d.isServer).toList();
    final locators = app.devices.where((d) => !d.isServer).toList();
    final missing = app.missingPlacements;

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
            child: hoverTip(
              'UDP 브로드캐스트(포트 40010)로 LAN의 서버/로케이터 카드를 검색합니다.\n'
              '배치된 로케이터의 IP가 바뀌었으면 자동으로 갱신됩니다.',
              FilledButton.icon(
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
          ),
          Expanded(
            child: app.devices.isEmpty && missing.isEmpty
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
                      if (missing.isNotEmpty) ...[
                        _sectionTitle('배치됨 · 검색 안 됨 (${missing.length})'),
                        for (final p in missing) _MissingLocatorTile(placement: p),
                      ],
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
            : hoverTip(
                '이 카드를 설정 전송·MQTT 연결의 대상 서버로 지정합니다.',
                TextButton(
                  onPressed: () => app.setServerIp(device.ip),
                  child: const Text('선택'),
                ),
              ),
      ),
    );
  }
}

/// 배치돼 있지만 마지막 검색에서 발견되지 않은 로케이터 경고 타일.
class _MissingLocatorTile extends StatelessWidget {
  final PlacedLocator placement;
  const _MissingLocatorTile({required this.placement});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Card(
      color: Colors.orange.shade50,
      child: ListTile(
        dense: true,
        leading: Icon(Icons.signal_wifi_off, color: Colors.orange.shade700),
        title: Text(
          placement.deviceName.isNotEmpty
              ? placement.deviceName
              : placement.shortId,
        ),
        subtitle: Text(
          '${placement.ip.isNotEmpty ? placement.ip : 'IP 미상'}\n'
          '${placement.locatorId}\n전원/네트워크를 확인하거나 교체됐으면 배치를 제거하세요.',
          style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: '배치 제거',
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () => app.removePlacement(placement.locatorId),
        ),
        onTap: () => app.selectLocator(placement.locatorId),
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

    return hoverTip(
      '캔버스로 드래그해서 이 로케이터를 배치합니다.',
      _buildDraggable(tile),
    );
  }

  Widget _buildDraggable(Widget tile) {
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
