import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../canvas/case_mesh_renderer.dart';
import '../models/placement.dart';
import '../services/case_mesh.dart';
import '../state/app_state.dart';
import '../state/mqtt_state.dart';
import '../widgets/mqtt_connect_bar.dart';
import '../widgets/tab_guide.dart';

/// AOA 모드(방향각): 살아 있는 로케이터 하나를 골라 그 로케이터가 보고하는
/// 각도를 2D 원(방위 바늘 + 앙각 점) 또는 3D 뷰(안테나 판 + 방향 화살표)와
/// 흐르는 그래프(방위·앙각 따로)로 본다. 내부망 브로커의
/// `controlbit/aoa/angle/<locator>/<tag>` 를 받는다.
///
/// 각도 규약 (RTL 원값):
///  - 방위(azimuth): 안테나 판 위에서 보드 x축(0° · 빨간 노치)에서 y축(90° ·
///    초록) 쪽으로 돈 각도. 원값 -180~180.
///  - 앙각(elevation): 판 평면에서 정면(판에 수직) 쪽으로 올라온 각도.
///    0° = 판과 나란히(옆), 90° = 판 정면(천장 설치면 바로 아래).
///  - 방향 벡터 (보드 로컬) = (cos 앙각·cos 방위, cos 앙각·sin 방위, sin 앙각)
class AoaModePage extends StatefulWidget {
  const AoaModePage({super.key});

  @override
  State<AoaModePage> createState() => _AoaModePageState();
}

/// 각도 샘플 하나 (RTL 원값을 방위 0..360으로만 정규화).
class _Sample {
  final DateTime ts;
  final double az; // 0..360
  final double el; // 판 평면 기준 0..90 (90 = 정면)
  final double? rssi;
  const _Sample(this.ts, this.az, this.el, this.rssi);
}

/// 표시 설정 (이 화면 전용).
class _AoaSettings {
  bool signedAz = false; // 방위를 -180~180으로
  bool elFromNormal = false; // 앙각을 정면 기준(0 = 정면)으로
  bool worldFrame = false; // 3D: 실제 설치 방향(위치 설정 orientation)으로
  bool showCase = true; // 3D: 실물 케이스
  int windowSec = 60; // 그래프 시간 폭
  int trailSec = 5; // 자취 길이

  double az(double az360) => signedAz && az360 > 180 ? az360 - 360 : az360;
  double el(double elPlane) => elFromNormal ? 90 - elPlane : elPlane;
  String get azRange => signedAz ? '-180~180°' : '0~360°';
  String get elNote => elFromNormal ? '0 = 정면' : '90 = 정면';
}

class _AoaModePageState extends State<AoaModePage> {
  static const _aliveAfter = Duration(seconds: 10); // 이 시간 수신 없으면 끊김
  static const _keep = Duration(seconds: 120); // 최대 보관 (그래프 최대 폭)

  StreamSubscription<MqttMessageRecord>? _sub;
  Timer? _tick;

  // 로케이터 ID → 태그 ID → 최근 샘플
  final _data = <String, Map<String, List<_Sample>>>{};
  String? _locator;

  // 태그 표시: 체크를 끈 태그 · 처음 수신 순서 (색이 태그를 따라가도록 고정)
  final _hiddenTags = <String>{};
  final _tagOrder = <String>[];

  Color _colorOf(String tag) {
    final i = _tagOrder.indexOf(tag);
    return _tagPalette[(i < 0 ? 0 : i) % _tagPalette.length];
  }

  final _cfg = _AoaSettings();
  bool _is3d = false;
  double _yaw = -0.7, _pitch = 0.9; // 3D 시점

