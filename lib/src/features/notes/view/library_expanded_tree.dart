// 文件: lib/src/features/notes/view/library_expanded_tree.dart
// 作用: 在笔记主页同页展示文件夹与书—章—节的可展开树。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/errors/result.dart';
import '../models/library_organization.dart';
import '../models/note.dart';
import '../models/library_location.dart';
import '../models/subject.dart';
import '../models/subject_folder.dart';
import '../note_constants.dart';
import '../providers.dart';
import 'library_item_action_menu.dart';

typedef LibraryExpandedAction =
    void Function(
      LibraryItemKind kind,
      String itemId,
      String itemName,
      String? parentId,
      LibraryItemAction action,
    );

final expandedLibraryProvider = FutureProvider.autoDispose<ExpandedLibraryData>(
  (ref) async {
    T value<T>(Result<T> result) => switch (result) {
      Success<T>(:final value) => value,
      Failure<T>(:final exception) => throw exception,
    };
    final folders = value(await ref.read(folderRepositoryProvider).listAll());
    final subjects = value(await ref.read(subjectRepositoryProvider).listAll());
    final notes = value(await ref.read(noteRepositoryProvider).listAll());
    return ExpandedLibraryData(
      folders: folders,
      subjects: subjects,
      notes: notes,
    );
  },
);

void refreshLibraryExpandedTree(WidgetRef ref) {
  ref.invalidate(expandedLibraryProvider);
}

class LibraryExpandedTree extends ConsumerWidget {
  final LibraryLocation location;
  final LibraryExpandedAction? onAction;

  const LibraryExpandedTree({super.key, required this.location, this.onAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(expandedLibraryProvider);
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('加载失败：$error')),
      data: (value) => ListView(
        key: const Key('library-browser-expanded-mode'),
        children: _childrenForLocation(value),
      ),
    );
  }

  List<Widget> _childrenForLocation(ExpandedLibraryData data) =>
      switch (location) {
        LibraryRootLocation() => [
          ...data.rootFolders.map(
            (folder) =>
                _FolderNode(data: data, folder: folder, onAction: onAction),
          ),
          if (data.ungroupedBooks.isNotEmpty)
            ExpansionTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('未归类书籍'),
              children: data.ungroupedBooks
                  .map(
                    (book) => _SubjectNode(
                      data: data,
                      subject: book,
                      depth: 0,
                      onAction: onAction,
                    ),
                  )
                  .toList(),
            ),
          ...data.rootNotes.map(
            (note) => _NoteTile(note: note, depth: 0, onAction: onAction),
          ),
        ],
        LibraryFolderLocation(:final folderId) => [
          if (data.folderById(folderId) case final folder?)
            _FolderNode(data: data, folder: folder, onAction: onAction),
        ],
        LibraryUngroupedBooksLocation() => [
          ...data.ungroupedBooks.map(
            (book) => _SubjectNode(
              data: data,
              subject: book,
              depth: 0,
              onAction: onAction,
            ),
          ),
        ],
        LibrarySubjectLocation(:final subjectId) => [
          if (data.subjectById(subjectId) case final subject?)
            _SubjectNode(
              data: data,
              subject: subject,
              depth: 0,
              onAction: onAction,
            ),
        ],
      };
}

class ExpandedLibraryData {
  final List<SubjectFolder> folders;
  final List<Subject> subjects;
  final List<Note> notes;

  const ExpandedLibraryData({
    required this.folders,
    required this.subjects,
    required this.notes,
  });

  List<SubjectFolder> get rootFolders =>
      _sortedFolders(folders.where((folder) => folder.parentId == null));
  SubjectFolder? folderById(String id) =>
      folders.where((folder) => folder.id == id).firstOrNull;
  Subject? subjectById(String id) =>
      subjects.where((subject) => subject.id == id).firstOrNull;
  List<SubjectFolder> foldersIn(String id) =>
      _sortedFolders(folders.where((folder) => folder.parentId == id));
  List<Subject> booksIn(String? folderId) => _sortedSubjects(
    subjects.where(
      (subject) => subject.level == 0 && subject.folderId == folderId,
    ),
  );
  List<Subject> childrenOf(String id) =>
      _sortedSubjects(subjects.where((subject) => subject.parentId == id));
  List<Note> notesIn(String id) =>
      _sortedNotes(notes.where((note) => note.subjectId == id));
  List<Note> get rootNotes =>
      _sortedNotes(notes.where((note) => note.subjectId == defaultSubjectId));
  List<Subject> get ungroupedBooks => booksIn(null);

  List<SubjectFolder> _sortedFolders(Iterable<SubjectFolder> values) =>
      values.toList()..sort((left, right) {
        final byOrder = left.sortOrder.compareTo(right.sortOrder);
        if (byOrder != 0) return byOrder;
        final byCreatedAt = left.createdAt.compareTo(right.createdAt);
        if (byCreatedAt != 0) return byCreatedAt;
        return left.id.compareTo(right.id);
      });

