import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/deploy_service.dart';

/// 카드 소프트웨어 업데이트(재배포) 진행 다이얼로그.
/// provision.sh 출력을 실시간 로그로 보여주고 완료/실패를 표시한다.
/// 성공 시 true, 실패 시 false, 사용자가 중단하면 null을 돌려준다.
Future<bool?> showCardUpdateDialog(
  BuildContext context, {
  required String deviceLabel,
  required String ip,
  required String repoDir,
  required String bashPath,
  required String tag,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _UpdateDialog(
      deviceLabel: deviceLabel,
      ip: ip,
      repoDir: repoDir,
      bashPath: bashPath,
      tag: tag,
    ),
  );
}

class _UpdateDialog extends StatefulWidget {
  final String deviceLabel;
  final String ip;
  final String repoDir;
  final String bashPath;
  final String tag;

  const _UpdateDialog({
    required this.deviceLabel,
    required this.ip,
    required this.repoDir,
    required this.bashPath,
    required this.tag,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  static final _ansi = RegExp('\x1B\\[[0-9;]*[A-Za-z]');

  final _lines = <String>[];
  final _scroll = ScrollController();
  String _current = ''; // \r 진행 바가 덮어쓰는 마지막 줄
  Process? _proc;
  int? _exitCode;

  bool get _running => _exitCode == null;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _proc?.kill();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final proc = await DeployService.startProvision(
        widget.bashPath,
        widget.repoDir,
        widget.ip,
      );
      _proc = proc;
      const dec = Utf8Decoder(allowMalformed: true);
      proc.stdout.transform(dec).listen(_append);
      proc.stderr.transform(dec).listen(_append);
      final code = await proc.exitCode;
      if (!mounted) return;
      setState(() {
        _flushCurrent();
        _exitCode = code;
        if (code != 0) {
          _lines.add('');
          _lines.add('✗ 실패 (exit $code) — 카드 전원/네트워크를 확인하세요. '
              'SSH 키가 등록되지 않은 새 카드는 저장소의 provision.bat으로 최초 구축해야 합니다.');
        }
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _exitCode = -1;
        _lines.add('실행 실패: $e');
      });
    }
  }

  /// provision.sh 출력 반영 — ANSI 색은 제거하고,
  /// \r(update.sh --quiet의 한 줄 진행 바)은 마지막 줄 덮어쓰기로 처리한다.
  void _append(String chunk) {
    if (!mounted) return;
    setState(() {
      for (final ch in chunk.replaceAll(_ansi, '').split('')) {
        if (ch == '\n') {
          _lines.add(_current);
          _current = '';
        } else if (ch == '\r') {
          _current = '';
        } else {
          _current += ch;
        }
      }
    });
    _scrollToEnd();
  }

  void _flushCurrent() {
    if (_current.isNotEmpty) {
      _lines.add(_current);
      _current = '';
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _abort() {
    _proc?.kill();
    Navigator.pop(context, null);
  }

  @override
  Widget build(BuildContext context) {
    final ok = _exitCode == 0;
    final text =
        [..._lines, if (_current.isNotEmpty) _current].join('\n');

    return AlertDialog(
      title: Row(
        children: [
          if (_running)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              ok ? Icons.check_circle : Icons.error,
              color: ok ? Colors.green : Colors.red,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _running
                  ? '업데이트 중 — ${widget.deviceLabel} (${widget.ip}) → ${widget.tag}'
                  : ok
                      ? '업데이트 완료 — ${widget.deviceLabel} (${widget.tag})'
                      : '업데이트 실패 — ${widget.deviceLabel} (${widget.ip})',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        height: 400,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
          ),
          child: SingleChildScrollView(
            controller: _scroll,
            child: Align(
              alignment: Alignment.topLeft,
              child: SelectableText(
                text.isEmpty ? '시작하는 중...' : text,
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12,
                  color: Color(0xFFDDDDDD),
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (_running)
          TextButton(
            onPressed: _abort,
            child: const Text('중단'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(context, ok),
            child: const Text('닫기'),
          ),
      ],
    );
  }
}