  @override
  void initState() {
    super.initState();
    _sub = context.read<MqttState>().records.listen(_onRecord);
    // 그래프가 흐르도록 주기적으로 다시 그림 (수신이 없어도 시간축은 흐름)
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(_prune);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _onRecord(MqttMessageRecord r) {
    final parts = r.topic.split('/');
    // <루트>/aoa/angle/<locator>/<tag> (내부 토픽도 MqttState가 고객용 이름으로 바꿔 줌)
    if (parts.length < 5 || parts[1] != 'aoa' || parts[2] != 'angle') return;
    Map<String, dynamic> j;
    try {
      j = jsonDecode(r.payload) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final az = (j['azimuth'] as num?)?.toDouble();
    final el = (j['elevation'] as num?)?.toDouble();
    if (az == null || el == null) return;
    final s = _Sample(r.ts, (az % 360 + 360) % 360, el, (j['rssi'] as num?)?.toDouble());
    _data.putIfAbsent(parts[3], () => {}).putIfAbsent(parts[4], () => []).add(s);
    if (!_tagOrder.contains(parts[4])) _tagOrder.add(parts[4]);
  }

  void _prune() {
    final cut = DateTime.now().subtract(_keep);
    for (final tags in _data.values) {
      for (final l in tags.values) {
        l.removeWhere((s) => s.ts.isBefore(cut));
      }
      tags.removeWhere((_, l) => l.isEmpty);
    }
    _data.removeWhere((_, t) => t.isEmpty);
  }

  DateTime? _lastSeen(String loc) {
    DateTime? t;
    for (final l in _data[loc]!.values) {
      if (l.isNotEmpty && (t == null || l.last.ts.isAfter(t))) t = l.last.ts;
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttState>();
    final app = context.watch<AppState>();
    final locs = _data.keys.toList()..sort();
    if (_locator == null || !_data.containsKey(_locator)) {
      _locator = locs.isEmpty ? null : locs.first;
    }
    final tags = _locator == null ? <String>[] : (_data[_locator]!.keys.toList()..sort());
    final series = <String, List<_Sample>>{
      for (final t in tags)
        if (!_hiddenTags.contains(t)) t: _data[_locator]![t]!,
    };
    final colors = {for (final t in tags) t: _colorOf(t)};
    final placement = app.placements.where((p) => p.locatorId == _locator).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabGuide(
          icon: Icons.explore,
          text: '살아 있는 로케이터를 골라 태그가 있는 방향(방향각)을 실시간으로 봅니다 — '
              '2D 원 / 3D 뷰 · 오른쪽 그래프는 최근 각도 · [방위·앙각이란?]에 설명',
        ),
        if (!mqtt.isConnected) const MqttConnectBar(),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 240, child: _locatorList(app, locs)),
              const VerticalDivider(width: 1),
              Expanded(
                child: _locator == null
                    ? Center(
                        child: Text(
                          mqtt.isConnected
                              ? '각도를 보내는 로케이터가 없습니다.\n태그가 켜져 있는지 확인하세요.'
                              : '내부망 브로커에 연결하세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : _detail(tags, series, colors, placement),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _locatorList(AppState app, List<String> locs) {
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text('로케이터 (${locs.length})',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        for (final id in locs)
          Builder(builder: (_) {
            final seen = _lastSeen(id);
            final alive = seen != null && now.difference(seen) < _aliveAfter;
            final short = id.length >= 4 ? id.substring(id.length - 4) : id;
            final dev = app.devices.where((d) => !d.isServer && d.locatorId == id).firstOrNull;
            return Card(
              color: id == _locator
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                  : null,
              child: ListTile(
                dense: true,
                selected: id == _locator,
                leading: Icon(Icons.settings_input_antenna,
                    color: alive ? Colors.green.shade600 : Colors.grey),
                title: Text(short, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${dev?.ip ?? id}\n${alive ? '수신 중' : '끊김'} · 태그 ${_data[id]!.length}'),
                isThreeLine: true,
                onTap: () => setState(() => _locator = id),
              ),
            );
          }),
      ],
    );
  }

  Widget _detail(List<String> tags, Map<String, List<_Sample>> series, Map<String, Color> colors,
      PlacedLocator? placement) {
    final short = _locator!.length >= 4 ? _locator!.substring(_locator!.length - 4) : _locator!;
    final window = Duration(seconds: _cfg.windowSec);
    final since = DateTime.now().subtract(window);
    final shown = {
      for (final e in series.entries) e.key: e.value.where((s) => !s.ts.isBefore(since)).toList(),
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Text('로케이터 $short',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              // 태그 체크: 끈 태그는 원·3D·그래프에서 뺀다 (색은 태그마다 고정)
              for (final t in tags)
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  avatar: CircleAvatar(backgroundColor: colors[t], radius: 6),
                  label: Text(t.length >= 4 ? t.substring(t.length - 4) : t,
                      style: const TextStyle(fontSize: 12)),
                  tooltip: t,
                  selected: !_hiddenTags.contains(t),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _hiddenTags.remove(t);
                    } else {
                      _hiddenTags.add(t);
                    }
                  }),
                ),
              SegmentedButton<bool>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('2D')),
                  ButtonSegment(value: true, label: Text('3D')),
                ],
                selected: {_is3d},
                onSelectionChanged: (v) => setState(() => _is3d = v.first),
              ),
              TextButton.icon(
                onPressed: _showHelp,
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('방위·앙각이란?'),
              ),
              TextButton.icon(
                onPressed: _showSettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('표시 설정'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 태그별 현재 값 (색 점 = 그림의 태그 색)
          Wrap(spacing: 18, runSpacing: 4, children: [
            for (final e in series.entries)
              if (e.value.isNotEmpty)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(backgroundColor: colors[e.key], radius: 5),
                  const SizedBox(width: 6),
                  Text(
                    '${e.key.length >= 4 ? e.key.substring(e.key.length - 4) : e.key}  '
                    '방위 ${_cfg.az(e.value.last.az).toStringAsFixed(1)}° · '
                    '앙각 ${_cfg.el(e.value.last.el).toStringAsFixed(1)}°'
                    '${e.value.last.rssi == null ? '' : ' · RSSI ${e.value.last.rssi!.toStringAsFixed(0)} dBm'}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ]),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 4,
                  child: _is3d
                      ? _view3d(series, colors, placement)
                      : Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: CustomPaint(painter: _DialPainter(series, colors, _cfg)),
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: CustomPaint(
                          painter: _TracePainter(
                              shown,
                              colors,
                              (s) => _cfg.az(s.az),
                              _cfg.signedAz ? -180 : 0,
                              _cfg.signedAz ? 180 : 360,
                              90,
                              '방위 (°) · ${_cfg.azRange}',
                              window),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: CustomPaint(
                          painter: _TracePainter(shown, colors, (s) => _cfg.el(s.el), 0, 90, 30,
                              '앙각 (°) · ${_cfg.elNote}', window),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _view3d(
      Map<String, List<_Sample>> series, Map<String, Color> colors, PlacedLocator? placement) {
    final world = _cfg.worldFrame && placement != null;
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          onPanUpdate: (d) => setState(() {
            _yaw += d.delta.dx * 0.01;
            _pitch = (_pitch + d.delta.dy * 0.01).clamp(0.1, 1.5);
          }),
          child: CustomPaint(
            painter: _Aoa3dPainter(
              series: series,
              colors: colors,
              cfg: _cfg,
              yaw: _yaw,
              pitch: _pitch,
              placement: world ? placement : null,
            ),
          ),
        ),
      ),
      Positioned(
        left: 4,
        bottom: 4,
        child: Text(
          '드래그: 시점 회전 · '
          '${world ? '실제 설치 방향 (위치 설정 자세)' : '로케이터 기준 (안테나 판이 바닥)'}'
          '${_cfg.worldFrame && placement == null ? ' · 위치 설정에 배치되지 않은 로케이터' : ''}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ),
    ]);
  }

  void _showSettings() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        void upd(VoidCallback f) {
          setD(f);
          setState(() {});
        }

        return AlertDialog(
          title: const Text('AOA 모드 표시 설정'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(
                title: const Text('방위를 -180~180°로 표시'),
                subtitle: const Text('끄면 0~360° (0° = 보드 x축 · 빨간 노치 방향)'),
                value: _cfg.signedAz,
                onChanged: (v) => upd(() => _cfg.signedAz = v),
              ),
              SwitchListTile(
                title: const Text('앙각을 정면 기준으로 표시'),
                subtitle: const Text('켜면 0° = 판 정면(수직), 90° = 판과 나란히\n'
                    '끄면 RTL 원값: 0° = 판과 나란히, 90° = 정면'),
                value: _cfg.elFromNormal,
                onChanged: (v) => upd(() => _cfg.elFromNormal = v),
              ),
              SwitchListTile(
                title: const Text('3D: 실제 설치 방향으로 보기'),
                subtitle: const Text('위치 설정의 자세(orientation)를 적용해 방 기준으로 그림\n'
                    '끄면 로케이터 기준 (안테나 판을 바닥에 눕혀서)'),
                value: _cfg.worldFrame,
                onChanged: (v) => upd(() => _cfg.worldFrame = v),
              ),
              SwitchListTile(
                title: const Text('3D: 실물 케이스 표시'),
                value: _cfg.showCase,
                onChanged: (v) => upd(() => _cfg.showCase = v),
              ),
              ListTile(
                title: const Text('그래프 시간 폭'),
                trailing: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 30, label: Text('30초')),
                    ButtonSegment(value: 60, label: Text('60초')),
                    ButtonSegment(value: 120, label: Text('120초')),
                  ],
                  selected: {_cfg.windowSec},
                  onSelectionChanged: (v) => upd(() => _cfg.windowSec = v.first),
                ),
              ),
              ListTile(
                title: const Text('자취 길이'),
                trailing: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('없음')),
                    ButtonSegment(value: 5, label: Text('5초')),
                    ButtonSegment(value: 15, label: Text('15초')),
                  ],
                  selected: {_cfg.trailSec},
                  onSelectionChanged: (v) => upd(() => _cfg.trailSec = v.first),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
          ],
        );
      }),
    );
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('방위·앙각이란?'),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                height: 210,
                width: double.infinity,
                child: CustomPaint(painter: _HelpPainter()),
              ),
              const SizedBox(height: 12),
              const Text('로케이터는 안테나 판(4x4)을 기준으로 "태그가 어느 쪽에 있는지"를 두 각도로 알려 줍니다.',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('• 방위 (azimuth): 판 위에서 돌아간 방향 — 보드 x축(0° · 빨간 노치 · 커넥터 쪽)에서 '
                  'y축(90° · 초록) 쪽으로 잰 각도. 나침반처럼 "어느 쪽"을 뜻합니다.'),
              const SizedBox(height: 6),
              const Text('• 앙각 (elevation): 판에서 얼마나 "정면 쪽으로" 올라왔는지 — 0° = 판과 나란히(옆), '
                  '90° = 판 정면(판에 수직). 천장에 아래를 보고 달린 로케이터라면 90° = 바로 아래이고, '
                  '각도가 작을수록 멀리 비스듬히 있는 태그입니다.'),
              const SizedBox(height: 6),
              const Text('• 2D 원: 바늘 = 방위, 점이 가운데일수록 정면(앙각 90°), 테두리일수록 옆(0°).\n'
                  '• 3D: 화살표 = 태그 방향, 판 위 점선 = 방위, 세로 점선 = 앙각.\n'
                  '• 태그가 여럿이면 태그마다 색이 다르며, 위쪽 태그 칩으로 보일 태그를 고릅니다.'),
              const SizedBox(height: 6),
              Text('표시 기준(방위 0~360 / -180~180, 앙각 기준)은 [표시 설정]에서 바꿀 수 있습니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
  }
}

