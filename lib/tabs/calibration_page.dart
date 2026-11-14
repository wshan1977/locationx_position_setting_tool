import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../canvas/grid_painter.dart';
import '../canvas/world_transform.dart';
import '../models/vec3.dart';
import '../services/calibration.dart';
import '../state/app_state.dart';
import '../state/mqtt_state.dart';
import '../widgets/mqtt_connect_bar.dart';
import '../widgets/save_dialog.dart';
import '../widgets/tab_guide.dart';

/// 설정 › ④ 로케이터 보정: 기준점(실제 위치를 아는 곳)에 태그를 두고 각
/// 로케이터의 각도를 모아, 설치 기울기·회전을 orientation으로 보정한다.
/// 기준점은 현재 층 도면을 클릭해 찍는다 (로케이터 근처는 바로 아래로 스냅).
/// 기준점 3곳 이상을 권장 (1곳이면 잡음까지 기울기로 흡수해 신뢰할 수 없음).
class CalibrationPage extends StatefulWidget {
  const CalibrationPage({super.key});

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

/// 기준점 1곳의 입력과 수집 결과.
class _RefPoint {
  Offset world; // 월드 좌표 (m)
  final z = TextEditingController(text: '0');

  /// locatorId → (azimuth, elevation) 샘플 (마지막 수집)
  Map<String, List<(double, double)>> angles = {};

  /// 마지막 수집 중 positioning이 낸 위치 평균 (월드)
  Offset? estimated;

  /// 처음(보정 전) 수집 때의 위치 오차 (m) — 검증 비교용
  double? errorFirst;
  double? errorLast;

  _RefPoint(this.world);

  Vec3 get target =>
      Vec3(x: world.dx, y: world.dy, z: double.tryParse(z.text.trim()) ?? 0);

  bool get captured => angles.isNotEmpty;

  void dispose() => z.dispose();
}

class _CalibrationPageState extends State<CalibrationPage> {
  static const _captureSeconds = 20;

  final List<_RefPoint> _points = [];
  int? _selected;
  String? _tag;

  // 수집 진행
  int? _capturingIndex;
  int _remaining = 0;
  StreamSubscription<MqttMessageRecord>? _sub;
  Timer? _timer;

  // 계산 결과 (locatorId → fit) · 적용 전 orientation (되돌리기용)
  Map<String, CalibFit>? _fits;
  Map<String, int>? _pointCounts;
  Map<String, Vec3>? _previous;

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    for (final p in _points) {
      p.dispose();
    }
    super.dispose();
  }

  static final _angleTopic = RegExp(r'^controlbit/aoa/angle/([^/]+)/([^/]+)$');
  static final _posTopic = RegExp(r'^controlbit/aoa/position/[^/]+/([^/]+)$');

  /// 지금까지 angle 토픽에 나타난 태그 ID.
  List<String> _tags(MqttState mqtt) {
    final s = <String>{};
    for (final t in mqtt.topics.keys) {
      final m = _angleTopic.firstMatch(t);
      if (m != null) s.add(m.group(2)!);
    }
    return s.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final mqtt = context.watch<MqttState>();
    final tags = _tags(mqtt);
    if (_tag == null || !tags.contains(_tag)) {
      _tag = tags.isEmpty ? null : tags.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabGuide(
          icon: Icons.tune,
          text: '작업 순서: ① 내부망 MQTT 연결 → ② 도면에서 태그를 놓은 곳을 클릭(로케이터 근처는 바로 아래로 맞춤)'
              ' → ③ [수집] 20초 — 3곳 이상 → ④ [보정 계산] → ⑤ [적용] 후 서버로 전송 → '
              '⑥ 같은 기준점에서 다시 [수집]해 위치 오차가 줄었는지 검증',
        ),
        if (!mqtt.isConnected) const MqttConnectBar(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _CalibMap(
                  app: app,
                  points: _points,
                  selected: _selected,
                  locked: _capturingIndex != null,
                  onAdd: (w) => setState(() {
                    _points.add(_RefPoint(w));
                    _selected = _points.length - 1;
                  }),
                  onSelect: (i) => setState(() => _selected = i),
                  onMove: (i, w) => setState(() => _points[i].world = w),
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 470,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _tagRow(mqtt, tags),
                    const SizedBox(height: 10),
                    _pointsCard(mqtt),
                    const SizedBox(height: 10),
                    _resultCard(app),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tagRow(MqttState mqtt, List<String> tags) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Icon(Icons.circle,
            size: 12, color: mqtt.isConnected ? Colors.green : Colors.grey),
        Text(mqtt.isConnected ? 'MQTT ${mqtt.host}:${mqtt.port}' : 'MQTT 미연결',
            style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        const Text('태그', style: TextStyle(fontSize: 13)),
        if (tags.isEmpty)
          Text('angle 수신 대기 중…',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600))
        else
          DropdownButton<String>(
            value: _tag,
            isDense: true,
            items: [
              for (final t in tags)
                DropdownMenuItem(
                    value: t, child: Text(t, style: const TextStyle(fontSize: 13))),
            ],
            onChanged:
                _capturingIndex != null ? null : (v) => setState(() => _tag = v),
          ),
      ],
    );
  }

  // =========================================================
  // 기준점
  // =========================================================
  Widget _pointsCard(MqttState mqtt) {
    return _card(
      Icons.place,
      '기준점 (${_points.length})',
      '도면을 클릭해 추가 · 점을 드래그해 이동 · 높이 z는 바닥이면 0',
      _points.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('왼쪽 도면에서 태그를 놓은 위치를 클릭하세요.',
                  style: TextStyle(color: Colors.grey.shade600)),
            )
          : Column(
              children: [
                for (var i = 0; i < _points.length; i++) _pointRow(mqtt, i),
              ],
            ),
    );
  }

