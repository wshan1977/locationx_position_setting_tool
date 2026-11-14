import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../models/placement.dart';
import '../models/vec3.dart';
import 'mqtt_state.dart';

/// 외부 브로커의 retained status 토픽으로 파악한 장치 1대.
class ExternalDevice {
  final String deviceId;
  final String type; // "server" | "locator"
  final bool online;
  final String ip;
  final String ver;
  final double? cpuTempC;
  final List<String> throttled;
  final Map<String, String> services;
  final bool? mqttConnected;
  final double? uartRxRateBps;
  final String? locatorId;

  /// positioning_config에 배치된 로케이터의 좌표(m)·자세(°) — 서버 카드
  /// cloud-agent v1.2.0+가 상태에 포함한다. 미배치/구버전이면 null.
  final Vec3? coordinate;
  final Vec3? orientation;

  /// 부팅 후 경과(초) · 부팅 시각(epoch sec) — 카드가 얼마나 켜져 있었는지.
  final int? uptimeSec;
  final int? bootTs;

  final int ts; // 에이전트 발행 시각 (epoch sec)
  final DateTime lastRx; // 도구 수신 시각

  ExternalDevice({
    required this.deviceId,
    required this.type,
    required this.online,
    required this.ip,
    required this.ver,
    required this.cpuTempC,
    required this.throttled,
    required this.services,
    required this.mqttConnected,
    required this.uartRxRateBps,
    required this.locatorId,
    required this.coordinate,
    required this.orientation,
    required this.uptimeSec,
    required this.bootTs,
    required this.ts,
    required this.lastRx,
  });

  bool get isServer => type == 'server';

  /// "3일 4시간" 형태의 가동시간 문자열. 수신 후 경과분을 더해 보정한다
  /// (상태는 주기 발행이라 uptimeSec 자체는 발행 시점 값).
  String? get uptimeText {
    var sec = uptimeSec;
    if (sec == null) return null;
    sec += DateTime.now().difference(lastRx).inSeconds;
    final d = sec ~/ 86400;
    final h = (sec % 86400) ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (d > 0) return '$d일 $h시간';
    if (h > 0) return '$h시간 $m분';
    return '$m분';
  }

  /// 부팅 시각 "07-10 09:12" 형태.
  String? get bootTimeText {
    final t = bootTs;
    if (t == null) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  }

  static ExternalDevice? fromPayload(String deviceId, String payload) {
    final dynamic j;
    try {
      j = jsonDecode(payload);
    } catch (_) {
      return null;
    }
    if (j is! Map) return null;
    final services = <String, String>{};
    final rawSvc = j['services'];
    if (rawSvc is Map) {
      rawSvc.forEach((k, v) => services[k.toString()] = v.toString());
    }
    return ExternalDevice(
      deviceId: deviceId,
      type: j['type']?.toString() ?? 'locator',
      online: j['online'] == true,
      ip: j['ip']?.toString() ?? '',
      ver: j['ver']?.toString() ?? '',
      cpuTempC: (j['cpu_temp_c'] as num?)?.toDouble(),
      throttled: (j['throttled'] is List)
          ? (j['throttled'] as List).map((e) => e.toString()).toList()
          : const [],
      services: services,
      mqttConnected:
          j.containsKey('mqtt_connected') ? j['mqtt_connected'] == true : null,
      uartRxRateBps: (j['uart_rx_rate_bps'] as num?)?.toDouble(),
      locatorId: j['locator_id']?.toString(),
      coordinate: (j['coordinate'] is Map)
          ? Vec3.fromJson((j['coordinate'] as Map).cast())
          : null,
      orientation: (j['orientation'] is Map)
          ? Vec3.fromJson((j['orientation'] as Map).cast())
          : null,
      uptimeSec: (j['uptime_sec'] as num?)?.toInt(),
      bootTs: (j['boot_ts'] as num?)?.toInt(),
      ts: (j['ts'] as num?)?.toInt() ?? 0,
      lastRx: DateTime.now(),
    );
  }
}

/// 원격 명령 1건의 결과 (cmdres 수신 또는 타임아웃).
class CmdResult {
  final bool ok;
  final String message;
  CmdResult(this.ok, this.message);
}

/// 외부망 테스트 탭 상태: 외부 브로커 전용 [MqttState]를 소유하고
/// `locationx/<siteId>/` 프리픽스 아래의 status·agent·cmdres 토픽을 해석한다.
/// 프리픽스는 MqttState가 수신 시 제거하므로 여기서는 벗겨진 토픽만 다룬다.
/// controlbit/aoa/position/... 도 같은 연결로 들어와 PositionLiveView가
/// (중첩 Provider로 이 mqtt를 주입하면) 무수정으로 위치를 그린다.
class ExternalState extends ChangeNotifier {
  final MqttState mqtt = MqttState();

  String brokerHost = 'broker.hivemq.com';
  int brokerPort = 1883;
  String siteId = '';

  /// 클라우드 에이전트 자체의 생존 상태 (agent 토픽 · LWT).
  bool? agentOnline;
  String agentVer = '';

  final Map<String, ExternalDevice> devices = {};
  final Map<String, Completer<CmdResult>> _pending = {};
  final _rand = Random();

  /// 서버 카드가 placements 토픽(retained)으로 중계한 로케이터 배치
  /// (적용본 positioning_config의 좌표·자세). 내부망에 접속한 적 없는
  /// PC에서도 위치 확인 뷰가 로케이터를 그릴 수 있게 한다.
  final List<PlacedLocator> placements = [];
  String _placementsRaw = '';

