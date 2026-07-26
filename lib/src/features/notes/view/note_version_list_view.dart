// 文件: lib/src/features/notes/view/note_version_list_view.dart
// 作用: 展示单条笔记的历史版本，并提供二次确认后的版本恢复。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/note_version.dart';
import '../view_model/view_model_providers.dart';

/// 笔记历史版本列表页。
class NoteVersionListView extends ConsumerStatefulWidget {
  final String noteId;

  const NoteVersionListView({super.key, required this.noteId});

  @override
  ConsumerState<NoteVersionListView> createState() =>
      _NoteVersionListViewState();
}

class _NoteVersionListViewState extends ConsumerState<NoteVersionListView> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(noteVersionVmProvider(widget.noteId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史版本'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回编辑器',
          onPressed: () => context.pop(),
        ),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('读取历史版本失败：$error')),
        data: (versions) {
          if (versions.isEmpty) {
            return const Center(child: Text('暂无历史版本'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: versions.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final version = versions[index];
              return ListTile(
                leading: CircleAvatar(child: Text('${version.versionNo}')),
                title: Text('版本 ${version.versionNo}'),
                subtitle: Text(_formatCreatedAt(version)),
                trailing: FilledButton.tonal(
                  onPressed: () => _restore(version),
                  child: const Text('恢复'),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _restore(NoteVersion version) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('恢复版本 ${version.versionNo}？'),
        content: const Text('当前正文会先保存为一个新版本，然后恢复所选版本。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(noteVersionVmProvider(widget.noteId).notifier)
        .restore(versionNo: version.versionNo);
    if (!mounted) return;
    if (ok) {
      context.pop(true);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('恢复失败，请稍后重试')));
    }
  }

  String _formatCreatedAt(NoteVersion version) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      version.createdAt,
    ).toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }
}
