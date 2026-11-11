import 'dart:convert';

import 'project.dart';

/// 층 1개: 도면·스케일·원점·로케이터 배치·서버 IP·전역 positioning 설정
/// (= 프로젝트 파일 1개 분량).
class FloorEntry {
  final String id;
  String name; // "1층", "지하 1층"...
  ProjectFile project;

  FloorEntry({required this.id, required this.name, ProjectFile? project})
      : project = project ?? ProjectFile();

  factory FloorEntry.fromJson(Map<String, dynamic> j) => FloorEntry(
        id: j['id']?.toString() ?? newId('f'),
        name: j['name']?.toString() ?? '1층',
        project: j['project'] is Map
            ? ProjectFile.fromJson(Map<String, dynamic>.from(j['project'] as Map))
            : null,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'project': project.toJson()};
}

/// 장소(건물·현장) 1개: 층 목록 (비어 있지 않음).
class SiteEntry {
  final String id;
  String name;
  final List<FloorEntry> floors;

  SiteEntry({required this.id, required this.name, List<FloorEntry>? floors})
      : floors = (floors == null || floors.isEmpty)
            ? [FloorEntry(id: newId('f'), name: '1층')]
            : floors;

  factory SiteEntry.fromJson(Map<String, dynamic> j) => SiteEntry(
        id: j['id']?.toString() ?? newId('s'),
        name: j['name']?.toString() ?? '장소',
        floors: [
          if (j['floors'] is List)
            for (final f in j['floors'] as List)
              if (f is Map) FloorEntry.fromJson(Map<String, dynamic>.from(f)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'floors': [for (final f in floors) f.toJson()],
      };

  FloorEntry? floorById(String id) =>
      floors.where((f) => f.id == id).firstOrNull;
}

/// 등록된 장소 전체 + 지금 작업 중인 장소/층.
class SiteBook {
  final List<SiteEntry> sites; // 비어 있지 않음
  String activeSiteId;
  String activeFloorId;

  SiteBook({
    required this.sites,
    required this.activeSiteId,
    required this.activeFloorId,
  });

  /// 장소 기능 이전 세션: 기존 작업을 "기본 장소 › 1층"으로 옮긴다.
  factory SiteBook.initial([ProjectFile? project]) {
    final floor = FloorEntry(id: newId('f'), name: '1층', project: project);
    final site = SiteEntry(id: newId('s'), name: '기본 장소', floors: [floor]);
    return SiteBook(sites: [site], activeSiteId: site.id, activeFloorId: floor.id);
  }

  factory SiteBook.fromJson(Map<String, dynamic> j) {
    final sites = [
      if (j['sites'] is List)
        for (final s in j['sites'] as List)
          if (s is Map) SiteEntry.fromJson(Map<String, dynamic>.from(s)),
    ];
    if (sites.isEmpty) return SiteBook.initial();
    final book = SiteBook(
      sites: sites,
      activeSiteId: j['activeSiteId']?.toString() ?? '',
      activeFloorId: j['activeFloorId']?.toString() ?? '',
    );
    book._fixActive();
    return book;
  }

  Map<String, dynamic> toJson() => {
        'sites': [for (final s in sites) s.toJson()],
        'activeSiteId': activeSiteId,
        'activeFloorId': activeFloorId,
      };

  SiteEntry get activeSite =>
      sites.where((s) => s.id == activeSiteId).firstOrNull ?? sites.first;

  FloorEntry get activeFloor =>
      activeSite.floorById(activeFloorId) ?? activeSite.floors.first;

  SiteEntry? siteById(String id) => sites.where((s) => s.id == id).firstOrNull;

  /// 활성 id가 없어진 장소/층을 가리키면 첫 항목으로 맞춘다.
  void _fixActive() {
    activeSiteId = activeSite.id;
    activeFloorId = activeFloor.id;
  }

  void fixActive() => _fixActive();
}

/// 층 프로젝트 깊은 복사 (배치 객체가 편집 중 상태와 공유되지 않게).
ProjectFile copyProject(ProjectFile p) =>
    ProjectFile.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);

int _idSeq = 0;

String newId(String prefix) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_idSeq++).toRadixString(36)}';
