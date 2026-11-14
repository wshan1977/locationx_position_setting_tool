import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:universal_ble/universal_ble.dart';

import '../services/release_repo.dart';
import '../state/app_state.dart';
import '../state/mqtt_state.dart';
import '../state/tag_state.dart';
import '../widgets/hover_tip.dart';
import '../widgets/tab_guide.dart';

/// 설정 › ② Tag 설정.
/// PC 블루투스 또는 로케이터 카드 내장 블루투스로 주변 태그를 검색하고,
/// 선택한 태그의 Device Information을
/// 읽거나 .gbl 펌웨어로 OTA 업데이트한다 (TagState 참고).
class TagSettingsTab extends StatefulWidget {
  const TagSettingsTab({super.key});

  @override
  State<TagSettingsTab> createState() => _TagSettingsTabState();
}

class _TagSettingsTabState extends State<TagSettingsTab> {
  String? _selectedMac;

  // 태그별 마지막 상태 읽기 결과
  final _info = <String, BleTagInfo>{};

  // 선택한 펌웨어 (GitHub 릴리즈에서 받았거나 로컬 파일)
  String? _gblName;
  Uint8List? _gbl;

  // 공개 배포 저장소(locationx-release)의 Hart 태그 펌웨어 버전
  List<String>? _relVersions; // null = 아직 안 불러옴
  String? _relSel;
  bool _relLoading = false;
  bool _relDownloading = false;

  // CTE 송신 주기 (ms) 입력 · 태그별 마지막 적용값
  final _intervalCtrl = TextEditingController(text: '100');
  final _appliedInterval = <String, double>{};

  @override
  void dispose() {
    _intervalCtrl.dispose();
    super.dispose();
  }

  // OTA 진행
  OtaProgress? _progress;
  String? _otaError;
  bool _showTrace = false;

  @override
  Widget build(BuildContext context) {
    final tags = context.watch<TagState>();
    final selected = tags.tags[_selectedMac];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabGuide(
          icon: Icons.sell,
          text: tags.link == TagLink.pc
              ? '작업 순서: ① [Tag 검색]으로 주변 태그 찾기 (PC 블루투스) → '
                  '② 왼쪽 목록에서 태그 선택 → ③ 상태 읽기 · 펌웨어(.gbl) 선택 후 OTA 업데이트 — '
                  '태그를 PC 가까이(1~2m) 두고 진행하세요'
              : '작업 순서: ① [Tag 검색] — 로케이터 카드들이 내장 블루투스로 동시에 검색 → '
                  '② 태그 선택 (가장 크게 들은 로케이터가 접속을 맡음) → ③ 상태 읽기 · OTA 업데이트 — '
                  'PC가 태그 근처에 없어도 됩니다',
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 340, child: _tagList(tags)),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? Center(
                        child: Text(
                          '좌측에서 Tag를 선택하세요.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : _detailPanel(tags, selected),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        _statusBar(tags),
      ],
    );
  }