const _ink = Color(0xFF37474F); // 텍스트·축
const _grid = Color(0x1F37474F); // 은은한 격자
const _series = Color(0xFF1E6FD9); // 도움말 그림의 방향 화살표

/// 태그 색 — AOD(위치측위) 화면과 같은 순서 (처음 수신한 태그부터).
const _tagPalette = [
  Colors.red,
  Colors.deepPurple,
  Colors.green,
  Colors.brown,
  Colors.pink,
  Colors.indigo,
];
const _xAxis = Color(0xFFD32F2F); // 보드 x (0°)
const _yAxis = Color(0xFF388E3C); // 보드 y (90°)
const _zAxis = Color(0xFF5C6BC0); // 판 정면

void _text(Canvas c, String s, Offset at, {double size = 11, Color color = _ink, bool center = false}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
}

void _dashed(Canvas canvas, Offset a, Offset b, Paint p, {double dash = 4, double gap = 3}) {
  final total = (b - a).distance;
  if (total < 1e-3) return;
  final dir = (b - a) / total;
  for (var d = 0.0; d < total; d += dash + gap) {
    canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), p);
  }
}

/// 0~360° 원: 방위 바늘 + 앙각 점(가운데 = 90° 정면, 테두리 = 0° 판 평면) + 자취.
class _DialPainter extends CustomPainter {
  final Map<String, List<_Sample>> series;
  final Map<String, Color> colors;
  final _AoaSettings cfg;
  _DialPainter(this.series, this.colors, this.cfg);

