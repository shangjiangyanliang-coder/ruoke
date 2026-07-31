// 作用：显示可搜索、可展开且区分可选/路径节点的完整目录移动目标树。
import 'package:flutter/material.dart';

import '../models/library_organization.dart';
import '../utils/library_organization_rules.dart';

class LibraryMoveTargetTree extends StatefulWidget {
  final List<LibraryMoveTarget> targets;
  final ValueChanged<LibraryMoveTarget> onSelected;

  const LibraryMoveTargetTree({
    super.key,
    required this.targets,
    required this.onSelected,
  });

  @override
  State<LibraryMoveTargetTree> createState() => _LibraryMoveTargetTreeState();
}

class _LibraryMoveTargetTreeState extends State<LibraryMoveTargetTree> {
  final _searchController = TextEditingController();
  final _expandedKeys = <String>{};
  var _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleKeys = visibleTargetIds(
      keyword: _keyword,
      targets: widget.targets,
    );
    final visibleTargets = widget.targets
        .where((target) => visibleKeys.contains(target.key))
        .toList();
    final root = visibleTargets
        .where((target) => target.id == null)
        .firstOrNull;
    final topLevel = root == null
        ? visibleTargets.where((target) => target.parentId == null).toList()
        : [root];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: const Key('move-target-search'),
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索文件夹、书、章或节',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _keyword.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _keyword = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _keyword = value),
          ),
        ),
        Expanded(
          child: visibleTargets.isEmpty
              ? const Center(child: Text('没有匹配的目录位置'))
              : ListView(
                  children: [
                    for (final target in topLevel)
                      _buildNode(target, visibleTargets),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildNode(
    LibraryMoveTarget target,
    List<LibraryMoveTarget> visibleTargets,
  ) {
    final children = visibleTargets
        .where(
          (candidate) =>
              candidate.id != null && candidate.parentId == target.id,
        )
        .toList();
    final key = ValueKey(
      'move-target-${target.kind.name}-${target.id ?? 'root'}',
    );
    final subtitle = target.pathLabels.length > 1
        ? Text(target.pathLabels.join(' / '))
        : null;
    final selectButton = target.canSelect
        ? TextButton(
            key: Key(
              'move-target-select-${target.kind.name}-${target.id ?? 'root'}',
            ),
            onPressed: () => widget.onSelected(target),
            child: const Text('选择'),
          )
        : null;

    if (children.isEmpty) {
      return ListTile(
        key: key,
        leading: Icon(_iconFor(target.kind)),
        title: Text(target.label),
        subtitle: subtitle,
        trailing: selectButton,
        onTap: target.canSelect ? () => widget.onSelected(target) : null,
      );
    }
    final searching = _keyword.trim().isNotEmpty;
    return KeyedSubtree(
      key: key,
      child: ExpansionTile(
        key: ValueKey('${target.key}-search-$searching'),
        initiallyExpanded: searching || _expandedKeys.contains(target.key),
        onExpansionChanged: (expanded) {
          setState(() {
            if (expanded) {
              _expandedKeys.add(target.key);
            } else {
              _expandedKeys.remove(target.key);
            }
          });
        },
        leading: Icon(_iconFor(target.kind)),
        title: Text(target.label),
        subtitle: subtitle,
        trailing: selectButton,
        children: [
          for (final child in children) _buildNode(child, visibleTargets),
        ],
      ),
    );
  }

  IconData _iconFor(LibraryItemKind kind) => switch (kind) {
    LibraryItemKind.folder => Icons.folder_outlined,
    LibraryItemKind.book => Icons.menu_book_outlined,
    LibraryItemKind.chapter => Icons.bookmark_outline,
    LibraryItemKind.section => Icons.article_outlined,
    LibraryItemKind.note => Icons.description_outlined,
  };
}
