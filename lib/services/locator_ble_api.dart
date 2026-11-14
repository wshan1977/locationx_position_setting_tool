import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 로케이터 카드의 태그 에이전트(:8081 · 로케이터 v1.0.31+) — 카드 내장
/// 블루투스(Pi Zero 2 W)로 태그를 검색·접속·OTA 한다. PC 블루투스가 없거나
/// 태그가 PC에서 멀 때 쓴다.
class LocatorBleApi {
  final String ip;
  const LocatorBleApi(this.ip);

  static const port = 8081;

  Uri _uri(String p) => Uri.parse('http://$ip:$port$p');

  static const _oldCard = '카드의 태그 에이전트(:8081)에 연결할 수 없습니다 (로케이터 v1.0.31 이상 배포 필요)';

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode == 404) throw _oldCard;
    final d = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (d['ok'] != true) throw d['error']?.toString() ?? 'HTTP ${res.statusCode}';
    return d;
  }

  Future<Map<String, dynamic>> _post(String p, Map<String, dynamic> body, Duration t) async {
    try {
      final res = await http
          .post(_uri(p), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(t);
      return _decode(res);
    } on http.ClientException {
      throw _oldCard;
    }
  }

  /// 어댑터·작업·네트워크 상태.
  Future<Map<String, dynamic>> status() async {
    try {
      return _decode(await http.get(_uri('/api/ble/status')).timeout(const Duration(seconds: 4)));
    } on http.ClientException {
      throw _oldCard;
    }
  }

  /// 태그·AppLoader 광고 목록 ({mac, name, rssi, appLoader}).
  Future<List<Map<String, dynamic>>> scan({int secs = 8, bool all = false}) async {
    final d = await _post('/api/ble/scan', {'secs': secs, 'all': all}, Duration(seconds: secs + 15));
    return [for (final t in d['tags'] as List) (t as Map).cast<String, dynamic>()];
  }

  Future<Map<String, dynamic>> info(String mac) =>
      _post('/api/ble/info', {'mac': mac}, const Duration(seconds: 45));

  /// 송신 주기 쓰기 → 실제 적용된 ms.
  Future<double> interval(String mac, int ms) async {
    final d = await _post('/api/ble/interval', {'mac': mac, 'ms': ms}, const Duration(seconds: 45));
    return (d['ms'] as num).toDouble();
  }

  /// 백그라운드 OTA 시작 (진행은 [otaStatus]로 폴링).
  Future<void> startOta(String mac, Uint8List gbl) async {
    try {
      _decode(await http
          .post(_uri('/api/ble/ota?mac=${Uri.encodeQueryComponent(mac)}'),
              headers: {'Content-Type': 'application/octet-stream'}, body: gbl)
          .timeout(const Duration(seconds: 20)));
    } on http.ClientException {
      throw _oldCard;
    }
  }

  /// {state: idle|running|done|failed, step, fraction, error, fw, trace}
  Future<Map<String, dynamic>> otaStatus() async =>
      _decode(await http.get(_uri('/api/ble/ota')).timeout(const Duration(seconds: 5)));
}
