import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/subject.dart';
import '../models/subject_scope.dart';
import '../view_model/subject_scope_picker_view_model.dart';
import '../view_model/view_model_providers.dart';

/// 范围选择结果，同时携带页面展示文案。
class SubjectScopeSelection {
  final SubjectScope scope;
  final String label;

  const SubjectScopeSelection({required this.scope, required this.label});
}

/// 显示紧凑层级入口和按需加载、可搜索的书章节树。
Future<SubjectScopeSelection?> showSubjectScopePicker({
  required BuildContext context,
}) {
  final sessionKey = Object();
  return showDialog<SubjectScopeSelection>(
    context: context,
    builder: (_) => _SubjectScopePickerDialog(sessionKey: sessionKey),
  );
}

class _SubjectScopePickerDialog extends ConsumerStatefulWidget {
  final Object sessionKey;

  const _SubjectScopePickerDialog({required this.sessionKey});

  @override
  ConsumerState<_SubjectScopePickerDialog> createState() =>
      _SubjectScopePickerDialogState();
}

class _SubjectScopePickerDialogState
    extends ConsumerState<_SubjectScopePickerDialog> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = subjectScopePickerVmProvider(widget.sessionKey);
    final picker = ref.watch(provider);
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('选择搜索范围')),
          PopupMenuButton<SubjectScopeSelection>(
            tooltip: '选择全部或指定层级',
            icon: const Icon(Icons.filter_alt_outlined),
            onSelected: (selection) => Navigator.pop(context, selection),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: SubjectScopeSelection(
                  scope: SubjectScope.all(),
                  label: '全部笔记',
                ),
                child: Text('全部笔记'),
              ),
              PopupMenuItem(
                value: SubjectScopeSelection(
                  scope: SubjectScope.level(0),
                  label: '全部书',
                ),
                child: Text('全部书'),
              ),
              PopupMenuItem(
                value: SubjectScopeSelection(
                  scope: SubjectScope.level(1),
                  label: '全部章',
                ),
                child: Text('全部章'),
              ),
              PopupMenuItem(
                value: SubjectScopeSelection(
                  scope: SubjectScope.level(2),
                  label: '全部节',
                ),
                child: Text('全部节'),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 480,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('subject-scope-search'),
              controller: _searchController,
              onChanged: ref.read(provider.notifier).setKeyword,
              decoration: const InputDecoration(
                labelText: '搜索书、章或节',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: picker.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _RootError(
                  error: error,
                  onRetry: () => ref.invalidate(provider),
                ),
                data: (state) => _PickerBody(
                  state: state,
                  onToggle: ref.read(provider.notifier).toggleExpanded,
                  onRetryBranch: ref.read(provider.notifier).loadChildren,
                  onRetrySearch: ref.read(provider.notifier).retrySearch,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _PickerBody extends StatelessWidget {
  final SubjectScopePickerState state;
  final Future<void> Function(String id) onToggle;
  final Future<void> Function(String id) onRetryBranch;
  final Future<void> Function() onRetrySearch;

  const _PickerBody({
    required this.state,
    required this.onToggle,
    required this.onRetryBranch,
    required this.onRetrySearch,
  });

  @override
  Widget build(BuildContext context) {
    if (state.keyword.isNotEmpty) {
      if (state.searching) {
        return const Center(child: CircularProgressIndicator());
      }
      if (state.searchError != null) {
        return _InlineError(
          message: state.searchError!.userMessage,
          onRetry: onRetrySearch,
        );
      }
      if (state.searchPaths.isEmpty) {
        return const Center(child: Text('没有匹配的书、章或节'));
      }
      final searchRoots = _mergeSearchPaths(
        state.searchPaths.map((path) => path.nodes),
      );
      return ListView(
        children: [
          for (final root in searchRoots)
            _SearchTreeTile(
              node: root,
              pathNames: [root.subject.name],
              state: state,
              onToggle: onToggle,
              onRetryBranch: onRetryBranch,
            ),
        ],
      );
    }
    if (state.roots.isEmpty) {
      return const Center(child: Text('还没有书'));
    }
    return ListView(
      children: [
        for (final root in state.roots)
          _SubjectTreeTile(
            subject: root,
            pathNames: [root.name],
            state: state,
            onToggle: onToggle,
            onRetryBranch: onRetryBranch,
          ),
      ],
    );
  }
}

class _SubjectTreeTile extends StatelessWidget {
  final Subject subject;
  final List<String> pathNames;
  final SubjectScopePickerState state;
  final Future<void> Function(String id) onToggle;
  final Future<void> Function(String id) onRetryBranch;

  const _SubjectTreeTile({
    required this.subject,
    required this.pathNames,
    required this.state,
    required this.onToggle,
    required this.onRetryBranch,
  });

  @override
  Widget build(BuildContext context) {
    final expandable = subject.level < 2;
    final expanded = state.expandedIds.contains(subject.id);
    final loading = state.loadingParentIds.contains(subject.id);
    final error = state.branchErrors[subject.id];
    final children = state.childrenByParent[subject.id] ?? const <Subject>[];
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: subject.level * 20, right: 4),
          leading: expandable
              ? IconButton(
                  key: ValueKey('scope-expand-${subject.id}'),
                  tooltip: expanded ? '收起${subject.name}' : '展开${subject.name}',
                  onPressed: () => onToggle(subject.id),
                  icon: loading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          expanded ? Icons.expand_more : Icons.chevron_right,
                        ),
                )
              : const SizedBox(width: 48),
          title: Text(subject.name),
          subtitle: Text('选择${subject.levelLabel}及其范围'),
          onTap: () => _selectSubject(context, subject, pathNames),
        ),
        if (expanded && error != null)
          _InlineError(
            message: error.userMessage,
            onRetry: () => onRetryBranch(subject.id),
          ),
        if (expanded)
          for (final child in children)
            _SubjectTreeTile(
              subject: child,
              pathNames: [...pathNames, child.name],
              state: state,
              onToggle: onToggle,
              onRetryBranch: onRetryBranch,
            ),
      ],
    );
  }
}

