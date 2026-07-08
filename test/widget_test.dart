import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:locationx_positon_seting_tool/main.dart';
import 'package:locationx_positon_seting_tool/state/app_state.dart';
import 'package:locationx_positon_seting_tool/state/mqtt_state.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) {
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState()),
          ChangeNotifierProvider(create: (_) => MqttState()),
        ],
        child: const LocationXApp(),
      ),
    );
  }

  testWidgets('4-tab layout renders', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('장치 설정'), findsOneWidget);
    expect(find.text('위치 설정 (서버)'), findsOneWidget);
    expect(find.text('데이터 수신'), findsOneWidget);
    expect(find.text('MQTT 뷰어'), findsOneWidget);

    // 초기 탭: 장치 설정
    expect(find.text('장치 검색 (UDP)'), findsOneWidget);
  });

  testWidgets('position setting tab keeps 3-pane layout',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('위치 설정 (서버)'));
    await tester.pumpAndSettle();

    expect(find.text('전역 Positioning 설정'), findsOneWidget);
    expect(find.text('서버로 전송'), findsOneWidget);
  });
}