  // 화면 위쪽 = 0°(보드 x), 시계 반대 방향으로 증가 (판 정면에서 바라본 모양)
  Offset _pt(Offset c, double r, double azDeg, double el) {
    final rr = r * (1 - el.clamp(0, 90) / 90);
    final a = azDeg * math.pi / 180;
    return c + Offset(-math.sin(a), -math.cos(a)) * rr;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 24;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = _grid
      ..strokeWidth = 1;
    for (final el in [0.0, 30.0, 60.0]) {
      canvas.drawCircle(c, r * (1 - el / 90), line);
    }
    canvas.drawCircle(c, r, line..color = _ink.withValues(alpha: 0.5));
    for (var d = 0; d < 360; d += 10) {
      final a = d * math.pi / 180;
      final dir = Offset(-math.sin(a), -math.cos(a));
      final big = d % 30 == 0;
      final axisCol = d == 0 ? _xAxis : (d == 90 ? _yAxis : null);
      canvas.drawLine(c + dir * r, c + dir * (r - (big ? 10 : 5)),
          Paint()
            ..color = axisCol ?? _ink.withValues(alpha: big ? 0.7 : 0.35)
            ..strokeWidth = axisCol != null ? 2.4 : 1);
      if (big) {
        _text(canvas, '${cfg.az(d.toDouble()).toStringAsFixed(0)}°', c + dir * (r + 13),
            size: 10, center: true, color: axisCol ?? _ink);
      }
    }
    for (final el in [30, 60]) {
      _text(canvas, '앙각 ${cfg.el(el.toDouble()).toStringAsFixed(0)}°',
          c + Offset(3, -r * (1 - el / 90) - 13),
          size: 9, color: _ink.withValues(alpha: 0.6));
    }
    _text(canvas, '정면', c + const Offset(6, 4), size: 9, color: _ink.withValues(alpha: 0.6));

    for (final e in series.entries) {
      final samples = e.value;
      if (samples.isEmpty) continue;
      final col = colors[e.key] ?? Colors.red;
      if (cfg.trailSec > 0) {
        final since = samples.last.ts.subtract(Duration(seconds: cfg.trailSec));
        final trail = samples.where((s) => !s.ts.isBefore(since)).toList();
        for (var i = 0; i < trail.length; i++) {
          final f = (i + 1) / trail.length;
          canvas.drawCircle(_pt(c, r, trail[i].az, trail[i].el), 2.5,
              Paint()..color = col.withValues(alpha: 0.12 + 0.3 * f));
        }
      }
      final s = samples.last;
      final a = s.az * math.pi / 180;
      final dir = Offset(-math.sin(a), -math.cos(a));
      canvas.drawLine(c, c + dir * r,
          Paint()
            ..color = col
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round);
      // 겹친 점은 흰 테두리(2px)로 구분
      final p = _pt(c, r, s.az, s.el);
      canvas.drawCircle(p, 7, Paint()..color = Colors.white);
      canvas.drawCircle(p, 5, Paint()..color = col);
    }
    canvas.drawCircle(c, 3, Paint()..color = _ink);
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) => true;
}

