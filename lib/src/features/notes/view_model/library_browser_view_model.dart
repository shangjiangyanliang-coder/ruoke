// 文件: lib/src/features/notes/view_model/library_browser_view_model.dart
// 作用: 按当前位置加载文件夹、书章节和直属笔记，供逐级浏览页面使用。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/result.dart';
import '../models/library_location.dart';
import '../models/note.dart';
import '../models/subject.dart';
import '../models/subject_folder.dart';
import '../note_constants.dart';
import '../providers.dart';

class LibraryBreadcrumb {
  final String label;
  final LibraryLocation location;

  const LibraryBreadcrumb({required this.label, required this.location});
}

/// 一个逐级页面所需的直属内容快照。
class LibraryBrowserState {
  final LibraryLocation location;
  final String title;
  final Subject? subject;
  final List<SubjectFolder> folders;
  final List<Subject> books;
  final List<Subject> childSubjects;
  final List<Note> notes;
  final List<LibraryBreadcrumb> breadcrumbs;

  const LibraryBrowserState({
    required this.location,
    required this.title,
    this.subject,
    this.folders = const [],
    this.books = const [],
    this.childSubjects = const [],
    this.notes = const [],
    this.breadcrumbs = const [],
  });
}

/// 逐级浏览数据会话；位置改变即创建独立、自动释放的加载状态。
final libraryBrowserProvider = FutureProvider.autoDispose
    .family<LibraryBrowserState, LibraryLocation>((ref, location) async {
      final folders = ref.read(folderRepositoryProvider);
      final subjects = ref.read(subjectRepositoryProvider);
      final notes = ref.read(noteRepositoryProvider);

      T value<T>(Result<T> result) {
        if (result is Success<T>) return result.value;
        throw (result as Failure<T>).exception;
      }

      switch (location) {
        case LibraryRootLocation():
          return LibraryBrowserState(
            location: location,
            title: '笔记',
            folders: value(await folders.childrenOf(null)),
            books: value(await folders.booksIn(null)),
            notes: value(await notes.listBySubject(defaultSubjectId)),
            breadcrumbs: const [
              LibraryBreadcrumb(label: '笔记', location: LibraryLocation.root()),
            ],
          );
        case LibraryUngroupedBooksLocation():
          return LibraryBrowserState(
            location: location,
            title: '未归类书',
            books: value(await folders.booksIn(null)),
            breadcrumbs: const [
              LibraryBreadcrumb(label: '笔记', location: LibraryLocation.root()),
              LibraryBreadcrumb(
                label: '未归类书',
                location: LibraryLocation.ungroupedBooks(),
              ),
            ],
          );
        case LibraryFolderLocation(:final folderId):
          final allFolders = value(await folders.listAll());
          final path = _folderPath(allFolders, folderId);
          return LibraryBrowserState(
            location: location,
            title: path.isEmpty ? '文件夹' : path.last.name,
            folders: value(await folders.childrenOf(folderId)),
            books: value(await folders.booksIn(folderId)),
            breadcrumbs: [
              const LibraryBreadcrumb(
                label: '笔记',
                location: LibraryLocation.root(),
              ),
              for (final folder in path)
                LibraryBreadcrumb(
                  label: folder.name,
                  location: LibraryLocation.folder(folder.id),
                ),
            ],
          );
        case LibrarySubjectLocation(:final subjectId):
          final subject = value(await subjects.getById(subjectId));
          if (subject == null || subject.isDeleted) {
            throw StateError('浏览位置已不存在');
          }
          final allSubjects = value(await subjects.listAll());
          final allFolders = value(await folders.listAll());
          return LibraryBrowserState(
            location: location,
            title: subject.name,
            subject: subject,
            childSubjects: value(await subjects.childrenOf(subjectId)),
            notes: value(await notes.listBySubject(subjectId)),
            breadcrumbs: _subjectBreadcrumbs(allSubjects, allFolders, subject),
          );
      }
    });

/// 目录结构变化后失效全部位置实例，避免导航栈中的来源页或目标页保留旧快照。
void invalidateLibraryBrowserData(WidgetRef ref) {
  ref.invalidate(libraryBrowserProvider);
}

List<SubjectFolder> _folderPath(List<SubjectFolder> folders, String folderId) {
  final byId = {for (final folder in folders) folder.id: folder};
  final path = <SubjectFolder>[];
  var current = byId[folderId];
  while (current != null) {
    path.add(current);
    current = current.parentId == null ? null : byId[current.parentId];
  }
  return path.reversed.toList();
}

List<LibraryBreadcrumb> _subjectBreadcrumbs(
  List<Subject> subjects,
  List<SubjectFolder> folders,
  Subject target,
) {
  final byId = {for (final subject in subjects) subject.id: subject};
  final subjectPath = <Subject>[];
  var current = target;
  while (true) {
    subjectPath.add(current);
    if (current.parentId == null) break;
    final parent = byId[current.parentId];
    if (parent == null) break;
    current = parent;
  }
  final result = <LibraryBreadcrumb>[
    const LibraryBreadcrumb(label: '笔记', location: LibraryLocation.root()),
  ];
  final book = subjectPath.last;
  if (book.folderId != null) {
    result.addAll(
      _folderPath(folders, book.folderId!).map(
        (folder) => LibraryBreadcrumb(
          label: folder.name,
          location: LibraryLocation.folder(folder.id),
        ),
      ),
    );
  } else {
    result.add(
      const LibraryBreadcrumb(
        label: '未归类书',
        location: LibraryLocation.ungroupedBooks(),
      ),
    );
  }
  result.addAll(
    subjectPath.reversed.map(
      (subject) => LibraryBreadcrumb(
        label: subject.name,
        location: LibraryLocation.subject(subject.id),
      ),
    ),
  );
  return result;
}
