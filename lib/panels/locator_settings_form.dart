import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/placement.dart';
import '../services/mask_faces.dart';
import '../services/udp_control_service.dart';
import '../state/app_state.dart';
import '../widgets/hover_tip.dart';
import '../widgets/password_gate.dart';
import 'form_widgets.dart';

const _aoxModes = [
  'SL_RTL_AOD_MODE_REAL_TIME_FAST_RESPONSE',
  'SL_RTL_AOD_MODE_REAL_TIME_BASIC',
  'SL_RTL_AOX_MODE_REAL_TIME_BASIC',
  'SL_RTL_AOX_MODE_REAL_HIGH_ACCURACY',
];

const _antennaModes = [
  'SL_RTL_AOX_ARRAY_TYPE_4x4_URA',
  'SL_RTL_AOX_ARRAY_TYPE_3x3_URA',
  'SL_RTL_AOX_ARRAY_TYPE_1x4_ULA',
];

const _cteModes = ['SILABS', 'CONNLESS', 'CONN'];

/// 선택된 로케이터의 설정 폼: 좌표, 자세, AoA config.
class LocatorSettingsForm extends StatelessWidget {
  final PlacedLocator placement;

  const LocatorSettingsForm({super.key, required this.placement});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = placement;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            const Icon(Icons.settings_input_antenna, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.deviceName.isEmpty ? '(이름 없음)' : p.deviceName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  SelectableText(p.locatorId,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                  if (p.ip.isNotEmpty)
                    Text(p.ip,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 24),

        // ---- 좌표 ----
        const Text('좌표 (m)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: _cfgTip(
            '설치 위치 X 좌표 (m) — 도면 원점 기준.\n캔버스에서 마커를 드래그해도 변경됩니다.',
            NumField(
              label: 'X',
              value: p.coordinate.x,
              onChanged: (v) {
                p.coordinate.x = v;
                app.placementEdited();
              },
            ),
          )),
          const SizedBox(width: 6),
          Expanded(
              child: _cfgTip(
            '설치 위치 Y 좌표 (m) — 도면 원점 기준.\n캔버스에서 마커를 드래그해도 변경됩니다.',
            NumField(
              label: 'Y',
              value: p.coordinate.y,
              onChanged: (v) {
                p.coordinate.y = v;
                app.placementEdited();
              },
            ),
          )),
          const SizedBox(width: 6),
          Expanded(
              child: _cfgTip(
            '설치 높이 (m) — 바닥에서 안테나까지.\n위치 계산과 커버리지 반경에 직접 영향을 줍니다.',
            NumField(
              label: 'Z (높이)',
              value: p.coordinate.z,
              onChanged: (v) {
                p.coordinate.z = v;
                app.placementEdited();
              },
            ),
          )),
        ]),
        const SizedBox(height: 16),

        // ---- 자세 ----
        const Text('자세 (Euler °)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: _cfgTip(
            'X축 회전 (도) — 보드의 앞뒤 기울기.\n천장 수평 설치 기본 0.',
            NumField(
              label: 'X',
              value: p.orientation.x,
              fractionDigits: 0,
              onChanged: (v) {
                p.orientation.x = v;
                app.placementEdited();
              },
            ),
          )),
          const SizedBox(width: 6),
          Expanded(
              child: _cfgTip(
            'Y축 회전 (도) — 보드가 바라보는 방향.\n천장 설치(아래를 봄) 기본 180, 바닥 설치 0.',
            NumField(
              label: 'Y',
              value: p.orientation.y,
              fractionDigits: 0,
              onChanged: (v) {
                p.orientation.y = v;
                app.placementEdited();
              },
            ),
          )),
          const SizedBox(width: 6),
          Expanded(
              child: _cfgTip(
            'Z축 회전 (도) — 보드 기준축(x, 0° 노치)이 향하는 수평 방향.\n'
            '3D 뷰의 빨강/초록 노치로 확인할 수 있습니다. 기본 90.',
            NumField(
              label: 'Z',
              value: p.orientation.z,
              fractionDigits: 0,
              onChanged: (v) {
                p.orientation.z = v;
                app.placementEdited();
              },
            ),
          )),
        ]),
        const SizedBox(height: 8),
        Text(
          '천장 설치(안테나가 아래를 향함) 기본값: X=0, Y=180, Z=90',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        _cfgTip(
          'X/Y/Z는 관제의 신호선(빨간선)이 실제 태그를 가리키도록 맞추세요 — 위치 계산은 이 값만 씁니다.\n'
          '그 값으로 그린 케이스가 실물과 반대로 보이면 이 스위치를 켜세요.\n'
          '그림만 보드 면 안에서 180° 돌리며, 데이터와 위치 계산은 바뀌지 않습니다.',
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('케이스 그림만 180° 돌리기', style: TextStyle(fontSize: 13)),
            subtitle: const Text('데이터 변경 없음 · 그림이 실물과 반대일 때',
                style: TextStyle(fontSize: 11)),
            value: p.imageFlip,
            onChanged: (v) {
              p.imageFlip = v;
              app.placementEdited();
            },
          ),
        ),
        const SizedBox(height: 8),

        // ---- AoA config ----
        ExpansionTile(
          title: const Text('AoA 상세 설정',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            _cfgTip(
              'AoA 방향 추정 알고리즘 모드입니다.\n'
              '· REAL_TIME_FAST_RESPONSE: 반응이 빠름 — 움직이는 태그에 적합, 노이즈에 민감\n'
              '· REAL_TIME_BASIC: 기본 실시간 모드 (권장)\n'
              '· HIGH_ACCURACY: 가장 정확하지만 계산량이 많아 느림\n'
              '(AOD_*는 AoD 방식 전용 모드)',
              SafeDropdown(
                label: 'aoxMode',
                value: p.config['aoxMode']?.toString() ?? _aoxModes.first,
                options: _aoxModes,
                onChanged: (v) => _setConfig(app, 'aoxMode', v),
              ),
            ),
            const SizedBox(height: 8),
            _cfgTip(
              '로케이터 안테나 배열 형태입니다. 카드의 실제 안테나 보드와 일치해야 합니다.\n'
              '· 4x4_URA: 4×4 평면 배열 (기본)\n'
              '· 3x3_URA: 3×3 평면 배열\n'
              '· 1x4_ULA: 1×4 직선 배열 — azimuth만 정확, elevation 부정확',
              SafeDropdown(
                label: 'antennaMode',
                value:
                    p.config['antennaMode']?.toString() ?? _antennaModes.first,
                options: _antennaModes,
                onChanged: (v) => _setConfig(app, 'antennaMode', v),
              ),
            ),
            const SizedBox(height: 8),
            _cfgTip(
              'CTE(Constant Tone Extension) 수신 방식입니다. 태그의 송신 방식과 일치해야 합니다.\n'
              '· SILABS: Silicon Labs 독자 비연결 방식 (기본)\n'
              '· CONNLESS: BLE 표준 비연결(주기적 광고) 방식\n'
              '· CONN: BLE 연결 기반 방식',
              SafeDropdown(
                label: 'cteMode',
                value: p.config['cteMode']?.toString() ?? _cteModes.first,
                options: _cteModes,
                onChanged: (v) => _setConfig(app, 'cteMode', v),
              ),
            ),
            const SizedBox(height: 8),
            _cfgTip(
              '각도 필터링(스무딩) 사용 여부입니다.\n'
              '켜면 각도 노이즈가 줄어 안정적이지만, 태그가 움직일 때 반응이 느려집니다.',
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title:
                    const Text('angleFiltering', style: TextStyle(fontSize: 13)),
                value: p.config['angleFiltering'] == true,
                onChanged: (v) => _setConfig(app, 'angleFiltering', v),
              ),
            ),
            _cfgTip(
              '각도 필터 강도 (0~1)입니다. 기본 0.6.\n'
              '클수록 이전 값을 많이 유지해 부드러워지지만 변화에 늦게 반응합니다.',
              NumField(
                label: 'angleFilteringWeight',
                value: _num(p.config['angleFilteringWeight'], 0.6),
                onChanged: (v) => _setConfig(app, 'angleFilteringWeight', v),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: _cfgTip(
                'CTE 신호 길이입니다. 기본 160.\n'
                '길수록 IQ 샘플이 많아져 각도 품질이 좋아지지만 무선 점유 시간이 늘어납니다.',
                NumField(
                  label: 'cteLength',
                  value: _num(p.config['cteLength'], 160),
                  fractionDigits: 0,
                  onChanged: (v) => _setConfig(app, 'cteLength', v.toInt()),
                ),
              )),
              const SizedBox(width: 6),
              Expanded(
                  child: _cfgTip(
                'CTE 샘플링 간격입니다. 기본 1.\n'
                '작을수록 촘촘하게 샘플링해 정확도가 올라가지만 데이터양이 늘어납니다.',
                NumField(
                  label: 'cteSamplingInterval',
                  value: _num(p.config['cteSamplingInterval'], 1),
                  fractionDigits: 0,
                  onChanged: (v) =>
                      _setConfig(app, 'cteSamplingInterval', v.toInt()),
                ),
              )),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: _cfgTip(
                '각도 1회 계산에 사용하는 IQ 샘플 수입니다. 기본 64.\n'
                '많을수록 안정적이지만 갱신 주기와 계산량이 늘어납니다.',
                NumField(
                  label: 'periodSamples',
                  value: _num(p.config['periodSamples'], 64),
                  fractionDigits: 0,
                  onChanged: (v) => _setConfig(app, 'periodSamples', v.toInt()),
                ),
              )),
              const SizedBox(width: 6),
              Expanded(
                  child: _cfgTip(
                '안테나 스위칭 슬롯 길이(µs)입니다. BLE 표준상 1 또는 2. 기본 1.\n'
                '1µs면 같은 CTE에서 더 많은 안테나 샘플을 얻습니다.',
                NumField(
                  label: 'slotDuration',
                  value: _num(p.config['slotDuration'], 1),
                  fractionDigits: 0,
                  onChanged: (v) => _setConfig(app, 'slotDuration', v.toInt()),
                ),
              )),
            ]),
          ],
        ),
        const SizedBox(height: 8),

        // ---- 설정 그룹: 반사면 마스크 (카드 azimuthMask) ----
        _MaskSection(
          key: ValueKey('mask-${p.locatorId}'),
          placement: p,
        ),

        // ---- 설정 그룹: MQTT 브로커 (좌표/자세/AoA와 같은 "설정" 성격) ----
        _MqttBrokerSection(
          key: ValueKey('mqtt-${p.locatorId}'),
          placement: p,
        ),

        // ---- 제어 그룹: 카드에 즉시 실행되는 명령 (설정과 구분) ----
        const Divider(height: 28),
        Row(
          children: [
            Icon(Icons.gamepad_outlined, size: 16, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            const Text('Locator 제어', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text('카드에 즉시 실행되는 명령입니다 (저장/전송과 무관).',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        _DeviceControlButtons(
          key: ValueKey('ctrl-${p.locatorId}'),
          placement: p,
        ),

        const Divider(height: 28),
        _cfgTip(
          '이 로케이터 배치를 삭제합니다 (Ctrl+Z로 복구 가능).\n'
          '서버로 전송하기 전까지 서버에는 반영되지 않습니다.',
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => app.removePlacement(p.locatorId),
            icon: const Icon(Icons.delete_outline),
            label: const Text('캔버스에서 제거'),
          ),
        ),
        const SizedBox(height: 8),
        _cfgTip(
          '로케이터 선택을 해제하고 전역 Positioning 설정 폼을 표시합니다.',
          TextButton(
            onPressed: () => app.selectLocator(null),
            child: const Text('선택 해제 (전역 설정 보기)'),
          ),
        ),
      ],
    );
  }

  void _setConfig(AppState app, String key, Object? value) {
    placement.config[key] = value;
    app.placementEdited();
  }

  static double _num(Object? v, double fallback) =>
      v is num ? v.toDouble() : fallback;

  /// 설정 항목 설명 툴팁: 마우스를 1초쯤 올리고 있으면 표시된다.
  Widget _cfgTip(String message, Widget child) => Tooltip(
        message: message,
        waitDuration: const Duration(seconds: 1),
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
        child: child,
      );
}

