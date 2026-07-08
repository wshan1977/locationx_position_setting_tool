import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'canvas/floor_canvas.dart';
import 'canvas/placement_3d_view.dart';
import 'panels/left_settings_panel.dart';
import 'panels/right_device_panel.dart';
import 'state/app_state.dart';
import 'state/mqtt_state.dart';
import 'tabs/data_monitor_tab.dart';
import 'tabs/device_settings_tab.dart';
import 'tabs/mqtt_viewer_tab.dart';
import 'widgets/toolbar.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => MqttState()),
      ],
      child: const LocationXApp(),
    ),
  );
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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
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
            child: TabBar(
              controller: _tabs,
              onTap: (_) => setState(() {}),
              tabs: const [
                Tab(icon: Icon(Icons.tune, size: 18), text: '장치 설정'),
                Tab(icon: Icon(Icons.map, size: 18), text: '위치 설정 (서버)'),
                Tab(icon: Icon(Icons.monitor_heart, size: 18), text: '데이터 수신'),
                Tab(icon: Icon(Icons.account_tree, size: 18), text: 'MQTT 뷰어'),
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _is3d ? const Placement3dView() : const FloorCanvas(),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: SegmentedButton<bool>(
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
              textStyle:
                  const WidgetStatePropertyAll(TextStyle(fontSize: 11.5)),
            ),
          ),
        ),
      ],
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
        const AppToolbar(),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            // 태블릿/좁은 창에서는 사이드 패널 폭을 줄인다
            final w = constraints.maxWidth;
            final settings = w >= 1200 ? 320.0 : (w * 0.26).clamp(200.0, 320.0);
            final devices = w >= 1200 ? 300.0 : (w * 0.24).clamp(180.0, 300.0);
            // 카드 검색 패널은 장치 설정 탭과 동일하게 왼쪽에 둔다
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
