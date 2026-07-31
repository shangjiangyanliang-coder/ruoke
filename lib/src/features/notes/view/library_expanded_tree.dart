// 文件: lib/src/features/notes/view/library_expanded_tree.dart
// 作用: 在笔记主页同页展示文件夹与书—章—节的可展开树。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/errors/result.dart';
import '../models/note.dart';
import '../models/library_location.dart';
import '../models/subject.dart';
import '../models/subject_folder.dart';
import '../note_constants.dart';
import '../providers.dart';

final _expandedLibraryProvider =
    FutureProvider.autoDispose<_ExpandedLibraryData>((ref) async {
      T value<T>(Result<T> result) => switch (result) {
        Success<T>(:final value) => value,
        Failure<T>(:final exception) => throw exception,
      };
      final folders = value(await ref.read(folderRepositoryProvider).listAll());
      final subjects = value(
        await ref.read(subjectRepositoryProvider).listAll(),
      );
      final notes = value(await ref.read(noteRepositoryProvider).listAll());
      return _ExpandedLibraryData(
        folders: folders,
        subjects: subjects,
        notes: notes,
      );
    });

void refreshLibraryExpandedTree(WidgetRef ref) {
  ref.invalidate(_expandedLibraryProvider);
}

class LibraryExpandedTree extends ConsumerWidget {
  final LibraryLocation location;
  const LibraryExpandedTree({super.key, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_expandedLibraryProvider);
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('加载失败：$error')),
      data: (value) => ListView(
        key: const Key('library-browser-expanded-mode'),
        children: _childrenForLocation(value),
      ),
    );
  }

  List<Widget> _childrenForLocation(_ExpandedLibraryData data) =>
      switch (location) {
        LibraryRootLocation() => [
          ...data.rootFolders.map(
            (folder) => _FolderNode(data: data, folder: folder),
          ),
          if (data.ungroupedBooks.isNotEmpty)
            ExpansionTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('未归类书籍'),
              children: data.ungroupedBooks
                  .map(
                    (book) => _SubjectNode(data: data, subject: book, depth: 0),
                  )
                  .toList(),
            ),
          ...data.rootNotes.map((note) => _NoteTile(note: note, depth: 0)),
        ],
        LibraryFolderLocation(:final folderId) => [
          if (data.folderById(folderId) case final folder?)
            _FolderNode(data: data, folder: folder),
        ],
        LibraryUngroupedBooksLocation() => [
          ...data.ungroupedBooks.map(
            (book) => _SubjectNode(data: data, subject: book, depth: 0),
          ),
        ],
        LibrarySubjectLocation(:final subjectId) => [
          if (data.subjectById(subjectId) case final subject?)
            _SubjectNode(data: data, subject: subject, depth: 0),
        ],
      };
}

class _ExpandedLibraryData {
  final List<SubjectFolder> folders;
  final List<Subject> subjects;
  final List<Note> notes;

  const _ExpandedLibraryData({
    required this.folders,
    required this.subjects,
    required this.notes,
  });

  List<SubjectFolder> get rootFolders =>
      folders.where((folder) => folder.parentId == null).toList();
  SubjectFolder? folderById(String id) =>
      folders.where((folder) => folder.id == id).firstOrNull;
  Subject? subjectById(String id) =>
      subjects.where((subject) => subject.id == id).firstOrNull;
  List<SubjectFolder> foldersIn(String id) =>
      folders.where((folder) => folder.parentId == id).toList();
  List<Subject> booksIn(String? folderId) => subjects
      .where((subject) => subject.level == 0 && subject.folderId == folderId)
      .toList();
  List<Subject> childrenOf(String id) =>
      subjects.where((subject) => subject.parentId == id).toList();
  List<Note> notesIn(String id) =>
      _sortedNotes(notes.where((note) => note.subjectId == id));
  List<Note> get rootNotes =>
      _sortedNotes(notes.where((note) => note.subjectId == defaultSubjectId));
  List<Subject> get ungroupedBooks => booksIn(null);

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
  final _ExpandedLibraryData data;
  final SubjectFolder folder;
  const _FolderNode({required this.data, required this.folder});

  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: const Icon(Icons.folder_outlined),
    title: Text(folder.name),
    children: [
      ...data
          .foldersIn(folder.id)
          .map((child) => _FolderNode(data: data, folder: child)),
      ...data
          .booksIn(folder.id)
          .map((book) => _SubjectNode(data: data, subject: book, depth: 0)),
    ],
  );
}

class _SubjectNode extends StatelessWidget {
  final _ExpandedLibraryData data;
  final Subject subject;
  final int depth;
  const _SubjectNode({
    required this.data,
    required this.subject,
    required this.depth,
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
    if (children.isEmpty && notes.isEmpty) {
      return ListTile(leading: Icon(icon), title: Text(subject.name));
    }
    return ExpansionTile(
      leading: Icon(icon),
      title: Text(subject.name),
      childrenPadding: EdgeInsets.only(left: 16.0 + depth * 12),
      children: [
        ...notes.map((note) => _NoteTile(note: note, depth: depth + 1)),
        ...children.map(
          (child) => _SubjectNode(data: data, subject: child, depth: depth + 1),
        ),
      ],
    );
  }
}

class _NoteTile extends StatelessWidget {
  final Note note;
  final int depth;
  const _NoteTile({required this.note, required this.depth});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.only(left: 32.0 + depth * 16, right: 12),
    leading: const Icon(Icons.description_outlined),
    title: Text(note.displayTitle),
    subtitle: Text(note.summary, maxLines: 1),
    onTap: () => context.push('/notes/editor/${note.id}'),
  );
}
