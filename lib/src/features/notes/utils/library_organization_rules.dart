// 作用：以纯 Dart 规则构造目录移动目标，并计算搜索时可见的祖先路径。
import '../models/library_organization.dart';
import '../models/subject.dart';
import '../models/subject_folder.dart';

/// 根据待移动类型生成完整可展示目标树，并标记哪些节点可被选择。
List<LibraryMoveTarget> buildMoveTargets({
  required LibraryMoveRequest request,
  required List<SubjectFolder> folders,
  required List<Subject> subjects,
}) {
  final activeFolders = folders.where((folder) => !folder.isDeleted).toList()
    ..sort(_compareFolders);
  final activeSubjects =
      subjects.where((subject) => !subject.isDeleted).toList()
        ..sort(_compareSubjects);
  final folderById = {for (final folder in activeFolders) folder.id: folder};
  final subjectById = {
    for (final subject in activeSubjects) subject.id: subject,
  };
  final excludedFolderIds = request.kind == LibraryItemKind.folder
      ? _folderAndDescendantIds(request.itemId, activeFolders)
      : const <String>{};
  final targets = <LibraryMoveTarget>[];

  if (request.kind case LibraryItemKind.folder || LibraryItemKind.book) {
    targets.add(
      LibraryMoveTarget(
        kind: LibraryItemKind.folder,
        id: null,
        parentId: null,
        label: '根目录',
        pathLabels: const ['根目录'],
        canSelect: true,
      ),
    );
  }

  for (final folder in activeFolders) {
    if (excludedFolderIds.contains(folder.id)) continue;
    targets.add(
      LibraryMoveTarget(
        kind: LibraryItemKind.folder,
        id: folder.id,
        parentId: folder.parentId,
        label: folder.name,
        pathLabels: _folderPath(folder, folderById),
        canSelect:
            request.kind == LibraryItemKind.folder ||
            request.kind == LibraryItemKind.book,
      ),
    );
  }

  final maxSubjectLevel = switch (request.kind) {
    LibraryItemKind.chapter => 0,
    LibraryItemKind.section => 1,
    LibraryItemKind.note => 2,
    LibraryItemKind.folder || LibraryItemKind.book => -1,
  };
  if (maxSubjectLevel < 0) return targets;

  for (final subject in activeSubjects) {
    if (subject.level < 0 || subject.level > maxSubjectLevel) continue;
    final kind = _kindForLevel(subject.level);
    targets.add(
      LibraryMoveTarget(
        kind: kind,
        id: subject.id,
        parentId: subject.level == 0 ? subject.folderId : subject.parentId,
        label: subject.name,
        pathLabels: _subjectPath(subject, subjectById, folderById),
        canSelect: switch (request.kind) {
          LibraryItemKind.chapter => kind == LibraryItemKind.book,
          LibraryItemKind.section => kind == LibraryItemKind.chapter,
          LibraryItemKind.note => kind != LibraryItemKind.folder,
          LibraryItemKind.folder || LibraryItemKind.book => false,
        },
      ),
    );
  }
  return targets;
}

/// 返回关键词命中节点和它们全部祖先的稳定 key；空关键词显示全部。
Set<String> visibleTargetIds({
  required String keyword,
  required List<LibraryMoveTarget> targets,
}) {
  final normalized = keyword.trim().toLowerCase();
  if (normalized.isEmpty) return targets.map((target) => target.key).toSet();

  final byId = <String, LibraryMoveTarget>{
    for (final target in targets)
      if (target.id != null) target.id!: target,
  };
  final root = targets.where((target) => target.id == null).firstOrNull;
  final visible = <String>{};
  for (final target in targets) {
    if (!target.label.toLowerCase().contains(normalized)) continue;
    var current = target;
    final visited = <String>{};
    while (true) {
      if (!visited.add(current.key)) break;
      visible.add(current.key);
      final parentId = current.parentId;
      if (parentId == null) {
        if (root != null) visible.add(root.key);
        break;
      }
      final parent = byId[parentId];
      if (parent == null) break;
      current = parent;
    }
  }
  return visible;
}

LibraryItemKind _kindForLevel(int level) => switch (level) {
  0 => LibraryItemKind.book,
  1 => LibraryItemKind.chapter,
  2 => LibraryItemKind.section,
  _ => throw ArgumentError.value(level, 'level', '只支持书、章、节'),
};

Set<String> _folderAndDescendantIds(
  String folderId,
  List<SubjectFolder> folders,
) {
  final childrenByParent = <String, List<String>>{};
  for (final folder in folders) {
    final parentId = folder.parentId;
    if (parentId != null) {
      (childrenByParent[parentId] ??= []).add(folder.id);
    }
  }
  final excluded = <String>{};
  final pending = <String>[folderId];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (excluded.add(current)) {
      pending.addAll(childrenByParent[current] ?? const []);
    }
  }
  return excluded;
}

List<String> _folderPath(
  SubjectFolder target,
  Map<String, SubjectFolder> folderById,
) {
  final reversed = <String>[];
  final visited = <String>{};
  SubjectFolder? current = target;
  while (current != null && visited.add(current.id)) {
    reversed.add(current.name);
    current = current.parentId == null ? null : folderById[current.parentId];
  }
  return reversed.reversed.toList();
}

List<String> _subjectPath(
  Subject target,
  Map<String, Subject> subjectById,
  Map<String, SubjectFolder> folderById,
) {
  final reversed = <String>[];
  final visited = <String>{};
  Subject? current = target;
  Subject? book;
  while (current != null && visited.add(current.id)) {
    reversed.add(current.name);
    if (current.level == 0) book = current;
    current = current.parentId == null ? null : subjectById[current.parentId];
  }
  final result = <String>[];
  if (book?.folderId case final folderId?) {
    final folder = folderById[folderId];
    if (folder != null) result.addAll(_folderPath(folder, folderById));
  } else if (book != null) {
    result.add('未归类书籍');
  }
  result.addAll(reversed.reversed);
  return result;
}

int _compareFolders(SubjectFolder left, SubjectFolder right) {
  final byOrder = left.sortOrder.compareTo(right.sortOrder);
  if (byOrder != 0) return byOrder;
  final byCreatedAt = left.createdAt.compareTo(right.createdAt);
  if (byCreatedAt != 0) return byCreatedAt;
  return left.id.compareTo(right.id);
}

int _compareSubjects(Subject left, Subject right) {
  final byLevel = left.level.compareTo(right.level);
  if (byLevel != 0) return byLevel;
  final byOrder = left.sortOrder.compareTo(right.sortOrder);
  if (byOrder != 0) return byOrder;
  final byCreatedAt = left.createdAt.compareTo(right.createdAt);
  if (byCreatedAt != 0) return byCreatedAt;
  return left.id.compareTo(right.id);
}
