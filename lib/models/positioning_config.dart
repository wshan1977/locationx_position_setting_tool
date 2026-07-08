import 'vec3.dart';

/// 서버 DEFAULT_POSITIONING_JSON의 locator config와 동일한 기본값.
Map<String, dynamic> defaultLocatorAoaConfig() => {
      'version': 1,
      // AoA 시스템이므로 AOX 모드여야 한다. AOD 모드는 bt_host_positioning이
      // "Failed to set AoX mode" 에러로 거부한다 (실측).
      'aoxMode': 'SL_RTL_AOX_MODE_REAL_TIME_BASIC',
      'antennaMode': 'SL_RTL_AOX_ARRAY_TYPE_4x4_URA',
      'antennaArray': null,
      'angleFiltering': true,
      'angleFilteringWeight': 0.6,
      'angleCorrectionTimeout': 5,
      'angleCorrectionDelay': 1,
      'cteMode': 'SILABS',
      'periodSamples': 64,
      'cteSamplingInterval': 1,
      'cteLength': 160,
      'slotDuration': 1,
      'reportMode': 'ANGLE',
      'allowList': <dynamic>[],
      'azimuthMask': <dynamic>[],
      'elevationMask': <dynamic>[],
    };

/// positioning_config.json 한 개의 locator 항목.
/// config는 미지 필드 보존을 위해 Map 그대로 유지한다.
class LocatorEntry {
  String id;
  Map<String, dynamic> config;
  Vec3 coordinate;
  Vec3 orientation;
  final Map<String, dynamic> extras;

  LocatorEntry({
    required this.id,
    Map<String, dynamic>? config,
    Vec3? coordinate,
    Vec3? orientation,
    Map<String, dynamic>? extras,
  })  : config = config ?? defaultLocatorAoaConfig(),
        coordinate = coordinate ?? Vec3(z: 3.0),
        orientation = orientation ?? Vec3(x: 0, y: 180, z: 90),
        extras = extras ?? {};

  factory LocatorEntry.fromJson(Map<String, dynamic> json) {
    const known = {'id', 'config', 'coordinate', 'orientation'};
    return LocatorEntry(
      id: json['id']?.toString() ?? '',
      config: json['config'] is Map
          ? Map<String, dynamic>.from(json['config'] as Map)
          : defaultLocatorAoaConfig(),
      coordinate: Vec3.fromJson((json['coordinate'] as Map?)?.cast()),
      orientation: Vec3.fromJson((json['orientation'] as Map?)?.cast()),
      extras: {
        for (final e in json.entries)
          if (!known.contains(e.key)) e.key: e.value,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'config': config,
        'coordinate': coordinate.toJson(),
        'orientation': orientation.toJson(),
        ...extras,
      };
}

/// positioning_config.json 전체. 알려진 전역 필드는 타입으로 노출하고
/// 나머지는 extras에 보존해 round-trip 시 유실을 막는다.
class PositioningConfig {
  int version;
  String id;
  String estimationModeLocation;
  String validationModeLocation;
  double estimationIntervalSec;
  bool locationFiltering;
  double locationFilteringWeight;
  int numberOfSequenceIds;
  int maximumSequenceIdDiffs;
  List<LocatorEntry> locators;
  final Map<String, dynamic> extras;

  PositioningConfig({
    this.version = 1,
    this.id = 'positioning-test_room',
    this.estimationModeLocation =
        'SL_RTL_LOC_ESTIMATION_MODE_THREE_DIM_HIGH_ACCURACY',
    this.validationModeLocation = 'SL_RTL_LOC_MEASUREMENT_VALIDATION_FULL',
    this.estimationIntervalSec = 0.02,
    this.locationFiltering = true,
    this.locationFilteringWeight = 0.1,
    this.numberOfSequenceIds = 6,
    this.maximumSequenceIdDiffs = 20,
    List<LocatorEntry>? locators,
    Map<String, dynamic>? extras,
  })  : locators = locators ?? [],
        extras = extras ?? {};

  static const _known = {
    'version',
    'id',
    'estimationModeLocation',
    'validationModeLocation',
    'estimationIntervalSec',
    'locationFiltering',
    'locationFilteringWeight',
    'numberOfSequenceIds',
    'maximumSequenceIdDiffs',
    'locators',
  };

  factory PositioningConfig.fromJson(Map<String, dynamic> json) {
    final def = PositioningConfig();
    return PositioningConfig(
      version: (json['version'] as num?)?.toInt() ?? def.version,
      id: json['id']?.toString() ?? def.id,
      estimationModeLocation: json['estimationModeLocation']?.toString() ??
          def.estimationModeLocation,
      validationModeLocation: json['validationModeLocation']?.toString() ??
          def.validationModeLocation,
      estimationIntervalSec:
          (json['estimationIntervalSec'] as num?)?.toDouble() ??
              def.estimationIntervalSec,
      locationFiltering:
          json['locationFiltering'] as bool? ?? def.locationFiltering,
      locationFilteringWeight:
          (json['locationFilteringWeight'] as num?)?.toDouble() ??
              def.locationFilteringWeight,
      numberOfSequenceIds: (json['numberOfSequenceIds'] as num?)?.toInt() ??
          def.numberOfSequenceIds,
      maximumSequenceIdDiffs:
          (json['maximumSequenceIdDiffs'] as num?)?.toInt() ??
              def.maximumSequenceIdDiffs,
      locators: [
        if (json['locators'] is List)
          for (final l in json['locators'] as List)
            if (l is Map) LocatorEntry.fromJson(Map<String, dynamic>.from(l)),
      ],
      extras: {
        for (final e in json.entries)
          if (!_known.contains(e.key)) e.key: e.value,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'id': id,
        'estimationModeLocation': estimationModeLocation,
        'validationModeLocation': validationModeLocation,
        'estimationIntervalSec': estimationIntervalSec,
        'locationFiltering': locationFiltering,
        'locationFilteringWeight': locationFilteringWeight,
        'numberOfSequenceIds': numberOfSequenceIds,
        'maximumSequenceIdDiffs': maximumSequenceIdDiffs,
        'locators': [for (final l in locators) l.toJson()],
        ...extras,
      };
}
