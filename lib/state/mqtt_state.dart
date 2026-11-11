import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

enum MqttStatus { disconnected, connecting, connected, error }

/// 수신 메시지 1건.
class MqttMessageRecord {
  final String topic;
  final String payload;
  final DateTime ts;
  final bool retained;

  MqttMessageRecord({
    required this.topic,
    required this.payload,
    required this.ts,
    required this.retained,
  });
}

/// 토픽별 누적 통계.
class TopicStat {
  int count = 0;
  DateTime? lastTs;
  String lastPayload = '';
  bool retained = false;

  /// 수신율 계산용 최근 타임스탬프 (5초 창)
  final Queue<DateTime> _recent = Queue();

  void add(MqttMessageRecord m) {
    count++;
    lastTs = m.ts;
    lastPayload = m.payload;
    retained = m.retained;
    _recent.addLast(m.ts);
    _prune(m.ts);
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(const Duration(seconds: 5));
    while (_recent.isNotEmpty && _recent.first.isBefore(cutoff)) {
      _recent.removeFirst();
    }
  }

  /// 최근 5초 기준 msg/s.
  double rateHz(DateTime now) {
    _prune(now);
    return _recent.length / 5.0;
  }
}

/// MQTT 브로커 연결 + 수신 데이터 집계.
/// 데이터 수신 확인 탭과 MQTT 뷰어 탭이 하나의 연결을 공유한다.
class MqttState extends ChangeNotifier {
  static const int maxLogEntries = 500;

  MqttServerClient? _client;
  StreamSubscription? _updatesSub;
  Timer? _uiTick;

  MqttStatus status = MqttStatus.disconnected;
  String lastError = '';
  String host = '';
  int port = 1883;

  /// 수신 시 토픽 앞에서 떼어내고, 발행 시 앞에 붙이는 프리픽스.
  /// 외부망 중계 토픽(`locationx/<siteId>/silabs/aoa/...`)을 프리픽스만 벗겨
  /// 내부망과 같은 토픽 모양으로 만들면 positionByTag() 등 하류 소비자가
  /// 무수정으로 동작한다. clientId도 구분해 내부 연결과 공존 가능.
  String topicPrefix = '';

  /// 기본 구독 필터. 루트 와일드카드 `#`는 공개 브로커(broker.hivemq.com 등)가
  /// 거부(SUBACK 0x80)하므로 이 시스템의 토픽 루트인 silabs/#를 쓴다 (실측).
  String subscribeFilter = defaultFilter;
  static const defaultFilter = 'silabs/#';

  /// 구세션에 저장된 레거시 `#` 필터를 silabs/#로 이관.
  static String _normalizeFilter(String f) => f == '#' ? defaultFilter : f;

  bool paused = false;

  /// 최신 메시지가 앞에 오는 로그 (최대 [maxLogEntries]).
  final ListQueue<MqttMessageRecord> log = ListQueue();

  /// 토픽 → 통계.
  final Map<String, TopicStat> topics = {};

  final _records = StreamController<MqttMessageRecord>.broadcast();

  /// 수신 메시지 실시간 스트림 (일시정지와 무관 · 로케이터 보정 수집용).
  Stream<MqttMessageRecord> get records => _records.stream;

  bool _dirty = false;

  bool get isConnected => status == MqttStatus.connected;

  /// 세션 복원용: 연결하지 않고 접속 정보만 채운다 (연결 바 프리필).
  void restoreEndpoint(String newHost, int newPort, {String? filter}) {
    host = newHost.trim();
    port = newPort;
    if (filter != null && filter.trim().isNotEmpty) {
      subscribeFilter = _normalizeFilter(filter.trim());
    }
    notifyListeners();
  }

