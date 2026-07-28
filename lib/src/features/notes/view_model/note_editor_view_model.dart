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
import '../models/tag.dart';
import '../note_constants.dart';
import '../providers.dart';

/// 编辑器保存结果：区分成功、空新笔记跳过和真实失败。
enum NoteSaveResult { saved, skippedEmpty, failed }

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

  /// 当前会话是否正在保存，用于阻止重复提交。
  final bool saving;

  /// 新建时归属的科目节点 id（由 FAB 定级窗传入；'new' 态用）。
  /// null 则回退 defaultSubjectId（未分类）。
  final String? subjectId;

  /// 当前编辑会话中的标签草稿；保存前不写数据库。
  final List<String> tagNames;

  const NoteEditorState({
    this.note,
    this.dirty = false,
    this.isNew = false,
    this.ready = false,
    this.saving = false,
    this.subjectId,
    this.tagNames = const [],
  });

  NoteEditorState copyWith({
    Note? note,
    bool? dirty,
    bool? isNew,
    bool? ready,
    bool? saving,
    String? subjectId,
    List<String>? tagNames,
  }) => NoteEditorState(
    note: note ?? this.note,
    dirty: dirty ?? this.dirty,
    isNew: isNew ?? this.isNew,
    ready: ready ?? this.ready,
    saving: saving ?? this.saving,
    subjectId: subjectId ?? this.subjectId,
    tagNames: tagNames ?? this.tagNames,
  );
}

/// 笔记编辑器 ViewModel。
class NoteEditorVm extends AsyncNotifier<NoteEditorState> {
  int _initGeneration = 0;
  int _editRevision = 0;
  int? _savingGeneration;

  @override
  NoteEditorState build() => const NoteEditorState();

  /// View 在 initState 调一次，传 route 的 noteId。新建态可传 subjectId 定级。
  Future<void> init(String noteId, {String? subjectId}) async {
    final generation = ++_initGeneration;
    _editRevision = 0;
    state = const AsyncLoading<NoteEditorState>();
    try {
      if (noteId == 'new') {
        state = AsyncData(
          NoteEditorState(isNew: true, ready: true, subjectId: subjectId),
        );
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
      if (generation != _initGeneration) return;
      if (note == null) {
        throw StateError('笔记不存在: $noteId');
      }
      final tagsResult = await ref
          .read(tagRepositoryProvider)
          .listTagsForNote(noteId);
      if (tagsResult is! Success<List<Tag>>) {
        throw (tagsResult as Failure<List<Tag>>).exception;
      }
      if (generation != _initGeneration) return;
      state = AsyncData(
        NoteEditorState(
          note: note,
          ready: true,
          tagNames: List.unmodifiable(tagsResult.value.map((tag) => tag.name)),
        ),
      );
    } catch (e, s) {
      if (generation == _initGeneration) {
        state = AsyncError(e, s);
      }
    }
  }

  /// 标记有未保存改动。
  void markDirty() {
    final cur = state.value;
    if (cur != null && cur.ready) {
      _editRevision++;
      if (!cur.dirty) {
        state = AsyncData(cur.copyWith(dirty: true));
      }
    }
  }

  /// 只修改标签草稿；真正的标签创建和关联由保存事务完成。
  void addTagName(String name) {
    final cur = state.value;
    if (cur == null || !cur.ready) return;
    final normalized = name.trim();
    if (normalized.isEmpty || cur.tagNames.contains(normalized)) return;
    _editRevision++;
    state = AsyncData(
      cur.copyWith(
        dirty: true,
        tagNames: List.unmodifiable([...cur.tagNames, normalized]),
      ),
    );
  }

  /// 从当前编辑草稿移除标签，不立即修改数据库。
  void removeTagName(String name) {
    final cur = state.value;
    if (cur == null || !cur.ready || !cur.tagNames.contains(name)) return;
    _editRevision++;
    state = AsyncData(
      cur.copyWith(
        dirty: true,
        tagNames: List.unmodifiable(
          cur.tagNames.where((tagName) => tagName != name),
        ),
      ),
    );
  }

  /// 保存标题与正文。新笔记没有任何可见内容时跳过创建。
  Future<NoteSaveResult> save({
    String? title,
    String? contentJson,
    required bool hasVisibleContent,
  }) async {
    final cur = state.value;
    if (cur == null || !cur.ready) return NoteSaveResult.failed;
    final generation = _initGeneration;
    if (_savingGeneration == generation) return NoteSaveResult.failed;
    final hasTitle = title?.trim().isNotEmpty ?? false;
    if (cur.isNew && !hasTitle && !hasVisibleContent) {
      return NoteSaveResult.skippedEmpty;
    }
    final revision = _editRevision;
    _savingGeneration = generation;
    state = AsyncData(cur.copyWith(saving: true));
    final repo = ref.read(noteRepositoryProvider);
    try {
      if (cur.isNew) {
        final r = await repo.create(
          // 新建时用 init 带入的 subjectId，未传则兜底 defaultSubjectId（未分类）
          subjectId: cur.subjectId ?? defaultSubjectId,
          title: title,
          contentJson: contentJson,
          isDraft: false,
          tagNames: cur.tagNames,
        );
        if (r is! Success<Note>) return NoteSaveResult.failed;
        final note = r.value;
        // 保存期间可能已切换编辑对象；旧请求成功也不能覆盖新会话。
        if (generation == _initGeneration) {
          final latest = state.value ?? cur;
          // 新建后必须转为已存态；若保存期间继续编辑，则保留未保存标记。
          state = AsyncData(
            NoteEditorState(
              note: note,
              ready: true,
              dirty: revision != _editRevision,
              tagNames: latest.tagNames,
            ),
          );
        }
        return NoteSaveResult.saved;
      }
      final r = await repo.update(
        id: cur.note!.id,
        title: title,
        contentJson: contentJson,
        tagNames: cur.tagNames,
      );
      if (r is Success && generation == _initGeneration) {
        final current = state.value;
        if (current != null) {
          state = AsyncData(
            current.copyWith(dirty: revision != _editRevision, saving: false),
          );
        }
      }
      return r is Success ? NoteSaveResult.saved : NoteSaveResult.failed;
    } finally {
      if (_savingGeneration == generation) {
        _savingGeneration = null;
      }
      if (generation == _initGeneration) {
        final current = state.value;
        if (current?.saving == true) {
          state = AsyncData(current!.copyWith(saving: false));
        }
      }
    }
  }

  /// 删除当前笔记（软删），返回是否成功。
  Future<bool> delete() async {
    final cur = state.value;
    if (cur == null || cur.isNew || cur.note == null) return false;
    final r = await ref.read(noteRepositoryProvider).softDelete(cur.note!.id);
    return r is Success;
  }
}
