import 'positioning_config.dart';
import 'vec3.dart';

/// 캔버스에 배치된 로케이터 하나.
/// coordinate.x/y는 캔버스 드래그로, z와 orientation은 왼쪽 패널에서 편집한다.
class PlacedLocator {
  final String locatorId;
  String deviceName;
  String ip;
  Vec3 coordinate;
  Vec3 orientation;
  Map<String, dynamic> config;

  PlacedLocator({
    required this.locatorId,
    this.deviceName = '',
    this.ip = '',
    Vec3? coordinate,
    Vec3? orientation,
    Map<String, dynamic>? config,
  })  : coordinate = coordinate ?? Vec3(z: 3.0),
        orientation = orientation ?? Vec3(x: 0, y: 180, z: 90),
        config = config ?? defaultLocatorAoaConfig();

  String get shortId => locatorId.length >= 4
      ? locatorId.substring(locatorId.length - 4)
      : locatorId;

  LocatorEntry toLocatorEntry() => LocatorEntry(
        id: locatorId,
        config: config,
        coordinate: coordinate.copy(),
        orientation: orientation.copy(),
      );

  factory PlacedLocator.fromJson(Map<String, dynamic> json) => PlacedLocator(
        locatorId: json['locatorId']?.toString() ?? '',
        deviceName: json['deviceName']?.toString() ?? '',
        ip: json['ip']?.toString() ?? '',
        coordinate: Vec3.fromJson((json['coordinate'] as Map?)?.cast()),
        orientation: Vec3.fromJson((json['orientation'] as Map?)?.cast()),
        config: json['config'] is Map
            ? Map<String, dynamic>.from(json['config'] as Map)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'locatorId': locatorId,
        'deviceName': deviceName,
        'ip': ip,
        'coordinate': coordinate.toJson(),
        'orientation': orientation.toJson(),
        'config': config,
      };
}
