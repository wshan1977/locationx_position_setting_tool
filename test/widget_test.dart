import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:locationx_position_setting_tool/main.dart';
import 'package:locationx_position_setting_tool/services/session_storage.dart';
import 'package:locationx_position_setting_tool/state/app_state.dart';
import 'package:locationx_position_setting_tool/state/external_state.dart';
import 'package:locationx_position_setting_tool/state/mqtt_state.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) {
    // 데스크톱 창 크기 — 기본(800x600)에서는 툴바가 가로로 넘친다.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // main()과 같은 Provider 구성 (AutoSaver는 타이머를 피해 start() 생략).
    final app = AppState();
    final mqtt = MqttState();
    final ext = ExternalState();
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider.value(value: mqtt),
          ChangeNotifierProvider.value(value: ext),
          ChangeNotifierProvider.value(value: SessionAutoSaver(app, mqtt, ext)),
        ],
        child: const LocationXApp(),
      ),
    );
  }

  testWidgets('5-tab layout renders', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('① 장치 설정'), findsOneWidget);
    expect(find.text('② 위치 설정 (서버)'), findsOneWidget);
    expect(find.text('③ 데이터 수신'), findsOneWidget);
    expect(find.text('④ MQTT 뷰어 (내부망)'), findsOneWidget);
    expect(find.text('⑤ 외부망 테스트'), findsOneWidget);

    // 초기 탭: 장치 설정
    expect(find.text('장치 검색 (UDP)'), findsOneWidget);
  });

  testWidgets('position setting tab keeps 3-pane layout',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('② 위치 설정 (서버)'));
    await tester.pumpAndSettle();

    expect(find.text('전역 Positioning 설정'), findsOneWidget);
    expect(find.text('서버로 전송'), findsOneWidget);
  });
}