/// 검색 결과 우선, 없으면 배치에 저장된 IP.
String _resolvePlacementIp(AppState app, PlacedLocator placement) {
  final live = app.devices
      .where((d) =>
          !d.isServer && d.hasValidMac && d.locatorId == placement.locatorId)
      .firstOrNull;
  return live?.ip ?? placement.ip;
}

Widget _noIpHint() => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '카드 IP를 알 수 없습니다. [Locator 검색]으로 이 로케이터가 검색되면 사용할 수 있습니다.',
        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
      ),
    );

void _controlSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool?> _controlConfirm(BuildContext context, String title, String body) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확인')),
      ],
    ),
  );
}

Future<void> _restartAoaService(
    BuildContext context, UdpControlService control, String ip) async {
  final resp = await control.restartService(targetIp: ip);
  if (!context.mounted) return;
  _controlSnack(
      context,
      resp['ok'] == true
          ? 'AOA 서비스 재시작 완료'
          : '재시작 실패: ${resp['error'] ?? resp['rc'] ?? '알 수 없는 오류'}');
}

/// 설정 그룹: 반사면 마스크 — 도면 4면 중 벽·반사면 쪽을 골라 그 방향에서 오는
/// 각도(반사파)를 카드의 각도 계산에서 제외한다 (azimuthMask · 로케이터 v1.0.29+).
class _MaskSection extends StatefulWidget {
  final PlacedLocator placement;