  List<Subject> _sortedSubjects(Iterable<Subject> values) =>
      values.toList()..sort((left, right) {
        final byOrder = left.sortOrder.compareTo(right.sortOrder);
        if (byOrder != 0) return byOrder;
        final byCreatedAt = left.createdAt.compareTo(right.createdAt);
        if (byCreatedAt != 0) return byCreatedAt;
        return left.id.compareTo(right.id);
      });

  List<Note> _sortedNotes(Iterable<Note> values) =>
      values.toList()..sort((left, right) {
        final byOrder = left.sortOrder.compareTo(right.sortOrder);
        if (byOrder != 0) return byOrder;
        final byCreatedAt = left.createdAt.compareTo(right.createdAt);
        if (byCreatedAt != 0) return byCreatedAt;
        return left.id.compareTo(right.id);
      });
}

class _FolderNode extends StatelessWidget {
  final ExpandedLibraryData data;
  final SubjectFolder folder;
  final LibraryExpandedAction? onAction;

  const _FolderNode({
    required this.data,
    required this.folder,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: const Icon(Icons.folder_outlined),
    title: Text(folder.name),
    trailing: onAction == null
        ? null
        : LibraryItemActionMenu(
            key: ValueKey('library-item-menu-folder-${folder.id}'),
            kind: LibraryItemKind.folder,
            onSelected: (action) => onAction!(
              LibraryItemKind.folder,
              folder.id,
              folder.name,
              folder.parentId,
              action,
            ),
          ),
    children: [
      ...data
          .foldersIn(folder.id)
          .map(
            (child) =>
                _FolderNode(data: data, folder: child, onAction: onAction),
          ),
      ...data
          .booksIn(folder.id)
          .map(
            (book) => _SubjectNode(
              data: data,
              subject: book,
              depth: 0,
              onAction: onAction,
            ),
          ),
    ],
  );
}

class _SubjectNode extends StatelessWidget {
  final ExpandedLibraryData data;
  final Subject subject;
  final int depth;
  final LibraryExpandedAction? onAction;
  const _SubjectNode({
    required this.data,
    required this.subject,
    required this.depth,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final children = data.childrenOf(subject.id);
    final notes = data.notesIn(subject.id);
    final icon = const {
      0: Icons.menu_book_outlined,
      1: Icons.bookmark_outline,
      2: Icons.article_outlined,
    }[subject.level]!;
    final kind = _subjectKind(subject);
    final menu = onAction == null
        ? null
        : LibraryItemActionMenu(
            key: ValueKey('library-item-menu-${kind.name}-${subject.id}'),
            kind: kind,
            onSelected: (action) => onAction!(
              kind,
              subject.id,
              subject.name,
              subject.level == 0 ? subject.folderId : subject.parentId,
              action,
            ),
          );
    if (children.isEmpty && notes.isEmpty) {
      return ListTile(
        leading: Icon(icon),
        title: Text(subject.name),
        trailing: menu,
      );
    }
    return ExpansionTile(
      leading: Icon(icon),
      title: Text(subject.name),
      trailing: menu,
      childrenPadding: EdgeInsets.only(left: 16.0 + depth * 12),
      children: [
        ...notes.map(
          (note) => _NoteTile(note: note, depth: depth + 1, onAction: onAction),
        ),
        ...children.map(
          (child) => _SubjectNode(
            data: data,
            subject: child,
            depth: depth + 1,
            onAction: onAction,
          ),
        ),
      ],
    );
  }
}

class _NoteTile extends StatelessWidget {
  final Note note;
  final int depth;
  final LibraryExpandedAction? onAction;

  const _NoteTile({
    required this.note,
    required this.depth,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.only(left: 32.0 + depth * 16, right: 12),
    leading: const Icon(Icons.description_outlined),
    title: Text(note.displayTitle),
    subtitle: Text(note.summary, maxLines: 1),
    trailing: onAction == null
        ? null
        : LibraryItemActionMenu(
            key: ValueKey('library-item-menu-note-${note.id}'),
            kind: LibraryItemKind.note,
            onSelected: (action) => onAction!(
              LibraryItemKind.note,
              note.id,
              note.displayTitle,
              note.subjectId,
              action,
            ),
          ),
    onTap: () => context.push('/notes/editor/${note.id}'),
  );
}

LibraryItemKind _subjectKind(Subject subject) => switch (subject.level) {
  0 => LibraryItemKind.book,
  1 => LibraryItemKind.chapter,
  2 => LibraryItemKind.section,
  _ => throw StateError('未知书章节层级：${subject.level}'),
};
