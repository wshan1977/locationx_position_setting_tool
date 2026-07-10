import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'canvas/floor_canvas.dart';
import 'canvas/placement_3d_view.dart';
import 'models/session.dart';
import 'panels/left_settings_panel.dart';
import 'panels/right_device_panel.dart';
import 'services/session_storage.dart';
import 'state/app_state.dart';
import 'state/external_state.dart';
import 'state/mqtt_state.dart';
import 'tabs/data_monitor_tab.dart';
import 'tabs/device_settings_tab.dart';
import 'tabs/external_test_tab.dart';
import 'tabs/mqtt_viewer_tab.dart';
import 'widgets/hover_tip.dart';
import 'widgets/tab_guide.dart';
import 'widgets/toolbar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final app = AppState();
  final mqtt = MqttState();
  final ext = ExternalState();

  // 끄기 전 상태(도면/배치/서버 IP/MQTT 설정)를 즉시 복원
  final session = await SessionStorage.load();
  if (session != null) {
    await app.restoreSession(session);
    if (session.mqttHost.isNotEmpty) {
      mqtt.restoreEndpoint(session.mqttHost, session.mqttPort,
          filter: session.mqttFilter);
    }
    if (session.mqttConnected && session.mqttHost.isNotEmpty) {
      unawaited(_autoReconnect(app, mqtt, session));
    }
    // 외부망 탭은 프리필만 하고 자동 연결은 하지 않는다 (공개 브로커)
    ext.restore(session.extHost, session.extPort, session.extSiteId);
  }

  // 이후 변경은 자동으로 세션에 기록
  final autoSaver = SessionAutoSaver(app, mqtt, ext)..start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: mqtt),
        ChangeNotifierProvider.value(value: ext),
        ChangeNotifierProvider.value(value: autoSaver),
      ],
      child: const LocationXApp(),
    ),
  );
}

/// 종료 시점에 MQTT가 연결돼 있었다면, 장치 검색으로 서버 주소가
/// 그대로인지 확인한 뒤 자동으로 다시 연결한다.
/// (검색된 서버 카드 IP가 저장된 주소와 다르면 자동 연결하지 않음)
Future<void> _autoReconnect(
    AppState app, MqttState mqtt, SessionData session) async {
  try {
    await app.scan();
  } catch (_) {
    // 검색 실패(네트워크 등)는 무시하고 연결만 시도
  }
  final server = app.serverDevice;
  final serverMoved = server != null &&
      session.project.serverIp.isNotEmpty &&
      server.ip != session.project.serverIp;
  if (serverMoved) return;
  await mqtt.connect(session.mqttHost, session.mqttPort,
      filter: session.mqttFilter);
}

class LocationXApp extends StatelessWidget {
  const LocationXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocationX Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabs,
                    onTap: (_) => setState(() {}),
                    // 현장 작업 순서대로 번호를 붙인다: 장치 준비 → 배치 →
                    // 수신 점검 → 내부망 확인 → 외부망 확인
                    tabs: const [
                      Tab(icon: Icon(Icons.tune, size: 18),
                          text: '① 장치 설정'),
                      Tab(icon: Icon(Icons.map, size: 18),
                          text: '② 위치 설정 (서버)'),
                      Tab(icon: Icon(Icons.monitor_heart, size: 18),
                          text: '③ 데이터 수신'),
                      Tab(icon: Icon(Icons.account_tree, size: 18),
                          text: '④ MQTT 뷰어 (내부망)'),
                      Tab(icon: Icon(Icons.cloud_sync, size: 18),
                          text: '⑤ 외부망 테스트'),
                    ],
                  ),
                ),
                if (_version.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'v$_version',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            // 탭 전환 시에도 캔버스/연결 상태가 유지되도록 IndexedStack 사용
            child: IndexedStack(
              index: _tabs.index,
              children: const [
                DeviceSettingsTab(),
                PositionSettingScreen(),
                DataMonitorTab(),
                MqttViewerTab(),
                ExternalTestTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 위치 설정 캔버스 영역: Top view(배치 편집) ↔ 3D view(자세 확인·X/Y/Z 편집) 전환.
class _CanvasArea extends StatefulWidget {
  const _CanvasArea();

  @override
  State<_CanvasArea> createState() => _CanvasAreaState();
}

class _CanvasAreaState extends State<_CanvasArea> {
  bool _is3d = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'positionCanvas');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 캔버스 편집 실행 취소/다시 실행. 좌표 입력 필드에 포커스가 있을 때는
    // 텍스트 자체의 undo가 동작하고, 캔버스를 클릭하면 여기로 포커스가 온다.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            context.read<AppState>().undo(),
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): () => context.read<AppState>().redo(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
            context.read<AppState>().redo(),
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Listener(
          onPointerDown: (_) => _focusNode.requestFocus(),
          child: Stack(
            children: [
              Positioned.fill(
                child: _is3d ? const Placement3dView() : const FloorCanvas(),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: hoverTip(
                  'Top: 위에서 본 도면에서 배치 편집 (드래그로 이동)\n'
                  '3D: 설치 자세(orientation)를 입체로 확인',
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Top')),
                      ButtonSegment(value: true, label: Text('3D')),
                    ],
                    selected: {_is3d},
                    onSelectionChanged: (s) => setState(() => _is3d = s.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: WidgetStatePropertyAll(
                          Colors.white.withValues(alpha: 0.85)),
                      textStyle: const WidgetStatePropertyAll(
                          TextStyle(fontSize: 11.5)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 탭 2: AOA Locator 위치 설정 (기존 화면).
class PositionSettingScreen extends StatelessWidget {
  const PositionSettingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const TabGuide(
          icon: Icons.map,
          text: '작업 순서: ① 도면 이미지 불러오기 → ② 오른쪽 장치 목록의 로케이터를 '
              '도면에 드래그해 배치 → ③ 좌표·설치 자세 조정 → ④ 서버로 전송',
        ),
        const AppToolbar(),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            // 태블릿/좁은 창에서는 사이드 패널 폭을 줄인다
            final w = constraints.maxWidth;
            final settings = w >= 1200 ? 320.0 : (w * 0.26).clamp(200.0, 320.0);
            final devices = w >= 1200 ? 300.0 : (w * 0.24).clamp(180.0, 300.0);
            // 장치 검색 패널은 장치 설정 탭과 동일하게 왼쪽에 둔다
            return Row(
              children: [
                SizedBox(width: devices, child: const RightDevicePanel()),
                const Expanded(child: _CanvasArea()),
                SizedBox(width: settings, child: const LeftSettingsPanel()),
              ],
            );
          }),
        ),
      ],
    );
  }
}
