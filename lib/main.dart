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
import 'services/case_mesh.dart';
import 'services/locator_images.dart';
import 'services/session_storage.dart';
import 'state/app_state.dart';
import 'state/external_state.dart';
import 'state/mqtt_state.dart';
import 'state/tag_state.dart';
import 'tabs/calibration_page.dart';
import 'tabs/data_monitor_tab.dart';
import 'tabs/device_settings_tab.dart';
import 'tabs/external_test_tab.dart';
import 'tabs/mqtt_viewer_tab.dart';
import 'tabs/sites_page.dart';
import 'tabs/tag_settings_tab.dart';
import 'widgets/hover_tip.dart';
import 'widgets/tab_guide.dart';
import 'widgets/toolbar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final app = AppState();
  final mqtt = MqttState();
  final ext = ExternalState();
  final tags = TagState();

  // 로케이터 실물 케이스 3D 메시·실물 사진 — 로드 후 다음 리페인트부터 표시
  unawaited(CaseMesh.ensureLoaded());
  unawaited(LocatorImages.ensureLoaded());

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
        ChangeNotifierProvider.value(value: tags),
        ChangeNotifierProvider.value(value: autoSaver),
      ],
      child: const LocationXApp(),
    ),
  );
}

/// 종료 시점에 MQTT가 연결돼 있었다면, Locator 검색으로 서버 주소가
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
    // 아이폰(iOS) 스타일: 시스템 블루 액센트 · 연회색 그룹 배경 위 흰 카드 ·
    // 큰 라운드 코너 · 플랫(무그림자) · iOS 스크롤 물리(platform: iOS)
    const iosBlue = Color(0xFF007AFF);
    return MaterialApp(
      title: 'LocationX Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        platform: TargetPlatform.iOS,
        colorScheme:
            ColorScheme.fromSeed(seedColor: iosBlue).copyWith(primary: iosBlue),
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
        ),
        dividerTheme: DividerThemeData(color: Colors.grey.shade300),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: iosBlue,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: iosBlue,
            side: BorderSide(color: Colors.grey.shade400),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: iosBlue),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
        ),
        dialogTheme: DialogThemeData(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: iosBlue,
          indicatorColor: iosBlue,
        ),
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

