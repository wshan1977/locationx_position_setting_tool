import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:locationx_install_tool/models/placement.dart';
import 'package:locationx_install_tool/models/vec3.dart';
import 'package:locationx_install_tool/state/app_state.dart';
import 'package:locationx_install_tool/state/external_state.dart';
import 'package:locationx_install_tool/state/mqtt_state.dart';
import 'package:locationx_install_tool/tabs/position_live_view.dart';

void main() {
  testWidgets('실측 position 토픽(positioning-id 포함) 수신 시 태그가 표시된다',
      (WidgetTester tester) async {
    final mqtt = MqttState();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState()),
          ChangeNotifierProvider.value(value: mqtt),
        ],
        child: const MaterialApp(home: Scaffold(body: PositionLiveView())),
      ),
    );

    // 데이터 없음 → 안내 문구
    expect(find.textContaining('표시할 데이터가 없습니다'), findsOneWidget);

    // 실제 서버 발행 형식 그대로 주입:
    // silabs/aoa/position/<positioning-id>/<tag-id>
    const topic =
        'silabs/aoa/position/positioning-test_room/ble-pd-30FB1064F881';
    mqtt.topics[topic] = TopicStat()
      ..add(MqttMessageRecord(
        topic: topic,
        payload:
            '{"x": 13.24, "x_stdev": 0.8, "y": 3.39, "y_stdev": 0.4, '
            '"z": 2.41, "z_stdev": 0.3, "sequence": 37828}',
        ts: DateTime.now(),
        retained: false,
      ));
    mqtt.setPaused(false); // notifyListeners 트리거

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 태그 트랙이 생겨 안내 문구가 사라지고 캔버스가 그려져야 한다
    expect(find.textContaining('표시할 데이터가 없습니다'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('placements 재정의 시 AppState 배치 없이도 로케이터가 그려진다',
      (WidgetTester tester) async {
    // 내부망에 접속한 적 없는 PC 시나리오: AppState.placements는 비어 있고,
    // 서버 카드가 중계한 배치만 있다.
    final external = [
      PlacedLocator(
        locatorId: 'ble-pd-4C5BB3CAD71E',
        coordinate: Vec3(x: 1.0, y: 2.0, z: 3.0),
        orientation: Vec3(x: 0, y: 180, z: 90),
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState()),
          ChangeNotifierProvider(create: (_) => MqttState()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PositionLiveView(
              supportsAngle: false,
              placements: external,
            ),
          ),
        ),
      ),
    );

    // 배치가 있으므로 안내 문구 대신 캔버스가 그려진다
    expect(find.textContaining('표시할 데이터가 없습니다'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  test('ExternalState가 placements 토픽을 PlacedLocator 목록으로 파싱한다', () {
    final ext = ExternalState();

    // cloud-agent v1.2.0이 발행하는 retained placements 형식 그대로 주입
    ext.mqtt.topics['placements'] = TopicStat()
      ..add(MqttMessageRecord(
        topic: 'placements',
        payload: '{"schema":1,"source":"positioning_config","ts":1752300000,'
            '"locators":[{"id":"ble-pd-4C5BB3CAD71E",'
            '"coordinate":{"x":1.5,"y":-2.0,"z":3.0},'
            '"orientation":{"x":0,"y":180,"z":90}}]}',
        ts: DateTime.now(),
        retained: true,
      ));
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    ext.mqtt.notifyListeners();

    expect(ext.placements, hasLength(1));
    final p = ext.placements.single;
    expect(p.locatorId, 'ble-pd-4C5BB3CAD71E');
    expect(p.coordinate.x, 1.5);
    expect(p.coordinate.y, -2.0);
    expect(p.coordinate.z, 3.0);
    expect(p.orientation.y, 180);
    expect(p.orientation.z, 90);

    ext.dispose();
  });
}
