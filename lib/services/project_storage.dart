import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../models/project.dart';

/// .lxpos.json 프로젝트 파일 저장/열기 (네이티브 파일 다이얼로그).
///
/// 데스크톱: saveFile은 경로만 돌려주므로 직접 파일에 쓴다.
/// Android/iOS: saveFile에 bytes를 넘기면 picker가 직접 기록한다.
class ProjectStorage {
  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  Future<String?> pickOpenPath() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '프로젝트 열기',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    return result?.files.single.path;
  }

  Future<ProjectFile> load(String path) async {
    final text = await File(path).readAsString();
    final json = jsonDecode(text);
    if (json is! Map) {
      throw const FormatException('프로젝트 파일 형식이 아닙니다');
    }
    return ProjectFile.fromJson(Map<String, dynamic>.from(json));
  }

  /// 저장 다이얼로그를 띄우고 project를 기록한다. 저장된 경로(취소 시 null).
  Future<String?> saveWithDialog(ProjectFile project,
      {String? suggestedName}) async {
    final text = _encoder.convert(project.toJson());
    final bytes = Uint8List.fromList(utf8.encode(text));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '프로젝트 저장',
      fileName: suggestedName ?? 'positions.${ProjectFile.extension}',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes, // 모바일에서는 picker가 직접 기록
    );
    if (path == null) return null;
    if (!_isMobile) {
      await File(path).writeAsString(text);
    }
    return path;
  }

  /// 이미 알고 있는 경로에 덮어쓰기 (데스크톱 전용 — 모바일은 다이얼로그 사용).
  Future<void> saveTo(String path, ProjectFile project) async {
    await File(path).writeAsString(_encoder.convert(project.toJson()));
  }
}
