// 文件: lib/src/features/notes/view_model/subject_tree_view_model.dart
// 作用: B1 笔记分级浏览页 ViewModel（手写 AsyncNotifier，不走 generator）。
//       build() 拉全部科目 + 全部未软删笔记，在内存构造「书→章→节→笔记」嵌套树。
//       一并返回挂"未分类"(subjectId=占位兜底)的笔记组。
//       View watch 此 Provider 渲染 B1 树。详见技术方案 A §4.2 + 线框图 B1。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/result.dart';
import '../models/note.dart';
import '../models/subject.dart';
import '../note_constants.dart';
import '../providers.dart';

/// 树节点：科目 + 子节点 + 直接挂在该节点的笔记（不区分这部分挂整本/整章/整节）。
class SubjectTreeNode {
  final Subject subject;

  /// 子节点（章下的节、书下的章）。节级节点为空。
  final List<SubjectTreeNode> children;

  /// 直接挂在本节点的笔记（subjectId == 本节点 id）。
  /// 注：B1 线框支持「整章/整本笔记」，即笔记 subjectId 可指向书或章节点，
  ///     所以书/章节点也可能有 notes。本批先如实按 subjectId 分组，不额外处理语义。
  final List<Note> notes;

  const SubjectTreeNode({
    required this.subject,
    this.children = const [],
    this.notes = const [],
  });
}

/// B1 树整体状态：书级树根列表 + 未分类笔记组 + 折叠态（ViewModel 持有，跨 tab 保）。
class SubjectTreeState {
  /// 书级节点（level0）的树，每棵含其章/节子树。
  final List<SubjectTreeNode> books;

  /// 未分类笔记（subjectId == defaultSubjectId 或指向不存在的科目）。
  final List<Note> uncategorized;

  /// 当前展开的科目节点 id 集合（不在集合里=折叠）。切 tab 不重建时保留。
  final Set<String> expandedIds;

  /// 未分类笔记组是否展开。
  final bool uncategorizedExpanded;

  const SubjectTreeState({
    this.books = const [],
    this.uncategorized = const [],
    this.expandedIds = const {},
    this.uncategorizedExpanded = true,
  });

  SubjectTreeState copyWith({
    List<SubjectTreeNode>? books,
    List<Note>? uncategorized,
    Set<String>? expandedIds,
    bool? uncategorizedExpanded,
  }) => SubjectTreeState(
    books: books ?? this.books,
    uncategorized: uncategorized ?? this.uncategorized,
    expandedIds: expandedIds ?? this.expandedIds,
    uncategorizedExpanded: uncategorizedExpanded ?? this.uncategorizedExpanded,
  );
}

/// B1 笔记分级树 ViewModel（手写 AsyncNotifier）。
class SubjectTreeVm extends AsyncNotifier<SubjectTreeState> {
  @override
  Future<SubjectTreeState> build() async => _load();

  /// 拉科目全量 + 笔记全量，构造嵌套树。
  /// 刷新时保留已有折叠态（expandedIds / uncategorizedExpanded）。
  Future<SubjectTreeState> _load() async {
    final sRepo = ref.read(subjectRepositoryProvider);
    final nRepo = ref.read(noteRepositoryProvider);

    final sResult = await sRepo.listAll();
    final nResult = await nRepo.listAll();

    final List<Subject> subjects;
    if (sResult is Success<List<Subject>>) {
      subjects = sResult.value;
    } else {
      throw (sResult as Failure<List<Subject>>).exception;
    }
    final List<Note> notes;
    if (nResult is Success<List<Note>>) {
      notes = nResult.value;
    } else {
      throw (nResult as Failure<List<Note>>).exception;
    }

    final tree = _buildTree(subjects, notes);
    // 保留上次的折叠态；首次加载（无先前 state）用默认展开全部书级节点
    final prev = state.value;
    final Set<String> expanded;
    final bool uncategorizedExpanded;
    if (prev != null) {
      expanded = prev.expandedIds;
      uncategorizedExpanded = prev.uncategorizedExpanded;
    } else {
      // 首次：默认展开所有书级节点，让用户一眼看到章
      expanded = tree.books.map((b) => b.subject.id).toSet();
      uncategorizedExpanded = true;
    }
    return SubjectTreeState(
      books: tree.books,
      uncategorized: tree.uncategorized,
      expandedIds: expanded,
      uncategorizedExpanded: uncategorizedExpanded,
    );
  }

  /// 切换某科目节点展开/折叠。
  void toggleExpand(String subjectId) {
    final cur = state.value;
    if (cur == null) return;
    final next = Set<String>.from(cur.expandedIds);
    if (next.contains(subjectId)) {
      next.remove(subjectId);
    } else {
      next.add(subjectId);
    }
    state = AsyncData(cur.copyWith(expandedIds: next));
  }

  /// 切换"未分类"笔记组展开/折叠。
  void toggleUncategorized() {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(
      cur.copyWith(uncategorizedExpanded: !cur.uncategorizedExpanded),
    );
  }

  /// 把扁平 subjects + notes 构造成嵌套树。
  SubjectTreeState _buildTree(List<Subject> subjects, List<Note> notes) {
    // 有效 subject id 集合，用于把"指向不存在科目"的笔记也算未分类。
    final validIds = subjects.map((s) => s.id).toSet();

    // 笔记按 subjectId 分组。
    final notesBySubject = <String, List<Note>>{};
    final uncategorized = <Note>[];
    for (final n in notes) {
      if (n.subjectId == defaultSubjectId || !validIds.contains(n.subjectId)) {
        uncategorized.add(n);
      } else {
        notesBySubject.putIfAbsent(n.subjectId, () => []).add(n);
      }
    }

    // 按 parentId 索引子节点，便于递归构造。
    final byParent = <String?, List<Subject>>{};
    for (final s in subjects) {
      byParent.putIfAbsent(s.parentId, () => []).add(s);
    }
    // parentId 在 child 列表里的已按 sortOrder 升序（listAll 已排序），保持。

    SubjectTreeNode buildNode(Subject s) {
      final children = (byParent[s.id] ?? const <Subject>[])
          .map(buildNode)
          .toList();
      return SubjectTreeNode(
        subject: s,
        children: children,
        notes: notesBySubject[s.id] ?? const <Note>[],
      );
    }

    final books = (byParent[null] ?? const <Subject>[])
        .where((s) => s.level == 0)
        .map(buildNode)
        .toList();

    return SubjectTreeState(books: books, uncategorized: uncategorized);
  }

  /// 手动刷新（编辑器保存返回后调用）。
  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  /// 软删某笔记并刷新树（树行删除按钮调）。
  Future<void> softDeleteNote(String noteId) async {
    final r = await ref.read(noteRepositoryProvider).softDelete(noteId);
    if (r is! Success) {
      // 删除失败不静默，靠 Result 失败时丢弃异常信息（MVP 阶段上层先不弹错）
      return;
    }
    await refresh();
  }
}