/// 상단 [설정] [관제] 두 탭 (175_BDCI 도구와 같은 구성). 각 탭 안은 왼쪽
/// 세로 메뉴(NavigationRail)로 화면을 고른다. 탭·메뉴를 바꿔도 캔버스와
/// 연결 상태가 유지되도록 모두 IndexedStack으로 둔다.
class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
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
                const SizedBox(width: 16),
                const Text('LocationX',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text('Manager',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade700)),
                if (_version.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text('v$_version',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
                const SizedBox(width: 24),
                SizedBox(
                  width: 240,
                  child: TabBar(
                    controller: _tabs,
                    onTap: (_) => setState(() {}),
                    tabs: const [
                      Tab(
                          height: 48,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.tune, size: 17),
                            SizedBox(width: 6),
                            Text('설정'),
                          ])),
                      Tab(
                          height: 48,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.monitor_heart_outlined, size: 17),
                            SizedBox(width: 6),
                            Text('관제'),
                          ])),
                    ],
                  ),
                ),
                const Spacer(),
                const _FloorSelector(),
                const SizedBox(width: 12),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tabs.index,
              children: const [
                _RailShell(
                  key: ValueKey('settings'),
                  items: [
                    _RailItem(Icons.apartment, '장소 · 층',
                        '장소(건물·현장)와 층을 등록·삭제하고\n작업할 층을 고릅니다.'),
                    _RailItem(Icons.settings_input_antenna, '① Locator 설정',
                        'UDP로 서버·로케이터 카드를 검색하고\n브로커·재부팅·LED·업데이트를 합니다.'),
                    _RailItem(Icons.sell, '② Tag 설정',
                        'PC 블루투스로 태그를 검색하고\n상태 읽기·펌웨어 OTA를 합니다.'),
                    _RailItem(Icons.map, '③ 위치 설정',
                        '선택한 층의 도면에 로케이터를 배치하고\n서버로 전송합니다.'),
                    _RailItem(Icons.tune, '④ 로케이터 보정',
                        '기준점에 태그를 두고 각도를 모아\n설치 기울기·회전을 보정합니다.'),
                  ],
                  pages: [
                    SitesPage(),
                    DeviceSettingsTab(),
                    TagSettingsTab(),
                    PositionSettingScreen(),
                    CalibrationPage(),
                  ],
                ),
                _RailShell(
                  key: ValueKey('monitor'),
                  items: [
                    _RailItem(Icons.monitor_heart, '데이터 수신',
                        '로케이터별 angle·position 수신 상태를\n확인합니다.'),
                    _RailItem(Icons.account_tree, 'MQTT 뷰어',
                        '내부망 브로커의 토픽과\n3D 위치를 확인합니다.'),
                    _RailItem(Icons.cloud_sync, '외부망',
                        '외부 브로커로 중계된 상태·위치를 보고\n원격 제어합니다.'),
                  ],
                  pages: [
                    DataMonitorTab(),
                    MqttViewerTab(),
                    ExternalTestTab(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem {
  final IconData icon;
  final String label;
  final String tip;
  const _RailItem(this.icon, this.label, this.tip);
}

/// 왼쪽 세로 메뉴 + 오른쪽 화면.
class _RailShell extends StatefulWidget {
  final List<_RailItem> items;
  final List<Widget> pages;

  const _RailShell({super.key, required this.items, required this.pages});

  @override
  State<_RailShell> createState() => _RailShellState();
}

class _RailShellState extends State<_RailShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NavigationRail(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          labelType: NavigationRailLabelType.all,
          minWidth: 96,
          destinations: [
            for (final it in widget.items)
              NavigationRailDestination(
                icon: Tooltip(message: it.tip, child: Icon(it.icon)),
                label: Text(it.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: IndexedStack(index: _index, children: widget.pages),
        ),
      ],
    );
  }
}

/// 상단 우측: 지금 작업 중인 장소 › 층. 눌러서 다른 층으로 바로 전환.
class _FloorSelector extends StatelessWidget {
  const _FloorSelector();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final book = app.sites;
    return PopupMenuButton<(String, String)>(
      tooltip: '작업할 장소 · 층 선택',
      onSelected: (v) async {
        final missing = await app.switchFloor(v.$1, v.$2);
        if (missing != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '도면 파일이 없습니다: $missing — [③ 위치 설정]에서 다시 불러오세요')));
        }
      },
      itemBuilder: (_) => [
        for (final s in book.sites) ...[
          PopupMenuItem(
            enabled: false,
            height: 30,
            child: Text(s.name,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          for (final f in s.floors)
            PopupMenuItem(
              value: (s.id, f.id),
              child: Row(children: [
                Icon(
                  s.id == book.activeSiteId && f.id == book.activeFloorId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(f.name),
              ]),
            ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.apartment, size: 16),
          const SizedBox(width: 6),
          Text('${app.activeSite.name} › ${app.activeFloor.name}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Icon(Icons.arrow_drop_down, size: 20),
        ]),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    hoverTip(
                      '로케이터를 실물 이미지로 표시합니다.\n'
                      'Top 뷰 = 실물 사진 (천장 설치는 뒷면 · 바닥 설치는 앞면)\n'
                      '3D 뷰 = 실물 케이스 형상',
                      FilterChip(
                        label: const Text('실물 이미지',
                            style: TextStyle(fontSize: 11)),
                        selected: context.watch<AppState>().showLocatorPhoto,
                        visualDensity: VisualDensity.compact,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.85),
                        onSelected: (v) =>
                            context.read<AppState>().setShowLocatorPhoto(v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    hoverTip(
                      'Top: 위에서 본 도면에서 배치 편집 (드래그로 이동)\n'
                      '3D: 설치 자세(orientation)를 입체로 확인',
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Top')),
                          ButtonSegment(value: true, label: Text('3D')),
                        ],
                        selected: {_is3d},
                        onSelectionChanged: (s) =>
                            setState(() => _is3d = s.first),
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: WidgetStatePropertyAll(
                              Colors.white.withValues(alpha: 0.85)),
                          textStyle: const WidgetStatePropertyAll(
                              TextStyle(fontSize: 11.5)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 설정 › ③ 위치 설정: 선택한 층의 도면·로케이터 배치.
class PositionSettingScreen extends StatelessWidget {
  const PositionSettingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const TabGuide(
          icon: Icons.map,
          text: '작업 순서: ① 도면 이미지 불러오기 → ② Locator 목록의 로케이터를 '
              '도면에 드래그해 배치 → ③ 좌표·설치 자세 조정 → ④ 서버로 전송',
        ),
        const AppToolbar(),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            // 태블릿/좁은 창에서는 사이드 패널 폭을 줄인다
            final w = constraints.maxWidth;
            final settings = w >= 1200 ? 320.0 : (w * 0.26).clamp(200.0, 320.0);
            final devices = w >= 1200 ? 300.0 : (w * 0.24).clamp(180.0, 300.0);
            // Locator 검색 패널은 Locator 설정 탭과 동일하게 왼쪽에 둔다
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
