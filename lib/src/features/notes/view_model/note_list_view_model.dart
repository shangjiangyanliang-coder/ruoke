// 文件: lib/src/features/notes/view_model/note_list_view_model.dart
// 作用: 笔记列表页 ViewModel（手写 AsyncNotifier，不走 generator 以避开 4.x 注解坑）。
//       进入页面即拉全部笔记，提供新建/删除动作并刷新本地状态。View 只 watch 此 Provider。
//       详见技术方案 A §4.2。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/result.dart';
import '../models/note.dart';
import '../note_constants.dart';
import '../providers.dart';

/// 笔记列表 ViewModel（手写 AsyncNotifier）。
class NoteListVm extends AsyncNotifier<List<Note>> {
  @override
  Future<List<Note>> build() async => _list();

  /// 拉"全部未软删笔记"列表，把 Result 翻成数据/异常。
  Future<List<Note>> _list() async {
    final r = await ref.read(noteRepositoryProvider).listAll();
    // 注意：此处不用 switch 模式匹配（Dart 3.12.2 analyzer bug，见
    //   note_editor_view_model.dart 同名注释），用 if-else 规避。
    if (r is Success<List<Note>>) {
      return r.value;
    }
    throw (r as Failure<List<Note>>).exception;
  }

  /// 新建一条空草稿笔记，返回新 id（供路由跳编辑器）。
  Future<String> createEmpty() async {
    final r = await ref.read(noteRepositoryProvider).create(
          subjectId: defaultSubjectId,
          title: null,
          contentJson: null,
          isDraft: true,
        );
    if (r is Success<String>) {
      final id = r.value;
      // 刷新列表
      state = AsyncData(await _list());
      return id;
    }
    throw (r as Failure<String>).exception;
  }

  /// 软删某笔记并从本地状态移除。
  Future<void> softDelete(String id) async {
    final r = await ref.read(noteRepositoryProvider).softDelete(id);
    if (r is Success) {
      state = AsyncData(
        (state.value ?? []).where((n) => n.id != id).toList(),
      );
    } else {
      throw (r as Failure).exception;
    }
  }

  /// 手动刷新（编辑器保存返回后调用）。
  Future<void> refresh() async {
    state = await AsyncValue.guard(_list);
  }
}
