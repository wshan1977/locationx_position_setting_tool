import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/positioning_config.dart';

class ConfigApiException implements Exception {
  final String message;
  ConfigApiException(this.message);
  @override
  String toString() => message;
}

class ApplyResult {
  final bool ok;
  final String backupStamp;
  final bool restarted;
  final String restartError;

  ApplyResult({
    required this.ok,
    required this.backupStamp,
    required this.restarted,
    required this.restartError,
  });
}

/// 서버 카드 config 서버(포트 8080)의 /api/* 클라이언트.
class ConfigApiClient {
  final String host;
  final int port;
  final Duration timeout;

  ConfigApiClient(this.host,
      {this.port = 8080, this.timeout = const Duration(seconds: 8)});

  Uri _uri(String path) => Uri.parse('http://$host:$port$path');

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await http.get(_uri(path)).timeout(timeout);
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final res = await http
        .post(_uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(timeout);
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ConfigApiException(
          'HTTP ${res.statusCode}: 서버 응답이 JSON이 아닙니다 (config 서버가 구버전일 수 있음)');
    }
    if (json['ok'] != true) {
      throw ConfigApiException(json['error']?.toString() ?? '알 수 없는 서버 오류');
    }
    return json;
  }

  /// GET /api/status — 연결 및 서버 버전 확인.
  Future<Map<String, dynamic>> status() => _get('/api/status');

  /// GET /api/positioning — 스테이징 config 조회.
  Future<PositioningConfig> fetchPositioning() async {
    final json = await _get('/api/positioning');
    final pos = json['positioning'];
    if (pos is! Map) {
      throw ConfigApiException('positioning 필드가 없습니다');
    }
    return PositioningConfig.fromJson(Map<String, dynamic>.from(pos));
  }

  /// POST /api/positioning — 스테이징 저장.
  Future<int> pushPositioning(PositioningConfig config) async {
    final json = await _post('/api/positioning', config.toJson());
    return (json['locator_count'] as num?)?.toInt() ?? 0;
  }

  /// POST /api/apply — 백업 후 서비스 파일 교체 (+선택적 재시작).
  Future<ApplyResult> apply({bool restart = false}) async {
    final json = await _post('/api/apply', {'restart': restart});
    final restartInfo = json['restart'];
    return ApplyResult(
      ok: json['ok'] == true,
      backupStamp: json['backup_stamp']?.toString() ?? '',
      restarted: json['restarted'] == true,
      restartError: restartInfo is Map
          ? (restartInfo['err']?.toString() ?? '').trim()
          : '',
    );
  }
}
