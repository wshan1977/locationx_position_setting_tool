import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../canvas/case_mesh_renderer.dart';
import '../canvas/world_transform.dart';
import '../models/placement.dart';
import '../services/case_mesh.dart';
import '../services/locator_images.dart';
import '../state/app_state.dart';
import '../state/mqtt_state.dart';
import '../widgets/hover_tip.dart';

/// MQTT 뷰어 탭의 서브탭: 3D 위치인식 확인.
///
/// 설치자가 보고 판단할 수 있도록:
/// - 로케이터는 자세(orientation)를 가진 보드 모양으로 그린다
///   (천장/벽/바닥 설치 판정 + 바라보는 방향 화살표 + 회전 기준 노치).
/// - 천장 설치면 바닥 커버리지 원을 점선으로 표시한다.
/// - angle 방향 점선, 태그 위치(+오차 원, 궤적)를 실시간 표시한다.
///
/// 3D 모드: 회전 가능한 입체 시점 (드래그=회전, 휠=줌).
/// 2D 모드: 위에서 본 평면도 (드래그=이동, 휠=줌).
class PositionLiveView extends StatefulWidget {
  /// angle 데이터가 있는 연결인지. 외부망 중계는 position만 포워딩하므로
  /// false — angle 점선 토글·레이 표시를 숨긴다.
  final bool supportsAngle;

  /// 로케이터 배치 소스 재정의. null이면 AppState.placements(로컬 프로젝트)를
  /// 쓴다. 외부망 탭은 서버 카드가 중계한 배치(placements 토픽)를 넘겨,
  /// 내부망에 접속한 적 없는 PC에서도 로케이터가 보이게 한다.
  final List<PlacedLocator>? placements;

  const PositionLiveView({super.key, this.supportsAngle = true, this.placements});

  @override
  State<PositionLiveView> createState() => _PositionLiveViewState();
}

/// 화면에 그릴 angle 레이 1개.
class _AngleRay {
  final String locatorId;
  final String tagId;
  final double azimuth;
  final double elevation;
  final double distance;
  final bool live;

  _AngleRay({
    required this.locatorId,
    required this.tagId,
    required this.azimuth,
    required this.elevation,
    required this.distance,
    required this.live,
  });
}

class _TrailPoint {
  final Offset xy;
  final double z;
  _TrailPoint(this.xy, this.z);
}

/// 태그 하나의 최신 위치 + 궤적.
class _TagTrack {
  final List<_TrailPoint> trail = [];
  Offset pos = Offset.zero;
  double z = 0;
  double stdevXY = 0;
  DateTime lastTs = DateTime.fromMillisecondsSinceEpoch(0);

  /// 위치 계산 실패(오차 발산) 수신 시각. 유효 위치는 유지한 채 경고만 띄운다.
  DateTime? lastInvalidTs;
  bool everValid = false;

  void add(Offset p, double newZ, double stdev, DateTime ts) {
    pos = p;
    z = newZ;
    stdevXY = stdev;
    lastTs = ts;
    everValid = true;
    if (trail.isEmpty || (trail.last.xy - p).distance > 0.02) {
      trail.add(_TrailPoint(p, newZ));
      if (trail.length > 120) trail.removeAt(0);
    }
  }

  void markInvalid(DateTime ts) => lastInvalidTs = ts;

  bool get invalidNow {
    final t = lastInvalidTs;
    if (t == null) return false;
    // 마지막 무효 수신이 마지막 유효 수신보다 최근이면 실패 상태
    return t.isAfter(lastTs) &&
        DateTime.now().difference(t).inSeconds < 5;
  }
}

/// 오일러 각(도) → 3x3 회전. R = Rz·Ry·Rx (로케이터 로컬 → world).
/// 보드 로컬 좌표: +z = 보드가 바라보는 방향(법선), +x = 보드 기준축.
class _Rot {
  final List<double> m; // row-major 3x3

  _Rot._(this.m);

  factory _Rot.eulerDeg(double xDeg, double yDeg, double zDeg) {
    final a = xDeg * math.pi / 180;
    final b = yDeg * math.pi / 180;
    final c = zDeg * math.pi / 180;
    final ca = math.cos(a), sa = math.sin(a);
    final cb = math.cos(b), sb = math.sin(b);
    final cc = math.cos(c), sc = math.sin(c);
    // Rz(c)·Ry(b)·Rx(a)
    return _Rot._([
      cc * cb, cc * sb * sa - sc * ca, cc * sb * ca + sc * sa, //
      sc * cb, sc * sb * sa + cc * ca, sc * sb * ca - cc * sa, //
      -sb, cb * sa, cb * ca,
    ]);
  }

  ({double x, double y, double z}) apply(double x, double y, double z) => (
        x: m[0] * x + m[1] * y + m[2] * z,
        y: m[3] * x + m[4] * y + m[5] * z,
        z: m[6] * x + m[7] * y + m[8] * z,
      );
}

/// 설치 자세 판정.
({String label, Color color, bool facingDown}) _mountInfo(_Rot rot) {
  final n = rot.apply(0, 0, 1); // 보드 법선(바라보는 방향)
  if (n.z < -0.7) {
    return (label: '천장 설치 · 아래를 봄 ✓', color: Colors.teal, facingDown: true);
  }
  if (n.z > 0.7) {
    return (label: '바닥 설치 · 위를 봄', color: Colors.orange, facingDown: false);
  }
  return (label: '벽/경사 설치', color: Colors.indigo, facingDown: false);
}

/// AoA 유효 커버리지 반각 (근사). 천장 설치 시 바닥 커버 원 계산에 사용.
const _fovHalfDeg = 55.0;

class _PositionLiveViewState extends State<PositionLiveView> {
  /// 태그별 위치 궤적 (world 좌표, 미터).
  final Map<String, _TagTrack> _tracks = {};

  /// [태그 갱신]으로 제거된 태그의 제거 시각.
  /// 이 시각 이후의 새 수신만 태그를 다시 살린다
  /// (토픽 통계에 남은 마지막 메시지로 즉시 재생성되는 것을 방지).
  final Map<String, DateTime> _dismissedAt = {};

  bool _is3d = true;
  bool _showCoverage = true;
  bool _showRays = true;
  bool _showFloor = true;
  bool _showTrail = true;
  bool _showCase = true;

  // ---- 2D 뷰 상태 ----
  double? _zoom;
  Offset _pan = Offset.zero;
  Size _lastCanvas = Size.zero;

  // ---- 3D 카메라 상태 ----
  double _yaw = -0.6; // rad
  double _pitch = 1.0; // rad (0=정면, pi/2=수직 위)
  double? _scale3d; // px per meter
  Offset _pan3d = Offset.zero; // 화면 이동 (가운데 버튼 드래그)

  /// 2D 뷰 마우스 커서의 world 좌표 (좌하단 표시용)
  Offset? _cursorWorld;

