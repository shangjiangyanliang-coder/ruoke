// 作用：为文件夹、书、章、节和笔记提供统一的三点操作菜单。
import 'package:flutter/material.dart';

import '../models/library_organization.dart';

class LibraryItemActionMenu extends StatelessWidget {
  final LibraryItemKind kind;
  final ValueChanged<LibraryItemAction> onSelected;

  const LibraryItemActionMenu({
    super.key,
    required this.kind,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<LibraryItemAction>(
    tooltip: '更多操作',
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final action in _actionsFor(kind))
        PopupMenuItem(value: action, child: Text(_labelFor(action))),
    ],
  );
}

List<LibraryItemAction> _actionsFor(LibraryItemKind kind) => switch (kind) {
  LibraryItemKind.folder => const [
    LibraryItemAction.rename,
    LibraryItemAction.move,
    LibraryItemAction.reorder,
    LibraryItemAction.dissolve,
  ],
  LibraryItemKind.book ||
  LibraryItemKind.chapter ||
  LibraryItemKind.section ||
  LibraryItemKind.note => const [
    LibraryItemAction.rename,
    LibraryItemAction.move,
    LibraryItemAction.reorder,
  ],
};

String _labelFor(LibraryItemAction action) => switch (action) {
  LibraryItemAction.rename => '重命名',
  LibraryItemAction.move => '移动',
  LibraryItemAction.reorder => '调整顺序',
  LibraryItemAction.dissolve => '安全解散',
};
