import 'package:flutter/material.dart';

import '../services/deploy_service.dart';
import 'password_gate.dart';
import 'update_dialog.dart';

/// 카드 소프트웨어 업데이트(재배포) 공통 플로우 — 장치 설정 탭과
/// 외부망 장치 목록에서 함께 쓴다.
///
/// PC 배포 저장소의 최신 태그와 카드 설치 버전을 비교해, 다르면 확인 후
/// Git Bash로 `provision.sh <ip>`를 실행해 재배포한다 (SSH 직접 접속 필요).
/// 재배포가 성공했을 때만 true.
Future<bool> runCardUpdateFlow(
  BuildContext context, {
  required String deviceLabel,
  required String ip,
  required bool isServer,
  required String currentVer,
}) async {
  final repoName = DeployService.repoNameFor(isServer: isServer);
  var repoDir = await DeployService.findRepo(repoName);
  if (!context.mounted) return false;
  repoDir ??= await _askRepoPath(context, repoName);
  if (repoDir == null || !context.mounted) return false;

  final tag = await DeployService.latestTag(repoDir);
  if (!context.mounted) return false;
  if (tag == null) {
    await _info(
      context,
      '업데이트 불가',
      '저장소에서 배포 태그를 찾지 못했습니다.\n'
          '$repoDir\n'
          'git이 설치돼 있고 저장소에 태그(v*)가 있는지 확인하세요.',
    );
    return false;
  }

  // 버전 비교 — 카드 ver(/etc/rpi-config-version)와 저장소 최신 태그
  if (DeployService.normalizeVer(tag) ==
      DeployService.normalizeVer(currentVer)) {
    await _info(
      context,
      '업데이트 확인',
      '이미 최신 버전입니다.\n'
          '카드 $currentVer = 저장소 최신 태그 $tag\n'
          '(같은 버전 강제 재적용은 저장소의 deploy 스크립트에서 --force 사용)',
    );
    return false;
  }

  final bash = await DeployService.findGitBash();
  if (!context.mounted) return false;
  if (bash == null) {
    await _info(
      context,
      '업데이트 불가',
      'Git Bash(bash.exe)를 찾지 못했습니다.\n'
          'Git for Windows가 설치돼 있어야 합니다.',
    );
    return false;
  }

  final curVer = currentVer.isEmpty ? 'unknown' : currentVer;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('소프트웨어 업데이트'),
      content: Text(
        '$deviceLabel ($ip) 카드를 재배포합니다.\n\n'
        '설치 버전: $curVer  →  배포 버전: $tag\n\n'
        '수 분 걸릴 수 있고 진행 중 카드의 서비스가 재시작됩니다. 계속할까요?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('확인'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  // 재배포는 운영 중인 카드를 갈아끼우는 작업 — 설정 변경과 같은 비밀번호 확인
  final pw = await confirmSettingsPassword(context, '소프트웨어 업데이트');
  if (!pw || !context.mounted) return false;

  final success = await showCardUpdateDialog(
    context,
    deviceLabel: deviceLabel,
    ip: ip,
    repoDir: repoDir,
    bashPath: bash,
    tag: tag,
  );
  return success == true;
}

/// 배포 저장소를 자동으로 못 찾았을 때 경로를 직접 입력받는다 (입력값은 기억).
Future<String?> _askRepoPath(BuildContext context, String repoName) async {
  final ctrl = TextEditingController();
  String? error;
  final path = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('배포 저장소 위치'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '이 PC에서 배포 저장소($repoName)를 찾지 못했습니다.\n'
                '저장소 폴더의 전체 경로를 입력하세요 (provision.sh가 있는 폴더).',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: '예: D:\\project\\...\\$repoName',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (!DeployService.isRepoDir(v)) {
                setState(
                  () => error = 'provision.sh가 있는 git 저장소가 아닙니다',
                );
                return;
              }
              Navigator.pop(context, v);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    ),
  );
  if (path != null) await DeployService.saveRepoPath(repoName, path);
  return path;
}

Future<void> _info(BuildContext context, String title, String body) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}