  MqttState? _mqtt;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // 수신이 끊긴 뒤에도 경과 시간/슬립 상태가 갱신되도록 주기적으로 다시 그린다.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _tracks.isNotEmpty) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mqtt = context.read<MqttState>();
    if (!identical(mqtt, _mqtt)) {
      _mqtt?.removeListener(_onMqtt);
      _mqtt = mqtt;
      mqtt.addListener(_onMqtt);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _mqtt?.removeListener(_onMqtt);
    super.dispose();
  }

  /// MQTT 수신 때마다 position 페이로드를 궤적에 반영.
  void _onMqtt() {
    final mqtt = _mqtt;
    if (mqtt == null) return;
    for (final entry in mqtt.topics.entries) {
      if (!entry.key.startsWith(MqttState.positionPrefix)) continue;
      // 토픽 형식: silabs/aoa/position/<positioning-id>/<tag-id>
      // 마지막 세그먼트(태그 ID)만 키로 사용해 angle 쪽 태그 ID와 맞춘다.
      final tagId =
          entry.key.substring(MqttState.positionPrefix.length).split('/').last;
      final stat = entry.value;
      final ts = stat.lastTs;
      if (ts == null) continue;
      final dismissed = _dismissedAt[tagId];
      if (dismissed != null) {
        if (!ts.isAfter(dismissed)) continue; // 제거 이후 새 데이터 없음 → 숨김 유지
        _dismissedAt.remove(tagId); // 새 신호 수신 → 다시 표시
      }
      final track = _tracks.putIfAbsent(tagId, () => _TagTrack());
      if (!ts.isAfter(track.lastTs)) continue;
      try {
        final j = jsonDecode(stat.lastPayload);
        if (j is! Map) continue;
        final x = (j['x'] as num?)?.toDouble();
        final y = (j['y'] as num?)?.toDouble();
        final z = (j['z'] as num?)?.toDouble() ?? 0;
        if (x == null || y == null) continue;
        final sx = (j['x_stdev'] as num?)?.toDouble() ?? 0;
        final sy = (j['y_stdev'] as num?)?.toDouble() ?? 0;
        final stdev = math.max(sx, sy);
        // 계산 실패 페이로드: (0,0,0) + 발산한 stdev — 위치로 반영하지 않음
        if (stdev > 1000 || (x == 0 && y == 0 && z == 0 && stdev > 100)) {
          track.markInvalid(ts);
        } else {
          track.add(Offset(x, y), z, stdev, ts);
        }
      } catch (_) {
        // JSON이 아니면 무시
      }
    }
    if (mounted) setState(() {});
  }

  /// [태그 갱신]: 슬립 태그를 제거하고 결과 메시지를 띄운다.
  /// 제거된 태그는 갱신 시각 이후의 새 수신이 있어야 다시 나타난다.
  void _refreshTags() {
    final now = DateTime.now();
    var removed = 0;
    setState(() {
      _tracks.removeWhere((id, t) {
        final invalid = t.lastInvalidTs;
        final last = invalid != null && invalid.isAfter(t.lastTs)
            ? invalid
            : t.lastTs;
        final sleep = now.difference(last).inSeconds > _sleepAfterSec;
        if (sleep) {
          _dismissedAt[id] = now;
          removed++;
        }
        return sleep;
      });
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      content: Text(removed == 0
          ? '슬립 상태 태그가 없습니다 — 모든 태그가 수신 중입니다'
          : '슬립 태그 $removed개를 제거했습니다. 새 신호가 수신되면 다시 표시됩니다.'),
    ));
  }

  List<_AngleRay> _collectRays(MqttState mqtt) {
    final now = DateTime.now();
    final rays = <_AngleRay>[];
    for (final entry in mqtt.topics.entries) {
      if (!entry.key.startsWith(MqttState.anglePrefix)) continue;
      final rest = entry.key.substring(MqttState.anglePrefix.length);
      final segs = rest.split('/');
      if (segs.length < 2) continue;
      final stat = entry.value;
      final last = stat.lastTs;
      if (last == null) continue;
      final age = now.difference(last).inMilliseconds / 1000.0;
      if (age > 10) continue; // 오래된 데이터는 그리지 않음
      try {
        final j = jsonDecode(stat.lastPayload);
        if (j is! Map) continue;
        rays.add(_AngleRay(
          locatorId: segs[0],
          tagId: segs.sublist(1).join('/'),
          azimuth: (j['azimuth'] as num?)?.toDouble() ?? 0,
          elevation: (j['elevation'] as num?)?.toDouble() ?? 0,
          distance: (j['distance'] as num?)?.toDouble() ?? 0,
          live: age < 3,
        ));
      } catch (_) {}
    }
    return rays;
  }

