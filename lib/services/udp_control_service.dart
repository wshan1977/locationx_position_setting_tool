import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 로케이터 카드 discover agent(UDP 40010)의 제어 프로토콜 클라이언트.
///
/// - MQTT 브로커 설정: {"type":"MQTT_SET","broker_host":"...","broker_port":1883}
/// - 재부팅:          {"type":"REBOOT","delay_sec":2,"reason":"ui"}
/// - 서비스 재시작:    {"type":"SERVICE_RESTART","service":"aoa-antenna.service"}
///   (카드 쪽 허용 목록은 aoa-antenna.service 뿐)
///
/// LED 식별은 별도 에이전트(UDP 40002)로 보낸다 — 응답 없음(fire-and-forget).
class UdpControlService {
  static const int controlPort = 40010;
  static const int ledPort = 40002;
  static const String appName = 'LocationX-PositionTool';

  final Duration timeout;

  const UdpControlService({this.timeout = const Duration(seconds: 3)});

  Future<Map<String, dynamic>> _sendAndWait({
    required String targetIp,
    required Map<String, dynamic> req,
    required String expectType,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final completer = Completer<Map<String, dynamic>>();

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      // 타겟에서 온 응답만 처리 (브로드캐스트 혼선 방지)
      if (dg.address.address != targetIp) return;
      try {
        final decoded = jsonDecode(utf8.decode(dg.data));
        if (decoded is! Map) return;
        final msg = decoded.cast<String, dynamic>();
        if (msg['type'] != expectType) return;
        if (!completer.isCompleted) completer.complete(msg);
      } catch (_) {
        // 무관한 패킷 무시
      }
    });

    try {
      final payload = utf8.encode(jsonEncode(req));
      // UDP 유실 대비 재전송
      socket.send(payload, InternetAddress(targetIp), controlPort);
      Timer(const Duration(milliseconds: 700), () {
        if (!completer.isCompleted) {
          try {
            socket.send(payload, InternetAddress(targetIp), controlPort);
          } catch (_) {}
        }
      });

      return await completer.future.timeout(
        timeout,
        onTimeout: () => {'type': expectType, 'ok': false, 'error': 'timeout'},
      );
    } finally {
      socket.close();
    }
  }

  Future<Map<String, dynamic>> setMqtt({
    required String targetIp,
    required String brokerHost,
    required int brokerPort,
  }) {
    return _sendAndWait(
      targetIp: targetIp,
      req: {
        'type': 'MQTT_SET',
        'app': appName,
        'broker_host': brokerHost,
        'broker_port': brokerPort,
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      expectType: 'MQTT_SET_RESPONSE',
    );
  }

  Future<Map<String, dynamic>> reboot({
    required String targetIp,
    int delaySec = 2,
  }) {
    return _sendAndWait(
      targetIp: targetIp,
      req: {
        'type': 'REBOOT',
        'app': appName,
        'delay_sec': delaySec,
        'reason': 'ui',
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      expectType: 'REBOOT_RESPONSE',
    );
  }

  Future<Map<String, dynamic>> restartService({
    required String targetIp,
    String serviceName = 'aoa-antenna.service',
  }) {
    return _sendAndWait(
      targetIp: targetIp,
      req: {
        'type': 'SERVICE_RESTART',
        'app': appName,
        'service': serviceName,
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      expectType: 'SERVICE_RESTART_RESPONSE',
    );
  }

  /// LED 점멸로 카드 식별 (응답 없음).
  Future<void> ledBlink({
    required String targetIp,
    String color = 'magenta',
    double hz = 3.0,
    int durationSec = 8,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.send(
        utf8.encode(jsonEncode({
          'type': 'LED_BLINK',
          'color': color,
          'hz': hz,
          'durationSec': durationSec,
        })),
        InternetAddress(targetIp),
        ledPort,
      );
    } finally {
      socket.close();
    }
  }
}