/// Rz·Ry·Rx (도) row-major 3x3 — 위치 설정과 같은 규약.
List<double> _euler(double xDeg, double yDeg, double zDeg) {
  final a = xDeg * math.pi / 180, b = yDeg * math.pi / 180, c = zDeg * math.pi / 180;
  final ca = math.cos(a), sa = math.sin(a);
  final cb = math.cos(b), sb = math.sin(b);
  final cc = math.cos(c), sc = math.sin(c);
  return [
    cc * cb, cc * sb * sa - sc * ca, cc * sb * ca + sc * sa, //
    sc * cb, sc * sb * sa + cc * ca, sc * sb * ca - cc * sa, //
    -sb, cb * sa, cb * ca,
  ];
}

const _identity = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];

/// 3D 뷰: 안테나 판(또는 실물 케이스) + 보드 축 + 앙각 반구 가이드 +
/// 태그 방향 화살표 + 방위(판 위 점선)·앙각(세로 점선) 보조선.
/// [placement]가 있으면 그 자세(orientation)로 돌려 방 기준으로 그린다.
class _Aoa3dPainter extends CustomPainter {
  final Map<String, List<_Sample>> series;
  final Map<String, Color> colors;
  final _AoaSettings cfg;
  final double yaw, pitch;
  final PlacedLocator? placement;

  _Aoa3dPainter({
    required this.series,
    required this.colors,
    required this.cfg,
    required this.yaw,
    required this.pitch,
    required this.placement,
  });

  Matrix4 _m = Matrix4.identity();
  List<double> _r = _identity; // 보드 로컬 → 그릴 좌표

