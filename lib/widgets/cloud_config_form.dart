import 'package:flutter/material.dart';

import '../services/config_api_client.dart';
import 'hover_tip.dart';
import 'password_gate.dart';

/// 서버 카드 cloud-agent(외부망 중계) 설정 폼.
/// Locator 설정 탭의 서버 패널과 외부망 테스트 탭의 설정 다이얼로그가 공유한다.
/// /api/cloud 조회 → 활성화·브로커·전송속도 편집 → 저장+적용(비밀번호 확인)
/// 후 에이전트가 생성한 siteId를 다시 읽어 [onApplied]로 알린다.
class CloudConfigForm extends StatefulWidget {
  final String serverIp;

  /// 적용 후 최신 반영본(siteId 포함)을 받는 콜백 (연결란 프리필 등).
  final void Function(Map<String, dynamic> applied)? onApplied;

  const CloudConfigForm({super.key, required this.serverIp, this.onApplied});

  @override
  State<CloudConfigForm> createState() => _CloudConfigFormState();
}

class _CloudConfigFormState extends State<CloudConfigForm> {
  final _host = TextEditingController(text: 'broker.hivemq.com');
  final _port = TextEditingController(text: '1883');
  final _maxHz = TextEditingController(text: '10');
  // 외부 토픽 이름(siteId) — locationx/<siteId>/... · 비우면 서버가 무작위 생성 (데모·업체별 지정)
  final _siteId = TextEditingController();
  bool _enabled = false;
  bool _forwardAngle = false; // 각도 중계 (홈페이지 AOA 데모 · 서버 v2.7.2+)
  bool _acceptCommands = false; // 원격 명령 수신 (서버 v2.7.1+ · 기본 꺼짐)
  String _appliedSiteId = '';
  String _agentActive = '';
  String _message = '';
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _maxHz.dispose();
    _siteId.dispose();
    super.dispose();
  }

  ConfigApiClient get _client => ConfigApiClient(widget.serverIp);

  Future<void> _fetch() async {
    setState(() {
      _busy = true;
      _message = '서버 카드에서 설정 조회 중...';
    });
    try {
      final cloud = await _client.fetchCloud();
      final staged = cloud.staged;
      if (!mounted) return;
      setState(() {
        _host.text = staged['broker_host']?.toString() ?? _host.text;
        _port.text = '${(staged['broker_port'] as num?)?.toInt() ?? 1883}';
        _maxHz.text =
            '${(staged['forward_max_hz'] as num?)?.toInt() ?? 10}';
        _enabled = staged['enabled'] == true;
        _forwardAngle = staged['forward_angle'] == true;
        _acceptCommands = staged['accept_commands'] == true;
        _appliedSiteId = cloud.applied['site_id']?.toString() ?? '';
        _siteId.text = (staged['site_id']?.toString() ?? '').isNotEmpty
            ? staged['site_id'].toString()
            : _appliedSiteId;
        _agentActive = cloud.agentActive;
        _message = '';
        _loaded = true;
        widget.onApplied?.call(cloud.applied);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _message =
            '조회 실패: $e\n서버 카드 소프트웨어 v2.2.0 이상 필요 — 구버전이면 저장소 배포로 업데이트하세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveApply() async {
    final hz = int.tryParse(_maxHz.text.trim());
    if (hz == null || hz < 1 || hz > 100) {
      setState(() => _message = '전송속도는 1~100 Hz 범위로 입력하세요');
      return;
    }
    final site = _siteId.text.trim();
    if (site.isNotEmpty && !RegExp(r'^[A-Za-z0-9_-]{3,40}$').hasMatch(site)) {
      setState(() => _message = '외부 토픽 이름(siteId)은 영문·숫자·-·_ 3~40자');
      return;
    }
    final ok = await confirmSettingsPassword(context, '외부망 중계 설정 변경');
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _message = '저장·적용 중... (siteId 생성에 몇 초 걸림)';
    });
    try {
      await _client.pushCloud({
        'enabled': _enabled,
        'broker_host': _host.text.trim(),
        'broker_port': int.tryParse(_port.text.trim()) ?? 1883,
        'forward_max_hz': hz,
        'forward_angle': _forwardAngle,
        if (site.isNotEmpty) 'site_id': site,
        'accept_commands': _acceptCommands,
      });
      await _client.applyCloud();
      // 에이전트가 반영본 mtime을 감지(5초 주기)해 재접속·siteId 생성 → 재조회
      await Future.delayed(const Duration(seconds: 7));
      if (!mounted) return;
      await _fetch();
      if (!mounted) return;
      setState(() => _message = _appliedSiteId.isEmpty && _enabled
          ? '적용됨 — siteId 생성 대기 중 (몇 초 후 다시 가져오기를 누르세요)'
          : '적용됨');
    } catch (e) {
      if (mounted) setState(() => _message = '적용 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('중계 활성화 (cloud-agent)',
              style: TextStyle(fontSize: 13.5)),
          subtitle: const Text(
              'position 결과·Locator 상태를 외부 브로커로 발행합니다',
              style: TextStyle(fontSize: 11.5)),
          value: _enabled,
          onChanged:
              (_busy || !_loaded) ? null : (v) => setState(() => _enabled = v),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('각도(AOA)도 중계', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text(
              '로케이터별 방위·앙각을 외부로 보냅니다 — 홈페이지 실시간 AOA 데모용 (서버 v2.7.2+)',
              style: TextStyle(fontSize: 11.5)),
          value: _forwardAngle,
          onChanged: (_busy || !_loaded) ? null : (v) => setState(() => _forwardAngle = v),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('원격 명령 허용 (재부팅·재시작·LED)', style: TextStyle(fontSize: 13.5)),
          subtitle: Text(
              _acceptCommands
                  ? '주의: siteId를 아는 사람은 누구나 장비를 재부팅할 수 있습니다 — 홈페이지에 공개하는 동안은 끄세요'
                  : '꺼짐 — 위치·상태만 중계 (홈페이지 공개 데모에 안전)',
              style: TextStyle(
                  fontSize: 11.5, color: _acceptCommands ? Colors.orange.shade800 : null)),
          value: _acceptCommands,
          onChanged: (_busy || !_loaded) ? null : (v) => setState(() => _acceptCommands = v),
        ),
        const SizedBox(height: 8),
        hoverTip(
          '외부 브로커에서 이 현장을 구분하는 이름입니다 — 토픽 locationx/<이 이름>/...\n'
          '데모는 예) controlbit-demo, 업체별은 예) acme-plant1. 비우면 무작위로 만들어집니다.\n'
          '바꾸면 외부망 뷰·홈페이지 데모도 새 이름으로 접속해야 합니다.',
          TextField(
            controller: _siteId,
            enabled: !_busy,
            decoration: const InputDecoration(
                labelText: '외부 토픽 이름 (siteId)',
                hintText: '예) controlbit-demo',
                isDense: true,
                border: OutlineInputBorder()),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _host,
                enabled: !_busy,
                decoration: const InputDecoration(
                    labelText: '외부 브로커 호스트',
                    isDense: true,
                    border: OutlineInputBorder()),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _port,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '포트',
                    isDense: true,
                    border: OutlineInputBorder()),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: hoverTip(
                'position 포워딩 최대 속도 (토픽당 Hz · 1~100).\n'
                '높일수록 외부망 뷰가 부드럽지만 인터넷 업로드 트래픽이 늘어납니다.',
                TextField(
                  controller: _maxHz,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '전송속도 (Hz)',
                      isDense: true,
                      border: OutlineInputBorder()),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('적용된 siteId: ',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
            Expanded(
              child: SelectableText(
                _appliedSiteId.isEmpty ? '(아직 없음)' : _appliedSiteId,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ),
            if (_agentActive.isNotEmpty)
              Text('에이전트: $_agentActive',
                  style: TextStyle(
                      fontSize: 12,
                      color: _agentActive == 'active'
                          ? Colors.green
                          : Colors.red)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '주의: 공개 브로커에서는 siteId를 아는 누구나 위치를 보고 명령을 보낼 수 '
          '있습니다. siteId를 외부에 노출하지 마세요 (테스트 용도).',
          style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
        ),
        if (_message.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(_message,
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _fetch,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('다시 가져오기', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: (_busy || !_loaded) ? null : _saveApply,
              icon: const Icon(Icons.cloud_upload, size: 16),
              label: const Text('저장 + 적용', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }
}
