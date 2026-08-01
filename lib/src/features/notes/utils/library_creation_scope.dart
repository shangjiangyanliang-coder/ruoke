// 文件: lib/src/features/notes/utils/library_creation_scope.dart
// 作用: 根据当前浏览位置筛选文件夹、书、章、节的合法新建父位置。
import '../models/library_location.dart';
import '../models/subject.dart';
import '../models/subject_folder.dart';

enum LibraryContentKind { folder, book, chapter, section }

class LibraryCreationTarget {
  final String? id;
  final String name;

  const LibraryCreationTarget({required this.id, required this.name});
}

class LibraryCreationScope {
  final LibraryLocation location;
  final List<SubjectFolder> _folders;
  final List<Subject> _subjects;

  const LibraryCreationScope._(this.location, this._folders, this._subjects);

  factory LibraryCreationScope.build({
    required LibraryLocation location,
    required List<SubjectFolder> folders,
    required List<Subject> subjects,
  }) => LibraryCreationScope._(location, folders, subjects);

  List<LibraryCreationTarget> targetsFor(LibraryContentKind kind) {
    return switch (kind) {
      LibraryContentKind.folder => _folderTargets(),
      LibraryContentKind.book => _folderTargets(),
      LibraryContentKind.chapter => _subjectTargets(0),
      LibraryContentKind.section => _subjectTargets(1),
    };
  }

  List<LibraryCreationTarget> _folderTargets() {
    final allowed = _allowedFolderIds();
    if (allowed == null) {
      return [
        const LibraryCreationTarget(id: null, name: '根目录'),
        ..._folders.map(
          (folder) => LibraryCreationTarget(id: folder.id, name: folder.name),
        ),
      ];
    }
    return _folders
        .where((folder) => allowed.contains(folder.id))
        .map(
          (folder) => LibraryCreationTarget(id: folder.id, name: folder.name),
        )
        .toList();
  }

  List<LibraryCreationTarget> _subjectTargets(int targetLevel) {
    final allowed = _allowedSubjectIds();
    return _subjects
        .where(
          (subject) =>
              subject.level == targetLevel && allowed.contains(subject.id),
        )
        .map(
          (subject) =>
              LibraryCreationTarget(id: subject.id, name: subject.name),
        )
        .toList();
  }

  Set<String>? _allowedFolderIds() {
    return switch (location) {
      LibraryRootLocation() => null,
      LibraryFolderLocation(:final folderId) => _folderDescendants(folderId),
      LibraryUngroupedBooksLocation() => <String>{},
      LibrarySubjectLocation() => <String>{},
    };
  }

  Set<String> _allowedSubjectIds() {
    return switch (location) {
      LibraryRootLocation() => _subjects.map((subject) => subject.id).toSet(),
      LibraryUngroupedBooksLocation() => _subjectDescendants(
        _subjects
            .where((subject) => subject.level == 0 && subject.folderId == null)
            .map((subject) => subject.id),
      ),
      LibraryFolderLocation(:final folderId) => _subjectDescendants(
        _subjects
            .where(
              (subject) =>
                  subject.level == 0 &&
                  _folderDescendants(folderId).contains(subject.folderId),
            )
            .map((subject) => subject.id),
      ),
      LibrarySubjectLocation(:final subjectId) => _subjectDescendants([
        subjectId,
      ]),
    };
  }

  Set<String> _folderDescendants(String rootId) {
    final children = <String, List<String>>{};
    for (final folder in _folders) {
      if (folder.parentId != null)
        (children[folder.parentId!] ??= []).add(folder.id);
    }
    final result = <String>{};
    final pending = <String>[rootId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (result.add(current)) pending.addAll(children[current] ?? const []);
    }
    return result;
  }

  Set<String> _subjectDescendants(Iterable<String> roots) {
    final children = <String, List<String>>{};
    for (final subject in _subjects) {
      if (subject.parentId != null)
        (children[subject.parentId!] ??= []).add(subject.id);
    }
    final result = <String>{};
    final pending = roots.toList();
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (result.add(current)) pending.addAll(children[current] ?? const []);
    }
    return result;
  }
}
