// 文件: lib/src/features/notes/view_model/note_version_view_model.dart
// 作用: 管理单条笔记的历史版本列表，以及恢复指定版本后的重新加载。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/result.dart';
import '../models/note_version.dart';
import '../providers.dart';

/// 历史版本列表 ViewModel。
class NoteVersionVm extends AsyncNotifier<List<NoteVersion>> {
  final String noteId;

  NoteVersionVm(this.noteId);

  @override
  Future<List<NoteVersion>> build() => _load();

  /// 加载当前笔记的历史版本，按 Repository 返回顺序交给页面显示。
  Future<List<NoteVersion>> _load() async {
    final result = await ref.read(noteRepositoryProvider).listVersions(noteId);
    if (result is Success<List<NoteVersion>>) {
      return result.value;
    }
    throw (result as Failure<List<NoteVersion>>).exception;
  }

  /// 恢复版本并重新加载列表，成功后由页面返回编辑器刷新正文。
  Future<bool> restore({required int versionNo}) async {
    final result = await ref
        .read(noteRepositoryProvider)
        .restoreVersion(noteId: noteId, versionNo: versionNo);
    if (result is Success<void>) {
      try {
        state = AsyncData(await _load());
      } catch (error, stackTrace) {
        state = AsyncError(error, stackTrace);
      }
      return true;
    }
    return false;
  }
}