  Offset _p(double x, double y, double z) {
    final wx = _r[0] * x + _r[1] * y + _r[2] * z;
    final wy = _r[3] * x + _r[4] * y + _r[5] * z;
    final wz = _r[6] * x + _r[7] * y + _r[8] * z;
    final s = _m.storage;
    final tx = s[0] * wx + s[4] * wy + s[8] * wz + s[12];
    final ty = s[1] * wx + s[5] * wy + s[9] * wz + s[13];
    final tw = s[3] * wx + s[7] * wy + s[11] * wz + s[15];
    return Offset(tx / tw, ty / tw);
  }

  Offset _pv(List<double> v, [double k = 1]) => _p(v[0] * k, v[1] * k, v[2] * k);

  static List<double> _vec(double azDeg, double elDeg) {
    final a = azDeg * math.pi / 180, e = elDeg * math.pi / 180;
    return [math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) * 0.36;
    _m = Matrix4.identity()
      ..translate(size.width / 2, size.height * 0.58)
      ..setEntry(3, 2, -0.0009)
      ..rotateX(math.pi / 2 - pitch)
      ..rotateZ(yaw)
      ..scale(scale, -scale, scale);
    final p = placement;

    // 실제 설치 방향이면 방 바닥 격자로 위아래 감 잡기
    if (p != null) {
      _r = _identity;
      final g = Paint()
        ..color = _grid
        ..strokeWidth = 1;
      for (var i = -2; i <= 2; i++) {
        canvas.drawLine(_p(i * 0.5, -1, -1.1), _p(i * 0.5, 1, -1.1), g);
        canvas.drawLine(_p(-1, i * 0.5, -1.1), _p(1, i * 0.5, -1.1), g);
      }
      _text(canvas, '방 바닥', _p(1, -1, -1.1), size: 10, color: _ink.withValues(alpha: 0.6));
    }
    _r = p == null ? _identity : _euler(p.orientation.x, p.orientation.y, p.orientation.z);

    // 앙각 반구 가이드: 판 평면 원(0°) + 30°/60° 위도선 + 방위 30° 경선
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final el in [0.0, 30.0, 60.0]) {
      canvas.drawPoints(
          PointMode.polygon,
          [for (var d = 0; d <= 360; d += 6) _pv(_vec(d.toDouble(), el))],
          guide..color = el == 0 ? _ink.withValues(alpha: 0.35) : _grid);
    }
    for (var d = 0; d < 360; d += 30) {
      canvas.drawPoints(PointMode.polygon,
          [for (var e = 0; e <= 90; e += 6) _pv(_vec(d.toDouble(), e.toDouble()))], guide..color = _grid);
      _text(canvas, '${cfg.az(d.toDouble()).toStringAsFixed(0)}°', _pv(_vec(d.toDouble(), 0), 1.12),
          size: 9, center: true, color: _ink.withValues(alpha: 0.7));
    }