  /// 그릴 로케이터 배치 — 재정의(외부망 중계)가 있으면 그것을, 없으면
  /// 로컬 프로젝트(AppState) 배치를 쓴다.
  List<PlacedLocator> _placements(AppState app) =>
      widget.placements ?? app.placements;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final placements = _placements(app);
    final mqtt = context.watch<MqttState>();
    final rays =
        widget.supportsAngle ? _collectRays(mqtt) : const <_AngleRay>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              hoverTip(
                '3D: 회전 가능한 입체 시점 (드래그=회전)\n2D: 위에서 본 평면도 (드래그=이동)',
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('3D')),
                    ButtonSegment(value: false, label: Text('2D')),
                  ],
                  selected: {_is3d},
                  onSelectionChanged: (s) => setState(() => _is3d = s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle:
                        WidgetStatePropertyAll(TextStyle(fontSize: 11.5)),
                  ),
                ),
              ),
              _legendPlate(),
              _legendDot(Colors.red, '태그(+오차원)'),
              if (widget.supportsAngle)
                hoverTip(
                  '로케이터가 측정한 태그 방향(azimuth/elevation) 점선을 표시합니다.',
                  FilterChip(
                    label:
                        const Text('angle 점선', style: TextStyle(fontSize: 11)),
                    selected: _showRays,
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) => setState(() => _showRays = v),
                  ),
                ),
              hoverTip(
                '천장 설치 로케이터의 바닥 커버리지 원을 표시합니다.',
                FilterChip(
                  label: const Text('커버리지', style: TextStyle(fontSize: 11)),
                  selected: _showCoverage,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) => setState(() => _showCoverage = v),
                ),
              ),
              if (_is3d && CaseMesh.instance != null)
                hoverTip(
                  '로케이터를 실물 케이스(LocatorXCase) 3D 형상으로 표시합니다.\n'
                  '끄면 기존 보드 사각형으로 표시합니다.',
                  FilterChip(
                    label:
                        const Text('실물 케이스', style: TextStyle(fontSize: 11)),
                    selected: _showCase,
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) => setState(() => _showCase = v),
                  ),
                ),
              hoverTip(
                '바닥에 도면 이미지를 표시합니다.',
                FilterChip(
                  label: const Text('도면', style: TextStyle(fontSize: 11)),
                  selected: _showFloor,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) => setState(() => _showFloor = v),
                ),
              ),
              hoverTip(
                '태그 이동 궤적(잔상)을 표시합니다. 꺼도 기록은 계속 쌓입니다.',
                FilterChip(
                  label: const Text('잔상', style: TextStyle(fontSize: 11)),
                  selected: _showTrail,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) => setState(() => _showTrail = v),
                ),
              ),
              hoverTip(
                '모든 태그의 궤적만 삭제합니다 (현재 위치는 유지).',
                TextButton.icon(
                  onPressed: () => setState(() {
                    for (final t in _tracks.values) {
                      t.trail.clear();
                    }
                  }),
                  icon: const Icon(Icons.clear_all, size: 15),
                  label:
                      const Text('잔상 지우기', style: TextStyle(fontSize: 12)),
                ),
              ),
              Tooltip(
                message:
                    '${_sleepAfterSec.toInt()}초 이상 수신이 없는(슬립) 태그를 화면에서 제거합니다.\n'
                    '제거된 태그는 새 신호가 수신될 때만 다시 나타납니다.',
                waitDuration: const Duration(seconds: 1),
                child: TextButton.icon(
                  onPressed: () => _refreshTags(),
                  icon: const Icon(Icons.sync, size: 15),
                  label: const Text('태그 갱신', style: TextStyle(fontSize: 12)),
                ),
              ),
              Text(
                _is3d ? '드래그: 회전 · 가운데 버튼: 이동 · 휠: 줌' : '드래그: 이동 · 휠: 줌',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              hoverTip(
                '태그·궤적을 모두 지우고 카메라 시점을 초기 상태로 되돌립니다.',
                TextButton.icon(
                  onPressed: () => setState(() {
                    _tracks.clear();
                    _zoom = null;
                    _scale3d = null;
                    _yaw = -0.6;
                    _pitch = 1.0;
                    _pan3d = Offset.zero;
                  }),
                  icon: const Icon(Icons.refresh, size: 15),
                  label: const Text('뷰 초기화', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_tracks.values.any((t) => t.invalidNow))
          Container(
            color: Colors.orange.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.warning_amber,
                    color: Colors.orange, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'position은 수신 중이지만 위치 계산이 실패하고 있습니다 (오차 발산 · x=0,y=0). '
                    '태그가 로케이터 커버리지 교차 영역 밖이거나 각도 품질이 낮은 상태입니다. '
                    '마지막 유효 위치를 흐리게 유지합니다.',
                    style: TextStyle(
                        fontSize: 11.5, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: placements.isEmpty && _tracks.isEmpty
              ? Center(
                  child: Text(
                    widget.placements != null
                        ? '표시할 데이터가 없습니다.\n'
                            '서버 카드가 배치(placements)를 중계하면 로케이터가,\n'
                            'position이 수신되면 태그가 표시됩니다.'
                        : '표시할 데이터가 없습니다.\n'
                            '[위치 설정] 탭에서 도면과 로케이터를 배치하고,\n'
                            '상단에서 MQTT 브로커에 연결하세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : LayoutBuilder(builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return _is3d
                      ? _build3d(app, placements, rays, size)
                      : _build2d(app, placements, rays, size);
                }),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            '보드 사각형=로케이터 자세 · 화살표=바라보는 방향 · 빨간 노치=x축(0°), 초록 노치=y축(90°) → 둘을 보면 설치 회전 방향을 알 수 있습니다. '
            '커버리지 원: 보드 법선이 바닥과 만나는 점이 중심, 반경 = 법선 거리 × tan(${_fovHalfDeg.toInt()}°) — 천장 수평 설치(높이 h)면 반경 ≈ h × ${math.tan(_fovHalfDeg * math.pi / 180).toStringAsFixed(2)}. '
            '태그 옅은 원=위치 오차(stdev, 표시상 3m 상한).',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // 3D 뷰
  // =========================================================
  Widget _build3d(AppState app, List<PlacedLocator> placements,
      List<_AngleRay> rays, Size size) {
    _scale3d ??= _fitScale3d(app, placements, size);
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          setState(() {
            final factor = e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
            _scale3d = (_scale3d! * factor).clamp(2.0, 2000.0);
          });
        }
      },
      // 가운데 버튼 드래그 = 화면 이동 (좌클릭 회전과 별개)
      onPointerMove: (e) {
        if (e.buttons & kMiddleMouseButton != 0) {
          setState(() => _pan3d += e.delta);
        }
      },
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _yaw += d.delta.dx * 0.008;
          _pitch = (_pitch + d.delta.dy * 0.008).clamp(0.15, 1.52);
        }),
        child: ClipRect(
          child: CustomPaint(
            size: size,
            painter: _Live3dPainter(
              app: app,
              placements: placements,
              rays: rays,
              tracks: _tracks,
              now: DateTime.now(),
              yaw: _yaw,
              pitch: _pitch,
              scale: _scale3d!,
              pan: _pan3d,
              showCoverage: _showCoverage,
              showRays: _showRays,
              showFloor: _showFloor,
              showTrail: _showTrail,
              showCase: _showCase,
            ),
          ),
        ),
      ),
    );
  }

  /// 장면(도면 또는 배치 영역)을 화면에 맞추는 3D 스케일 (px/m).
  double _fitScale3d(AppState app, List<PlacedLocator> placements, Size canvas) {
    final b = _sceneBounds(app, placements);
    final extent = math.max(b.width, b.height).clamp(2.0, double.infinity);
    return math.min(canvas.width, canvas.height) / extent * 0.7;
  }

  /// world 좌표(미터) 기준 장면 영역.
  Rect _sceneBounds(AppState app, List<PlacedLocator> placements) {
    final img = app.floorImage;
    if (img != null) {
      final t = app.transform;
      final a = t.imageToWorld(Offset.zero);
      final b = t.imageToWorld(
          Offset(img.width.toDouble(), img.height.toDouble()));
      return Rect.fromPoints(a, b);
    }
    final pts = <Offset>[
      for (final p in placements) Offset(p.coordinate.x, p.coordinate.y),
      for (final t in _tracks.values) t.pos,
    ];
    if (pts.isEmpty) return const Rect.fromLTWH(-5, -5, 10, 10);
    var r = Rect.fromPoints(pts.first, pts.first);
    for (final p in pts) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r.inflate(2);
  }

  // =========================================================
  // 2D 뷰 (기존 평면도)
  // =========================================================
  Widget _build2d(AppState app, List<PlacedLocator> placements,
      List<_AngleRay> rays, Size size) {
    final view = _viewTransform(app, placements, size);
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          final factor = e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
          setState(() {
            final t = view.zoomAt(e.localPosition, view.zoom * factor);
            _zoom = t.zoom;
            _pan = t.panPx;
          });
        }
      },
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _zoom ??= view.zoom;
          _pan = view.panPx + d.delta;
        }),
        child: MouseRegion(
          onHover: (e) =>
              setState(() => _cursorWorld = view.screenToWorld(e.localPosition)),
          onExit: (_) => setState(() => _cursorWorld = null),
          child: ClipRect(
            child: Stack(
              children: [
                CustomPaint(
                  size: size,
                  painter: _Live2dPainter(
                    app: app,
                    placements: placements,
                    view: view,
                    rays: rays,
                    tracks: _tracks,
                    now: DateTime.now(),
                    showCoverage: _showCoverage,
                    showRays: _showRays,
                    showFloor: _showFloor,
                    showTrail: _showTrail,
                  ),
                ),
                if (_cursorWorld != null)
                  Positioned(
                    left: 8,
                    bottom: 6,
                    child: Text(
                      '커서: (${_cursorWorld!.dx.toStringAsFixed(2)}, '
                      '${_cursorWorld!.dy.toStringAsFixed(2)}) m',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: Colors.grey.shade700),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 도면(또는 배치 영역)을 캔버스에 맞추는 2D 뷰 변환.
  WorldTransform _viewTransform(
      AppState app, List<PlacedLocator> placements, Size canvas) {
    final base = app.transform;
    if (_zoom != null && canvas == _lastCanvas) {
      return base.copyWith(zoom: _zoom, panPx: _pan);
    }
    _lastCanvas = canvas;

    Rect fitRect;
    final img = app.floorImage;
    if (img != null) {
      fitRect =
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    } else {
      final pts = <Offset>[
        for (final p in placements)
          base.worldToImage(Offset(p.coordinate.x, p.coordinate.y)),
        for (final t in _tracks.values) base.worldToImage(t.pos),
      ];
      if (pts.isEmpty) {
        fitRect = const Rect.fromLTWH(-100, -100, 200, 200);
      } else {
        var r = Rect.fromPoints(pts.first, pts.first);
        for (final p in pts) {
          r = r.expandToInclude(Rect.fromPoints(p, p));
        }
        fitRect = r.inflate(60);
      }
    }
    if (fitRect.width < 1 || fitRect.height < 1) {
      fitRect = fitRect.inflate(50);
    }

    final zoom = math.min(
            canvas.width / fitRect.width, canvas.height / fitRect.height) *
        0.92;
    final pan = Offset(
      (canvas.width - fitRect.width * zoom) / 2 - fitRect.left * zoom,
      (canvas.height - fitRect.height * zoom) / 2 - fitRect.top * zoom,
    );
    _zoom = zoom;
    _pan = pan;
    return base.copyWith(zoom: zoom, panPx: pan);
  }

  Widget _legendDot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: c),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );

  Widget _legendPlate() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.3),
              border: Border.all(color: Colors.blue, width: 1.2),
            ),
          ),
          const SizedBox(width: 4),
          const Text('로케이터 보드(자세)', style: TextStyle(fontSize: 11)),
        ],
      );

}

