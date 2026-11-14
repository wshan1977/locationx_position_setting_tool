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

  /// 외부망 테스트 탭 연결 정보 (프리필용 · 자동 연결은 하지 않음).
  final String extHost;
  final int extPort;
  final String extSiteId;

  /// 등록된 장소·층 ([SiteBook] JSON). null = 장소 기능 이전 세션.
  final Map<String, dynamic>? sites;

  SessionData({
    this.version = currentVersion,
    required this.project,
    this.projectPath,
    this.dirty = false,
    this.mqttHost = '',
    this.mqttPort = 1883,
    this.mqttFilter = 'controlbit/#',
    this.mqttConnected = false,
    this.extHost = '',
    this.extPort = 1883,
    this.extSiteId = '',
    this.sites,
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
        mqttFilter: json['mqttFilter']?.toString() ?? 'controlbit/#',
        mqttConnected: json['mqttConnected'] == true,
        extHost: json['extHost']?.toString() ?? '',
        extPort: (json['extPort'] as num?)?.toInt() ?? 1883,
        extSiteId: json['extSiteId']?.toString() ?? '',
        sites: json['sites'] is Map
            ? Map<String, dynamic>.from(json['sites'] as Map)
            : null,
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
        'extHost': extHost,
        'extPort': extPort,
        'extSiteId': extSiteId,
        'sites': sites,
      };
}