class _SearchTreeNode {
  final Subject subject;
  final Map<String, _SearchTreeNode> children = {};
  bool matched = false;

  _SearchTreeNode(this.subject);
}

List<_SearchTreeNode> _mergeSearchPaths(Iterable<List<Subject>> paths) {
  final roots = <String, _SearchTreeNode>{};
  for (final path in paths) {
    Map<String, _SearchTreeNode> siblings = roots;
    _SearchTreeNode? current;
    for (final subject in path) {
      current = siblings.putIfAbsent(
        subject.id,
        () => _SearchTreeNode(subject),
      );
      siblings = current.children;
    }
    if (current != null) current.matched = true;
  }
  return roots.values.toList();
}

class _SearchTreeTile extends StatelessWidget {
  final _SearchTreeNode node;
  final List<String> pathNames;
  final SubjectScopePickerState state;
  final Future<void> Function(String id) onToggle;
  final Future<void> Function(String id) onRetryBranch;

  const _SearchTreeTile({
    required this.node,
    required this.pathNames,
    required this.state,
    required this.onToggle,
    required this.onRetryBranch,
  });

  @override
  Widget build(BuildContext context) {
    final subject = node.subject;
    final expandable = subject.level < 2;
    final expanded = state.expandedIds.contains(subject.id);
    final visibleChildren = <_SearchTreeNode>[...node.children.values];
    if (expanded) {
      for (final child
          in state.childrenByParent[subject.id] ?? const <Subject>[]) {
        if (visibleChildren.every((node) => node.subject.id != child.id)) {
          visibleChildren.add(_SearchTreeNode(child));
        }
      }
    }
    final ancestors = pathNames.take(pathNames.length - 1).join(' > ');
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: subject.level * 20, right: 4),
          leading: expandable
              ? IconButton(
                  key: ValueKey('scope-search-expand-${subject.id}'),
                  tooltip: expanded ? '收起${subject.name}' : '展开${subject.name}',
                  onPressed: () => onToggle(subject.id),
                  icon: state.loadingParentIds.contains(subject.id)
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          expanded ? Icons.expand_more : Icons.chevron_right,
                        ),
                )
              : _levelIcon(subject.level),
          title: Text(subject.name),
          subtitle: node.matched && ancestors.isNotEmpty
              ? Text(ancestors)
              : null,
          onTap: () => _selectSubject(context, subject, pathNames),
        ),
        if (expanded && state.branchErrors[subject.id] != null)
          _InlineError(
            message: state.branchErrors[subject.id]!.userMessage,
            onRetry: () => onRetryBranch(subject.id),
          ),
        for (final child in visibleChildren)
          _SearchTreeTile(
            node: child,
            pathNames: [...pathNames, child.subject.name],
            state: state,
            onToggle: onToggle,
            onRetryBranch: onRetryBranch,
          ),
      ],
    );
  }
}

Widget _levelIcon(int level) => Icon(switch (level) {
  0 => Icons.menu_book_outlined,
  1 => Icons.article_outlined,
  _ => Icons.notes_outlined,
});

void _selectSubject(
  BuildContext context,
  Subject subject,
  List<String> pathNames,
) {
  Navigator.pop(
    context,
    SubjectScopeSelection(
      scope: SubjectScope.subtree(subject.id),
      label: pathNames.join(' > '),
    ),
  );
}

class _RootError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _RootError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _InlineError(message: '读取书列表失败：$error', onRetry: onRetry);
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final FutureOr<void> Function() onRetry;

  const _InlineError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          TextButton(
            onPressed: () {
              onRetry();
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