// =========================================================
// 공통 그리기 도우미
// =========================================================
const _tagColors = [
  Colors.red,
  Colors.deepPurple,
  Colors.green,
  Colors.brown,
  Colors.pink,
  Colors.indigo,
];

Color _tagColor(String tagId) =>
    _tagColors[tagId.hashCode.abs() % _tagColors.length];

/// 마지막 수신 경과 시간 표기 (예: '42초 전', '5분 전', '2시간 전').
String _ageText(double ageSec) {
  if (ageSec < 60) return '${ageSec.toStringAsFixed(0)}초 전';
  if (ageSec < 3600) return '${(ageSec / 60).floor()}분 전';
  return '${(ageSec / 3600).floor()}시간 전';
}

/// 이 시간(초) 이상 수신이 없으면 슬립 상태로 표시하고,
/// [태그 갱신]을 누르면 화면에서 제거된다.
const double _sleepAfterSec = 10;

void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
    {double dash = 7, double gap = 5}) {
  final total = (b - a).distance;
  if (total < 1e-3) return;
  final dir = (b - a) / total;
  var drawn = 0.0;
  while (drawn < total) {
    final segEnd = math.min(drawn + dash, total);
    canvas.drawLine(a + dir * drawn, a + dir * segEnd, paint);
    drawn = segEnd + gap;
  }
}

void _label(Canvas canvas, Offset pos, String text,
    {Color color = Colors.black87, double fontSize = 11}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: FontWeight.w600,
        shadows: const [
          Shadow(color: Colors.white, blurRadius: 3),
          Shadow(color: Colors.white, blurRadius: 3),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, pos);
}

/// angle → world 3D 방향 벡터.
/// 보드 로컬 좌표(+z=법선)에서 azimuth/elevation으로 방향을 만들고,
/// 보드 그리기와 동일한 회전행렬(orientation x/y/z 전체)로 world로 변환한다.
/// 로케이터마다 설치 방향이 달라도 각자의 orientation을 그대로 반영한다.
({double dx, double dy, double dz}) _rayDirection(
    PlacedLocator placement, _AngleRay ray) {
  final rot = _Rot.eulerDeg(
      placement.orientation.x, placement.orientation.y, placement.orientation.z);
  final az = ray.azimuth * math.pi / 180;
  final el = ray.elevation * math.pi / 180;
  // 보드 로컬: 정면(+z) 기준, azimuth는 x-y 평면 회전, elevation은 법선 쪽 기울기
  final w = rot.apply(
    math.cos(el) * math.cos(az),
    math.cos(el) * math.sin(az),
    math.sin(el),
  );
  return (dx: w.x, dy: w.y, dz: w.z);
}

// =========================================================
// 3D 페인터
// =========================================================
class _Live3dPainter extends CustomPainter {
  final AppState app;
  final List<PlacedLocator> placements;
  final List<_AngleRay> rays;
  final Map<String, _TagTrack> tracks;
  final DateTime now;
  final double yaw;
  final double pitch;
  final double scale;
  final Offset pan;
  final bool showCoverage;
  final bool showRays;
  final bool showFloor;
  final bool showTrail;
  final bool showCase;

  _Live3dPainter({
    required this.app,
    required this.placements,
    required this.rays,
    required this.tracks,
    required this.now,
    required this.yaw,
    required this.pitch,
    required this.scale,
    this.pan = Offset.zero,
    required this.showCoverage,
    required this.showRays,
    required this.showFloor,
    required this.showTrail,
    this.showCase = true,
  });

  late Matrix4 _m;

  /// 태그 색: 수신 순서 기준 (첫 태그 = 빨강). angle만 있는 태그는 해시 폴백.
  Color _colorFor(String tagId) {
    final idx = tracks.keys.toList().indexOf(tagId);
    return idx >= 0 ? _tagColors[idx % _tagColors.length] : _tagColor(tagId);
  }

  /// world(x,y,z 미터, z-up) → 스크린 px.
  Offset _p(double x, double y, double z) {
    final s = _m.storage;
    final tx = s[0] * x + s[4] * y + s[8] * z + s[12];
    final ty = s[1] * x + s[5] * y + s[9] * z + s[13];
    final tw = s[3] * x + s[7] * y + s[11] * z + s[15];
    return Offset(tx / tw, ty / tw);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = canvasBackground);

