// 文件: lib/src/features/notes/view_model/view_model_providers.dart
// 作用: 笔记页 ViewModel 的 Provider（手写，不与 generator part 文件混放）。
//       providers.dart 手写 appDatabase/noteRepository/subjectRepository；
//       这里手写带状态的 AsyncNotifierProvider，避开 4.x class-Notifier 注解坑。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../models/note_version.dart';
import 'note_editor_view_model.dart';
import 'note_list_view_model.dart';
import 'note_search_view_model.dart';
import 'note_version_view_model.dart';
import 'subject_manage_view_model.dart';
import 'subject_scope_picker_view_model.dart';
import 'subject_tree_view_model.dart';
import 'tag_management_view_model.dart';
import 'tag_search_view_model.dart';

/// 笔记列表 ViewModel Provider（保留，第3批 UI 改用 B1 树，此 Provider 暂备用）。
final noteListVmProvider = AsyncNotifierProvider<NoteListVm, List<Note>>(
  NoteListVm.new,
);

/// 笔记编辑器 ViewModel Provider（普通 AsyncNotifier，arg 经 init() 传入）。
final noteEditorVmProvider =
    AsyncNotifierProvider<NoteEditorVm, NoteEditorState>(NoteEditorVm.new);

/// 单条笔记历史版本 ViewModel Provider；按 noteId 隔离并随页面销毁。
final noteVersionVmProvider = AsyncNotifierProvider.autoDispose
    .family<NoteVersionVm, List<NoteVersion>, String>(NoteVersionVm.new);

/// B1 笔记分级树 ViewModel Provider（书-章-节-笔记嵌套树 + 未分类组）。
final subjectTreeVmProvider =
    AsyncNotifierProvider<SubjectTreeVm, SubjectTreeState>(SubjectTreeVm.new);

/// 学科管理 ViewModel Provider（我的tab 学科管理入口）。
final subjectManageVmProvider =
    AsyncNotifierProvider<SubjectManageVm, SubjectManageState>(
      SubjectManageVm.new,
    );

/// 标签管理页 ViewModel Provider。
final tagManagementVmProvider =
    AsyncNotifierProvider<TagManagementVm, TagManagementState>(
      TagManagementVm.new,
      retry: (_, _) => null,
    );

/// 单条笔记标签 Provider；按 noteId 隔离并随使用方销毁。
final noteTagsVmProvider = AsyncNotifierProvider.autoDispose
    .family<NoteTagsVm, NoteTagsState, String>(
      NoteTagsVm.new,
      retry: (_, _) => null,
    );

/// 笔记搜索条件与结果 ViewModel Provider。
final noteSearchVmProvider =
    AsyncNotifierProvider.autoDispose<NoteSearchVm, NoteSearchState>(
      NoteSearchVm.new,
      retry: (_, _) => null,
    );

/// 标签搜索页面会话；退出页面后销毁全部搜索条件。
final tagSearchVmProvider =
    AsyncNotifierProvider.autoDispose<TagSearchVm, TagSearchState>(
      TagSearchVm.new,
      retry: (_, _) => null,
    );

/// 搜索范围弹窗会话；sessionKey 隔离每次打开并在关闭后自动销毁。
final subjectScopePickerVmProvider = AsyncNotifierProvider.autoDispose
    .family<SubjectScopePickerVm, SubjectScopePickerState, Object>(
      SubjectScopePickerVm.new,
      retry: (_, _) => null,
    );
