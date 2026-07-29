// 文件: lib/src/features/notes/view/note_version_list_view.dart
// 作用: 展示笔记历史版本，并提供恢复、重命名和批量删除操作。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/note_version.dart';
import '../view_model/note_version_view_model.dart';
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
    final asyncState = ref.watch(noteVersionVmProvider(widget.noteId));
    return asyncState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: _normalAppBar(),
        body: Center(child: Text('读取历史版本失败：$error')),
      ),
      data: (state) => _buildLoadedPage(context, state),
    );
  }

  Widget _buildLoadedPage(BuildContext context, NoteVersionState state) {
    return Scaffold(
      appBar: state.managing ? _managementAppBar(state) : _normalAppBar(),
      bottomNavigationBar: state.managing ? _deleteBar(state) : null,
      body: Stack(
        children: [
          if (state.versions.isEmpty)
            const Center(child: Text('暂无历史版本'))
          else
            ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: state.versions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _versionTile(state, state.versions[index]),
            ),
          if (state.mutating)
            const ColoredBox(
              color: Color(0x22000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  AppBar _normalAppBar() => AppBar(
    title: const Text('历史版本'),
    leading: IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: '返回编辑器',
      onPressed: () => context.pop(),
    ),
    actions: [
      TextButton(
        onPressed: () => ref
            .read(noteVersionVmProvider(widget.noteId).notifier)
            .enterManagement(),
        child: const Text('管理'),
      ),
    ],
  );

  AppBar _managementAppBar(NoteVersionState state) => AppBar(
    title: Text('已选 ${state.selectedIds.length} 项'),
    leading: TextButton(
      onPressed: state.mutating
          ? null
          : () => ref
                .read(noteVersionVmProvider(widget.noteId).notifier)
                .exitManagement(),
      child: const Text('取消'),
    ),
    actions: [
      TextButton(
        onPressed: state.mutating
            ? null
            : () => ref
                  .read(noteVersionVmProvider(widget.noteId).notifier)
                  .toggleSelectAll(),
        child: Text(
          state.selectedIds.length == state.versions.length ? '取消全选' : '全选',
        ),
      ),
    ],
  );

  Widget _versionTile(NoteVersionState state, NoteVersion version) => ListTile(
    leading: state.managing
        ? Checkbox(
            value: state.selectedIds.contains(version.id),
            onChanged: state.mutating
                ? null
                : (_) => ref
                      .read(noteVersionVmProvider(widget.noteId).notifier)
                      .toggleSelected(version.id),
          )
        : CircleAvatar(child: Text('${version.versionNo}')),
    title: Text(version.displayName),
    subtitle: Text(_formatCreatedAt(version)),
    onTap: state.managing
        ? () => ref
              .read(noteVersionVmProvider(widget.noteId).notifier)
              .toggleSelected(version.id)
        : null,
    trailing: state.managing
        ? null
        : Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: state.mutating ? null : () => _rename(version),
                child: const Text('重命名'),
              ),
              FilledButton.tonal(
                onPressed: state.mutating ? null : () => _restore(version),
                child: const Text('恢复'),
              ),
            ],
          ),
  );

  Widget _deleteBar(NoteVersionState state) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: state.selectedIds.isEmpty || state.mutating
            ? null
            : _deleteSelected,
        icon: const Icon(Icons.delete),
        label: Text('删除所选（${state.selectedIds.length}）'),
      ),
    ),
  );

  Future<void> _rename(NoteVersion version) async {
    final controller = TextEditingController(text: version.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名历史版本'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(hintText: '留空则恢复默认版本名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;

    final ok = await ref
        .read(noteVersionVmProvider(widget.noteId).notifier)
        .rename(versionId: version.id, name: name);
    if (!mounted) return;
    if (!ok || _hasOperationError()) _showOperationError();
  }

  Future<void> _deleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('永久删除历史版本？'),
        content: const Text('删除后无法恢复，确定要删除所选版本吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(noteVersionVmProvider(widget.noteId).notifier)
        .deleteSelected();
    if (!mounted) return;
    if (!ok || _hasOperationError()) _showOperationError();
  }

  Future<void> _restore(NoteVersion version) async {
    var saveCurrentBeforeRestore = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('恢复${version.displayName}？'),
          content: CheckboxListTile(
            value: saveCurrentBeforeRestore,
            onChanged: (value) =>
                setDialogState(() => saveCurrentBeforeRestore = value ?? false),
            title: const Text('恢复前将当前内容保存为新版本'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
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
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(noteVersionVmProvider(widget.noteId).notifier)
        .restore(
          versionNo: version.versionNo,
          saveCurrentBeforeRestore: saveCurrentBeforeRestore,
        );
    if (!mounted) return;
    if (ok) {
      context.pop(true);
    } else {
      _showOperationError();
    }
  }

  void _showOperationError() {
    final message =
        ref
            .read(noteVersionVmProvider(widget.noteId))
            .value
            ?.operationError
            ?.userMessage ??
        '操作失败，请稍后重试';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _hasOperationError() =>
      ref.read(noteVersionVmProvider(widget.noteId)).value?.operationError !=
      null;

  String _formatCreatedAt(NoteVersion version) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      version.createdAt,
    ).toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }
}