    final bounds = _bounds();
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;

    _m = Matrix4.identity()
      ..translate(size.width / 2 + pan.dx, size.height * 0.55 + pan.dy)
      ..setEntry(3, 2, -0.0009)
      ..rotateX(math.pi / 2 - pitch)
      ..rotateZ(yaw)
      ..scale(scale, -scale, scale)
      ..translate(-cx, -cy, 0);

    if (showFloor) _drawFloor(canvas, bounds);
    _drawGrid(canvas, bounds);
    _drawAxes(canvas, bounds);

    final placementById = {for (final p in placements) p.locatorId: p};

    // 커버리지 원 (바닥에 먼저)
    if (showCoverage) {
      for (final p in placements) {
        _drawCoverage3d(canvas, p);
      }
    }

    // angle 점선 (3D 방향)
    if (showRays) {
      for (final ray in rays) {
        final placement = placementById[ray.locatorId];
        if (placement == null) continue;
        _drawRay3d(canvas, placement, ray);
      }
    }

    // 로케이터 보드 (자세 표현)
    for (final p in placements) {
      final receiving = rays.any((r) => r.locatorId == p.locatorId && r.live);
      _drawLocatorBoard3d(canvas, p, receiving);
    }

    // 태그
    tracks.forEach((tagId, track) => _drawTag3d(canvas, tagId, track));
  }

  Rect _bounds() {
    final img = app.floorImage;
    if (img != null) {
      final t = app.transform;
      final a = t.imageToWorld(Offset.zero);
      final b =
          t.imageToWorld(Offset(img.width.toDouble(), img.height.toDouble()));
      return Rect.fromPoints(a, b);
    }
    final pts = <Offset>[
      for (final p in placements) Offset(p.coordinate.x, p.coordinate.y),
      for (final t in tracks.values) t.pos,
    ];
    if (pts.isEmpty) return const Rect.fromLTWH(-5, -5, 10, 10);
    var r = Rect.fromPoints(pts.first, pts.first);
    for (final p in pts) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r.inflate(2);
  }

  /// 도면 이미지를 바닥 평면(z=0)에 원근 투영으로 깐다.
  void _drawFloor(Canvas canvas, Rect bounds) {
    final img = app.floorImage;
    if (img == null) return;
    final t = app.transform;

    final worldFromImage = Matrix4.identity()
      ..scale(t.metersPerPixel, -t.metersPerPixel, 1.0)
      ..translate(-t.originPx.dx, -t.originPx.dy, 0.0);

    canvas.save();
    canvas.transform((_m.clone()..multiply(worldFromImage)).storage);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Rect b) {
    final extent = math.max(b.width, b.height);
    final step = extent > 40 ? 10.0 : (extent > 15 ? 5.0 : 1.0);
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.25)
      ..strokeWidth = 0.7;

    for (var x = (b.left / step).floor() * step; x <= b.right; x += step) {
      canvas.drawLine(_p(x, b.top, 0), _p(x, b.bottom, 0), gridPaint);
    }
    for (var y = (b.top / step).floor() * step; y <= b.bottom; y += step) {
      canvas.drawLine(_p(b.left, y, 0), _p(b.right, y, 0), gridPaint);
    }
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.grey.shade500
      ..strokeWidth = 1;
    final path = Path()
      ..moveTo(_p(b.left, b.top, 0).dx, _p(b.left, b.top, 0).dy)
      ..lineTo(_p(b.right, b.top, 0).dx, _p(b.right, b.top, 0).dy)
      ..lineTo(_p(b.right, b.bottom, 0).dx, _p(b.right, b.bottom, 0).dy)
      ..lineTo(_p(b.left, b.bottom, 0).dx, _p(b.left, b.bottom, 0).dy)
      ..close();
    canvas.drawPath(path, border);
  }

  void _drawAxes(Canvas canvas, Rect b) {
    final len = (math.max(b.width, b.height) * 0.12).clamp(0.5, 5.0);
    final o = _p(0, 0, 0);
    void axis(double x, double y, double z, Color c, String name) {
      final e = _p(x, y, z);
      canvas.drawLine(
          o,
          e,
          Paint()
            ..color = c
            ..strokeWidth = 1.6);
      _label(canvas, e + const Offset(3, -3), name, color: c, fontSize: 10);
    }

    axis(len, 0, 0, Colors.red.shade700, 'x');
    axis(0, len, 0, Colors.green.shade700, 'y');
    axis(0, 0, len, Colors.blue.shade700, 'z');
  }

  /// 로케이터를 자세(orientation)를 가진 보드로 그린다.
  /// - 사각 판: 보드 몸체 (기울기 그대로)
  /// - 파란 화살표: 보드가 바라보는 방향(법선)
  /// - 빨간 노치: 보드 기준축(+x) — 회전(orientation.z) 확인용
  void _drawLocatorBoard3d(Canvas canvas, PlacedLocator p, bool receiving) {
    final rot = _Rot.eulerDeg(
        p.orientation.x, p.orientation.y, p.orientation.z);
    final mount = _mountInfo(rot);
    final cx = p.coordinate.x, cy = p.coordinate.y, cz = p.coordinate.z;

    Offset world(double lx, double ly, double lz) {
      final w = rot.apply(lx, ly, lz);
      return _p(cx + w.x, cy + w.y, cz + w.z);
    }

    // 바닥 기준점 + 수직 보조선 (높이 파악)
    final foot = _p(cx, cy, 0);
    final center = _p(cx, cy, cz);
    canvas.drawLine(
        foot,
        center,
        Paint()
          ..color = Colors.blueGrey.withValues(alpha: 0.4)
          ..strokeWidth = 1);
    canvas.drawCircle(
        foot, 2.5, Paint()..color = Colors.blueGrey.withValues(alpha: 0.5));

    // 실물 케이스(로드됨 + 토글 on)면 케이스 메시, 아니면 보드 판 (0.5m 사각).
    // 노치·라벨은 케이스 위에도 그려 설치 회전 확인 기준을 유지한다.
    const h = 0.25;
    final bodyColor = receiving ? Colors.blue : Colors.blueGrey;
    final mesh = CaseMesh.instance;
    if (showCase && mesh != null) {
      drawCaseMesh(canvas, mesh,
          rot: rot.m,
          cx: cx,
          cy: cy,
          cz: cz,
          cam: _m.storage,
          color: receiving
              ? const Color(0xFF90B8E0) // 수신 중 = 푸른 톤
              : const Color(0xFFAEB6BE));
    } else {
      final c1 = world(-h, -h, 0);
      final c2 = world(h, -h, 0);
      final c3 = world(h, h, 0);
      final c4 = world(-h, h, 0);
      final plate = Path()
        ..moveTo(c1.dx, c1.dy)
        ..lineTo(c2.dx, c2.dy)
        ..lineTo(c3.dx, c3.dy)
        ..lineTo(c4.dx, c4.dy)
        ..close();
      canvas.drawPath(
          plate, Paint()..color = bodyColor.withValues(alpha: 0.35));
      canvas.drawPath(
          plate,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = bodyColor);
    }

    // 기준축 노치: +x(빨강, 0°) / +y(초록, 90°) — 설치 회전 방향 확인용
    final notchA = world(h, 0, 0);
    final notchB = world(h * 1.9, 0, 0);
    canvas.drawLine(
        notchA,
        notchB,
        Paint()
          ..color = Colors.red
          ..strokeWidth = 2.4);
    _label(canvas, notchB + const Offset(2, -4), 'x(0°)',
        color: Colors.red.shade700, fontSize: 9);
    final notchYA = world(0, h, 0);
    final notchYB = world(0, h * 1.9, 0);
    canvas.drawLine(
        notchYA,
        notchYB,
        Paint()
          ..color = Colors.green.shade600
          ..strokeWidth = 2.4);
    _label(canvas, notchYB + const Offset(2, -4), 'y(90°)',
        color: Colors.green.shade700, fontSize: 9);

    // 바라보는 방향 화살표 (법선 +z, 0.9m)
    final tip = world(0, 0, 0.9);
    canvas.drawLine(
        center,
        tip,
        Paint()
          ..color = bodyColor
          ..strokeWidth = 2.2);
    // 화살촉
    final tipL = world(0.07, 0, 0.72);
    final tipR = world(-0.07, 0, 0.72);
    canvas.drawLine(tip, tipL, Paint()..color = bodyColor..strokeWidth = 2);
    canvas.drawLine(tip, tipR, Paint()..color = bodyColor..strokeWidth = 2);

    // 라벨: ID + 설치 판정
    _label(canvas, center + const Offset(12, -26),
        '${p.shortId} (${p.coordinate.x.toStringAsFixed(2)}, ${p.coordinate.y.toStringAsFixed(2)}, ${p.coordinate.z.toStringAsFixed(2)})',
        color: Colors.blue.shade900);
    _label(canvas, center + const Offset(12, -12), mount.label,
        color: mount.color, fontSize: 10);
  }

  /// 천장(아래를 보는) 로케이터의 바닥 커버리지 원.
  void _drawCoverage3d(Canvas canvas, PlacedLocator p) {
    final rot =
        _Rot.eulerDeg(p.orientation.x, p.orientation.y, p.orientation.z);
    final n = rot.apply(0, 0, 1);
    if (n.z >= -0.3) return; // 아래를 보지 않으면 생략
    final cz = p.coordinate.z;
    if (cz <= 0.1) return;

    // 법선이 바닥과 만나는 점 = 커버리지 중심
    final t = cz / -n.z;
    final cxF = p.coordinate.x + n.x * t;
    final cyF = p.coordinate.y + n.y * t;
    final radius = t * math.tan(_fovHalfDeg * math.pi / 180);

    final paint = Paint()
      ..color = Colors.teal.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    const seg = 36;
    for (var i = 0; i < seg; i += 2) {
      final a0 = i / seg * 2 * math.pi;
      final a1 = (i + 1) / seg * 2 * math.pi;
      canvas.drawLine(
        _p(cxF + radius * math.cos(a0), cyF + radius * math.sin(a0), 0),
        _p(cxF + radius * math.cos(a1), cyF + radius * math.sin(a1), 0),
        paint,
      );
    }
    canvas.drawCircle(_p(cxF, cyF, 0), 2,
        Paint()..color = Colors.teal.withValues(alpha: 0.6));
    _label(
      canvas,
      _p(cxF + radius * 0.72, cyF + radius * 0.72, 0),
      '커버 r≈${radius.toStringAsFixed(1)}m',
      color: Colors.teal.shade700,
      fontSize: 10,
    );
  }

  void _drawTag3d(Canvas canvas, String tagId, _TagTrack track) {
    if (!track.everValid) return;
    // 수신이 끊겨도 마지막 위치를 계속 표시한다 ([태그 갱신]으로 정리).
    final ageSec = now.difference(track.lastTs).inMilliseconds / 1000.0;
    final color = _colorFor(tagId);

    if (showTrail && track.trail.length >= 2) {
      for (var i = 1; i < track.trail.length; i++) {
        final t = i / track.trail.length;
        final a = track.trail[i - 1];
        final b = track.trail[i];
        canvas.drawLine(
          _p(a.xy.dx, a.xy.dy, a.z),
          _p(b.xy.dx, b.xy.dy, b.z),
          Paint()
            ..color = color.withValues(alpha: 0.08 + 0.35 * t)
            ..strokeWidth = 2,
        );
      }
    }

    final live = ageSec < 3;
    final sleep = ageSec > _sleepAfterSec; // 슬립: 회색 표시, 오차원 생략
    final drawColor = sleep ? Colors.blueGrey : color;
    final pt = _p(track.pos.dx, track.pos.dy, track.z);
    final shadow = _p(track.pos.dx, track.pos.dy, 0);

    // 오차 원 (태그 높이 평면, 표시상 3m 상한)
    if (!sleep && track.stdevXY > 0.05) {
      final rM = math.min(track.stdevXY, 3.0);
      final path = Path();
      const seg = 24;
      for (var i = 0; i <= seg; i++) {
        final a = i / seg * 2 * math.pi;
        final o = _p(track.pos.dx + rM * math.cos(a),
            track.pos.dy + rM * math.sin(a), track.z);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
          path, Paint()..color = color.withValues(alpha: 0.10));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: 0.35));
    }

    canvas.drawLine(
        shadow,
        pt,
        Paint()
          ..color = drawColor.withValues(alpha: 0.3)
          ..strokeWidth = 1);
    canvas.drawCircle(
        shadow, 3, Paint()..color = drawColor.withValues(alpha: 0.25));
    canvas.drawCircle(pt, 7,
        Paint()..color = live ? color : drawColor.withValues(alpha: 0.35));
    canvas.drawCircle(
        pt,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white);
    final short =
        tagId.length >= 4 ? tagId.substring(tagId.length - 4) : tagId;
    _label(
      canvas,
      pt + const Offset(10, 4),
      '$short (${track.pos.dx.toStringAsFixed(2)}, '
      '${track.pos.dy.toStringAsFixed(2)}, ${track.z.toStringAsFixed(2)})'
      '${live ? '' : (sleep ? ' · 슬립 ${_ageText(ageSec)}' : ' · ${_ageText(ageSec)}')}',
      color: sleep ? Colors.blueGrey.shade600 : color,
    );
  }

  void _drawRay3d(Canvas canvas, PlacedLocator placement, _AngleRay ray) {
    final d = _rayDirection(placement, ray);
    final sx = placement.coordinate.x;
    final sy = placement.coordinate.y;
    final sz = placement.coordinate.z;
    final ex = sx + d.dx * ray.distance;
    final ey = sy + d.dy * ray.distance;
    final ez = sz + d.dz * ray.distance;

    final color = _colorFor(ray.tagId).withValues(alpha: ray.live ? 0.9 : 0.3);

    const steps = 14;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6;
    for (var i = 0; i < steps; i += 2) {
      final t0 = i / steps;
      final t1 = (i + 1) / steps;
      canvas.drawLine(
        _p(sx + (ex - sx) * t0, sy + (ey - sy) * t0, sz + (ez - sz) * t0),
        _p(sx + (ex - sx) * t1, sy + (ey - sy) * t1, sz + (ez - sz) * t1),
        paint,
      );
    }

    _label(
      canvas,
      _p(ex, ey, ez) + const Offset(6, -6),
      'az ${ray.azimuth.toStringAsFixed(1)}° · el ${ray.elevation.toStringAsFixed(1)}° · ${ray.distance.toStringAsFixed(2)}m',
      color: color,
      fontSize: 10,
    );
  }

  @override
  bool shouldRepaint(covariant _Live3dPainter old) => true;
}

