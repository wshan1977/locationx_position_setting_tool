import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/session_storage.dart';
import '../state/app_state.dart';
import 'password_gate.dart';
import 'save_dialog.dart';

/// 상단 툴바: 프로젝트 관리 / 도면 / 보정 / 서버 전송.
class AppToolbar extends StatelessWidget {
  const AppToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Material(
      elevation: 2,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _btn(Icons.note_add_outlined, '새 프로젝트',
                () => _guardDirty(context, app, app.newProject)),
            _btn(Icons.folder_open, '프로젝트 열기',
                () => _guardDirty(context, app, () => _open(context, app))),
            _btn(Icons.save, '프로젝트 저장', () => app.saveProject()),
            _btn(Icons.save_as, '다른 이름으로 저장',
                () => app.saveProject(saveAs: true)),
            const VerticalDivider(width: 16, indent: 10, endIndent: 10),
            _btn(Icons.undo, '실행 취소 (Ctrl+Z)',
                app.canUndo ? () => app.undo() : null),
            _btn(Icons.redo, '다시 실행 (Ctrl+Y)',
                app.canRedo ? () => app.redo() : null),
            const VerticalDivider(width: 16, indent: 10, endIndent: 10),
            _btn(Icons.image, '도면 불러오기', () => _loadImage(context, app)),
            _modeBtn(
                Icons.open_with,
                '도면 이동/크기 조정 (배치는 고정)',
                app.canvasMode == CanvasMode.adjustImage,
                app.floorImage == null
                    ? null
                    : () => app.setCanvasMode(
                        app.canvasMode == CanvasMode.adjustImage
                            ? CanvasMode.normal
                            : CanvasMode.adjustImage)),
            _btn(
                Icons.hide_image_outlined,
                '도면 삭제',
                app.floorImage == null && app.floorImagePath == null
                    ? null
                    : () => app.removeFloorImage()),
            _modeBtn(
                Icons.straighten,
                '스케일 보정 (2점)',
                app.canvasMode == CanvasMode.calibrateP1 ||
                    app.canvasMode == CanvasMode.calibrateP2,
                app.floorImage == null
                    ? null
                    : () => app.setCanvasMode(
                        app.canvasMode == CanvasMode.calibrateP1 ||
                                app.canvasMode == CanvasMode.calibrateP2
                            ? CanvasMode.normal
                            : CanvasMode.calibrateP1)),
            _modeBtn(
                Icons.my_location,
                '원점 설정',
                app.canvasMode == CanvasMode.setOrigin,
                () => app.setCanvasMode(app.canvasMode == CanvasMode.setOrigin
                    ? CanvasMode.normal
                    : CanvasMode.setOrigin)),
            const Spacer(),
            _autoSaveIndicator(context),
            if (app.projectPath != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${app.projectPath!.split(RegExp(r'[\\/]')).last}'
                  '${app.dirty ? ' *' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              )
            else if (app.dirty)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text('(저장 안 됨) *',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            FilledButton.icon(
              onPressed: () async {
                final ok = await confirmSettingsPassword(context, '서버로 전송');
                if (ok && context.mounted) showPushToServerDialog(context);
              },
              icon: const Icon(Icons.cloud_upload, size: 18),
              label: const Text('서버로 전송'),
            ),
          ],
        ),
      ),
    );
  }

  /// 자동 저장 상태 표시: 마지막 세션 기록 시각.
  Widget _autoSaveIndicator(BuildContext context) {
    final saver = context.watch<SessionAutoSaver>();
    final t = saver.lastSavedAt;
    final text = t == null
        ? '자동 저장 켜짐'
        : '자동 저장됨 ${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}:'
            '${t.second.toString().padLeft(2, '0')}';
    return Tooltip(
      message: '작업 상태(도면·배치·서버 IP·MQTT 설정)는 변경 후 1초 뒤 자동 저장되어\n'
          '다음 실행 때 그대로 복원됩니다. 프로젝트 파일 저장과는 별개입니다.',
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_done_outlined,
                size: 15, color: Colors.teal.shade600),
            const SizedBox(width: 4),
            Text(text,
                style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  /// 캔버스 클릭 모드를 켜는 토글 버튼: 활성 상태를 주황 배경으로 표시한다
  /// (캔버스의 모드 안내 배너와 같은 색). 다시 누르면 모드가 꺼진다.
  Widget _modeBtn(
      IconData icon, String tooltip, bool active, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: active ? '$tooltip — 편집 중, 클릭하면 종료' : tooltip,
      isSelected: active,
      onPressed: onPressed,
      style: active
          ? IconButton.styleFrom(
              backgroundColor: Colors.orange.shade200,
              foregroundColor: Colors.deepOrange.shade900,
            )
          : null,
    );
  }

  Future<void> _guardDirty(
      BuildContext context, AppState app, VoidCallback action) async {
    if (app.dirty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('저장되지 않은 변경'),
          content: const Text('현재 작업에 저장되지 않은 변경이 있습니다.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('취소')),
            TextButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: const Text('버리기')),
            FilledButton(
                onPressed: () => Navigator.pop(context, 'save'),
                child: const Text('저장 후 계속')),
          ],
        ),
      );
      if (choice == 'cancel' || choice == null) return;
      if (choice == 'save') {
        final saved = await app.saveProject();
        if (!saved) return;
      }
    }
    action();
  }

  Future<void> _open(BuildContext context, AppState app) async {
    try {
      final missingImage = await app.openProject();
      if (missingImage != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('도면 이미지를 찾을 수 없습니다: $missingImage\n'
              '[도면 불러오기]로 다시 선택하세요.'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('프로젝트 열기 실패: $e')));
      }
    }
  }

  Future<void> _loadImage(BuildContext context, AppState app) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '도면 이미지 선택',
      type: FileType.image,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      await app.loadFloorImage(path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('이미지 로드 실패: $e')));
      }
    }
  }
}
