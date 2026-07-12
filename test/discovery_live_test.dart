@Tags(['live'])
library;

// mock discover agent가 떠 있을 때만 실행하는 라이브 테스트:
//   python tools/mock/mock_discover_agent.py
//   flutter test test/discovery_live_test.dart --tags live
import 'package:flutter_test/flutter_test.dart';

import 'package:locationx_position_setting_tool/services/discovery_service.dart';

void main() {
  test('scan finds mock devices (1 server + 3 locators)', () async {
    final devices = await DiscoveryService()
        .scan(window: const Duration(seconds: 2));

    expect(devices.length, 4);
    final servers = devices.where((d) => d.isServer).toList();
    final locators = devices.where((d) => !d.isServer).toList();
    expect(servers.length, 1);
    expect(locators.length, 3);
    // 정렬: 서버 먼저
    expect(devices.first.isServer, true);
    expect(locators.first.locatorId, startsWith('ble-pd-4C5BB3CAD7'));
  }, tags: 'live');
}
