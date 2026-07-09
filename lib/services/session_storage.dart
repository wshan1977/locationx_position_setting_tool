import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/session.dart';
import '../state/app_state.dart';
import '../state/mqtt_state.dart';

/// 세션(마지막 작업 상태) 자동 저장/복원.
/// 프로젝트 파일과 별개로, 앱 데이터 폴더에 항상 최신 상태를 기록한다.
class SessionStorage {
  static File? _file() {
    final env = Platform.environment;
    String? base;
    if (Platform.isWindows) {
      base = env['APPDATA'];
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = env['HOME'];
      if (home != null) base = p.join(home, '.config');
    }
    if (base == null) return null;
    return File(p.join(base, 'LocationXPositionTool', 'session.json'));
  }

  static Future<SessionData?> load() async {
    try {
      final f = _file();
      if (f == null || !f.existsSync()) return null;
      final json = jsonDecode(await f.readAsString());
      if (json is! Map) return null;
      return SessionData.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null; // 세션 파일이 깨졌으면 무시하고 새로 시작
    }
  }

  static Future<void> save(SessionData session) async {
    try {
      final f = _file();
      if (f == null) return;
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(session.toJson()));
    } catch (_) {
      // 저장 실패는 치명적이지 않으므로 무시
    }
  }
}

/// AppState/MqttState 변경을 감지해 세션을 주기적으로 저장한다.
/// MQTT 수신 중에는 notify가 계속 발생하므로 디바운스 대신 스로틀을 쓴다
/// (첫 변경 후 일정 시간 뒤 그 시점의 최신 상태를 저장).
/// UI에 자동 저장 시각을 표시할 수 있도록 저장할 때마다 notify한다.
class SessionAutoSaver extends ChangeNotifier {
  SessionAutoSaver(this._app, this._mqtt);

  final AppState _app;
  final MqttState _mqtt;
  Timer? _pending;
  String _lastSaved = '';

  /// 마지막으로 세션이 기록된 시각 (아직 없으면 null).
  DateTime? lastSavedAt;

  void start() {
    _app.addListener(_schedule);
    _mqtt.addListener(_schedule);
  }

  void _schedule() {
    _pending ??= Timer(const Duration(seconds: 1), () {
      _pending = null;
      _save();
    });
  }

  Future<void> _save() async {
    final session = SessionData(
      project: _app.toProject(),
      projectPath: _app.projectPath,
      dirty: _app.dirty,
      mqttHost: _mqtt.host,
      mqttPort: _mqtt.port,
      mqttFilter: _mqtt.subscribeFilter,
      mqttConnected: _mqtt.isConnected,
    );
    final encoded = jsonEncode(session.toJson());
    if (encoded == _lastSaved) return;
    _lastSaved = encoded;
    await SessionStorage.save(session);
    lastSavedAt = DateTime.now();
    notifyListeners();
  }
}
