import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:locationx_positon_seting_tool/canvas/world_transform.dart';
import 'package:locationx_positon_seting_tool/models/discovered_device.dart';
import 'package:locationx_positon_seting_tool/models/positioning_config.dart';

void main() {
  group('DiscoveredDevice', () {
    test('MAC normalization to locator id', () {
      final dev = DiscoveredDevice.fromJson({
        'type': 'DISCOVER_RESPONSE',
        'device': 'aoa-locator-1',
        'ip': '192.168.1.10',
        'mac': '4c:5b:b3:ca:d7:1e',
        'model': 'x',
        'ver': '1.0.3',
        'cap': {'mqtt_set': true},
      })!;
      expect(dev.locatorId, 'ble-pd-4C5BB3CAD71E');
      expect(dev.shortId, 'D71E');
      expect(dev.isServer, false);
      expect(dev.hasValidMac, true);
    });

    test('server card detection (no cap) and MAC_ERR', () {
      final dev = DiscoveredDevice.fromJson({
        'type': 'DISCOVER_RESPONSE',
        'device': 'aoa-server-1',
        'ip': '192.168.1.5',
        'mac': 'MAC_ERR',
        'model': 'x',
        'ver': '1.0.0',
      })!;
      expect(dev.isServer, true);
      expect(dev.hasValidMac, false);
      expect(dev.dedupeKey, 'ip:192.168.1.5');
    });

    test('non-response messages return null', () {
      expect(DiscoveredDevice.fromJson({'type': 'DISCOVER'}), isNull);
    });

    test('mac containing full ble-pd id does not double the prefix', () {
      // 카드 ble_macaddress.txt에 전체 ID가 저장된 경우 discover 응답의
      // mac 필드가 "ble-pd-..."로 온다 (실측: aoa-locator 카드)
      final dev = DiscoveredDevice.fromJson({
        'type': 'DISCOVER_RESPONSE',
        'device': 'aoa-locator-1',
        'ip': '192.168.1.10',
        'mac': 'ble-pd-4C5BB3CAD71E',
        'model': 'x',
        'ver': '1.0.3',
        'cap': {'mqtt_set': true},
      })!;
      expect(dev.locatorId, 'ble-pd-4C5BB3CAD71E');
    });
  });

  group('WorldTransform', () {
    const t = WorldTransform(
      metersPerPixel: 0.05,
      originPx: Offset(100, 500),
      zoom: 2.0,
      panPx: Offset(30, 40),
    );

    test('world <-> screen round trip', () {
      const world = Offset(3.7, 1.2);
      final back = t.screenToWorld(t.worldToScreen(world));
      expect(back.dx, closeTo(world.dx, 1e-9));
      expect(back.dy, closeTo(world.dy, 1e-9));
    });

    test('y-up: +y world is up (smaller image y)', () {
      final o = t.worldToImage(Offset.zero);
      final up = t.worldToImage(const Offset(0, 1));
      expect(up.dy, lessThan(o.dy));
      expect(up.dx, o.dx);
    });

    test('zoomAt keeps focus point fixed', () {
      const focus = Offset(200, 150);
      final world = t.screenToWorld(focus);
      final zoomed = t.zoomAt(focus, t.zoom * 1.5);
      final after = zoomed.worldToScreen(world);
      expect(after.dx, closeTo(focus.dx, 1e-6));
      expect(after.dy, closeTo(focus.dy, 1e-6));
    });
  });

  group('PositioningConfig', () {
    test('round trip preserves unknown fields', () {
      final source = {
        'version': 1,
        'id': 'positioning-x',
        'estimationModeLocation': 'MODE_A',
        'validationModeLocation': 'MODE_B',
        'estimationIntervalSec': 0.02,
        'locationFiltering': true,
        'locationFilteringWeight': 0.1,
        'numberOfSequenceIds': 6,
        'maximumSequenceIdDiffs': 20,
        'someFutureField': {'nested': 42},
        'locators': [
          {
            'id': 'ble-pd-AABBCCDDEEFF',
            'config': {'version': 1, 'customKey': 'kept'},
            'coordinate': {'x': 1.5, 'y': 2.5, 'z': 3.0},
            'orientation': {'x': 0, 'y': 180, 'z': 90},
            'futureLocatorField': 'kept-too',
          }
        ],
      };
      final config = PositioningConfig.fromJson(source);
      final out = jsonDecode(jsonEncode(config.toJson())) as Map;

      expect(out['someFutureField'], {'nested': 42});
      expect(out['id'], 'positioning-x');
      final loc = (out['locators'] as List).first as Map;
      expect(loc['futureLocatorField'], 'kept-too');
      expect((loc['config'] as Map)['customKey'], 'kept');
      expect((loc['coordinate'] as Map)['x'], 1.5);
    });

    test('defaults match server DEFAULT_POSITIONING_JSON locator config', () {
      final config = defaultLocatorAoaConfig();
      // AoA용 유효 모드 (AOD 모드는 positioning 서비스가 거부함)
      expect(config['aoxMode'], 'SL_RTL_AOX_MODE_REAL_TIME_BASIC');
      expect(config['cteMode'], 'SILABS');
      expect(config['periodSamples'], 64);
      expect(config['cteLength'], 160);
    });
  });
}
