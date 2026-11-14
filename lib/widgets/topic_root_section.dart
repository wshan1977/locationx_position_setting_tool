import 'package:flutter/material.dart';

import '../services/config_api_client.dart';
import 'password_gate.dart';

/// 서버 카드의 고객용 토픽 이름(루트) 설정 — 고객 시스템이 구독하는
/// `<루트>/aoa/position/...`, `<루트>/aoa/angle/...`의 맨 앞 이름 (기본 controlbit).
/// 업체·데모마다 다르게 쓸 수 있다. 바꾸면 서버 브로커가 재시작된다 (서버 v2.8.0+).
class TopicRootSection extends StatefulWidget {
  final String serverIp;
  const TopicRootSection({super.key, required this.serverIp});

  @override
  State<TopicRootSection> createState() => _TopicRootSectionState();
}

class _TopicRootSectionState extends State<TopicRootSection> {
  final _ctrl = TextEditingController();
  String _current = '';
  String _message = '';
  bool _busy = false;
  bool _supported = true;

  static final _valid = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

  ConfigApiClient get _client => ConfigApiClient(widget.serverIp);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final r = await _client.fetchTopicRoot();
      if (!mounted) return;
      setState(() {
        _current = r;
        _ctrl.text = r;
        _supported = true;
        _message = '';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _supported = false;
          _message = '서버 카드 소프트웨어 v2.8.0 이상에서 설정할 수 있습니다 (현재 고정: controlbit)';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final v = _ctrl.text.trim();
    if (!_valid.hasMatch(v) || v == 'silabs') {
      setState(() => _message = '영문·숫자·-·_ 1~32자로 입력하세요');
      return;
    }
    if (v == _current) {
      setState(() => _message = '변경 없음');
      return;
    }
    final ok = await confirmSettingsPassword(context, '고객용 토픽 이름 변경');
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _message = '적용 중... (서버 브로커 재시작 — 로케이터·위치 계산은 몇 초 뒤 자동 재접속)';
    });
    try {
      await _client.pushTopicRoot(v);
      if (!mounted) return;
      setState(() {
        _current = v;
        _message = '적용됨 — 고객 시스템은 이제 $v/# 를 구독합니다. 이 도구의 MQTT도 다시 연결하세요.';
      });
    } catch (e) {
      if (mounted) setState(() => _message = '적용 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final root = _ctrl.text.trim().isEmpty ? 'controlbit' : _ctrl.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              enabled: _supported && !_busy,
              decoration: const InputDecoration(
                labelText: '토픽 이름 (루트)',
                hintText: 'controlbit',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: (!_supported || _busy) ? null : _apply,
            child: const Text('적용'),
          ),
        ]),
        const SizedBox(height: 6),
        SelectableText(
          '고객 구독 토픽: $root/aoa/position/<그룹ID>/<태그>  ·  $root/aoa/angle/<로케이터>/<태그>',
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
        ),
        if (_message.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(_message, style: const TextStyle(fontSize: 11.5)),
        ],
      ],
    );
  }
}