  Widget _pointRow(MqttState mqtt, int i) {
    final p = _points[i];
    final capturing = _capturingIndex == i;
    final busy = _capturingIndex != null;
    final selected = _selected == i;
    final samples = p.angles.values.fold<int>(0, (a, b) => a + b.length);
    return InkWell(
      onTap: () => setState(() => _selected = i),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.07)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: p.captured ? Colors.green : Colors.orange,
                  child: Text('${i + 1}',
                      style: const TextStyle(fontSize: 11, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '(${p.world.dx.toStringAsFixed(2)}, ${p.world.dy.toStringAsFixed(2)})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                ),
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: p.z,
                    enabled: !busy,
                    decoration: const InputDecoration(labelText: 'z (m)', isDense: true),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.tonalIcon(
                  onPressed: busy || !mqtt.isConnected || _tag == null
                      ? null
                      : () => _capture(i),
                  icon: capturing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.fiber_manual_record, size: 16),
                  label: Text(capturing ? '$_remaining초' : '수집'),
                ),
                IconButton(
                  tooltip: '기준점 삭제',
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            _points.removeAt(i).dispose();
                            _selected = null;
                          }),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            if (samples > 0)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 2),
                child: Text(
                  '로케이터 ${p.angles.length}대 · 샘플 $samples'
                  '${p.errorLast == null ? '' : ' · 위치 오차 ${p.errorLast!.toStringAsFixed(2)} m'}'
                  '${p.errorFirst != null && p.errorLast != null && p.errorFirst != p.errorLast ? ' (보정 전 ${p.errorFirst!.toStringAsFixed(2)} m)' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // 결과
  // =========================================================
  Widget _resultCard(AppState app) {
    final fits = _fits;
    final ready = _points.where((p) => p.captured).length;
    return _card(
      Icons.calculate,
      '보정 결과',
      '로케이터별 기준점 평균 각도 오차와 보정 orientation (기준점 2곳 이상 수집한 로케이터만)',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed:
                    _capturingIndex != null || ready < 2 ? null : () => _compute(app),
                icon: const Icon(Icons.calculate),
                label: Text('보정 계산 (수집된 기준점 $ready곳)'),
              ),
              FilledButton.icon(
                onPressed: fits == null || fits.isEmpty ? null : () => _apply(app),
                icon: const Icon(Icons.check),
                label: const Text('적용 (현재 층)'),
              ),
              OutlinedButton.icon(
                onPressed: _previous == null ? null : () => _revert(app),
                icon: const Icon(Icons.undo),
                label: const Text('되돌리기'),
              ),
              OutlinedButton.icon(
                onPressed: () => showPushToServerDialog(context),
                icon: const Icon(Icons.cloud_upload),
                label: const Text('서버로 전송'),
              ),
            ],
          ),
          if (fits != null) ...[
            const SizedBox(height: 12),
            if (fits.isEmpty)
              const Text('계산할 수 있는 로케이터가 없습니다 (로케이터마다 기준점 2곳 이상 필요).')
            else
              for (final e in fits.entries) _fitTile(app, e.key, e.value),
          ],
        ],
      ),
    );
  }

  Widget _fitTile(AppState app, String id, CalibFit f) {
    String fmt(Vec3 v) =>
        '(${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}, ${v.z.toStringAsFixed(1)})';
    final cur = app.placements.where((p) => p.locatorId == id).firstOrNull?.orientation ??
        Vec3();
    final base = _previous?[id] ?? cur;
    final warn = <String>[
      if ((f.orientation.x - base.x).abs() > 25 || (f.orientation.y - base.y).abs() > 25)
        '기울기 25° 초과',
      if ((f.orientation.z - base.z).abs() > 30) '회전 30° 초과',
      if (f.errorAfter > 8) '보정 후 오차 큼',
      if ((_pointCounts?[id] ?? 0) < 3) '기준점 3곳 미만',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${id.length > 4 ? id.substring(id.length - 4) : id} · 각도 오차 '
            '${f.errorBefore.toStringAsFixed(1)}° → ${f.errorAfter.toStringAsFixed(1)}° · '
            '${warn.isEmpty ? '정상' : warn.join(' · ')}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: warn.isEmpty ? Colors.green.shade800 : Colors.orange.shade900,
            ),
          ),
          Text('orientation ${fmt(base)} → ${fmt(f.orientation)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
        ],
      ),
    );
  }

  Widget _card(IconData icon, String title, String subtitle, Widget child) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(title,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );

  // =========================================================
  // 동작
  // =========================================================
  void _capture(int i) {
    final mqtt = context.read<MqttState>();
    final p = _points[i];
    final target = p.target;
    final tag = _tag!;
    final angles = <String, List<(double, double)>>{};
    final xs = <double>[], ys = <double>[];
    setState(() {
      _capturingIndex = i;
      _selected = i;
      _remaining = _captureSeconds;
    });
    _sub = mqtt.records.listen((r) {
      final a = _angleTopic.firstMatch(r.topic);
      if (a != null && a.group(2) == tag) {
        final d = _json(r.payload);
        final az = (d?['azimuth'] as num?)?.toDouble();
        final el = (d?['elevation'] as num?)?.toDouble();
        if (az != null && el != null) {
          angles.putIfAbsent(a.group(1)!, () => []).add((az, el));
        }
        return;
      }
      final m = _posTopic.firstMatch(r.topic);
      if (m != null && m.group(1) == tag) {
        final d = _json(r.payload);
        final x = (d?['x'] as num?)?.toDouble();
        final y = (d?['y'] as num?)?.toDouble();
        if (x != null && y != null) {
          xs.add(x);
          ys.add(y);
        }
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining > 0) return;
      t.cancel();
      _sub?.cancel();
      _sub = null;
      setState(() {
        _capturingIndex = null;
        p.angles = angles;
        if (xs.isNotEmpty) {
          final ex = xs.reduce((a, b) => a + b) / xs.length;
          final ey = ys.reduce((a, b) => a + b) / ys.length;
          p.estimated = Offset(ex, ey);
          p.errorLast =
              math.sqrt(math.pow(ex - target.x, 2) + math.pow(ey - target.y, 2));
          p.errorFirst ??= p.errorLast;
        }
      });
      if (angles.isEmpty) {
        _snack('20초 동안 태그 $tag의 angle 메시지를 받지 못했습니다');
      }
    });
  }

  static Map<String, dynamic>? _json(String s) {
    try {
      final d = jsonDecode(s);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  void _compute(AppState app) {
    final fits = <String, CalibFit>{};
    final counts = <String, int>{};
    for (final l in app.placements) {
      final pairs = <(List<double>, List<double>)>[];
      for (final p in _points) {
        final s = p.angles[l.locatorId];
        if (s == null || s.length < 20) continue;
        pairs.add((Calib.meanLocalDir(s), Calib.trueDir(l.coordinate, p.target)));
      }
      counts[l.locatorId] = pairs.length;
      if (pairs.length < 2) continue;
      // 이미 적용했다면 보정 전 orientation에서 다시 출발 (누적 방지)
      final start = _previous?[l.locatorId] ?? l.orientation;
      fits[l.locatorId] = Calib.fit(start, pairs);
    }
    setState(() {
      _fits = fits;
      _pointCounts = counts;
    });
  }

  void _apply(AppState app) {
    final fits = _fits!;
    _previous ??= {
      for (final l in app.placements)
        if (fits.containsKey(l.locatorId)) l.locatorId: l.orientation.copy(),
    };
    final n = app
        .applyOrientations({for (final e in fits.entries) e.key: e.value.orientation});
    setState(() {});
    _snack('로케이터 $n대에 보정 orientation을 적용했습니다 — [서버로 전송] 후 기준점에서 다시 [수집]해 검증하세요');
  }

  void _revert(AppState app) {
    final n = app.applyOrientations(_previous!);
    setState(() => _previous = null);
    _snack('로케이터 $n대를 보정 전 orientation으로 되돌렸습니다 — [서버로 전송]해야 서버에 반영됩니다');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// 보정용 도면: 현재 층 도면·그리드·로케이터와 기준점을 그린다.
/// 클릭 = 기준점 추가 (로케이터 0.3m 이내면 그 바로 아래로 스냅) ·
/// 점 드래그 = 이동 · 빈 곳 드래그 = 화면 이동 · 휠 = 확대/축소.
/// 위치 설정 화면의 줌/팬과는 따로 움직인다 (스케일·원점만 공유).
class _CalibMap extends StatefulWidget {
  final AppState app;
  final List<_RefPoint> points;
  final int? selected;
  final bool locked;
  final void Function(Offset world) onAdd;
  final void Function(int index) onSelect;
  final void Function(int index, Offset world) onMove;

  const _CalibMap({
    required this.app,
    required this.points,
    required this.selected,
    required this.locked,
    required this.onAdd,
    required this.onSelect,
    required this.onMove,
  });

  @override
  State<_CalibMap> createState() => _CalibMapState();
}

class _CalibMapState extends State<_CalibMap> {
  static const _snapM = 0.3;
  static const _hitPx = 14.0;

  WorldTransform? _view;
  Size? _fittedFor;
  int? _dragging;
  bool _panning = false;

  WorldTransform _base() => WorldTransform(
        metersPerPixel: widget.app.transform.metersPerPixel,
        originPx: widget.app.transform.originPx,
      );

  /// 도면(없으면 로케이터 범위)이 화면에 들어오게 맞춘다.
  WorldTransform _fit(Size size) {
    final t = _base();
    final img = widget.app.floorImage;
    Rect r;
    if (img != null) {
      r = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    } else {
      final pts = [
        for (final l in widget.app.placements)
          t.worldToImage(Offset(l.coordinate.x, l.coordinate.y)),
        for (final p in widget.points) t.worldToImage(p.world),
      ];
      if (pts.isEmpty) {
        r = Rect.fromCenter(center: t.worldToImage(Offset.zero), width: 200, height: 200);
      } else {
        r = Rect.fromPoints(pts.first, pts.first);
        for (final q in pts) {
          r = r.expandToInclude(Rect.fromPoints(q, q));
        }
        r = r.inflate(math.max(r.width, r.height) * 0.25 + 40);
      }
    }
    final z = math.min(size.width / r.width, size.height / r.height) * 0.92;
    return t.copyWith(
      zoom: z,
      panPx: Offset(size.width / 2, size.height / 2) - r.center * z,
    );
  }

  int? _hit(WorldTransform v, Offset screen) {
    for (var i = widget.points.length - 1; i >= 0; i--) {
      if ((v.worldToScreen(widget.points[i].world) - screen).distance <= _hitPx) {
        return i;
      }
    }
    return null;
  }

  Offset _snap(Offset world) {
    for (final l in widget.app.placements) {
      final c = Offset(l.coordinate.x, l.coordinate.y);
      if ((c - world).distance <= _snapM) return c;
    }
    return Offset((world.dx * 100).roundToDouble() / 100,
        (world.dy * 100).roundToDouble() / 100);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      if (_view == null || _fittedFor != size) {
        _view = _fit(size);
        _fittedFor = size;
      }
      // 위치 설정에서 스케일·원점이 바뀌면 따라간다 (줌/팬은 유지)
      final b = _base();
      if (_view!.metersPerPixel != b.metersPerPixel || _view!.originPx != b.originPx) {
        _view = _view!.copyWith(metersPerPixel: b.metersPerPixel, originPx: b.originPx);
      }
      final v = _view!;
      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            setState(() => _view = v.zoomAt(
                e.localPosition, v.zoom * (e.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15)));
          }
        },
        child: GestureDetector(
          onTapUp: widget.locked
              ? null
              : (d) {
                  final i = _hit(v, d.localPosition);
                  if (i != null) {
                    widget.onSelect(i);
                  } else {
                    widget.onAdd(_snap(v.screenToWorld(d.localPosition)));
                  }
                },
          onPanStart: (d) {
            final i = widget.locked ? null : _hit(v, d.localPosition);
            _dragging = i;
            _panning = i == null;
            if (i != null) widget.onSelect(i);
          },
          onPanUpdate: (d) {
            if (_dragging != null) {
              widget.onMove(_dragging!, _snap(v.screenToWorld(d.localPosition)));
            } else if (_panning) {
              setState(() => _view = v.copyWith(panPx: v.panPx + d.delta));
            }
          },
          onPanEnd: (_) {
            _dragging = null;
            _panning = false;
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xFFF7F7F9),
                  child: CustomPaint(
                    painter: FloorPainter(image: widget.app.floorImage, t: v),
                    foregroundPainter: _CalibOverlayPainter(
                      t: v,
                      locators: [
                        for (final l in widget.app.placements)
                          (
                            Offset(l.coordinate.x, l.coordinate.y),
                            l.locatorId.length > 4
                                ? l.locatorId.substring(l.locatorId.length - 4)
                                : l.locatorId,
                          ),
                      ],
                      points: [
                        for (final p in widget.points) (p.world, p.captured, p.estimated),
                      ],
                      selected: widget.selected,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '클릭: 기준점 추가 · 점 드래그: 이동 · 빈 곳 드래그: 화면 이동 · 휠: 확대/축소\n'
                    '● 주황 = 미수집 · 초록 = 수집됨 · ✕ = 그때 계산된 위치',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton.filledTonal(
                  tooltip: '화면에 맞추기',
                  onPressed: () => setState(() => _view = _fit(size)),
                  icon: const Icon(Icons.fit_screen),
                ),
              ),
              if (widget.app.floorImage == null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Text('도면 없음 — [③ 위치 설정]에서 도면을 불러오면 함께 표시됩니다',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _CalibOverlayPainter extends CustomPainter {
  final WorldTransform t;
  final List<(Offset, String)> locators;
  final List<(Offset, bool, Offset?)> points; // (위치, 수집됨, 계산 위치)
  final int? selected;

  _CalibOverlayPainter({
    required this.t,
    required this.locators,
    required this.points,
    required this.selected,
  });

  void _label(Canvas canvas, String text, Offset at, Color color,
      {double size = 11, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              fontSize: size,
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 로케이터: 파란 사각 + 이름
    for (final (w, name) in locators) {
      final s = t.worldToScreen(w);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: s, width: 16, height: 16),
            const Radius.circular(3)),
        Paint()..color = const Color(0xFF1565C0),
      );
      _label(canvas, name, s + const Offset(0, -16), const Color(0xFF1565C0), bold: true);
    }
    // 기준점
    for (var i = 0; i < points.length; i++) {
      final (w, captured, est) = points[i];
      final s = t.worldToScreen(w);
      final color = captured ? const Color(0xFF2E7D32) : const Color(0xFFEF6C00);
      if (est != null) {
        final e = t.worldToScreen(est);
        canvas.drawLine(
            s, e, Paint()..color = Colors.red.withValues(alpha: 0.6)..strokeWidth = 1.5);
        final p = Paint()
          ..color = Colors.red
          ..strokeWidth = 2;
        canvas.drawLine(e + const Offset(-5, -5), e + const Offset(5, 5), p);
        canvas.drawLine(e + const Offset(-5, 5), e + const Offset(5, -5), p);
      }
      if (i == selected) {
        canvas.drawCircle(s, 15, Paint()..color = color.withValues(alpha: 0.25));
      }
      canvas.drawCircle(s, 10, Paint()..color = color);
      canvas.drawCircle(
          s,
          10,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      _label(canvas, '${i + 1}', s, Colors.white, size: 11, bold: true);
    }
  }

  @override
  bool shouldRepaint(_CalibOverlayPainter old) => true;
}