  const _MaskSection({super.key, required this.placement});

  @override
  State<_MaskSection> createState() => _MaskSectionState();
}

class _MaskSectionState extends State<_MaskSection> {
  bool _busy = false;
  List<(double, double)>? _card; // 카드에 적용된 값 (불러온 경우)
  bool _cardLoaded = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = widget.placement;
    final ip = _resolvePlacementIp(app, p);
    final ranges = MaskFaces.localRanges(p.maskFaces, p.orientation);

    return ExpansionTile(
      initiallyExpanded: p.maskFaces.isNotEmpty,
      title: Text(
          '반사면 마스크${p.maskFaces.isEmpty ? '' : ' (${p.maskFaces.length}면)'}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '로케이터 뒤나 옆이 벽·반사면이면 그 면을 고르세요. 그 방향에서 오는 각도(반사파)를 '
          '카드가 계산에서 뺍니다. 방향은 도면 기준이며 현재 자세(orientation)로 변환됩니다 — '
          '자세를 바꾸면 다시 적용하세요.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in MaskFaces.labels.keys)
              FilterChip(
                label: Text(MaskFaces.labels[f]!, style: const TextStyle(fontSize: 12)),
                selected: p.maskFaces.contains(f),
                onSelected: _busy
                    ? null
                    : (v) {
                        if (v) {
                          p.maskFaces.add(f);
                        } else {
                          p.maskFaces.remove(f);
                        }
                        app.placementEdited();
                      },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text('카드 azimuthMask: ${MaskFaces.describe(ranges)}',
            style: const TextStyle(fontSize: 12)),
        if (_cardLoaded)
          Text('카드에 적용된 값: ${_card == null ? '없음' : MaskFaces.describe(_card!)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        if (ip.isEmpty)
          _noIpHint()
        else
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _apply(ip, ranges),
                icon: _busy
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send, size: 16),
                label: Text(ranges.isEmpty ? '카드 마스크 해제' : '카드에 적용'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _load(ip),
              child: const Text('카드 값'),
            ),
          ]),
      ],
    );
  }

  Future<void> _load(String ip) async {
    setState(() => _busy = true);
    try {
      final v = await LocatorCardApi(ip).getAzimuthMask();
      if (mounted) {
        setState(() {
          _card = v;
          _cardLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) _controlSnack(context, '카드 값 읽기 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(String ip, List<(double, double)> ranges) async {
    final go = await _controlConfirm(
      context,
      '반사면 마스크 적용',
      '${widget.placement.shortId} ($ip)에 azimuthMask ${MaskFaces.describe(ranges)}를 적용합니다.\n'
          '카드의 AOA 서비스가 재시작되어 몇 초간 각도가 끊깁니다.',
    );
    if (go != true || !mounted) return;
    final ok = await confirmSettingsPassword(context, '반사면 마스크 적용');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final v = await LocatorCardApi(ip).setAzimuthMask(ranges);
      if (!mounted) return;
      setState(() {
        _card = v;
        _cardLoaded = true;
      });
      _controlSnack(context, '마스크 적용됨 · AOA 서비스 재시작 (${MaskFaces.describe(v ?? const [])})');
    } catch (e) {
      if (mounted) _controlSnack(context, '마스크 적용 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// 설정 그룹: 카드의 MQTT 브로커 설정 (UDP MQTT_SET).
class _MqttBrokerSection extends StatefulWidget {
  final PlacedLocator placement;

  const _MqttBrokerSection({super.key, required this.placement});

  @override
  State<_MqttBrokerSection> createState() => _MqttBrokerSectionState();
}

class _MqttBrokerSectionState extends State<_MqttBrokerSection> {
  final _control = const UdpControlService();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '1883');
  bool _busy = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ip = _resolvePlacementIp(app, widget.placement);

    if (!_prefilled) {
      _prefilled = true;
      final live = app.devices
          .where((d) => d.locatorId == widget.placement.locatorId)
          .firstOrNull;
      _host.text = live?.mqttHost ?? app.serverIp;
      if (live?.mqttPort != null) _port.text = live!.mqttPort.toString();
    }

    return ExpansionTile(
      title: const Text('MQTT 브로커 설정',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        if (ip.isEmpty)
          _noIpHint()
        else ...[
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: '브로커 호스트 (보통 서버 카드 IP)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
              width: 90,
              child: TextField(
                controller: _port,
                decoration: const InputDecoration(
                  labelText: '포트',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: '이 카드가 접속할 MQTT 브로커 주소를 UDP로 설정합니다.\n'
                    '전송 후 AOA 서비스 재시작이 필요하며 비밀번호 확인이 뜹니다.',
                waitDuration: const Duration(seconds: 1),
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _doSetMqtt(ip),
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('카드에 전송'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text('전송 후 AOA 서비스 재시작(또는 재부팅)해야 적용됩니다.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ],
    );
  }

  Future<void> _doSetMqtt(String ip) async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null) {
      _controlSnack(context, '호스트/포트를 올바르게 입력하세요');
      return;
    }
    final ok = await confirmSettingsPassword(context, 'MQTT 브로커 설정 변경');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final resp = await _control.setMqtt(
          targetIp: ip, brokerHost: host, brokerPort: port);
      if (!mounted) return;
      if (resp['ok'] == true) {
        _controlSnack(context, 'MQTT 브로커 설정 저장됨 ($host:$port)');
        final restart = await _controlConfirm(context, 'AOA 서비스 재시작',
            '설정을 적용하려면 AOA 서비스를 재시작해야 합니다.\n지금 재시작할까요?');
        if (restart == true && mounted) {
          await _restartAoaService(context, _control, ip);
        }
      } else {
        _controlSnack(context, '설정 실패: ${resp['error'] ?? '알 수 없는 오류'}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// 제어 그룹: 카드에 즉시 실행되는 명령 (LED 식별 / 서비스 재시작 / 재부팅).
class _DeviceControlButtons extends StatefulWidget {
  final PlacedLocator placement;

  const _DeviceControlButtons({super.key, required this.placement});

  @override
  State<_DeviceControlButtons> createState() => _DeviceControlButtonsState();
}

class _DeviceControlButtonsState extends State<_DeviceControlButtons> {
  final _control = const UdpControlService();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ip = _resolvePlacementIp(app, widget.placement);
    if (ip.isEmpty) return _noIpHint();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        hoverTip(
          '카드의 LED를 8초간 점멸시켜 현장에서 어떤 Locator인지 확인합니다.',
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _doLed(ip),
            icon: const Icon(Icons.lightbulb, size: 16),
            label: const Text('LED 식별', style: TextStyle(fontSize: 12)),
          ),
        ),
        hoverTip(
          '카드의 AOA 서비스를 재시작합니다.\n약 10초간 angle 송신이 중단됩니다.',
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _doRestart(ip),
            icon: const Icon(Icons.restart_alt, size: 16),
            label:
                const Text('AOA 서비스 재시작', style: TextStyle(fontSize: 12)),
          ),
        ),
        hoverTip(
          '카드를 재부팅합니다. 다시 켜질 때까지 1~2분 걸립니다.',
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _doReboot(ip),
            icon: const Icon(Icons.power_settings_new, size: 16),
            label: const Text('재부팅', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Future<void> _doRestart(String ip) async {
    setState(() => _busy = true);
    try {
      await _restartAoaService(context, _control, ip);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doReboot(String ip) async {
    final ok = await _controlConfirm(
        context, '재부팅', '${widget.placement.locatorId} ($ip) 카드를 재부팅할까요?');
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final resp = await _control.reboot(targetIp: ip);
      if (!mounted) return;
      _controlSnack(
          context,
          resp['ok'] == true
              ? '재부팅 명령 전송됨 — 카드가 다시 켜질 때까지 1~2분 걸립니다'
              : '재부팅 실패: ${resp['error'] ?? '알 수 없는 오류'}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doLed(String ip) async {
    await _control.ledBlink(targetIp: ip);
    if (mounted) _controlSnack(context, 'LED 점멸 전송 — 카드의 LED를 확인하세요');
  }
}