    // 안테나 판 / 실물 케이스
    final mesh = cfg.showCase ? CaseMesh.instance : null;
    if (mesh != null) {
      final rot = p == null
          ? CaseMesh.drawRotation(0, 0, 0)
          : CaseMesh.drawRotation(p.orientation.x, p.orientation.y, p.orientation.z,
              flip: p.imageFlip);
      // 케이스를 반구(반지름 1)의 절반쯤 크기로 (화살표가 가리지 않게)
      const k = 1.8;
      drawCaseMesh(canvas, mesh,
          rot: rot, cx: 0, cy: 0, cz: 0, cam: _m.storage,
          color: const Color(0xFFB9C3CD), scale: k);
    } else {
      const h = 0.35;
      final c1 = _p(-h, -h, 0), c2 = _p(h, -h, 0), c3 = _p(h, h, 0), c4 = _p(-h, h, 0);
      final plate = Path()
        ..moveTo(c1.dx, c1.dy)
        ..lineTo(c2.dx, c2.dy)
        ..lineTo(c3.dx, c3.dy)
        ..lineTo(c4.dx, c4.dy)
        ..close();
      canvas.drawPath(plate, Paint()..color = const Color(0x334C7FB0));
      canvas.drawPath(
          plate,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0xFF4C7FB0)
            ..strokeWidth = 1.4);
    }

    // 보드 축: x(0°) 빨강 · y(90°) 초록 · 정면 남색
    final o = _p(0, 0, 0);
    void axis(double x, double y, double z, Color c, String name) {
      final e = _p(x, y, z);
      canvas.drawLine(o, e, Paint()
        ..color = c
        ..strokeWidth = 2.2);
      _text(canvas, name, e + const Offset(4, -6), size: 10, color: c);
    }

    axis(0.75, 0, 0, _xAxis, 'x · 방위 0°');
    axis(0, 0.75, 0, _yAxis, 'y · 방위 90°');
    axis(0, 0, 0.75, _zAxis, '정면 · 앙각 90°');

    final many = series.values.where((l) => l.isNotEmpty).length > 1;
    for (final e in series.entries) {
      final samples = e.value;
      if (samples.isEmpty) continue;
      final col = colors[e.key] ?? Colors.red;
      if (cfg.trailSec > 0) {
        final since = samples.last.ts.subtract(Duration(seconds: cfg.trailSec));
        final trail = samples.where((s) => !s.ts.isBefore(since)).toList();
        for (var i = 0; i < trail.length; i++) {
          canvas.drawCircle(_pv(_vec(trail[i].az, trail[i].el)), 2.5,
              Paint()..color = col.withValues(alpha: 0.12 + 0.3 * (i + 1) / trail.length));
        }
      }

      // 현재 방향: 화살표 + 방위(판 위 그림자) + 앙각(세로선)
      final s = samples.last;
      final v = _vec(s.az, s.el);
      final tip = _pv(v);
      final foot = _p(v[0], v[1], 0); // 판 평면에 내린 그림자
      final aux = Paint()
        ..color = col.withValues(alpha: 0.7)
        ..strokeWidth = 1.4;
      _dashed(canvas, o, foot, aux);
      _dashed(canvas, foot, tip, aux);
      canvas.drawLine(o, tip, Paint()
        ..color = col
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round);
      canvas.drawCircle(tip, 7, Paint()..color = Colors.white);
      canvas.drawCircle(tip, 5, Paint()..color = col);
      final name = many ? '${e.key.length >= 4 ? e.key.substring(e.key.length - 4) : e.key} ' : '';
      _text(canvas, '$name방위 ${cfg.az(s.az).toStringAsFixed(0)}°', foot + const Offset(6, 2), size: 11);
      _text(canvas, '$name앙각 ${cfg.el(s.el).toStringAsFixed(0)}°', tip + const Offset(8, -8), size: 11);
    }
  }

  @override
  bool shouldRepaint(covariant _Aoa3dPainter old) => true;
}

