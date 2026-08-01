// 文件: lib/src/features/notes/utils/library_selection_rules.dart
// 作用: 限制主界面位置选择会话只能进入起点及其后代，并判断可创建目标。
import '../models/library_location.dart';
import '../models/library_navigation_state.dart';
import '../models/subject.dart';
import '../models/subject_folder.dart';
import 'library_creation_scope.dart';

class LibrarySelectionRules {
  final List<SubjectFolder> _folders;
  final Map<String, Subject> _subjectsById;

  factory LibrarySelectionRules({
    required List<SubjectFolder> folders,
    required List<Subject> subjects,
  }) => LibrarySelectionRules._(folders, {
    for (final subject in subjects) subject.id: subject,
  });

  LibrarySelectionRules._(this._folders, this._subjectsById);

  bool isWithinScope({
    required LibraryLocation origin,
    required LibraryLocation candidate,
  }) {
    return switch (origin) {
      LibraryRootLocation() => true,
      LibraryFolderLocation(:final folderId) => _isInFolderScope(
        folderId,
        candidate,
      ),
      LibraryUngroupedBooksLocation() => _isUngroupedScope(candidate),
      LibrarySubjectLocation(:final subjectId) => _isInSubjectScope(
        subjectId,
        candidate,
      ),
    };
  }

  bool canEnter({
    required LibrarySelectionSession session,
    required LibraryLocation location,
  }) => isWithinScope(origin: session.origin, candidate: location);

  bool canSelectCurrent({
    required LibrarySelectionSession session,
    required LibraryLocation location,
  }) {
    if (!isWithinScope(origin: session.origin, candidate: location))
      return false;
    if (session.kind == LibrarySelectionKind.noteLocation) {
      final subject = _subjectAt(location);
      return subject != null && subject.level >= 0 && subject.level <= 2;
    }
    return switch (session.contentDraft!.kind) {
      LibraryContentKind.folder || LibraryContentKind.book =>
        location is LibraryRootLocation || location is LibraryFolderLocation,
      LibraryContentKind.chapter => _subjectAt(location)?.level == 0,
      LibraryContentKind.section => _subjectAt(location)?.level == 1,
    };
  }

  Subject? _subjectAt(LibraryLocation location) => switch (location) {
    LibrarySubjectLocation(:final subjectId) => _subjectsById[subjectId],
    _ => null,
  };

  bool _isInFolderScope(String originId, LibraryLocation candidate) {
    final folderIds = _folderDescendants(originId);
    if (candidate case LibraryFolderLocation(:final folderId)) {
      return folderIds.contains(folderId);
    }
    if (candidate case LibrarySubjectLocation(:final subjectId)) {
      final folderId = _bookFor(subjectId)?.folderId;
      return folderId != null && folderIds.contains(folderId);
    }
    return false;
  }

  bool _isUngroupedScope(LibraryLocation candidate) => switch (candidate) {
    LibraryUngroupedBooksLocation() => true,
    LibrarySubjectLocation(:final subjectId) =>
      _bookFor(subjectId)?.folderId == null,
    _ => false,
  };

  bool _isInSubjectScope(String originId, LibraryLocation candidate) =>
      switch (candidate) {
        LibrarySubjectLocation(:final subjectId) => _subjectDescendants(
          originId,
        ).contains(subjectId),
        _ => false,
      };

  Subject? _bookFor(String subjectId) {
    var current = _subjectsById[subjectId];
    while (current != null && current.level != 0) {
      current = current.parentId == null
          ? null
          : _subjectsById[current.parentId!];
    }
    return current;
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

  Set<String> _subjectDescendants(String rootId) {
    final children = <String, List<String>>{};
    for (final subject in _subjectsById.values) {
      if (subject.parentId != null)
        (children[subject.parentId!] ??= []).add(subject.id);
    }
    final result = <String>{};
    final pending = <String>[rootId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (result.add(current)) pending.addAll(children[current] ?? const []);
    }
    return result;
  }
}