// =========================================================
// 2D 페인터 (위에서 본 평면도)
// =========================================================
class _Live2dPainter extends CustomPainter {
  final AppState app;
  final List<PlacedLocator> placements;
  final WorldTransform view;
  final List<_AngleRay> rays;
  final Map<String, _TagTrack> tracks;
  final DateTime now;
  final bool showCoverage;
  final bool showRays;
  final bool showFloor;
  final bool showTrail;

  _Live2dPainter({
    required this.app,
    required this.placements,
    required this.view,
    required this.rays,
    required this.tracks,
    required this.now,
    required this.showCoverage,
    required this.showRays,
    required this.showFloor,
    required this.showTrail,
  });

  /// world 미터 → 스크린 px 길이.
  double _len(double meters) => meters / view.metersPerPixel * view.zoom;

  /// 태그 색: 수신 순서 기준 (첫 태그 = 빨강). angle만 있는 태그는 해시 폴백.
  Color _colorFor(String tagId) {
    final idx = tracks.keys.toList().indexOf(tagId);
    return idx >= 0 ? _tagColors[idx % _tagColors.length] : _tagColor(tagId);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = canvasBackground);

    final img = showFloor ? app.floorImage : null;
    if (img != null) {
      final dst = Rect.fromLTWH(
        view.panPx.dx,
        view.panPx.dy,
        img.width * view.zoom,
        img.height * view.zoom,
      );
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.drawRect(
          dst,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.grey.shade400);
    }

