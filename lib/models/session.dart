import 'project.dart';

/// 앱 종료 전 마지막 상태 스냅샷 (자동 저장/복원용).
/// 프로젝트 파일과 달리 사용자가 명시적으로 저장하지 않아도 항상 기록된다.
class SessionData {
  static const int currentVersion = 1;

  final int version;
  final ProjectFile project;
  final String? projectPath;
  final bool dirty;
  final String mqttHost;
  final int mqttPort;
  final String mqttFilter;

  /// 종료 시점에 MQTT가 연결돼 있었는지 (재시작 시 자동 연결 여부).
  final bool mqttConnected;

  SessionData({
    this.version = currentVersion,
    required this.project,
    this.projectPath,
    this.dirty = false,
    this.mqttHost = '',
    this.mqttPort = 1883,
    this.mqttFilter = '#',
    this.mqttConnected = false,
  });

  factory SessionData.fromJson(Map<String, dynamic> json) => SessionData(
        version: (json['version'] as num?)?.toInt() ?? currentVersion,
        project: json['project'] is Map
            ? ProjectFile.fromJson(
                Map<String, dynamic>.from(json['project'] as Map))
            : ProjectFile(),
        projectPath: json['projectPath']?.toString(),
        dirty: json['dirty'] == true,
        mqttHost: json['mqttHost']?.toString() ?? '',
        mqttPort: (json['mqttPort'] as num?)?.toInt() ?? 1883,
        mqttFilter: json['mqttFilter']?.toString() ?? '#',
        mqttConnected: json['mqttConnected'] == true,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'project': project.toJson(),
        'projectPath': projectPath,
        'dirty': dirty,
        'mqttHost': mqttHost,
        'mqttPort': mqttPort,
        'mqttFilter': mqttFilter,
        'mqttConnected': mqttConnected,
      };
}
