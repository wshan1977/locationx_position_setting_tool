import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
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
            _btn(Icons.image, '도면 불러오기', () => _loadImage(context, app)),
            _btn(Icons.straighten, '스케일 보정 (2점)',
                app.floorImage == null
                    ? null
                    : () => app.setCanvasMode(CanvasMode.calibrateP1)),
            _btn(Icons.my_location, '원점 설정',
                () => app.setCanvasMode(CanvasMode.setOrigin)),
            const Spacer(),
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
              onPressed: () => showPushToServerDialog(context),
              icon: const Icon(Icons.cloud_upload, size: 18),
              label: const Text('서버로 전송'),
            ),
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
