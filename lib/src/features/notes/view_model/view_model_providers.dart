// 文件: lib/src/features/notes/view_model/view_model_providers.dart
// 作用: 两个笔记页 ViewModel 的 Provider（手写，不与 generator part 文件混放）。
//       providers.dart 手写 appDatabase/noteRepository；
//       这里手写带状态的 AsyncNotifierProvider，避开 4.x class-Notifier 注解坑。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import 'note_editor_view_model.dart';
import 'note_list_view_model.dart';

/// 笔记列表 ViewModel Provider。
final noteListVmProvider =
    AsyncNotifierProvider<NoteListVm, List<Note>>(NoteListVm.new);

/// 笔记编辑器 ViewModel Provider（普通 AsyncNotifier，arg 经 init() 传入）。
final noteEditorVmProvider =
    AsyncNotifierProvider<NoteEditorVm, NoteEditorState>(NoteEditorVm.new);
