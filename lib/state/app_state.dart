import 'dart:async';
import 'dart:convert';
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
import '../models/session.dart';
import '../services/discovery_service.dart';
import '../services/project_storage.dart';

/// 캔버스 클릭 모드.
enum CanvasMode { normal, calibrateP1, calibrateP2, setOrigin, adjustImage }

class AppState extends ChangeNotifier {
  final DiscoveryService _discovery = DiscoveryService();
  final ProjectStorage _storage = ProjectStorage();

  // ---- 디스커버리 ----
  List<DiscoveredDevice> devices = [];
  bool scanning = false;

  /// 이번 실행에서 검색을 한 번이라도 완료했는지 (미검색 경고 표시용).
  bool hasScanned = false;

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

  // ---- 실행 취소 (위치 설정 편집) ----
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  static const int _maxUndo = 50;
  DateTime _lastUndoPushAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

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
  // 실행 취소 / 다시 실행
  // =========================================================
  /// 변경 직전 상태를 스냅샷으로 쌓는다 (변경하는 메서드의 맨 앞에서 호출).
  /// [coalesce]면 짧은 간격의 연속 변경(마커 드래그)을 한 단계로 묶는다.
  /// JSON 문자열로 저장해 이후 편집이 스냅샷에 스며들지 않게 한다.
  void _pushUndo({bool coalesce = false}) {
    _redoStack.clear();
    final now = DateTime.now();
    if (coalesce &&
        _undoStack.isNotEmpty &&
        now.difference(_lastUndoPushAt).inMilliseconds < 700) {
      _lastUndoPushAt = now;
      return;
    }
    _lastUndoPushAt = now;
    _undoStack.add(jsonEncode(toProject().toJson()));
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
  }

  void _clearUndo() {
    _undoStack.clear();
    _redoStack.clear();
  }

  Future<void> undo() async {
    if (_undoStack.isEmpty) return;
    _redoStack.add(jsonEncode(toProject().toJson()));
    await _applySnapshot(_undoStack.removeLast());
  }

  Future<void> redo() async {
    if (_redoStack.isEmpty) return;
    _undoStack.add(jsonEncode(toProject().toJson()));
    await _applySnapshot(_redoStack.removeLast());
  }

