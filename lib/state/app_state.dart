import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../canvas/world_transform.dart';
import '../models/discovered_device.dart';
import '../models/placement.dart';
import '../models/positioning_config.dart';
import '../models/project.dart';
import '../services/discovery_service.dart';
import '../services/project_storage.dart';

/// 캔버스 클릭 모드.
enum CanvasMode { normal, calibrateP1, calibrateP2, setOrigin }

class AppState extends ChangeNotifier {
  final DiscoveryService _discovery = DiscoveryService();
  final ProjectStorage _storage = ProjectStorage();

  // ---- 디스커버리 ----
  List<DiscoveredDevice> devices = [];
  bool scanning = false;

  // ---- 서버 연결 ----
  String serverIp = '';

  // ---- 도면/캔버스 ----
  ui.Image? floorImage;
  String? floorImagePath;
  WorldTransform transform = const WorldTransform();
  CanvasMode canvasMode = CanvasMode.normal;
  Offset? calibP1; // 이미지 px
  Offset? calibP2;
  double? calibDistanceM;

  // ---- 배치 ----
  final List<PlacedLocator> placements = [];
  String? selectedLocatorId;

  // ---- 전역 설정 ----
  PositioningConfig globals = PositioningConfig();

  // ---- 프로젝트 ----
  String? projectPath;
  bool dirty = false;

  DiscoveredDevice? get serverDevice =>
      devices.where((d) => d.isServer).firstOrNull;

  PlacedLocator? get selectedPlacement =>
      placements.where((p) => p.locatorId == selectedLocatorId).firstOrNull;

  bool isPlaced(DiscoveredDevice d) =>
      placements.any((p) => p.locatorId == d.locatorId);

  void _markDirty() {
    dirty = true;
    notifyListeners();
  }

