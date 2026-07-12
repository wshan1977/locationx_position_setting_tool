import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 카드 소프트웨어 업데이트(재배포) 지원.
///
/// PC의 IaC 저장소(locationx_locator_config / locationx_position_server_config)에서
/// 최신 태그(= 배포될 버전)를 읽어 카드의 설치 버전(discover ver)과 비교하고,
/// Git Bash로 `provision.sh <IP>`를 실행해 재배포한다
/// (deploy_locator.ps1 / deploy_position_server.ps1과 동일한 경로).
class DeployService {
  static const locatorRepo = 'locationx_locator_config';
  static const serverRepo = 'locationx_position_server_config';

  static String repoNameFor({required bool isServer}) =>
      isServer ? serverRepo : locatorRepo;

  /// provision.sh가 있는 git 저장소인지 확인.
  static bool isRepoDir(String dir) =>
      File(p.join(dir, 'provision.sh')).existsSync() &&
      Directory(p.join(dir, '.git')).existsSync();

  // ── 저장소 경로 찾기 ─────────────────────────────────────
  // 수동 지정 경로는 %APPDATA%\LocationXPositionTool\deploy_repos.json에 기억한다
  // (도구 zip을 저장소와 무관한 위치에 풀어 쓰는 경우용).

  static File? _configFile() {
    final base = Platform.environment['APPDATA'];
    if (base == null) return null;
    return File(p.join(base, 'LocationXPositionTool', 'deploy_repos.json'));
  }

  static Future<Map<String, String>> _loadSaved() async {
    try {
      final f = _configFile();
      if (f == null || !f.existsSync()) return {};
      final json = jsonDecode(await f.readAsString());
      if (json is! Map) return {};
      return json.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveRepoPath(String repoName, String path) async {
    try {
      final f = _configFile();
      if (f == null) return;
      final saved = await _loadSaved();
      saved[repoName] = path;
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(saved));
    } catch (_) {
      // 기억 실패는 치명적이지 않음 (다음에 다시 물어봄)
    }
  }

  /// 수동 지정 경로 → 실행 파일/현재 폴더의 상위 방향 탐색 순으로 저장소를 찾는다.
  /// (개발 실행·릴리즈 zip을 저장소 옆에 푼 경우 모두 커버)
  static Future<String?> findRepo(String repoName) async {
    final saved = await _loadSaved();
    final s = saved[repoName];
    if (s != null && isRepoDir(s)) return s;

    final starts = <String>{
      Directory.current.path,
      p.dirname(Platform.resolvedExecutable),
    };
    for (final start in starts) {
      var dir = start;
      for (var i = 0; i < 8; i++) {
        final cand = p.join(dir, repoName);
        if (isRepoDir(cand)) return cand;
        final parent = p.dirname(dir);
        if (parent == dir) break;
        dir = parent;
      }
    }
    return null;
  }

  // ── 버전 ─────────────────────────────────────────────────

  /// 저장소의 최신 태그 = provision.sh가 배포할 버전 (없으면 null).
  static Future<String?> latestTag(String repoDir) async {
    try {
      final r = await Process.run(
        'git',
        ['-C', repoDir, 'tag', '--sort=-v:refname'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (r.exitCode != 0) return null;
      final tags = (r.stdout as String)
          .split(RegExp(r'\r?\n'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty);
      return tags.isEmpty ? null : tags.first;
    } catch (_) {
      return null; // git 미설치 등
    }
  }

  /// 비교용 정규화: "v1.0.2 " → "1.0.2". unknown/빈 값은 빈 문자열.
  static String normalizeVer(String v) {
    var s = v.trim().toLowerCase();
    if (s == 'unknown') return '';
    if (s.startsWith('v')) s = s.substring(1);
    return s;
  }

  // ── 실행 ─────────────────────────────────────────────────

  /// Git for Windows의 bash.exe 경로 (WSL bash가 아닌 것).
  static Future<String?> findGitBash() async {
    final env = Platform.environment;
    final candidates = [
      p.join(env['ProgramFiles'] ?? r'C:\Program Files', 'Git', 'bin',
          'bash.exe'),
      p.join(env['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)', 'Git',
          'bin', 'bash.exe'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    // PATH의 git(…\Git\cmd\git.exe)에서 …\Git\bin\bash.exe 유추
    try {
      final r = await Process.run('where', ['git']);
      if (r.exitCode == 0) {
        for (final line in (r.stdout as String).split(RegExp(r'\r?\n'))) {
          final gitExe = line.trim();
          if (gitExe.isEmpty) continue;
          final bash =
              p.join(p.dirname(p.dirname(gitExe)), 'bin', 'bash.exe');
          if (File(bash).existsSync()) return bash;
        }
      }
    } catch (_) {}
    return null;
  }

  /// `bash provision.sh <ip>` 시작 — 재배포 (키 등록된 카드 전제).
  static Future<Process> startProvision(
    String bashPath,
    String repoDir,
    String ip,
  ) {
    return Process.start(
      bashPath,
      ['provision.sh', ip],
      workingDirectory: repoDir,
    );
  }
}
