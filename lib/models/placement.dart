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

  /// 반사면 마스크로 고른 도면 방향 ('+x' '-x' '+y' '-y'). 카드의 azimuthMask로
  /// 변환해 적용한다 (services/mask_faces.dart · 위치 설정 › 로케이터 패널).
  Set<String> maskFaces;

  /// 그림만 보드 면 안에서 180° 돌려 그린다 (데이터·위치 계산은 그대로).
  /// 케이스 안 보드 조립 방향이 로케이터마다 달라, 신호가 맞는 orientation으로
  /// 그린 케이스가 실물과 반대로 보일 때 켠다 (2026-11-12 7924 실측).
  bool imageFlip;

  PlacedLocator({
    required this.locatorId,
    this.deviceName = '',
    this.ip = '',
    Vec3? coordinate,
    Vec3? orientation,
    Map<String, dynamic>? config,
    Set<String>? maskFaces,
    this.imageFlip = false,
  })  : maskFaces = maskFaces ?? {},
        coordinate = coordinate ?? Vec3(z: 3.0),
        orientation = orientation ?? Vec3(x: 0, y: 180, z: 90),
        config = config ?? defaultLocatorAoaConfig();

  String get shortId => locatorId.length >= 4
      ? locatorId.substring(locatorId.length - 4)
      : locatorId;

  /// 서버 positioning_config의 locator 항목. maskFaces는 positioning이 무시하는
  /// 추가 키로 함께 저장해 다른 PC·[서버에서 읽기]에서도 선택이 보이게 한다.
  LocatorEntry toLocatorEntry() => LocatorEntry(
        id: locatorId,
        config: config,
        coordinate: coordinate.copy(),
        orientation: orientation.copy(),
        extras: {'maskFaces': (maskFaces.toList()..sort()), 'imageFlip': imageFlip},
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
        maskFaces: {
          if (json['maskFaces'] is List)
            for (final f in json['maskFaces'] as List) f.toString(),
        },
        imageFlip: json['imageFlip'] == true,
      );

  Map<String, dynamic> toJson() => {
        'locatorId': locatorId,
        'deviceName': deviceName,
        'ip': ip,
        'coordinate': coordinate.toJson(),
        'orientation': orientation.toJson(),
        'config': config,
        if (maskFaces.isNotEmpty) 'maskFaces': (maskFaces.toList()..sort()),
        if (imageFlip) 'imageFlip': true,
      };
}
