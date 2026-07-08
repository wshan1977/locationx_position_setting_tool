import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:locationx_positon_seting_tool/state/app_state.dart';
import 'package:locationx_positon_seting_tool/state/mqtt_state.dart';
import 'package:locationx_positon_seting_tool/tabs/position_live_view.dart';

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
}