  // =========================================================
  // 디스커버리
  // =========================================================
  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    notifyListeners();
    try {
      devices = await _discovery.scan();
      final server = serverDevice;
      if (server != null && serverIp.isEmpty) {
        serverIp = server.ip;
      }
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  void setServerIp(String ip) {
    serverIp = ip.trim();
    notifyListeners();
  }

  // =========================================================
  // 도면 / 변환
  // =========================================================
  Future<void> loadFloorImage(String path) async {
    final bytes = await File(path).readAsBytes();
    final image = await decodeImageFromList(bytes);
    floorImage?.dispose();
    floorImage = image;
    floorImagePath = path;
    // 기본 원점: 이미지 좌하단
    transform = transform.copyWith(
      originPx: Offset(0, image.height.toDouble()),
    );
    _markDirty();
  }

  void setTransform(WorldTransform t) {
    transform = t;
    notifyListeners();
  }

  /// 캔버스 크기에 이미지를 맞춘다.
  void fitImage(Size canvasSize) {
    final img = floorImage;
    if (img == null) return;
    final zoom = math.min(
        canvasSize.width / img.width, canvasSize.height / img.height);
    final z = zoom * 0.95;
    transform = transform.copyWith(
      zoom: z,
      panPx: Offset(
        (canvasSize.width - img.width * z) / 2,
        (canvasSize.height - img.height * z) / 2,
      ),
    );
    notifyListeners();
  }

  void setCanvasMode(CanvasMode mode) {
    canvasMode = mode;
    if (mode == CanvasMode.calibrateP1) {
      calibP1 = null;
      calibP2 = null;
    }
    notifyListeners();
  }

  /// 보정/원점 모드에서의 캔버스 클릭 처리 (이미지 px 좌표).
  /// 2점이 모두 찍히면 true를 반환해 UI가 거리 입력을 띄우게 한다.
  bool handleCalibrationClick(Offset imagePx) {
    switch (canvasMode) {
      case CanvasMode.calibrateP1:
        calibP1 = imagePx;
        canvasMode = CanvasMode.calibrateP2;
        notifyListeners();
        return false;
      case CanvasMode.calibrateP2:
        calibP2 = imagePx;
        canvasMode = CanvasMode.normal;
        notifyListeners();
        return true;
      case CanvasMode.setOrigin:
        transform = transform.copyWith(originPx: imagePx);
        canvasMode = CanvasMode.normal;
        _markDirty();
        return false;
      case CanvasMode.normal:
        return false;
    }
  }

  /// 2점 보정 확정: 실거리(m) 입력 후 호출.
  void applyCalibration(double distanceM) {
    final p1 = calibP1, p2 = calibP2;
    if (p1 == null || p2 == null || distanceM <= 0) return;
    final pxDist = (p2 - p1).distance;
    if (pxDist <= 0) return;
    calibDistanceM = distanceM;
    transform = transform.copyWith(metersPerPixel: distanceM / pxDist);
    _markDirty();
  }

  void setMetersPerPixel(double mpp) {
    if (mpp <= 0) return;
    transform = transform.copyWith(metersPerPixel: mpp);
    _markDirty();
  }

  // =========================================================
  // 배치
  // =========================================================
  void placeDevice(DiscoveredDevice device, Offset world) {
    if (!device.hasValidMac || device.isServer) return;
    if (isPlaced(device)) return;
    final p = PlacedLocator(
      locatorId: device.locatorId,
      deviceName: device.device,
      ip: device.ip,
    );
    p.coordinate.x = _round2(world.dx);
    p.coordinate.y = _round2(world.dy);
    placements.add(p);
    selectedLocatorId = p.locatorId;
    _markDirty();
  }

  void moveLocator(String locatorId, Offset world) {
    final p = placements.where((e) => e.locatorId == locatorId).firstOrNull;
    if (p == null) return;
    p.coordinate.x = _round2(world.dx);
    p.coordinate.y = _round2(world.dy);
    _markDirty();
  }

  void selectLocator(String? locatorId) {
    selectedLocatorId = locatorId;
    notifyListeners();
  }

  void removePlacement(String locatorId) {
    placements.removeWhere((p) => p.locatorId == locatorId);
    if (selectedLocatorId == locatorId) selectedLocatorId = null;
    _markDirty();
  }

  /// 왼쪽 패널 폼 편집 후 호출 (필드는 이미 객체에 반영됨).
  void placementEdited() => _markDirty();

  void globalsEdited() => _markDirty();

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  // =========================================================
  // 서버 전송용 병합
  // =========================================================
  /// 서버에서 가져온 config의 전역 필드 + 미지 필드를 유지하되,
  /// 편집한 전역 설정으로 덮어쓰고 locators는 캔버스 배치로 전체 교체.
  PositioningConfig mergeForPush(PositioningConfig fetched) {
    final merged = PositioningConfig(
      version: globals.version,
      id: globals.id,
      estimationModeLocation: globals.estimationModeLocation,
      validationModeLocation: globals.validationModeLocation,
      estimationIntervalSec: globals.estimationIntervalSec,
      locationFiltering: globals.locationFiltering,
      locationFilteringWeight: globals.locationFilteringWeight,
      numberOfSequenceIds: globals.numberOfSequenceIds,
      maximumSequenceIdDiffs: globals.maximumSequenceIdDiffs,
      locators: [for (final p in placements) p.toLocatorEntry()],
      extras: Map<String, dynamic>.from(fetched.extras),
    );
    return merged;
  }

  // =========================================================
  // 프로젝트 파일
  // =========================================================
  ProjectFile _toProject() => ProjectFile(
        serverIp: serverIp,
        floorPlanImagePath: floorImagePath,
        metersPerPixel: transform.metersPerPixel,
        originPx: transform.originPx,
        calibP1: calibP1,
        calibP2: calibP2,
        calibDistanceM: calibDistanceM,
        placements: placements,
        globals: globals,
      );

  /// 저장. [saveAs]가 true거나 경로가 없으면 다이얼로그를 띄운다.
  /// 모바일(SAF)은 직접 경로에 쓸 수 없어 항상 다이얼로그를 사용한다.
  /// 저장했으면 true.
  Future<bool> saveProject({bool saveAs = false}) async {
    final needDialog = saveAs ||
        projectPath == null ||
        Platform.isAndroid ||
        Platform.isIOS;
    if (needDialog) {
      final path = await _storage.saveWithDialog(_toProject(),
          suggestedName: 'positions.${ProjectFile.extension}');
      if (path == null) return false;
      projectPath = path;
    } else {
      await _storage.saveTo(projectPath!, _toProject());
    }
    dirty = false;
    notifyListeners();
    return true;
  }

  /// 열기. 도면 이미지가 없으면 이미지 로드는 건너뛴다(경로는 유지).
  /// 반환: 없어진 이미지 경로 (재선택 안내용), 정상이면 null.
  Future<String?> openProject() async {
    final path = await _storage.pickOpenPath();
    if (path == null) return null;
    final project = await _storage.load(path);

    serverIp = project.serverIp;
    calibP1 = project.calibP1;
    calibP2 = project.calibP2;
    calibDistanceM = project.calibDistanceM;
    placements
      ..clear()
      ..addAll(project.placements);
    globals = project.globals;
    selectedLocatorId = null;
    projectPath = path;

    String? missingImage;
    final imgPath = project.floorPlanImagePath;
    floorImage?.dispose();
    floorImage = null;
    floorImagePath = imgPath;
    if (imgPath != null) {
      if (File(imgPath).existsSync()) {
        final bytes = await File(imgPath).readAsBytes();
        floorImage = await decodeImageFromList(bytes);
      } else {
        missingImage = imgPath;
      }
    }
    transform = WorldTransform(
      metersPerPixel: project.metersPerPixel,
      originPx: project.originPx,
      zoom: transform.zoom,
      panPx: transform.panPx,
    );
    dirty = false;
    notifyListeners();
    return missingImage;
  }

  void newProject() {
    serverIp = serverDevice?.ip ?? '';
    floorImage?.dispose();
    floorImage = null;
    floorImagePath = null;
    transform = const WorldTransform();
    canvasMode = CanvasMode.normal;
    calibP1 = null;
    calibP2 = null;
    calibDistanceM = null;
    placements.clear();
    selectedLocatorId = null;
    globals = PositioningConfig();
    projectPath = null;
    dirty = false;
    notifyListeners();
  }
}
