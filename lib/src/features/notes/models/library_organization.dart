// 作用：定义目录项目排序、移动和菜单动作之间共享的稳定数据契约。

/// 固定目录层级中的五类可组织项目。
enum LibraryItemKind { folder, book, chapter, section, note }

/// 目录项目三点菜单支持的动作。
enum LibraryItemAction { rename, move, reorder, dissolve }

/// 排序页中的最小项目快照。
class LibraryOrderItem {
  final String id;
  final String label;

  const LibraryOrderItem({required this.id, required this.label});
}

/// 打开同级排序页所需的稳定请求。
class LibraryReorderRequest {
  final LibraryItemKind kind;
  final String? parentId;
  final String title;

  const LibraryReorderRequest({
    required this.kind,
    required this.parentId,
    required this.title,
  });
}

/// 打开移动流程所需的项目快照。
class LibraryMoveRequest {
  final LibraryItemKind kind;
  final String itemId;
  final String itemName;

  const LibraryMoveRequest({
    required this.kind,
    required this.itemId,
    required this.itemName,
  });
}

/// 移动目标树节点；不可选择的节点仍可用于展示和展开祖先路径。
class LibraryMoveTarget {
  final LibraryItemKind kind;
  final String? id;
  final String? parentId;
  final String label;
  final List<String> pathLabels;
  final bool canSelect;

  const LibraryMoveTarget({
    required this.kind,
    required this.id,
    required this.parentId,
    required this.label,
    required this.pathLabels,
    required this.canSelect,
  });

  /// UI、搜索结果和测试共享的稳定节点键；根目录使用固定 root 标记。
  String get key => '${kind.name}:${id ?? 'root'}';
}