    _drawGrid2d(canvas, size);

    final placementById = {for (final p in placements) p.locatorId: p};

    if (showCoverage) {
      for (final p in placements) {
        _drawCoverage2d(canvas, p);
      }
    }

    if (showRays) {
      for (final ray in rays) {
        final placement = placementById[ray.locatorId];
        if (placement == null) continue;
        _drawRay(canvas, placement, ray);
      }
    }

    for (final p in placements) {
      final receiving = rays.any((r) => r.locatorId == p.locatorId && r.live);
      _drawLocatorBoard2d(canvas, p, receiving);
    }

    tracks.forEach((tagId, track) => _drawTag2d(canvas, tagId, track));
  }

  /// 화면상 그리드 간격이 40px 이상이 되도록 1/2/5... m 스텝을 고른다.
  double _gridStepMeters() {
    final pxPerMeter = view.zoom / view.metersPerPixel;
    double step = 1.0;
    const factors = [1.0, 2.0, 5.0];
    var scale = 1.0;
    while (true) {
      for (final f in factors) {
        step = f * scale;
        if (step * pxPerMeter >= 40) return step;
      }
      scale *= 10;
      if (scale > 1e6) return step;
    }
  }

  /// 위치 설정 캔버스와 동일한 미터 그리드 + 원점 축 (거리 확인용).
  void _drawGrid2d(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.25)
      ..strokeWidth = 1;

    final step = _gridStepMeters();
    final wTopLeft = view.screenToWorld(Offset.zero);
    final wBottomRight = view.screenToWorld(Offset(size.width, size.height));

    final xMin =
        (math.min(wTopLeft.dx, wBottomRight.dx) / step).floor() * step;
    final xMax = math.max(wTopLeft.dx, wBottomRight.dx);
    final yMin =
        (math.min(wTopLeft.dy, wBottomRight.dy) / step).floor() * step;
    final yMax = math.max(wTopLeft.dy, wBottomRight.dy);

    final labelColor = Colors.blueGrey.withValues(alpha: 0.7);
    for (var x = xMin; x <= xMax; x += step) {
      final s = view.worldToScreen(Offset(x, 0));
      canvas.drawLine(Offset(s.dx, 0), Offset(s.dx, size.height), paint);
      _label(canvas, Offset(s.dx + 2, size.height - 16), '${_fmtM(x)}m',
          color: labelColor, fontSize: 10);
    }
    for (var y = yMin; y <= yMax; y += step) {
      final s = view.worldToScreen(Offset(0, y));
      canvas.drawLine(Offset(0, s.dy), Offset(size.width, s.dy), paint);
      _label(canvas, Offset(2, s.dy + 2), '${_fmtM(y)}m',
          color: labelColor, fontSize: 10);
    }

    // 원점 축 표시
    final origin = view.worldToScreen(Offset.zero);
    canvas.drawLine(origin, origin + const Offset(40, 0),
        Paint()..color = Colors.red.withValues(alpha: 0.7)..strokeWidth = 2);
    canvas.drawLine(origin, origin + const Offset(0, -40),
        Paint()..color = Colors.green.withValues(alpha: 0.7)..strokeWidth = 2);
    canvas.drawCircle(origin, 4, Paint()..color = Colors.red);
    _label(canvas, origin + const Offset(6, 6), '(0,0)',
        color: Colors.red, fontSize: 11);
  }

  static String _fmtM(double v) {
    final r = (v * 100).round() / 100;
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }

  /// 2D: 로케이터를 회전된 보드 사각형 + 기준축 노치 + 설치 판정 라벨로.
  void _drawLocatorBoard2d(Canvas canvas, PlacedLocator p, bool receiving) {
    final rot =
        _Rot.eulerDeg(p.orientation.x, p.orientation.y, p.orientation.z);
    final mount = _mountInfo(rot);
    final center = view.worldToScreen(Offset(p.coordinate.x, p.coordinate.y));
    final bodyColor = receiving ? Colors.blue : Colors.blueGrey;

    Offset corner(double lx, double ly) {
      final w = rot.apply(lx, ly, 0);
      return view.worldToScreen(
          Offset(p.coordinate.x + w.x, p.coordinate.y + w.y));
    }

    const h = 0.25;
    final c1 = corner(-h, -h);
    final c2 = corner(h, -h);
    final c3 = corner(h, h);
    final c4 = corner(-h, h);
    final plate = Path()
      ..moveTo(c1.dx, c1.dy)
      ..lineTo(c2.dx, c2.dy)
      ..lineTo(c3.dx, c3.dy)
      ..lineTo(c4.dx, c4.dy)
      ..close();

    // 실물 사진이 로드돼 있으면 사진으로: 천장 설치(아래를 봄)는 위에서
    // 등(back)이 보이고, 바닥 설치(위를 봄)는 앞면(front)이 보인다.
    final nrm = rot.apply(0, 0, 1);
    final img = nrm.z < 0 ? LocatorImages.back : LocatorImages.front;
    if (img != null) {
      // 보드 +x(커넥터 · 0°)의 화면 방향각 — 이미지 위쪽 = 커넥터 가정
      final xw = rot.apply(1, 0, 0);
      final sx = view.worldToScreen(
          Offset(p.coordinate.x + xw.x, p.coordinate.y + xw.y));
      final ang = math.atan2(sx.dy - center.dy, sx.dx - center.dx);
      final sizePx = (corner(h, 0) - corner(-h, 0)).distance;
      LocatorImages.drawRotated(canvas, img, center, sizePx, ang);
      // 수신 상태는 테두리로 유지
      canvas.drawPath(
          plate,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = bodyColor.withValues(alpha: 0.8));
    } else {
      canvas.drawPath(
          plate, Paint()..color = bodyColor.withValues(alpha: 0.35));
      canvas.drawPath(
          plate,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = bodyColor);
    }

    // 기준축 노치: +x(빨강, 0°) / +y(초록, 90°)
    final notchX = corner(h * 1.9, 0);
    canvas.drawLine(
        corner(h, 0),
        notchX,
        Paint()
          ..color = Colors.red
          ..strokeWidth = 2.4);
    _label(canvas, notchX + const Offset(2, -4), 'x(0°)',
        color: Colors.red.shade700, fontSize: 9);
    final notchY = corner(0, h * 1.9);
    canvas.drawLine(
        corner(0, h),
        notchY,
        Paint()
          ..color = Colors.green.shade600
          ..strokeWidth = 2.4);
    _label(canvas, notchY + const Offset(2, -4), 'y(90°)',
        color: Colors.green.shade700, fontSize: 9);

    _label(canvas, center + const Offset(12, -26),
        '${p.shortId} (${p.coordinate.x.toStringAsFixed(2)}, ${p.coordinate.y.toStringAsFixed(2)}, ${p.coordinate.z.toStringAsFixed(2)})',
        color: Colors.blue.shade900);
    _label(canvas, center + const Offset(12, -12), mount.label,
        color: mount.color, fontSize: 10);
  }

  void _drawCoverage2d(Canvas canvas, PlacedLocator p) {
    final rot =
        _Rot.eulerDeg(p.orientation.x, p.orientation.y, p.orientation.z);
    final n = rot.apply(0, 0, 1);
    if (n.z >= -0.3) return;
    final cz = p.coordinate.z;
    if (cz <= 0.1) return;

    final t = cz / -n.z;
    final cxF = p.coordinate.x + n.x * t;
    final cyF = p.coordinate.y + n.y * t;
    final radiusM = t * math.tan(_fovHalfDeg * math.pi / 180);

    final center = view.worldToScreen(Offset(cxF, cyF));
    final radius = _len(radiusM);
    final paint = Paint()
      ..color = Colors.teal.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    const seg = 36;
    for (var i = 0; i < seg; i += 2) {
      final a0 = i / seg * 2 * math.pi;
      final a1 = (i + 1) / seg * 2 * math.pi;
      canvas.drawLine(
        center + Offset(math.cos(a0), math.sin(a0)) * radius,
        center + Offset(math.cos(a1), math.sin(a1)) * radius,
        paint,
      );
    }
    canvas.drawCircle(
        center, 2, Paint()..color = Colors.teal.withValues(alpha: 0.6));
    _label(
      canvas,
      center + Offset(radius * 0.72, -radius * 0.72),
      '커버 r≈${radiusM.toStringAsFixed(1)}m',
      color: Colors.teal.shade700,
      fontSize: 10,
    );
  }

  void _drawTag2d(Canvas canvas, String tagId, _TagTrack track) {
    if (!track.everValid) return;
    // 수신이 끊겨도 마지막 위치를 계속 표시한다 ([태그 갱신]으로 정리).
    final ageSec = now.difference(track.lastTs).inMilliseconds / 1000.0;
    final color = _colorFor(tagId);

    if (showTrail && track.trail.length >= 2) {
      for (var i = 1; i < track.trail.length; i++) {
        final t = i / track.trail.length;
        canvas.drawLine(
          view.worldToScreen(track.trail[i - 1].xy),
          view.worldToScreen(track.trail[i].xy),
          Paint()
            ..color = color.withValues(alpha: 0.08 + 0.35 * t)
            ..strokeWidth = 2,
        );
      }
    }

    final screen = view.worldToScreen(track.pos);
    final live = ageSec < 3;
    final sleep = ageSec > _sleepAfterSec; // 슬립: 회색 표시, 오차원 생략
    final drawColor = sleep ? Colors.blueGrey : color;

    // 오차 원 (표시상 3m 상한)
    if (!sleep && track.stdevXY > 0.05) {
      final r = _len(math.min(track.stdevXY, 3.0));
      canvas.drawCircle(
          screen, r, Paint()..color = color.withValues(alpha: 0.10));
      canvas.drawCircle(
          screen,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: 0.35));
    }

    canvas.drawCircle(screen, 7,
        Paint()..color = live ? color : drawColor.withValues(alpha: 0.35));
    canvas.drawCircle(
        screen,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white);
    final short =
        tagId.length >= 4 ? tagId.substring(tagId.length - 4) : tagId;
    _label(
      canvas,
      screen + const Offset(10, 4),
      '$short (${track.pos.dx.toStringAsFixed(2)}, '
      '${track.pos.dy.toStringAsFixed(2)}, ${track.z.toStringAsFixed(2)})'
      '${live ? '' : (sleep ? ' · 슬립 ${_ageText(ageSec)}' : ' · ${_ageText(ageSec)}')}',
      color: sleep ? Colors.blueGrey.shade600 : color,
    );
  }

  void _drawRay(Canvas canvas, PlacedLocator placement, _AngleRay ray) {
    final start = Offset(placement.coordinate.x, placement.coordinate.y);
    final d = _rayDirection(placement, ray);
    // 3D 방향의 수평 투영 = 위에서 본 점선 (길이도 투영 거리 그대로)
    final end = start + Offset(d.dx, d.dy) * ray.distance;

    final color = _colorFor(ray.tagId).withValues(alpha: ray.live ? 0.9 : 0.3);
    _dashedLine(canvas, view.worldToScreen(start), view.worldToScreen(end),
        Paint()
          ..color = color
          ..strokeWidth = 1.6);

    _label(
      canvas,
      view.worldToScreen(end) + const Offset(6, -6),
      'az ${ray.azimuth.toStringAsFixed(1)}° · el ${ray.elevation.toStringAsFixed(1)}° · ${ray.distance.toStringAsFixed(2)}m',
      color: color,
      fontSize: 10,
    );
  }

  @override
  bool shouldRepaint(covariant _Live2dPainter old) => true;
}
