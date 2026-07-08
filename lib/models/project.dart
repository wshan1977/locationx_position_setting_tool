import 'dart:ui';

import 'placement.dart';
import 'positioning_config.dart';

/// 로컬 프로젝트 파일(.lxpos.json) 스키마.
/// 도면 이미지는 경로만 저장한다 (열 때 없으면 재선택).
class ProjectFile {
  static const int currentVersion = 1;
  static const String extension = 'lxpos.json';

  int version;
  String serverIp;
  String? floorPlanImagePath;
  double metersPerPixel;
  Offset originPx;
  Offset? calibP1;
  Offset? calibP2;
  double? calibDistanceM;
  List<PlacedLocator> placements;

  /// 전역 positioning 설정 (locators 제외 — 배치가 소스).
  PositioningConfig globals;

  ProjectFile({
    this.version = currentVersion,
    this.serverIp = '',
    this.floorPlanImagePath,
    this.metersPerPixel = 0.05,
    this.originPx = Offset.zero,
    this.calibP1,
    this.calibP2,
    this.calibDistanceM,
    List<PlacedLocator>? placements,
    PositioningConfig? globals,
  })  : placements = placements ?? [],
        globals = globals ?? PositioningConfig();

  static Offset? _offsetFromJson(dynamic json) {
    if (json is! Map) return null;
    return Offset(
      (json['x'] as num?)?.toDouble() ?? 0,
      (json['y'] as num?)?.toDouble() ?? 0,
    );
  }

  static Map<String, double> _offsetToJson(Offset o) => {'x': o.dx, 'y': o.dy};

  factory ProjectFile.fromJson(Map<String, dynamic> json) => ProjectFile(
        version: (json['version'] as num?)?.toInt() ?? currentVersion,
        serverIp: json['serverIp']?.toString() ?? '',
        floorPlanImagePath: json['floorPlanImagePath']?.toString(),
        metersPerPixel: (json['metersPerPixel'] as num?)?.toDouble() ?? 0.05,
        originPx: _offsetFromJson(json['originPx']) ?? Offset.zero,
        calibP1: _offsetFromJson(json['calibP1']),
        calibP2: _offsetFromJson(json['calibP2']),
        calibDistanceM: (json['calibDistanceM'] as num?)?.toDouble(),
        placements: [
          if (json['placements'] is List)
            for (final p in json['placements'] as List)
              if (p is Map) PlacedLocator.fromJson(Map<String, dynamic>.from(p)),
        ],
        globals: json['globals'] is Map
            ? PositioningConfig.fromJson(
                Map<String, dynamic>.from(json['globals'] as Map))
            : null,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'serverIp': serverIp,
        'floorPlanImagePath': floorPlanImagePath,
        'metersPerPixel': metersPerPixel,
        'originPx': _offsetToJson(originPx),
        'calibP1': calibP1 == null ? null : _offsetToJson(calibP1!),
        'calibP2': calibP2 == null ? null : _offsetToJson(calibP2!),
        'calibDistanceM': calibDistanceM,
        'placements': [for (final p in placements) p.toJson()],
        'globals': globals.toJson(),
      };
}
