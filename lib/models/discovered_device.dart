/// UDP 40010 DISCOVER_RESPONSE 파싱 결과.
///
/// 로케이터 카드(discover agent v1.0.3)는 `cap` 필드가 있고,
/// MQTT 서버 카드(v1.0.0)는 없다 — 이걸로 역할을 구분한다.
class DiscoveredDevice {
  final String device;
  final String ip;
  final String mac;
  final String model;
  final String ver;
  final String? mqttHost;
  final int? mqttPort;
  final bool hasCap;

  DiscoveredDevice({
    required this.device,
    required this.ip,
    required this.mac,
    required this.model,
    required this.ver,
    this.mqttHost,
    this.mqttPort,
    required this.hasCap,
  });

  static DiscoveredDevice? fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'DISCOVER_RESPONSE') return null;
    final mqtt = json['mqtt'];
    return DiscoveredDevice(
      device: json['device']?.toString() ?? '(unknown)',
      ip: json['ip']?.toString() ?? '',
      mac: json['mac']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      ver: json['ver']?.toString() ?? '',
      mqttHost: mqtt is Map ? mqtt['host']?.toString() : null,
      mqttPort: mqtt is Map ? (mqtt['port'] as num?)?.toInt() : null,
      hasCap: json['cap'] is Map,
    );
  }

  bool get isServer => !hasCap;

  bool get hasValidMac => mac.isNotEmpty && mac != 'MAC_ERR';

  /// positioning_config.json의 locator id 형식: `ble-pd-` + MAC(대문자, 구분자 제거).
  /// 카드의 ble_macaddress.txt에 이미 `ble-pd-...` 전체 ID가 들어 있는 경우가 있어
  /// (discover agent는 파일 내용을 그대로 mac 필드로 보냄) 접두사 중복을 방지한다.
  String get locatorId {
    var m = mac.trim();
    if (m.toLowerCase().startsWith('ble-pd-')) m = m.substring(7);
    return 'ble-pd-${normalizeMac(m)}';
  }

  /// 리스트/마커 라벨용 MAC 뒤 4자리.
  String get shortId {
    final n = normalizeMac(mac);
    return n.length >= 4 ? n.substring(n.length - 4) : n;
  }

  static String normalizeMac(String mac) =>
      mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();

  /// 중복 제거 키 (MAC이 없으면 IP로 폴백).
  String get dedupeKey => hasValidMac ? normalizeMac(mac) : 'ip:$ip';
}