  /// 스냅샷 복원. 뷰 상태(줌/팬)와 프로젝트 경로는 유지한다.
  Future<void> _applySnapshot(String snapshot) async {
    final project =
        ProjectFile.fromJson(jsonDecode(snapshot) as Map<String, dynamic>);
    serverIp = project.serverIp;
    calibP1 = project.calibP1;
    calibP2 = project.calibP2;
    calibDistanceM = project.calibDistanceM;
    placements
      ..clear()
      ..addAll(project.placements);
    globals = project.globals;
    if (selectedLocatorId != null &&
        placements.every((p) => p.locatorId != selectedLocatorId)) {
      selectedLocatorId = null;
    }
    transform = transform.copyWith(
      metersPerPixel: project.metersPerPixel,
      originPx: project.originPx,
    );
    if (floorImagePath != project.floorPlanImagePath) {
      floorImage?.dispose();
      floorImage = null;
      floorImagePath = project.floorPlanImagePath;
      final path = project.floorPlanImagePath;
      if (path != null && File(path).existsSync()) {
        floorImage = await decodeImageFromList(await File(path).readAsBytes());
      }
    }
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
      hasScanned = true;
      final server = serverDevice;
      if (server != null && serverIp.isEmpty) {
        serverIp = server.ip;
      }
      _syncPlacementsWithDevices();
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  /// 검색 결과를 배치에 반영: 같은 로케이터(MAC)의 IP/이름이
  /// 바뀌었으면(DHCP 재할당, 카드 이름 변경 등) 자동 갱신한다.
  void _syncPlacementsWithDevices() {
    var changed = false;
    for (final d in devices) {
      if (d.isServer || !d.hasValidMac) continue;
      final p =
          placements.where((e) => e.locatorId == d.locatorId).firstOrNull;
      if (p == null) continue;
      if (p.ip != d.ip) {
        p.ip = d.ip;
        changed = true;
      }
      if (d.device.isNotEmpty && p.deviceName != d.device) {
        p.deviceName = d.device;
        changed = true;
      }
    }
    if (changed) dirty = true; // notify는 scan()에서 일괄 수행
  }

  /// 배치돼 있지만 마지막 검색에서 발견되지 않은 로케이터
  /// (전원 꺼짐, 교체됨, 다른 네트워크). 검색 전에는 판단하지 않는다.
  List<PlacedLocator> get missingPlacements {
    if (!hasScanned) return const [];
    final found = {
      for (final d in devices)
        if (!d.isServer && d.hasValidMac) d.locatorId,
    };
    return [
      for (final p in placements)
        if (!found.contains(p.locatorId)) p,
    ];
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
    _pushUndo();
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

  /// 도면 삭제: 이미지와 경로만 제거하고 배치/스케일/원점은 유지한다.
  void removeFloorImage() {
    if (floorImage == null && floorImagePath == null) return;
    _pushUndo();
    floorImage?.dispose();
    floorImage = null;
    floorImagePath = null;
    if (canvasMode == CanvasMode.adjustImage) canvasMode = CanvasMode.normal;
    _markDirty();
  }

  /// 도면 조정 모드: 배치(월드 좌표)는 고정한 채 도면 이미지만 화면 기준
  /// [screenDelta]만큼 이동한다 (원점을 반대로 옮기고 팬으로 보정).
  void nudgeImage(Offset screenDelta) {
    if (floorImage == null) return;
    _pushUndo(coalesce: true);
    final z = transform.zoom;
    transform = transform.copyWith(
      originPx: transform.originPx - screenDelta / z,
      panPx: transform.panPx + screenDelta,
    );
    dirty = true;
    notifyListeners();
  }

  /// 도면 조정 모드: 커서 위치의 도면 지점을 기준으로 배치는 고정한 채
  /// 도면 이미지 크기만 [factor]배 조정한다 (m/px 스케일도 함께 변경).
  void scaleImage(Offset cursorScreen, double factor) {
    if (floorImage == null || factor <= 0) return;
    _pushUndo(coalesce: true);
    final z = transform.zoom;
    final q = (cursorScreen - transform.panPx) / z; // 커서의 이미지 px 좌표
    transform = transform.copyWith(
      metersPerPixel: transform.metersPerPixel * factor,
      zoom: z * factor,
      panPx: transform.panPx + q * z * (1 - factor),
      originPx: (transform.originPx + q * (factor - 1)) / factor,
    );
    dirty = true;
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
        _pushUndo();
        transform = transform.copyWith(originPx: imagePx);
        canvasMode = CanvasMode.normal;
        _markDirty();
        return false;
      case CanvasMode.normal:
      case CanvasMode.adjustImage:
        return false;
    }
  }

  /// 2점 보정 확정: 실거리(m) 입력 후 호출.
  void applyCalibration(double distanceM) {
    final p1 = calibP1, p2 = calibP2;
    if (p1 == null || p2 == null || distanceM <= 0) return;
    final pxDist = (p2 - p1).distance;
    if (pxDist <= 0) return;
    _pushUndo();
    calibDistanceM = distanceM;
    transform = transform.copyWith(metersPerPixel: distanceM / pxDist);
    _markDirty();
  }

  void setMetersPerPixel(double mpp) {
    if (mpp <= 0) return;
    _pushUndo();
    transform = transform.copyWith(metersPerPixel: mpp);
    _markDirty();
  }

  // =========================================================
  // 배치
  // =========================================================
  void placeDevice(DiscoveredDevice device, Offset world) {
    if (!device.hasValidMac || device.isServer) return;
    if (isPlaced(device)) return;
    _pushUndo();
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
    _pushUndo(coalesce: true); // 드래그 연속 이동은 한 단계로
    p.coordinate.x = _round2(world.dx);
    p.coordinate.y = _round2(world.dy);
    _markDirty();
  }

  void selectLocator(String? locatorId) {
    selectedLocatorId = locatorId;
    notifyListeners();
  }

  void removePlacement(String locatorId) {
    if (placements.every((p) => p.locatorId != locatorId)) return;
    _pushUndo();
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
  ProjectFile toProject() => ProjectFile(
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
      final path = await _storage.saveWithDialog(toProject(),
          suggestedName: 'positions.${ProjectFile.extension}');
      if (path == null) return false;
      projectPath = path;
    } else {
      await _storage.saveTo(projectPath!, toProject());
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
    return applyProject(project, path: path);
  }

  /// 프로젝트 데이터를 현재 상태에 적용한다 (열기/세션 복원 공용).
  /// 반환: 없어진 도면 이미지 경로, 정상이면 null.
  Future<String?> applyProject(ProjectFile project, {String? path}) async {
    _clearUndo();
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

  /// 세션(마지막 작업 상태) 복원. 앱 시작 시 호출된다.
  Future<void> restoreSession(SessionData session) async {
    await applyProject(session.project, path: session.projectPath);
    dirty = session.dirty;
    notifyListeners();
  }

  void newProject() {
    _clearUndo();
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
