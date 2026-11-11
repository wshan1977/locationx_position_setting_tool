import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/site.dart';
import '../state/app_state.dart';
import '../widgets/tab_guide.dart';

/// 설정 › 장소 · 층: 장소(건물·현장)와 층을 등록·이름 변경·삭제하고,
/// 작업할 층을 고른다. 층마다 도면·스케일·원점·로케이터 배치·서버 IP를
/// 따로 보관한다 (위치 설정 화면은 선택한 층을 편집).
class SitesPage extends StatefulWidget {
  const SitesPage({super.key});

  @override
  State<SitesPage> createState() => _SitesPageState();
}

class _SitesPageState extends State<SitesPage> {
  String? _viewSiteId; // 오른쪽에 층 목록을 보여줄 장소 (기본: 활성 장소)

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final book = app.sites;
    final view = book.siteById(_viewSiteId ?? '') ?? book.activeSite;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabGuide(
          icon: Icons.apartment,
          text: '작업 순서: ① 장소(건물·현장) 등록 → ② 장소에 층 추가 → '
              '③ 작업할 층 선택 — 층마다 도면·로케이터 배치·서버 카드를 따로 보관합니다',
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: _siteList(app, view)),
              const VerticalDivider(width: 1),
              Expanded(child: _floorList(app, view)),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // 좌측: 장소 목록
  // =========================================================
  Widget _siteList(AppState app, SiteEntry view) {
    final book = app.sites;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton.icon(
            onPressed: () => _addSite(app),
            icon: const Icon(Icons.add_business),
            label: const Text('장소 추가'),
          ),
        ),
        _sectionTitle('장소 (${book.sites.length})'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final s in book.sites)
                Card(
                  color: s.id == view.id
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                      : null,
                  child: ListTile(
                    dense: true,
                    selected: s.id == view.id,
                    leading: const Icon(Icons.apartment),
                    title: Text(s.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('층 ${s.floors.length}개'
                        '${s.id == book.activeSiteId ? ' · 작업 중' : ''}'),
                    trailing: _menu(
                      onRename: () => _renameSite(app, s),
                      onDelete: book.sites.length > 1
                          ? () => _deleteSite(app, s)
                          : null,
                      deleteTip: '마지막 장소는 삭제할 수 없습니다',
                    ),
                    onTap: () => setState(() => _viewSiteId = s.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // 우측: 선택 장소의 층 목록
  // =========================================================
  Widget _floorList(AppState app, SiteEntry site) {
    final book = app.sites;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.apartment, size: 26),
              const SizedBox(width: 8),
              Text(site.name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _addFloor(app, site),
                icon: const Icon(Icons.add),
                label: const Text('층 추가'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final f in site.floors)
                _floorCard(app, site, f,
                    active: site.id == book.activeSiteId &&
                        f.id == book.activeFloorId),
            ],
          ),
        ),
      ],
    );
  }

  Widget _floorCard(AppState app, SiteEntry site, FloorEntry f,
      {required bool active}) {
    final proj = app.floorProject(site.id, f.id);
    final img = proj.floorPlanImagePath;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: active ? cs.primary.withValues(alpha: 0.08) : null,
      shape: active
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: cs.primary, width: 1.5))
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.layers, color: active ? cs.primary : Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(f.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    if (active) ...[
                      const SizedBox(width: 8),
                      Chip(
                        label: const Text('작업 중', style: TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: cs.primary.withValues(alpha: 0.15),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '서버 ${proj.serverIp.isEmpty ? '미지정' : proj.serverIp}'
                    ' · 로케이터 ${proj.placements.length}대'
                    ' · 도면 ${img == null ? '없음' : p.basename(img)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            if (!active)
              FilledButton.tonal(
                onPressed: () => _switch(app, site, f),
                child: const Text('이 층 작업'),
              ),
            _menu(
              onRename: () => _renameFloor(app, site, f),
              onDelete: site.floors.length > 1
                  ? () => _deleteFloor(app, site, f)
                  : null,
              deleteTip: '장소의 마지막 층은 삭제할 수 없습니다',
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
      );

  Widget _menu({
    required VoidCallback onRename,
    required VoidCallback? onDelete,
    required String deleteTip,
  }) {
    return PopupMenuButton<String>(
      tooltip: '이름 변경 · 삭제',
      onSelected: (v) => v == 'rename' ? onRename() : onDelete?.call(),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('이름 변경')),
        PopupMenuItem(
          value: 'delete',
          enabled: onDelete != null,
          child: Text(onDelete == null ? '삭제 ($deleteTip)' : '삭제',
              style: TextStyle(color: onDelete == null ? null : Colors.red)),
        ),
      ],
    );
  }

  // =========================================================
  // 동작
  // =========================================================
  Future<void> _addSite(AppState app) async {
    final name = await _askName('장소 추가', '장소 이름 (예: 본사 2동, 물류센터)', '');
    if (name == null) return;
    await app.addSite(name);
    if (mounted) setState(() => _viewSiteId = app.sites.activeSiteId);
    _snack('"$name" 장소를 만들고 1층으로 전환했습니다');
  }

  Future<void> _renameSite(AppState app, SiteEntry s) async {
    final name = await _askName('장소 이름 변경', '장소 이름', s.name);
    if (name != null) app.renameSite(s.id, name);
  }

  Future<void> _deleteSite(AppState app, SiteEntry s) async {
    final ok = await _confirm('장소 삭제',
        '"${s.name}"과(와) 그 안의 층 ${s.floors.length}개(도면·로케이터 배치)를 삭제합니다.\n'
        '서버 카드의 설정은 바뀌지 않습니다. 되돌릴 수 없습니다.');
    if (ok != true) return;
    await app.deleteSite(s.id);
    if (mounted) setState(() => _viewSiteId = null);
  }

  Future<void> _addFloor(AppState app, SiteEntry site) async {
    final name = await _askName(
        '층 추가', '층 이름 (예: 2층, 지하 1층)', '${site.floors.length + 1}층');
    if (name == null) return;
    final dirty = app.dirty;
    await app.addFloor(site.id, name);
    _snack('"${site.name} › $name"으로 전환했습니다 — [③ 위치 설정]에서 도면을 불러오세요'
        '${dirty ? ' (이전 층의 미저장 내용은 목록에 보관됨)' : ''}');
  }

  Future<void> _renameFloor(AppState app, SiteEntry site, FloorEntry f) async {
    final name = await _askName('층 이름 변경', '층 이름', f.name);
    if (name != null) app.renameFloor(site.id, f.id, name);
  }

  Future<void> _deleteFloor(AppState app, SiteEntry site, FloorEntry f) async {
    final ok = await _confirm('층 삭제',
        '"${site.name} › ${f.name}"의 도면 설정과 로케이터 배치를 삭제합니다.\n'
        '서버 카드의 설정은 바뀌지 않습니다. 되돌릴 수 없습니다.');
    if (ok != true) return;
    await app.deleteFloor(site.id, f.id);
  }

  Future<void> _switch(AppState app, SiteEntry site, FloorEntry f) async {
    final missing = await app.switchFloor(site.id, f.id);
    _snack(missing == null
        ? '"${site.name} › ${f.name}"으로 전환했습니다'
        : '"${f.name}"의 도면 파일이 없습니다: $missing — [③ 위치 설정]에서 다시 불러오세요');
  }

  Future<String?> _askName(String title, String label, String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) {
        void submit() {
          final v = c.text.trim();
          if (v.isNotEmpty) Navigator.pop(context, v);
        }

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 360,
            child: TextField(
              controller: c,
              autofocus: true,
              decoration: InputDecoration(labelText: label),
              onSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소')),
            FilledButton(onPressed: submit, child: const Text('확인')),
          ],
        );
      },
    );
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
