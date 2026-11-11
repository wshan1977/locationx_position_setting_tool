import 'package:flutter_test/flutter_test.dart';

import 'package:locationx_position_setting_tool/models/placement.dart';
import 'package:locationx_position_setting_tool/models/positioning_config.dart';
import 'package:locationx_position_setting_tool/models/project.dart';
import 'package:locationx_position_setting_tool/models/session.dart';
import 'package:locationx_position_setting_tool/models/site.dart';
import 'package:locationx_position_setting_tool/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('floors keep their own placements and server IP', () async {
    final app = AppState();
    app.setServerIp('192.168.1.10');
    app.placements.add(PlacedLocator(locatorId: 'ble-pd-AAA'));
    final site = app.activeSite.id;
    final f1 = app.activeFloor.id;

    await app.addFloor(site, '2층');
    // 새 층: 배치는 비고 서버 IP는 이어받음
    expect(app.activeFloor.name, '2층');
    expect(app.placements, isEmpty);
    expect(app.serverIp, '192.168.1.10');
    app.placements.add(PlacedLocator(locatorId: 'ble-pd-BBB'));
    app.setServerIp('192.168.1.20');

    await app.switchFloor(site, f1);
    expect(app.placements.map((p) => p.locatorId), ['ble-pd-AAA']);
    expect(app.serverIp, '192.168.1.10');

    final f2 = app.activeSite.floors.last.id;
    expect(app.floorProject(site, f2).placements.single.locatorId, 'ble-pd-BBB');
  });

  test('last floor / last site cannot be deleted; deleting active switches',
      () async {
    final app = AppState();
    final site = app.activeSite.id;
    expect(await app.deleteFloor(site, app.activeFloor.id), isFalse);
    expect(await app.deleteSite(site), isFalse);

    await app.addSite('물류센터');
    expect(app.activeSite.name, '물류센터');
    expect(await app.deleteSite(app.activeSite.id), isTrue);
    expect(app.activeSite.id, site);
    expect(app.sites.sites, hasLength(1));
  });

  test('pre-site session migrates to 기본 장소 › 1층 and round-trips', () async {
    final app = AppState();
    final old = SessionData(project: ProjectFile(serverIp: '10.0.0.5'));
    await app.restoreSession(old);
    expect(app.activeSite.name, '기본 장소');
    expect(app.activeFloor.name, '1층');
    expect(app.serverIp, '10.0.0.5');

    await app.addFloor(app.activeSite.id, 'B1');
    final saved = SessionData(project: app.toProject(), sites: app.siteBookJson());
    final again = AppState();
    await again.restoreSession(SessionData.fromJson(saved.toJson()));
    expect(again.activeFloor.name, 'B1');
    expect(again.activeSite.floors.map((f) => f.name), ['1층', 'B1']);
    expect(SiteBook.fromJson(saved.sites!).sites.single.floors.first.project.serverIp,
        '10.0.0.5');
  });

  test('mask faces survive push/read-back and are kept when server lacks them', () {
    final app = AppState();
    app.placements.add(PlacedLocator(locatorId: 'ble-pd-D71E', maskFaces: {'+y'}));
    // 전송본 → 서버에서 다시 읽기: maskFaces 유지
    final pushed = app.mergeForPush(PositioningConfig());
    final roundTrip = PositioningConfig.fromJson(pushed.toJson());
    app.placements.first.maskFaces.clear();
    app.applyServerConfig(roundTrip);
    expect(app.placements.single.maskFaces, {'+y'});

    // 서버에 maskFaces 키가 없으면(이전 도구로 전송) 현재 선택 유지
    final legacy = PositioningConfig.fromJson({
      'locators': [
        {'id': 'ble-pd-D71E', 'coordinate': {'x': 0, 'y': 0, 'z': 3}},
      ],
    });
    app.applyServerConfig(legacy);
    expect(app.placements.single.maskFaces, {'+y'});

    // 서버가 빈 목록이면 해제로 본다
    final cleared = PositioningConfig.fromJson({
      'locators': [
        {'id': 'ble-pd-D71E', 'coordinate': {'x': 0, 'y': 0, 'z': 3}, 'maskFaces': []},
      ],
    });
    app.applyServerConfig(cleared);
    expect(app.placements.single.maskFaces, isEmpty);
  });
}