/// 도움말 그림: 비스듬한 안테나 판 + x/y 축 + 태그 방향과 두 각도.
class _HelpPainter extends CustomPainter {
  const _HelpPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final o = Offset(size.width * 0.36, size.height * 0.74);
    const w = 160.0, d = 64.0;
    final plate = Path()
      ..moveTo(o.dx - w / 2 - d / 2, o.dy + d / 3)
      ..lineTo(o.dx + w / 2 - d / 2, o.dy + d / 3)
      ..lineTo(o.dx + w / 2 + d / 2, o.dy - d / 3)
      ..lineTo(o.dx - w / 2 + d / 2, o.dy - d / 3)
      ..close();
    canvas.drawPath(plate, Paint()..color = const Color(0x334C7FB0));
    canvas.drawPath(
        plate,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF4C7FB0));
    _text(canvas, '안테나 판', o + const Offset(-120, 24), size: 11);
    final xEnd = o + const Offset(100, 0);
    final yEnd = o + const Offset(42, -32);
    final zEnd = o + const Offset(0, -135);
    canvas.drawLine(o, xEnd, Paint()
      ..color = _xAxis
      ..strokeWidth = 2);
    canvas.drawLine(o, yEnd, Paint()
      ..color = _yAxis
      ..strokeWidth = 2);
    _dashed(canvas, o, zEnd, Paint()
      ..color = _zAxis
      ..strokeWidth = 1.4);
    _text(canvas, 'x (방위 0°)', xEnd + const Offset(4, -6), size: 11, color: _xAxis);
    _text(canvas, 'y (방위 90°)', yEnd + const Offset(4, -16), size: 11, color: _yAxis);
    _text(canvas, '정면 (앙각 90°)', zEnd + const Offset(-40, -16), size: 11, color: _zAxis);
    final foot = o + const Offset(84, -22);
    final tip = foot + const Offset(0, -84);
    final aux = Paint()
      ..color = _series.withValues(alpha: 0.7)
      ..strokeWidth = 1.4;
    _dashed(canvas, o, foot, aux);
    _dashed(canvas, foot, tip, aux);
    canvas.drawLine(o, tip, Paint()
      ..color = _series
      ..strokeWidth = 3);
    canvas.drawCircle(tip, 5, Paint()..color = _series);
    _text(canvas, '태그 방향', tip + const Offset(8, -6), size: 11, color: _series);
    canvas.drawArc(
        Rect.fromCircle(center: o, radius: 36),
        -0.26,
        0.26,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _ink
          ..strokeWidth = 1.2);
    _text(canvas, '방위', o + const Offset(40, -18), size: 11);
    _text(canvas, '앙각', foot + const Offset(6, -48), size: 11);
    _text(canvas, '판 위 점선 = 어느 쪽(방위)\n세로 점선 = 판에서 올라온 정도(앙각)',
        Offset(size.width * 0.66, size.height * 0.18),
        size: 11, color: _ink.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 흐르는 그래프 (최근 [window] · 오른쪽 끝 = 지금). 계열 하나라 범례 대신 제목.
class _TracePainter extends CustomPainter {
  final Map<String, List<_Sample>> series;
  final Map<String, Color> colors;
  final double Function(_Sample) value;
  final double min, max, step;
  final String title;
  final Duration window;
  _TracePainter(this.series, this.colors, this.value, this.min, this.max, this.step, this.title,
      this.window);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0, top = 18.0, right = 8.0, bottom = 16.0;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    _text(canvas, title, const Offset(0, 0), size: 12);
    // 범례: 계열이 2개 이상일 때만 (하나면 제목으로 충분)
    final live = series.entries.where((e) => e.value.isNotEmpty).toList();
    if (live.length > 1) {
      var lx = size.width - right;
      for (final e in live.reversed) {
        final name = e.key.length >= 4 ? e.key.substring(e.key.length - 4) : e.key;
        final tp = TextPainter(
          text: TextSpan(text: name, style: const TextStyle(fontSize: 11, color: _ink)),
          textDirection: TextDirection.ltr,
        )..layout();
        lx -= tp.width;
        tp.paint(canvas, Offset(lx, 1));
        lx -= 18;
        canvas.drawLine(Offset(lx, 8), Offset(lx + 14, 8), Paint()
          ..color = colors[e.key] ?? Colors.red
          ..strokeWidth = 2);
        lx -= 10;
      }
    }
    if (plot.width <= 0 || plot.height <= 0) return;

    double y(double v) => plot.bottom - (v - min) / (max - min) * plot.height;
    final now = DateTime.now();
    double x(DateTime t) =>
        plot.right - now.difference(t).inMilliseconds / window.inMilliseconds * plot.width;

    final grid = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    for (var v = min; v <= max + 1e-6; v += step) {
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), grid);
      _text(canvas, v.toStringAsFixed(0), Offset(0, y(v) - 7), size: 10);
    }
    final tickSec = window.inSeconds <= 30 ? 5 : (window.inSeconds <= 60 ? 10 : 20);
    for (var s = 0; s <= window.inSeconds; s += tickSec) {
      final xx = plot.right - s / window.inSeconds * plot.width;
      _text(canvas, s == 0 ? '지금' : '-${s}s', Offset(xx - 10, plot.bottom + 2),
          size: 9, color: _ink.withValues(alpha: 0.7));
    }

    canvas.save();
    canvas.clipRect(plot);
    for (final e in live) {
      final samples = e.value;
      final col = colors[e.key] ?? Colors.red;
      final paint = Paint()
        ..color = col
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      var started = false;
      double? prev;
      for (final s in samples) {
        final v = value(s);
        final pt = Offset(x(s.ts), y(v));
        // 방위 경계(0/360 또는 ±180)를 넘는 점프는 선을 끊는다
        final gap = prev != null && (v - prev).abs() > (max - min) / 2;
        if (!started || gap) {
          path.moveTo(pt.dx, pt.dy);
          started = true;
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
        prev = v;
      }
      canvas.drawPath(path, paint);
      final l = samples.last;
      final end = Offset(x(l.ts), y(value(l)));
      canvas.drawCircle(end, 5, Paint()..color = Colors.white);
      canvas.drawCircle(end, 4, Paint()..color = col);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TracePainter old) => true;
}
