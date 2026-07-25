// 文件: lib/src/features/notes/view/note_list_view.dart
// 作用: 笔记分级浏览页（B1，第3批）。书→章→节→笔记 四级可折叠树
//       （章/节可省以支持整本/整章笔记）。底部「未分类」组挂占位 subjectId 笔记。
//       FAB 新建弹定级窗（subject_picker_dialog）。点叶/笔记行进编辑器。
//       折叠态由 SubjectTreeVm 持有，切 tab 不丢。
//       第4批加历史版本入口、第5批加搜索/标签视图切换。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/note.dart';
import '../models/subject.dart';
import '../view_model/subject_tree_view_model.dart';
import '../view_model/view_model_providers.dart';
import 'subject_picker_dialog.dart';

/// 笔记分级浏览页（B1 书-章-节树）。
class NoteListView extends ConsumerWidget {
  const NoteListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(subjectTreeVmProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () {
              // TODO: 第5批笔记搜索（plain_text LIKE）
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('搜索待第5批开发')));
            },
          ),
        ],
      ),
      body: tree.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('加载失败：$e',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
        data: (state) {
          final totalNotes = state.uncategorized.length +
              state.books.fold<int>(
                  0,
                  (acc, b) =>
                      acc + _countNotesInNode(b) + (b.notes.length));
          if (totalNotes == 0 && state.books.isEmpty) {
            return const _EmptyHint();
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              ...state.books
                  .map((book) => _BookTile(book: book, depth: 0))
                  ,
              if (state.uncategorized.isNotEmpty)
                _UncategorizedTile(
                  notes: state.uncategorized,
                  expanded: state.uncategorizedExpanded,
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建笔记',
        onPressed: () async {
          // FAB 弹定级窗（#9）：选书/章/节，返回 subjectId
          final subjectId = await showSubjectPickerDialog(context, ref);
          if (!context.mounted || subjectId == null) return;
          await context.push(
              '/notes/editor/new?subjectId=$subjectId');
          // 编辑器返回后刷新树
          ref.read(subjectTreeVmProvider.notifier).refresh();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 递归统计某节点子树下的笔记总数（用于书行/章行显示计数，可选）。
  int _countNotesInNode(SubjectTreeNode node) {
    var n = node.notes.length;
    for (final c in node.children) {
      n += _countNotesInNode(c);
    }
    return n;
  }
}

/// 空态占位。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '还没有笔记\n点右下角 + 新建第一条',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// 书级节点（level0）Tile。可折叠展开章。
class _BookTile extends ConsumerWidget {
  final SubjectTreeNode book;
  final int depth;
  const _BookTile({required this.book, required this.depth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subjectTreeVmProvider).value;
    final expanded = state?.expandedIds.contains(book.subject.id) ?? false;
    return Column(
      children: [
        _SubjectRow(
          subject: book.subject,
          depth: depth,
          expanded: expanded,
          hasChildren: book.children.isNotEmpty,
          onTap: () => ref
              .read(subjectTreeVmProvider.notifier)
              .toggleExpand(book.subject.id),
        ),
        if (expanded) ...[
          // 整本书笔记（subjectId 指向书节点，F1.1.6 支持省章-节）
          ...book.notes.map((n) => _NoteRow(note: n, depth: depth + 1)),
          // 章节点
          ...book.children
              .map((ch) => _ChapterTile(chapter: ch, depth: depth + 1)),
        ],
      ],
    );
  }
}

/// 章级节点（level1）Tile。可折叠展开节。
class _ChapterTile extends ConsumerWidget {
  final SubjectTreeNode chapter;
  final int depth;
  const _ChapterTile({required this.chapter, required this.depth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subjectTreeVmProvider).value;
    final expanded =
        state?.expandedIds.contains(chapter.subject.id) ?? false;
    return Column(
      children: [
        _SubjectRow(
          subject: chapter.subject,
          depth: depth,
          expanded: expanded,
          hasChildren: chapter.children.isNotEmpty,
          onTap: () => ref
              .read(subjectTreeVmProvider.notifier)
              .toggleExpand(chapter.subject.id),
        ),
        if (expanded) ...[
          // 整章笔记（subjectId 指向章节点）
          ...chapter.notes.map((n) => _NoteRow(note: n, depth: depth + 1)),
          // 节点（level2，叶，不再折叠）
          ...chapter.children.map((sec) {
            return _SectionTile(section: sec, depth: depth + 1);
          }),
        ],
      ],
    );
  }
}

/// 节级节点（level2，叶）。直接展示其下笔记。
class _SectionTile extends ConsumerWidget {
  final SubjectTreeNode section;
  final int depth;
  const _SectionTile({required this.section, required this.depth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _SubjectRow(
          subject: section.subject,
          depth: depth,
          expanded: false,
          hasChildren: false,
          onTap: null, // 节级叶节点不折叠
        ),
        // 节级下挂的笔记
        ...section.notes.map((n) => _NoteRow(note: n, depth: depth + 1)),
      ],
    );
  }
}

/// 未分类笔记组（挂 defaultSubjectId 或指向不存在科目的遗留笔记）。
class _UncategorizedTile extends ConsumerWidget {
  final List<Note> notes;
  final bool expanded;
  const _UncategorizedTile({required this.notes, required this.expanded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        ListTile(
          dense: true,
          leading: Icon(Icons.category_outlined,
              color: Theme.of(context).hintColor),
          title: Text('未分类 (${notes.length})',
              style: TextStyle(color: Theme.of(context).hintColor)),
          trailing: Icon(expanded
              ? Icons.keyboard_arrow_down
              : Icons.keyboard_arrow_right),
          onTap: () =>
              ref.read(subjectTreeVmProvider.notifier).toggleUncategorized(),
        ),
        if (expanded)
          ...notes.map((n) => _NoteRow(note: n, depth: 1)),
      ],
    );
  }
}

/// 科目行（书/章/节通用）：图标 + 名 + 展开箭头。
class _SubjectRow extends StatelessWidget {
  final Subject subject;
  final int depth; // 缩进层级
  final bool expanded;
  final bool hasChildren;
  final VoidCallback? onTap;

  const _SubjectRow({
    required this.subject,
    required this.depth,
    required this.expanded,
    required this.hasChildren,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = const {0: Icons.menu_book, 1: Icons.bookmark, 2: Icons.article}[subject.level] ??
        Icons.circle;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: 16.0 + depth * 16, top: 8, bottom: 8, right: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subject.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: depth == 0 ? FontWeight.w600 : FontWeight.normal,
                    ),
              ),
            ),
            if (hasChildren)
              Icon(expanded
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right),
          ],
        ),
      ),
    );
  }
}

/// 笔记行：标题 + 摘要。点击进编辑器；返回树自动刷新。
class _NoteRow extends ConsumerWidget {
  final Note note;
  final int depth;
  const _NoteRow({required this.note, required this.depth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      contentPadding:
          EdgeInsets.only(left: 32.0 + depth * 16, right: 12),
      leading: const Icon(Icons.description_outlined, size: 18),
      title: Text(note.displayTitle,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(note.summary, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        tooltip: '删除',
        onPressed: () async {
          final ok = await _confirmDelete(context);
          if (!ok || !context.mounted) return;
          await ref.read(subjectTreeVmProvider.notifier).softDeleteNote(note.id);
        },
      ),
      onTap: () async {
        await context.push('/notes/editor/${note.id}');
        // 返回树后刷新（笔记可能被改/存）
        ref.read(subjectTreeVmProvider.notifier).refresh();
      },
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除笔记？'),
        content: const Text('删除后进回收站，可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    return ok ?? false;
  }
}
