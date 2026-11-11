import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 공개 배포 저장소(빌드된 바이너리만, 소스는 비공개) — 175_BDCI ReleaseRepo와 같은 방식.
///   tag/hart/versions.txt          게시된 버전 (최신 순)
///   tag/hart/v/VER/firmware.gbl    OTA 이미지
/// 게시: 태그 펌웨어 저장소 tag_hart/create_bin/publish_release.bat
class ReleaseRepo {
  static const String repo = 'wshan1977/locationx-release';
  static const String _raw = 'https://raw.githubusercontent.com/$repo/main';

  /// Hart 태그 펌웨어 경로.
  static const String hartTag = 'tag/hart';

  static String _fwPath(String kind, String ver) => '$kind/v/$ver/firmware.gbl';

  /// 게시된 버전 목록, 최신 순 ([] = 접속 불가).
  static Future<List<String>> versions(String kind) async {
    final t = await _fetch('$kind/versions.txt');
    if (t == null) return const [];
    return utf8
        .decode(t)
        .split(RegExp(r'\s+'))
        .where((s) => RegExp(r'^\d+\.\d+\.\d+$').hasMatch(s))
        .toList()
      ..sort((a, b) => compare(b, a));
  }

  /// [ver] 펌웨어(.gbl)를 받는다. 실패 시 작업자용 메시지로 throw.
  static Future<Uint8List> firmware(String kind, String ver) async {
    final b = await _fetch(_fwPath(kind, ver), timeout: const Duration(seconds: 60));
    if (b == null) throw '펌웨어 다운로드 실패 (v$ver) — 인터넷 연결을 확인하세요';
    // GBL 파일은 헤더 태그 0x03A617EB(리틀 엔디언)로 시작한다.
    if (b.length < 1024 ||
        !(b[0] == 0xEB && b[1] == 0x17 && b[2] == 0xA6 && b[3] == 0x03)) {
      throw '받은 파일이 태그 펌웨어(.gbl)가 아닙니다';
    }
    return b;
  }

  /// 저장소 파일 1개. GitHub API(저장소 직접 응답) 먼저, 안 되면 raw CDN.
  /// raw CDN은 게시 직후 몇 분간 옛 파일을 주는 경우가 있다(BDCI에서 확인).
  static Future<Uint8List?> _fetch(String path,
      {Duration timeout = const Duration(seconds: 10)}) async {
    return await _get(
          'https://api.github.com/repos/$repo/contents/$path?ref=main',
          {'Accept': 'application/vnd.github.raw'},
          timeout,
        ) ??
        await _get(
          '$_raw/$path?t=${DateTime.now().millisecondsSinceEpoch}',
          const {},
          timeout,
        );
  }

  static Future<Uint8List?> _get(
      String url, Map<String, String> headers, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers
        ..set(HttpHeaders.userAgentHeader, 'locationx-position-tool')
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final out = BytesBuilder(copy: false);
      await for (final c in res.timeout(timeout)) {
        out.add(c);
      }
      return out.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 점 표기 버전 비교 ("1.2.3" vs "1.10.0"); <0, 0, >0.
  static int compare(String a, String b) {
    List<int> p(String v) =>
        v.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }
}
