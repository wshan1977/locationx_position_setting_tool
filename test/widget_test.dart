import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:locationx_position_setting_tool/main.dart';
import 'package:locationx_position_setting_tool/services/session_storage.dart';
import 'package:locationx_position_setting_tool/state/app_state.dart';
import 'package:locationx_position_setting_tool/state/external_state.dart';
import 'package:locationx_position_setting_tool/state/mqtt_state.dart';
import 'package:locationx_position_setting_tool/state/tag_state.dart';

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
          ChangeNotifierProvider.value(value: TagState()),
          ChangeNotifierProvider.value(value: SessionAutoSaver(app, mqtt, ext)),
        ],
        child: const LocationXApp(),
      ),
    );
  }

  testWidgets('6-tab layout renders', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('① Locator 설정'), findsOneWidget);
    expect(find.text('② Tag 설정'), findsOneWidget);
    expect(find.text('③ 위치 설정 (서버)'), findsOneWidget);
    expect(find.text('④ 데이터 수신'), findsOneWidget);
    expect(find.text('⑤ MQTT 뷰어 (내부망)'), findsOneWidget);
    expect(find.text('⑥ 외부망 테스트'), findsOneWidget);

    // 초기 탭: Locator 설정
    expect(find.text('Locator 검색 (UDP)'), findsOneWidget);
  });

  testWidgets('tag settings tab shows BLE scan and empty list',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('② Tag 설정'));
    await tester.pumpAndSettle();

    expect(find.text('Tag 검색 (BLE)'), findsOneWidget);
    expect(find.text('좌측에서 Tag를 선택하세요.'), findsOneWidget);
  });

  testWidgets('position setting tab keeps 3-pane layout',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('③ 위치 설정 (서버)'));
    await tester.pumpAndSettle();

    expect(find.text('전역 Positioning 설정'), findsOneWidget);
    expect(find.text('서버로 전송'), findsOneWidget);
  });
}
