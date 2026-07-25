// 文件: lib/src/features/notes/view_model/note_editor_view_model.dart
// 作用: 笔记编辑器页 ViewModel（手写 AsyncNotifier，避开 4.x generator 注解坑与 3.x family 复杂度）。
//       build() 返回"待 init"的初始态；View 拿到 VM 后调 init(noteId) 加载：
//       'new' 走新建草稿、其它 id 走加载。维护标题与"未保存"脏标记，
//       save（把 Delta JSON 交 Repository，触发版本快照）与 delete。
//       QuillController 由 View 持有、序列化成 contentJson 后传入 save。
//       详见技术方案 A §4.2。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/result.dart';
import '../models/note.dart';
import '../note_constants.dart';
import '../providers.dart';

/// 编辑器状态：当前编辑的笔记 + 是否有未保存改动。
class NoteEditorState {
  /// null=尚未 init 或新建草稿态
  final Note? note;

  /// 是否有未保存改动
  final bool dirty;

  /// 是否新建态（noteId == 'new'）
  final bool isNew;

  /// 是否已加载完成（build 初始为 false，init 完成后 true）
  final bool ready;

  /// 新建时归属的科目节点 id（由 FAB 定级窗传入；'new' 态用）。
  /// null 则回退 defaultSubjectId（未分类）。
  final String? subjectId;

  const NoteEditorState({
    this.note,
    this.dirty = false,
    this.isNew = false,
    this.ready = false,
    this.subjectId,
  });

  NoteEditorState copyWith(
          {Note? note,
          bool? dirty,
          bool? isNew,
          bool? ready,
          String? subjectId}) =>
      NoteEditorState(
        note: note ?? this.note,
        dirty: dirty ?? this.dirty,
        isNew: isNew ?? this.isNew,
        ready: ready ?? this.ready,
        subjectId: subjectId ?? this.subjectId,
      );
}

/// 笔记编辑器 ViewModel。
class NoteEditorVm extends AsyncNotifier<NoteEditorState> {
  @override
  Future<NoteEditorState> build() async => const NoteEditorState();

  /// View 在 initState 调一次，传 route 的 noteId。新建态可传 subjectId 定级。
  Future<void> init(String noteId, {String? subjectId}) async {
    state = const AsyncLoading<NoteEditorState>();
    try {
      if (noteId == 'new') {
        state = AsyncData(
            NoteEditorState(isNew: true, ready: true, subjectId: subjectId));
        return;
      }
      final r = await ref.read(noteRepositoryProvider).getById(noteId);
      // 注意：此处不用 switch 模式匹配，Dart 3.12.2 对 sealed class 的
      //   exhaustiveness checker 有 analyzer bug，会导致 switch 所在文件 import 的
      //   其它文件全部级联报 uri_does_not_exist / undefined_class。用 if-else 规避。
      final Note? note;
      if (r is Success<Note?>) {
        note = r.value;
      } else {
        throw (r as Failure<Note?>).exception;
      }
      if (note == null) {
        throw StateError('笔记不存在: $noteId');
      }
      state = AsyncData(NoteEditorState(note: note, ready: true));
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  /// 标记有未保存改动。
  void markDirty() {
    final cur = state.value;
    if (cur != null && !cur.dirty) {
      state = AsyncData(cur.copyWith(dirty: true));
    }
  }

  /// 保存。title 与 contentJson 由 View 传入。成功返回 true。
  Future<bool> save({String? title, String? contentJson}) async {
    final cur = state.value;
    if (cur == null || !cur.ready) return false;
    final repo = ref.read(noteRepositoryProvider);
    if (cur.isNew) {
      final r = await repo.create(
        // 新建时用 init 带入的 subjectId，未传则兜底 defaultSubjectId（未分类）
        subjectId: cur.subjectId ?? defaultSubjectId,
        title: title,
        contentJson: contentJson,
        isDraft: false,
      );
      if (r is! Success) return false;
      final id = (r as Success<String>).value;
      final loaded = await repo.getById(id);
      final Note? note;
      if (loaded is Success<Note?>) {
        note = loaded.value;
      } else {
        note = null;
      }
      // 新建后变成"已存"态：保留 isNew=false 以便后续 update 走对分支
      state = AsyncData(NoteEditorState(note: note, ready: true, dirty: false));
      return true;
    }
    final r = await repo.update(
      id: cur.note!.id,
      title: title,
      contentJson: contentJson,
    );
    if (r is Success) {
      state = AsyncData(cur.copyWith(dirty: false));
      return true;
    }
    return false;
  }

  /// 删除当前笔记（软删），返回是否成功。
  Future<bool> delete() async {
    final cur = state.value;
    if (cur == null || cur.isNew || cur.note == null) return false;
    final r = await ref.read(noteRepositoryProvider).softDelete(cur.note!.id);
    return r is Success;
  }
}
