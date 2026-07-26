// 标签管理页：显示标签计数，支持增改删和多选后进入并集筛选。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/tag.dart';
import '../view_model/tag_management_view_model.dart';
import '../view_model/view_model_providers.dart';

/// 标签管理与筛选入口。
class TagManagementView extends ConsumerStatefulWidget {
  const TagManagementView({super.key});

  @override
  ConsumerState<TagManagementView> createState() => _TagManagementViewState();
}

class _TagManagementViewState extends ConsumerState<TagManagementView> {
  final Set<String> _selectedTagIds = {};

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagManagementVmProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('标签管理')),
      body: tags.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
        data: (state) => _buildContent(state),
      ),
      bottomNavigationBar: _selectedTagIds.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _openSelectedTags,
                icon: const Icon(Icons.filter_alt_outlined),
                label: Text('筛选已选标签 (${_selectedTagIds.length})'),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建标签',
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildContent(TagManagementState state) {
    if (state.tags.isEmpty) {
      return const Center(child: Text('还没有标签，点右下角 + 新建'));
    }
    return Column(
      children: [
        if (state.actionError != null)
          MaterialBanner(
            content: Text(state.actionError!.userMessage),
            actions: [
              TextButton(
                onPressed: ref
                    .read(tagManagementVmProvider.notifier)
                    .clearActionError,
                child: const Text('知道了'),
              ),
            ],
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: state.tags.length,
            itemBuilder: (_, index) {
              final tag = state.tags[index];
              return ListTile(
                leading: Checkbox(
                  value: _selectedTagIds.contains(tag.id),
                  onChanged: (_) => _toggleTag(tag.id),
                ),
                title: Text(tag.name),
                subtitle: Text('${tag.noteCount} 条笔记'),
                onTap: () => _toggleTag(tag.id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '改名',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showRenameDialog(tag),
                    ),
                    IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(tag),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _toggleTag(String tagId) {
    setState(() {
      if (!_selectedTagIds.add(tagId)) {
        _selectedTagIds.remove(tagId);
      }
    });
  }

  void _openSelectedTags() {
    final ids = _selectedTagIds.toList()..sort();
    final query = Uri(queryParameters: {'tagIds': ids.join(',')}).query;
    context.push('/notes/search?$query');
  }

  Future<void> _showCreateDialog() async {
    final controller = TextEditingController();
    await _showNameDialog(
      title: '新建标签',
      controller: controller,
      actionLabel: '新建',
      submit: (name) =>
          ref.read(tagManagementVmProvider.notifier).create(name: name),
    );
    await WidgetsBinding.instance.endOfFrame;
    controller.dispose();
  }

  Future<void> _showRenameDialog(TagWithCount tag) async {
    final controller = TextEditingController(text: tag.name);
    await _showNameDialog(
      title: '标签改名',
      controller: controller,
      actionLabel: '保存',
      submit: (name) => ref
          .read(tagManagementVmProvider.notifier)
          .rename(id: tag.id, name: name),
    );
    await WidgetsBinding.instance.endOfFrame;
    controller.dispose();
  }

  Future<void> _showNameDialog({
    required String title,
    required TextEditingController controller,
    required String actionLabel,
    required Future<bool> Function(String name) submit,
  }) async {
    String? errorMessage;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '标签名称',
              errorText: errorMessage,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (controller.text.trim().isEmpty) {
                  setDialogState(() => errorMessage = '标签名称不能为空');
                  return;
                }
                final success = await submit(controller.text);
                if (!dialogContext.mounted) return;
                if (success) {
                  Navigator.pop(dialogContext);
                  return;
                }
                final error = ref
                    .read(tagManagementVmProvider)
                    .value
                    ?.actionError;
                setDialogState(
                  () => errorMessage = error?.userMessage ?? '操作失败，请重试',
                );
              },
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(TagWithCount tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除标签？'),
        content: Text('将删除“${tag.name}”及其笔记关联，不会删除笔记本身。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success = await ref
        .read(tagManagementVmProvider.notifier)
        .delete(tag.id);
    if (!mounted) return;
    if (success) {
      setState(() => _selectedTagIds.remove(tag.id));
    }
  }
}
