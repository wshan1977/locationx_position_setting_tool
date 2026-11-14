import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:locationx_install_tool/main.dart';
import 'package:locationx_install_tool/services/session_storage.dart';
import 'package:locationx_install_tool/state/app_state.dart';
import 'package:locationx_install_tool/state/external_state.dart';
import 'package:locationx_install_tool/state/mqtt_state.dart';
import 'package:locationx_install_tool/state/tag_state.dart';

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

  testWidgets('settings/monitor tabs with rails render',
      (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('설정'), findsOneWidget);
    expect(find.text('AOD 모드 (위치측위)'), findsOneWidget);
    expect(find.text('AOA 모드 (방향각)'), findsOneWidget);
    expect(find.text('장소 · 층'), findsOneWidget);
    expect(find.text('① Locator 설정'), findsOneWidget);
    expect(find.text('② Tag 설정'), findsOneWidget);
    expect(find.text('③ 위치 설정'), findsOneWidget);

    // 첫 화면: 장소 · 층 (기본 장소 › 1층)
    expect(find.text('장소 추가'), findsOneWidget);
    expect(find.text('기본 장소 › 1층'), findsOneWidget);

    await tester.tap(find.text('① Locator 설정'));
    await tester.pumpAndSettle();
    expect(find.text('Locator 검색 (UDP)'), findsOneWidget);

    await tester.tap(find.text('AOD 모드 (위치측위)'));
    await tester.pumpAndSettle();
    expect(find.text('데이터 수신'), findsOneWidget);
    expect(find.textContaining('내부망\n('), findsOneWidget);
    expect(find.textContaining('외부망\n('), findsOneWidget);

    await tester.tap(find.text('AOA 모드 (방향각)'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('로케이터 각도'), findsOneWidget);
    expect(find.text('내부망 브로커에 연결하세요.'), findsOneWidget);
  });

  testWidgets('tag settings tab shows BLE scan and empty list',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('② Tag 설정'));
    await tester.pumpAndSettle();

    expect(find.text('Tag 검색 (BLE)'), findsOneWidget);
    expect(find.text('좌측에서 Tag를 선택하세요.'), findsOneWidget);
  });

  testWidgets('calibration page shows reference points and compute button',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('④ 로케이터 보정'));
    await tester.pumpAndSettle();

    expect(find.text('왼쪽 도면에서 태그를 놓은 위치를 클릭하세요.'), findsOneWidget);
    expect(find.text('보정 계산 (수집된 기준점 0곳)'), findsOneWidget);
    expect(find.text('MQTT 미연결'), findsOneWidget);

    // 도면 클릭 → 기준점 1 추가
    await tester.tapAt(const Offset(500, 600));
    await tester.pumpAndSettle();
    expect(find.text('기준점 (1)'), findsOneWidget);
  });

  testWidgets('position setting tab keeps 3-pane layout',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('③ 위치 설정'));
    await tester.pumpAndSettle();

    expect(find.text('전역 Positioning 설정'), findsOneWidget);
    expect(find.text('서버로 전송'), findsOneWidget);
  });
}