  Future<void> connect(String newHost, int newPort,
      {String? filter, String? prefix}) async {
    await disconnect();

    host = newHost.trim();
    port = newPort;
    if (prefix != null) topicPrefix = prefix;
    if (filter != null && filter.trim().isNotEmpty) {
      subscribeFilter = _normalizeFilter(filter.trim());
    }
    if (host.isEmpty) {
      lastError = '브로커 주소가 비어 있습니다';
      status = MqttStatus.error;
      notifyListeners();
      return;
    }

    status = MqttStatus.connecting;
    lastError = '';
    notifyListeners();

    final clientId = topicPrefix.isEmpty
        ? 'locationx-tool-${DateTime.now().millisecondsSinceEpoch % 100000}'
        : 'locationx-ext-${DateTime.now().millisecondsSinceEpoch % 100000}';
    final client = MqttServerClient.withPort(host, clientId, port);
    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.connectTimeoutPeriod = 5000;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();
    client.onDisconnected = _onDisconnected;

    try {
      await client.connect();
    } catch (e) {
      client.disconnect();
      status = MqttStatus.error;
      lastError = '연결 실패 ($host:$port): $e';
      notifyListeners();
      return;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      status = MqttStatus.error;
      lastError = '연결 실패 ($host:$port): ${client.connectionStatus?.returnCode}';
      notifyListeners();
      return;
    }

    _client = client;
    // 브로커가 구독을 거부하면(공개 브로커의 와일드카드 차단 등) 연결만 살아있고
    // 데이터가 전혀 안 들어와 원인을 알 수 없다 — 명시적으로 에러로 표시한다.
    client.onSubscribeFail = _onSubscribeFail;
    client.subscribe(subscribeFilter, MqttQos.atMostOnce);
    _updatesSub = client.updates?.listen(_onMessages);

    // 수신율 갱신 등 주기적 UI 리프레시 (수신이 있을 때만 notify)
    _uiTick = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (_dirty) {
        _dirty = false;
        notifyListeners();
      }
    });

    status = MqttStatus.connected;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _uiTick?.cancel();
    _uiTick = null;
    await _updatesSub?.cancel();
    _updatesSub = null;
    final c = _client;
    _client = null;
    if (c != null) {
      c.onDisconnected = null;
      c.disconnect();
    }
    if (status != MqttStatus.disconnected) {
      status = MqttStatus.disconnected;
      notifyListeners();
    }
  }

  void _onDisconnected() {
    _client = null;
    if (status == MqttStatus.connected) {
      status = MqttStatus.error;
      lastError = '브로커와의 연결이 끊어졌습니다';
      notifyListeners();
    }
  }

  void _onSubscribeFail(String topic) {
    // disconnect()는 비동기라 status를 나중에 덮어쓴다 — 여기서 동기 정리.
    _uiTick?.cancel();
    _uiTick = null;
    _updatesSub?.cancel();
    _updatesSub = null;
    final c = _client;
    _client = null;
    if (c != null) {
      c.onDisconnected = null;
      c.disconnect();
    }
    status = MqttStatus.error;
    lastError = "브로커가 '$topic' 구독을 거부했습니다";
    notifyListeners();
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> events) {
    final now = DateTime.now();
    for (final e in events) {
      final pub = e.payload;
      if (pub is! MqttPublishMessage) continue;
      String payload;
      try {
        payload =
            MqttPublishPayload.bytesToStringAsString(pub.payload.message);
      } catch (_) {
        payload = '(binary ${pub.payload.message.length} bytes)';
      }
      var topic = e.topic;
      if (topicPrefix.isNotEmpty && topic.startsWith(topicPrefix)) {
        topic = topic.substring(topicPrefix.length);
      }
      final rec = MqttMessageRecord(
        topic: topic,
        payload: payload,
        ts: now,
        retained: pub.header?.retain ?? false,
      );
      if (_records.hasListener) _records.add(rec);
      if (paused) continue;
      log.addFirst(rec);
      while (log.length > maxLogEntries) {
        log.removeLast();
      }
      topics.putIfAbsent(rec.topic, () => TopicStat()).add(rec);
    }
    _dirty = true;
  }

  void setPaused(bool value) {
    paused = value;
    notifyListeners();
  }

  void clear() {
    log.clear();
    topics.clear();
    notifyListeners();
  }

  void publish(String topic, String payload,
      {MqttQos qos = MqttQos.atMostOnce}) {
    final c = _client;
    if (c == null) return;
    final builder = MqttClientPayloadBuilder()..addString(payload);
    c.publishMessage(topicPrefix + topic, qos, builder.payload!);
  }

  // =========================================================
  // 데이터 수신 확인용 파생 데이터
  // =========================================================
  static const anglePrefix = 'silabs/aoa/angle/';
  static const positionPrefix = 'silabs/aoa/position/';

  /// 로케이터별 angle 수신 현황.
  /// key: locatorId, value: 해당 로케이터의 (태그별 토픽) 통계 목록.
  Map<String, List<MapEntry<String, TopicStat>>> angleByLocator() {
    final out = <String, List<MapEntry<String, TopicStat>>>{};
    for (final entry in topics.entries) {
      if (!entry.key.startsWith(anglePrefix)) continue;
      final rest = entry.key.substring(anglePrefix.length);
      final segs = rest.split('/');
      final locator = segs.isNotEmpty ? segs[0] : '(unknown)';
      final tag = segs.length > 1 ? segs.sublist(1).join('/') : '';
      out.putIfAbsent(locator, () => []).add(MapEntry(tag, entry.value));
    }
    for (final list in out.values) {
      list.sort((a, b) => a.key.compareTo(b.key));
    }
    return out;
  }

  /// 태그별 position 수신 현황. key: 토픽의 나머지 부분(태그 ID).
  Map<String, TopicStat> positionByTag() {
    final out = <String, TopicStat>{};
    for (final entry in topics.entries) {
      if (!entry.key.startsWith(positionPrefix)) continue;
      out[entry.key.substring(positionPrefix.length)] = entry.value;
    }
    return out;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