  /// 연결/해제/오류 등 mqtt 상태 변화를 UI에 전파하기 위한 직전 상태.
  MqttStatus _lastStatus = MqttStatus.disconnected;

  ExternalState() {
    mqtt.addListener(_onMqtt);
  }

  bool get isConnected => mqtt.isConnected;

  /// 세션 복원용 프리필 (연결하지 않음).
  void restore(String host, int port, String site) {
    if (host.trim().isNotEmpty) brokerHost = host.trim();
    if (port > 0) brokerPort = port;
    siteId = site.trim();
    notifyListeners();
  }

  Future<void> connect() async {
    devices.clear();
    placements.clear();
    _placementsRaw = '';
    agentOnline = null;
    mqtt.clear();
    await mqtt.connect(
      brokerHost,
      brokerPort,
      filter: 'locationx/$siteId/#',
      prefix: 'locationx/$siteId/',
    );
    notifyListeners();
  }

  Future<void> disconnect() async {
    await mqtt.disconnect();
    notifyListeners();
  }

  void _onMqtt() {
    var changed = false;

    // 연결됨/해제/오류 상태 변화도 이 State를 watch하는 UI에 전파한다
    // (topics 변화가 없으면 아래 루프는 changed를 세우지 않으므로 별도 감지).
    if (mqtt.status != _lastStatus) {
      _lastStatus = mqtt.status;
      changed = true;
    }

    for (final entry in mqtt.topics.entries) {
      final topic = entry.key;
      if (topic == 'agent') {
        final dynamic j;
        try {
          j = jsonDecode(entry.value.lastPayload);
        } catch (_) {
          continue;
        }
        if (j is Map) {
          final online = j['online'] == true;
          final ver = j['ver']?.toString() ?? agentVer;
          if (online != agentOnline || ver != agentVer) {
            agentOnline = online;
            agentVer = ver;
            changed = true;
          }
        }
      } else if (topic.startsWith('status/')) {
        final deviceId = topic.substring('status/'.length);
        final prev = devices[deviceId];
        // 같은 payload 재수신(주기 발행)이라도 ts가 다르면 갱신된 것
        final dev = ExternalDevice.fromPayload(deviceId, entry.value.lastPayload);
        if (dev != null && (prev == null || prev.ts != dev.ts ||
            prev.online != dev.online)) {
          devices[deviceId] = dev;
          changed = true;
        }
      } else if (topic == 'placements') {
        final raw = entry.value.lastPayload;
        if (raw != _placementsRaw) {
          _placementsRaw = raw;
          _parsePlacements(raw);
          changed = true;
        }
      } else if (topic.startsWith('cmdres/') && _pending.containsKey(topic)) {
        final completer = _pending.remove(topic)!;
        final payload = entry.value.lastPayload;
        final dynamic j;
        try {
          j = jsonDecode(payload);
        } catch (_) {
          completer.complete(CmdResult(false, '응답 파싱 실패: $payload'));
          continue;
        }
        final ok = j is Map && j['ok'] == true;
        final err = j is Map ? (j['error'] ?? j['detail'] ?? '') : '';
        completer.complete(
            CmdResult(ok, ok ? '완료' : '실패: $err'));
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  /// placements 페이로드 → [PlacedLocator] 목록.
  /// {"schema":1, "locators":[{"id","coordinate":{x,y,z},"orientation":{x,y,z}}]}
  void _parsePlacements(String payload) {
    placements.clear();
    final dynamic j;
    try {
      j = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (j is! Map) return;
    final locs = j['locators'];
    if (locs is! List) return;
    for (final loc in locs) {
      if (loc is! Map) continue;
      final id = loc['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      placements.add(PlacedLocator(
        locatorId: id,
        coordinate: Vec3.fromJson((loc['coordinate'] as Map?)?.cast()),
        orientation: Vec3.fromJson((loc['orientation'] as Map?)?.cast()),
      ));
    }
  }

  /// 정렬된 장치 목록: 서버 카드 먼저, 이후 이름순.
  List<ExternalDevice> get deviceList {
    final list = devices.values.toList()
      ..sort((a, b) {
        if (a.isServer != b.isServer) return a.isServer ? -1 : 1;
        return a.deviceId.compareTo(b.deviceId);
      });
    return list;
  }

  /// 명령 발행 → `cmdres/<deviceId>/<reqId>` 응답 대기 (12초 타임아웃).
  /// REBOOT는 카드가 응답 후 재부팅하므로 응답은 정상 수신된다.
  Future<CmdResult> sendCommand(String deviceId, String type,
      {String? service}) async {
    if (!isConnected) return CmdResult(false, '외부 브로커에 연결되어 있지 않습니다');
    final reqId = _rand.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final resTopic = 'cmdres/$deviceId/$reqId';
    final completer = Completer<CmdResult>();
    _pending[resTopic] = completer;

    mqtt.publish(
      'cmd/$deviceId',
      jsonEncode({
        'type': type,
        if (service != null) 'service': service,
        'reqId': reqId,
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }),
      qos: MqttQos.atLeastOnce,
    );

    try {
      return await completer.future.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      _pending.remove(resTopic);
      return CmdResult(false, '응답 시간 초과 (에이전트 오프라인?)');
    }
  }

  @override
  void dispose() {
    mqtt.removeListener(_onMqtt);
    mqtt.dispose();
    super.dispose();
  }
}
