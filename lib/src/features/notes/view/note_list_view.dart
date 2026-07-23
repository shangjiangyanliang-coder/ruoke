// 文件: lib/src/features/notes/view/note_list_view.dart
// 作用: 笔记列表页（B1 最小占位版，第2批）。底栏笔记 tab 落地页。
//       右下 FAB 新建→编辑器(new)；列表行显示标题+摘要，点开→编辑器；
//       行尾删除按钮软删。watch NoteListVm，loading/error/empty 三态占位。
//       第3批做分级树、第5批做搜索/标签，此时占位替换。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/note.dart';
import '../view_model/view_model_providers.dart';

/// 笔记列表页（B1 最小占位）。
class NoteListView extends ConsumerWidget {
  const NoteListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(noteListVmProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('笔记')),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('加载失败：$e',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
        data: (notes) => notes.isEmpty
            ? const _EmptyHint()
            : ListView.separated(
                itemCount: notes.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (context, i) {
                  final n = notes[i];
                  return _NoteRow(note: n);
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建笔记',
        onPressed: () async {
          final id = await ref.read(noteListVmProvider.notifier).createEmpty();
          if (context.mounted) {
            await context.push('/notes/editor/$id');
            // 编辑器返回后刷新列表
            ref.read(noteListVmProvider.notifier).refresh();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

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

class _NoteRow extends ConsumerWidget {
  final Note note;
  const _NoteRow({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(note.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(note.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: '删除',
        onPressed: () async {
          final ok = await _confirmDelete(context);
          if (ok) {
            ref.read(noteListVmProvider.notifier).softDelete(note.id);
          }
        },
      ),
      onTap: () async {
        await context.push('/notes/editor/${note.id}');
        ref.read(noteListVmProvider.notifier).refresh();
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
