import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/discovered_device.dart';

/// UDP 40010 브로드캐스트로 LAN의 AoA 카드를 검색한다.
class DiscoveryService {
  static const int discoverPort = 40010;

  Future<List<DiscoveredDevice>> scan({
    Duration window = const Duration(seconds: 3),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;

    final found = <String, DiscoveredDevice>{};
    final done = Completer<void>();

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? dg;
      while ((dg = socket.receive()) != null) {
        try {
          final json = jsonDecode(utf8.decode(dg!.data, allowMalformed: true));
          if (json is! Map<String, dynamic>) continue;
          final dev = DiscoveredDevice.fromJson(json);
          if (dev != null) found.putIfAbsent(dev.dedupeKey, () => dev);
        } catch (_) {
          // 무관한 UDP 패킷은 무시
        }
      }
    });

    final targets = await _broadcastTargets();
    final payload = utf8.encode(jsonEncode({'type': 'DISCOVER'}));

    // UDP 유실 대비 3회 재전송
    for (final delayMs in [0, 500, 1000]) {
      Timer(Duration(milliseconds: delayMs), () {
        if (done.isCompleted) return;
        for (final addr in targets) {
          try {
            socket.send(payload, addr, discoverPort);
          } catch (_) {}
        }
      });
    }

    Timer(window, () {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    socket.close();

    final devices = found.values.toList()
      ..sort((a, b) {
        // 서버 카드 먼저, 그다음 이름순
        if (a.isServer != b.isServer) return a.isServer ? -1 : 1;
        return a.device.compareTo(b.device);
      });
    return devices;
  }

  /// 255.255.255.255 + 인터페이스별 directed broadcast.
  /// Dart는 netmask를 노출하지 않으므로 /24로 가정한다 (중복 전송은 무해).
  Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <String>{'255.255.255.255'};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4 && parts[0] != '127') {
            targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
          }
        }
      }
    } catch (_) {}
    // 로컬 mock 테스트용: 루프백에도 전송
    targets.add('127.0.0.1');
    return [for (final t in targets) InternetAddress(t)];
  }
}