  // 화면 아래 상태줄: 지금 하는 일 / 마지막 결과 (+ 업데이트 로그 펼치기).
  Widget _statusBar(TagState tags) {
    final busy = tags.scanning || tags.busyMac != null;
    final t = tags.statusAt;
    final hh = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    final color = tags.statusError ? Colors.red.shade700 : null;
    return Container(
      color: tags.statusError
          ? Colors.red.withValues(alpha: 0.06)
          : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            if (busy)
              const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(tags.statusError ? Icons.error_outline : Icons.info_outline,
                  size: 16, color: color ?? Colors.grey),
            const SizedBox(width: 8),
            Text(hh, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(tags.status,
                  maxLines: 3, style: TextStyle(fontSize: 12, color: color)),
            ),
            if (tags.otaTrace.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(() => _showTrace = !_showTrace),
                icon: Icon(_showTrace ? Icons.expand_more : Icons.expand_less, size: 16),
                label: Text('로그 (${tags.otaTrace.length})', style: const TextStyle(fontSize: 12)),
              ),
          ]),
          if (_showTrace && tags.otaTrace.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(tags.otaTrace.join('\n'),
                    style: const TextStyle(fontSize: 11, fontFamily: 'Consolas')),
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================
  // 좌측: Tag 목록
  // =========================================================
  Widget _tagList(TagState tags) {
    final list = tags.visibleTags;
    final locked = tags.scanning || tags.busyMac != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: hoverTip(
            '접속 경로\n'
            '· PC: 이 PC의 블루투스 — 태그를 PC 가까이 두고 작업\n'
            '· 로케이터: 로케이터 카드(Pi) 내장 블루투스 — 현장에 설치된 그대로 작업\n'
            '  (로케이터 v1.0.31 이상 · 접속·OTA 중에는 그 카드의 각도가 잠시 흔들릴 수 있음)',
            SegmentedButton<TagLink>(
              segments: const [
                ButtonSegment(
                    value: TagLink.pc, icon: Icon(Icons.computer, size: 16), label: Text('PC')),
                ButtonSegment(
                    value: TagLink.locator,
                    icon: Icon(Icons.router, size: 16),
                    label: Text('로케이터')),
              ],
              selected: {tags.link},
              onSelectionChanged: locked
                  ? null
                  : (v) => setState(() {
                        tags.setLink(v.first);
                        _selectedMac = null;
                        _progress = null;
                        _otaError = null;
                      }),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: hoverTip(
            tags.link == TagLink.pc
                ? 'PC 블루투스로 8초 동안 주변 BLE 광고를 듣고 태그(AssetTag)와\n'
                    '업데이트 모드(AppLoader)에 멈춘 태그를 찾습니다.'
                : '[Locator 검색]으로 찾은 로케이터 카드 전부가 15초 동안 동시에 듣고,\n'
                    '태그마다 가장 크게 들은 카드를 기억합니다.',
            FilledButton.icon(
              onPressed: locked ? null : _scan,
              icon: tags.scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bluetooth_searching),
              label: Text(tags.scanning ? '검색 중...' : 'Tag 검색 (BLE)'),
            ),
          ),
        ),
        CheckboxListTile(
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('모든 BLE 기기 표시', style: TextStyle(fontSize: 12)),
          subtitle: const Text('이름이 AssetTag가 아닌 태그를 찾을 때',
              style: TextStyle(fontSize: 11)),
          value: tags.showAll,
          onChanged: (v) => tags.setShowAll(v ?? false),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    tags.scanning
                        ? ''
                        : '검색된 태그가 없습니다.\n[Tag 검색]을 눌러주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    _sectionTitle('태그 (${list.length})'),
                    for (final t in list) _tagTile(tags, t),
                  ],
                ),
        ),
        if (tags.locatorErrors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              [
                for (final e in tags.locatorErrors.entries) '로케이터 ${e.key}: ${e.value}',
              ].join('\n'),
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
            ),
          ),
      ],
    );
  }

  /// "7ACD -56 · 792E -71 dBm" (센 순서, 접속 담당 카드에 ★).
  String _heardBy(BleTag t) {
    final e = t.heardBy.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return '${[
      for (final x in e) '${x.key == t.via?.name ? '★' : ''}${x.key} ${x.value}'
    ].join(' · ')} dBm';
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
      );

  Widget _tagTile(TagState tags, BleTag t) {
    final isSelected = t.mac == _selectedMac;
    return Card(
      color: isSelected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
          : null,
      child: ListTile(
        dense: true,
        selected: isSelected,
        leading: Icon(
          t.appLoader ? Icons.system_update : Icons.sell,
          color: t.appLoader ? Colors.orange : Colors.indigo,
        ),
        title: Text(
          t.name.isEmpty ? '(이름 미수신 · 태그 ID로 확인)' : t.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${t.mac}\n'
            '${t.heardBy.isEmpty ? 'RSSI ${t.rssi} dBm · PC' : _heardBy(t)}'),
        isThreeLine: true,
        trailing: t.appLoader
            ? const Chip(
                label: Text('업데이트 모드', style: TextStyle(fontSize: 10)),
                visualDensity: VisualDensity.compact,
              )
            : null,
        onTap: () => setState(() {
          if (_selectedMac != t.mac) {
            _progress = null;
            _otaError = null;
          }
          _selectedMac = t.mac;
        }),
      ),
    );
  }

  // =========================================================
  // 우측: 선택 Tag 상세
  // =========================================================
  Widget _detailPanel(TagState tags, BleTag t) {
    final info = _info[t.mac];
    final busy = tags.busyMac != null || tags.scanning;
    final otaRunning = tags.busyMac == t.mac && _progress != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(t.appLoader ? Icons.system_update : Icons.sell,
                    color: t.appLoader ? Colors.orange : Colors.indigo,
                    size: 28),
                const SizedBox(width: 10),
                Text(
                  t.name.isEmpty ? t.mac : t.name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _sectionCard(
              Icons.info_outline,
              '태그 정보',
              'BLE로 접속해 Device Information 서비스를 읽습니다',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('BLE MAC', t.mac),
                  _kv('Tag ID', t.tagId, copy: true),
                  _kv('RSSI', '${t.rssi} dBm'),
                  _kv('접속 경로',
                      t.via == null ? 'PC 블루투스' : '로케이터 ${t.via!.name} (${t.via!.ip})'),
                  if (t.heardBy.isNotEmpty) _kv('들은 로케이터', _heardBy(t)),
                  if (t.appLoader)
                    _kv('상태', '업데이트 모드(AppLoader) · ${t.otaAddr ?? ''}'),
                  if (info != null) ...[
                    const Divider(),
                    _kv('제조사', info.manufacturer),
                    _kv('모델', info.model),
                    _kv('HW 리비전', info.hw),
                    _kv('FW 리비전', info.fw),
                    _kv('OTA 지원',
                        info.otaCapable ? '예 (in_place_ota_dfu)' : '아니오 — SWD 재기록 필요'),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: busy || t.appLoader ? null : () => _readStatus(t),
                    icon: tags.busyMac == t.mac && _progress == null
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: const Text('상태 읽기'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _sectionCard(
              Icons.battery_saver,
              '송신 주기 (저전력)',
              '로케이터가 위치 계산에 쓰는 CTE 신호를 얼마나 자주 보낼지 정합니다. '
                  '길게 하면 배터리가 오래 가지만 위치 갱신이 느려집니다. '
                  '태그 FW 1.2.0 이상은 재부팅 후에도 유지됩니다',
              _intervalEditor(tags, t, info, busy),
            ),
            const SizedBox(height: 14),
            _sectionCard(
              Icons.system_update_alt,
              '펌웨어 OTA 업데이트',
              'Silicon Labs AppLoader OTA — 태그 펌웨어에 in_place_ota_dfu가 있어야 합니다 '
                  '(Simplicity Studio 빌드 산출물 *.gbl, 부트로더 아닌 앱 이미지)',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 시작 전부터 항상 보이게: Hart 태그는 OTA 내내 버튼을 눌러야 한다
                  if (_progress == null) ...[
                    _holdButtonBanner(done: false),
                    const SizedBox(height: 12),
                  ],
                  _releasePicker(otaRunning),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: otaRunning ? null : _pickGbl,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('로컬 파일 선택'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _gblName == null
                              ? '선택된 펌웨어 없음'
                              : '$_gblName (${(_gbl!.length / 1024).toStringAsFixed(1)} KB'
                                  '${TagState.versionOf(_gblName!).isEmpty ? '' : ' · v${TagState.versionOf(_gblName!)}'})',
                          style: const TextStyle(fontSize: 12.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: busy || _gbl == null ? null : () => _ota(tags, t),
                    icon: const Icon(Icons.upload, size: 18),
                    label: Text(t.appLoader ? '업데이트 이어서 하기' : 'OTA 업데이트 시작'),
                  ),
                  if (_progress != null) ...[
                    const SizedBox(height: 12),
                    _holdButtonBanner(done: !otaRunning),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: _progress!.fraction),
                    const SizedBox(height: 6),
                    Text(_progress!.step, style: const TextStyle(fontSize: 12.5)),
                  ],
                  if (_otaError != null) ...[
                    const SizedBox(height: 10),
                    Text(_otaError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                  ],
                  if (tags.otaTrace.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () => setState(() => _showTrace = !_showTrace),
                      icon: Icon(_showTrace ? Icons.expand_less : Icons.expand_more,
                          size: 18),
                      label: const Text('진행 기록', style: TextStyle(fontSize: 12)),
                    ),
                    if (_showTrace)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        color: Colors.grey.shade100,
                        child: SelectableText(
                          tags.otaTrace.join('\n'),
                          style: const TextStyle(
                              fontFamily: 'Consolas', fontSize: 11),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// GitHub 공개 배포 저장소의 Hart 태그 펌웨어: 버전 선택 → 받기.
  Widget _releasePicker(bool otaRunning) {
    if (_relVersions == null && !_relLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadReleases());
    }
    final vers = _relVersions ?? const <String>[];
    return Row(
      children: [
        const Icon(Icons.cloud_download, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        const Text('GitHub 릴리즈', style: TextStyle(fontSize: 12.5)),
        const SizedBox(width: 10),
        if (_relLoading)
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
        else if (vers.isEmpty)
          Text('목록을 받지 못함',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600))
        else
          DropdownButton<String>(
            value: _relSel,
            isDense: true,
            items: [
              for (final v in vers)
                DropdownMenuItem(
                  value: v,
                  child: Text(v == vers.first ? 'v$v (최신)' : 'v$v',
                      style: const TextStyle(fontSize: 13)),
                ),
            ],
            onChanged: otaRunning ? null : (v) => setState(() => _relSel = v),
          ),
        const SizedBox(width: 8),
        hoverTip(
          '${ReleaseRepo.repo} 에서 선택한 버전의 .gbl을 받습니다.',
          FilledButton.tonalIcon(
            onPressed: otaRunning || _relDownloading || _relSel == null
                ? null
                : _downloadRelease,
            icon: _relDownloading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download, size: 18),
            label: const Text('받기'),
          ),
        ),
        IconButton(
          tooltip: '목록 새로고침',
          visualDensity: VisualDensity.compact,
          onPressed: _relLoading || otaRunning ? null : _loadReleases,
          icon: const Icon(Icons.refresh, size: 18),
        ),
      ],
    );
  }

  /// Hart 태그는 OTA 중 리셋(앱 → AppLoader → 새 앱) 때 BAT_HOLD(PA08)가 풀려
  /// 전원이 꺼지므로, 업데이트 내내 전원 버튼(S1)을 누르고 있어야 한다.
  Widget _holdButtonBanner({required bool done}) {
    final color = done ? Colors.green : Colors.orange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.touch_app,
              color: color.shade700, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              done
                  ? '이제 태그 전원 버튼을 놓아도 됩니다.'
                  : '태그 전원 버튼을 누른 상태로 시작하고,\n'
                      '완료될 때까지 계속 누르고 있으세요.',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: color.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// CTE 송신 주기 편집: ms 입력 + 프리셋 + [태그에 적용].
  Widget _intervalEditor(TagState tags, BleTag t, BleTagInfo? info, bool busy) {
    const presets = [(25, '25 ms · 초당 40회 (기본에 가까움)'), (100, '100 ms · 초당 10회'),
      (250, '250 ms · 초당 4회'), (1000, '1 s · 초당 1회 (저전력)')];
    final applied = _appliedInterval[t.mac];
    final oldFw = info != null && TagState.compareVersion(info.fw, '1.2.0') < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 120,
              child: TextField(
                controller: _intervalCtrl,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '송신 주기 (ms)', isDense: true, suffixText: 'ms'),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: busy || t.appLoader ? null : () => _applyInterval(tags, t),
              icon: tags.busyMac == t.mac && _progress == null
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, size: 18),
              label: const Text('태그에 적용'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (ms, label) in presets)
              ActionChip(
                label: Text(label, style: const TextStyle(fontSize: 11.5)),
                onPressed: busy ? null : () => setState(() => _intervalCtrl.text = '$ms'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${TagState.cteIntervalMinMs}~${TagState.cteIntervalMaxMs} ms · 0.625 ms 단위로 반올림'
          '${applied == null ? '' : ' · 마지막 적용: ${applied.toStringAsFixed(applied % 1 == 0 ? 0 : 3)} ms'}',
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
        ),
        if (oldFw)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '이 태그는 FW ${info.fw} — 적용은 되지만 재부팅하면 기본 주기로 돌아갑니다 '
              '(FW 1.2.0 이상으로 OTA 업데이트하면 유지됨)',
              style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800),
            ),
          ),
      ],
    );
  }

  Future<void> _applyInterval(TagState tags, BleTag t) async {
    final ms = int.tryParse(_intervalCtrl.text.trim());
    if (ms == null || ms < TagState.cteIntervalMinMs || ms > TagState.cteIntervalMaxMs) {
      _snack('송신 주기는 ${TagState.cteIntervalMinMs}~${TagState.cteIntervalMaxMs} ms로 입력하세요');
      return;
    }
    try {
      final actual = await tags.setCteIntervalMs(t.mac, ms);
      if (!mounted) return;
      setState(() => _appliedInterval[t.mac] = actual);
      _snack('송신 주기 ${actual.toStringAsFixed(actual % 1 == 0 ? 0 : 3)} ms 적용됨');
    } catch (e) {
      _snack('송신 주기 적용 실패: $e');
    }
  }

  Widget _sectionCard(
      IconData icon, String title, String? subtitle, Widget child) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool copy = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(k,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
            ),
            Expanded(
              child: SelectableText(v.isEmpty ? '-' : v,
                  style: const TextStyle(fontSize: 12.5)),
            ),
            if (copy)
              IconButton(
                tooltip: '복사',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: v));
                  _snack('복사됨: $v');
                },
                icon: const Icon(Icons.copy),
              ),
          ],
        ),
      );

  // =========================================================
  // 동작
  // =========================================================
  Future<void> _scan() async {
    final tags = context.read<TagState>();
    // MQTT로 각도·위치가 들어오는 태그는 이름을 못 들어도 목록에 보이게.
    tags.addKnownTagIds([
      for (final topic in context.read<MqttState>().topics.keys) topic.split('/').last,
    ]);
    if (tags.link == TagLink.locator) return _scanViaLocators(tags);
    try {
      final av = await tags.availability();
      if (av != AvailabilityState.poweredOn) {
        _snack('블루투스를 사용할 수 없습니다 ($av) — PC 블루투스를 켜 주세요.');
        return;
      }
      await tags.scan();
    } catch (e) {
      _snack('Tag 검색 실패: $e');
    }
  }

  Future<void> _scanViaLocators(TagState tags) async {
    final app = context.read<AppState>();
    List<LocatorCard> cards() => [
          for (final d in app.devices)
            if (!d.isServer) (ip: d.ip, name: d.shortId),
        ];
    try {
      // 로케이터 목록이 없으면 먼저 UDP로 카드를 찾는다.
      if (cards().isEmpty) await app.scan();
      final list = cards();
      if (list.isEmpty) {
        _snack('로케이터 카드를 찾지 못했습니다 — ① Locator 탭에서 [Locator 검색]을 확인하세요.');
        return;
      }
      await tags.scanViaLocators(list);
      if (tags.locatorErrors.length == list.length) {
        _snack('모든 로케이터에서 태그 검색 실패 — 로케이터 v1.0.31 이상 배포가 필요합니다.');
      }
    } catch (e) {
      _snack('Tag 검색 실패: $e');
    }
  }

  Future<void> _readStatus(BleTag t) async {
    try {
      final info = await context.read<TagState>().readStatus(t.mac);
      if (mounted) setState(() => _info[t.mac] = info);
    } catch (e) {
      _snack('상태 읽기 실패: $e');
    }
  }

  Future<void> _loadReleases() async {
    if (_relLoading) return;
    setState(() => _relLoading = true);
    final vers = await ReleaseRepo.versions(ReleaseRepo.hartTag);
    if (!mounted) return;
    setState(() {
      _relLoading = false;
      _relVersions = vers;
      if (_relSel == null || !vers.contains(_relSel)) {
        _relSel = vers.isEmpty ? null : vers.first;
      }
    });
  }

  Future<void> _downloadRelease() async {
    final ver = _relSel!;
    setState(() => _relDownloading = true);
    try {
      final bytes = await ReleaseRepo.firmware(ReleaseRepo.hartTag, ver);
      if (!mounted) return;
      setState(() {
        _gblName = 'locationx_hart_tag_v$ver.gbl (GitHub)';
        _gbl = bytes;
      });
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _relDownloading = false);
    }
  }

  Future<void> _pickGbl() async {
    // .gbl은 MIME 타입이 없어 Android에서 custom 필터가 안 먹으므로 전체에서 고른다.
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '태그 펌웨어(.gbl) 선택',
      type: FileType.any,
      withData: !Platform.isWindows,
    );
    final f = result?.files.single;
    if (f == null) return;
    if (!f.name.toLowerCase().endsWith('.gbl')) {
      _snack('.gbl 파일을 선택하세요 (선택: ${f.name})');
      return;
    }
    final bytes = f.bytes ?? await File(f.path!).readAsBytes();
    if (!mounted) return;
    setState(() {
      _gblName = p.basename(f.name);
      _gbl = bytes;
    });
  }

  Future<void> _ota(TagState tags, BleTag t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('태그 펌웨어 업데이트'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t.name.isEmpty ? t.mac : t.name} (${t.mac})에\n$_gblName 을(를) 기록합니다.',
            ),
            const SizedBox(height: 12),
            _holdButtonBanner(done: false),
            const SizedBox(height: 12),
            Text(
              '${t.via == null ? '진행 중에는 태그를 멀리 옮기지 마세요' : '로케이터 ${t.via!.name}이(가) 업데이트합니다 — 태그를 그 로케이터 근처에 두세요'}'
              ' (약 1~2분).\n'
              '중단되면 태그가 업데이트 모드로 남으며, 다시 검색해 이어서 할 수 있습니다.',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('업데이트'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _otaError = null;
      _progress = const OtaProgress('준비 중', 0);
    });
    try {
      final fw = await tags.otaUpdate(t.mac, _gbl!, (pr) {
        if (mounted) setState(() => _progress = pr);
      });
      _snack(fw.isEmpty ? '전송 완료 — 새 버전은 [상태 읽기]로 확인하세요' : '업데이트 완료 · FW $fw');
      _info.remove(t.mac);
    } catch (e) {
      if (mounted) {
        setState(() {
          _otaError = '업데이트 실패: $e';
          _progress = null;
        });
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
