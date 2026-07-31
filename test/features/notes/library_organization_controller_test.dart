// 作用：验证目录组织控制器对三类仓储的稳定分派与错误透传。
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/library_organization.dart';
import 'package:ruoke/src/features/notes/models/note.dart';
import 'package:ruoke/src/features/notes/models/note_search_query.dart';
import 'package:ruoke/src/features/notes/models/note_version.dart';
import 'package:ruoke/src/features/notes/models/subject.dart';
import 'package:ruoke/src/features/notes/models/subject_folder.dart';
import 'package:ruoke/src/features/notes/models/subject_path.dart';
import 'package:ruoke/src/features/notes/repository/folder_repository.dart';
import 'package:ruoke/src/features/notes/repository/note_repository.dart';
import 'package:ruoke/src/features/notes/repository/subject_repository.dart';
import 'package:ruoke/src/features/notes/view_model/library_organization_controller.dart';

void main() {
  late _FolderRepositoryFake folders;
  late _SubjectRepositoryFake subjects;
  late _NoteRepositoryFake notes;
  late LibraryOrganizationController controller;

  setUp(() {
    folders = _FolderRepositoryFake();
    subjects = _SubjectRepositoryFake();
    notes = _NoteRepositoryFake();
    controller = LibraryOrganizationController(
      folders: folders,
      subjects: subjects,
      notes: notes,
    );
  });

  test('loadSiblings 按五类项目读取正确仓储', () async {
    folders.folderChildren = [_folder('folder-a')];
    folders.bookChildren = [_subject('book-a', 0)];
    subjects.children = [_subject('subject-a', 1)];
    notes.children = [_note('note-a')];

    final folderItems = _success(
      await controller.loadSiblings(
        const LibraryReorderRequest(
          kind: LibraryItemKind.folder,
          parentId: 'parent-folder',
          title: '文件夹排序',
        ),
      ),
    );
    final bookItems = _success(
      await controller.loadSiblings(
        const LibraryReorderRequest(
          kind: LibraryItemKind.book,
          parentId: 'folder',
          title: '书排序',
        ),
      ),
    );
    final chapterItems = _success(
      await controller.loadSiblings(
        const LibraryReorderRequest(
          kind: LibraryItemKind.chapter,
          parentId: 'book',
          title: '章排序',
        ),
      ),
    );
    await controller.loadSiblings(
      const LibraryReorderRequest(
        kind: LibraryItemKind.section,
        parentId: 'chapter',
        title: '节排序',
      ),
    );
    final noteItems = _success(
      await controller.loadSiblings(
        const LibraryReorderRequest(
          kind: LibraryItemKind.note,
          parentId: 'section',
          title: '笔记排序',
        ),
      ),
    );

    expect(folderItems.single.label, 'folder-a');
    expect(bookItems.single.label, 'book-a');
    expect(chapterItems.single.label, 'subject-a');
    expect(noteItems.single.label, 'note-a');
    expect(folders.childrenCalls, ['parent-folder']);
    expect(folders.booksCalls, ['folder']);
    expect(subjects.childrenCalls, ['book', 'chapter']);
    expect(notes.listBySubjectCalls, ['section']);
  });

  test('saveOrder 按项目类型调用正确完整列表重排接口', () async {
    for (final request in _reorderRequests) {
      final result = await controller.saveOrder(request, const ['b', 'a']);
      expect(result, isA<Success<void>>());
    }

    expect(folders.reorderFolderCalls.single.orderedIds, ['b', 'a']);
    expect(folders.reorderBookCalls.single.orderedIds, ['b', 'a']);
    expect(subjects.reorderCalls, hasLength(2));
    expect(notes.reorderCalls.single.orderedIds, ['b', 'a']);
  });

  test('loadTargets 和 loadTargetSiblings 保留层级规则与目标父级', () async {
    folders.allFolders = [_folder('folder-a')];
    subjects.allSubjects = [_subject('book-a', 0, folderId: 'folder-a')];
    folders.bookChildren = [_subject('existing-book', 0)];
    final request = const LibraryMoveRequest(
      kind: LibraryItemKind.chapter,
      itemId: 'chapter-a',
      itemName: '章 A',
    );

    final targets = _success(await controller.loadTargets(request));
    final bookTarget = targets.singleWhere((target) => target.id == 'book-a');
    final siblings = _success(
      await controller.loadTargetSiblings(
        const LibraryMoveRequest(
          kind: LibraryItemKind.book,
          itemId: 'moving-book',
          itemName: '待移动书',
        ),
        const LibraryMoveTarget(
          kind: LibraryItemKind.folder,
          id: 'folder-a',
          parentId: null,
          label: 'folder-a',
          pathLabels: ['folder-a'],
          canSelect: true,
        ),
      ),
    );

    expect(bookTarget.canSelect, isTrue);
    expect(siblings.single.id, 'existing-book');
    expect(folders.booksCalls.last, 'folder-a');
  });

  test('move 将目标 id 和索引原样传入五类仓储接口', () async {
    await controller.move(
      const LibraryMoveRequest(
        kind: LibraryItemKind.folder,
        itemId: 'folder-moving',
        itemName: '文件夹',
      ),
      _target(LibraryItemKind.folder, null),
      0,
    );
    await controller.move(
      const LibraryMoveRequest(
        kind: LibraryItemKind.book,
        itemId: 'book-moving',
        itemName: '书',
      ),
      _target(LibraryItemKind.folder, 'folder-target'),
      1,
    );
    await controller.move(
      const LibraryMoveRequest(
        kind: LibraryItemKind.chapter,
        itemId: 'chapter-moving',
        itemName: '章',
      ),
      _target(LibraryItemKind.book, 'book-target'),
      2,
    );
    await controller.move(
      const LibraryMoveRequest(
        kind: LibraryItemKind.section,
        itemId: 'section-moving',
        itemName: '节',
      ),
      _target(LibraryItemKind.chapter, 'chapter-target'),
      3,
    );
    await controller.move(
      const LibraryMoveRequest(
        kind: LibraryItemKind.note,
        itemId: 'note-moving',
        itemName: '笔记',
      ),
      _target(LibraryItemKind.section, 'section-target'),
      4,
    );

    expect(folders.moveFolderCalls.single, ('folder-moving', null, 0));
    expect(folders.moveBookCalls.single, ('book-moving', 'folder-target', 1));
    expect(subjects.moveCalls, [
      ('chapter-moving', 'book-target', 2),
      ('section-moving', 'chapter-target', 3),
    ]);
    expect(notes.moveCalls.single, ('note-moving', 'section-target', 4));
  });

  test('仓储 Failure 原样返回且不会被吞掉', () async {
    const exception = ValidationException('模拟列表变化');
    folders.childrenResult = const Failure(exception);

    final result = await controller.loadSiblings(
      const LibraryReorderRequest(
        kind: LibraryItemKind.folder,
        parentId: null,
        title: '排序',
      ),
    );

    expect(result, isA<Failure<List<LibraryOrderItem>>>());
    expect(
      (result as Failure<List<LibraryOrderItem>>).exception,
      same(exception),
    );
  });
}

const _reorderRequests = [
  LibraryReorderRequest(
    kind: LibraryItemKind.folder,
    parentId: 'folder-parent',
    title: '文件夹',
  ),
  LibraryReorderRequest(
    kind: LibraryItemKind.book,
    parentId: 'folder',
    title: '书',
  ),
  LibraryReorderRequest(
    kind: LibraryItemKind.chapter,
    parentId: 'book',
    title: '章',
  ),
  LibraryReorderRequest(
    kind: LibraryItemKind.section,
    parentId: 'chapter',
    title: '节',
  ),
  LibraryReorderRequest(
    kind: LibraryItemKind.note,
    parentId: 'section',
    title: '笔记',
  ),
];

LibraryMoveTarget _target(LibraryItemKind kind, String? id) =>
    LibraryMoveTarget(
      kind: kind,
      id: id,
      parentId: null,
      label: id ?? '根目录',
      pathLabels: [id ?? '根目录'],
      canSelect: true,
    );

class _FolderRepositoryFake implements FolderRepository {
  List<SubjectFolder> allFolders = [];
  List<SubjectFolder> folderChildren = [];
  List<Subject> bookChildren = [];
  Result<List<SubjectFolder>>? childrenResult;
  final childrenCalls = <String?>[];
  final booksCalls = <String?>[];
  final reorderFolderCalls = <({String? parentId, List<String> orderedIds})>[];
  final reorderBookCalls = <({String? folderId, List<String> orderedIds})>[];
  final moveFolderCalls = <(String, String?, int)>[];
  final moveBookCalls = <(String, String?, int)>[];

  @override
  Future<Result<List<SubjectFolder>>> listAll() async => Success(allFolders);

  @override
  Future<Result<List<SubjectFolder>>> childrenOf(String? parentId) async {
    childrenCalls.add(parentId);
    return childrenResult ?? Success(folderChildren);
  }

  @override
  Future<Result<List<Subject>>> booksIn(String? folderId) async {
    booksCalls.add(folderId);
    return Success(bookChildren);
  }

  @override
  Future<Result<void>> reorderFolders({
    required String? parentId,
    required List<String> orderedIds,
  }) async {
    reorderFolderCalls.add((parentId: parentId, orderedIds: orderedIds));
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> reorderBooks({
    required String? folderId,
    required List<String> orderedIds,
  }) async {
    reorderBookCalls.add((folderId: folderId, orderedIds: orderedIds));
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> moveFolder({
    required String folderId,
    required String? newParentId,
    required int targetIndex,
  }) async {
    moveFolderCalls.add((folderId, newParentId, targetIndex));
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> moveBook({
    required String bookId,
    required String? folderId,
    required int targetIndex,
  }) async {
    moveBookCalls.add((bookId, folderId, targetIndex));
    return const Success<void>(null);
  }

  @override
  Future<Result<String>> create({required String name, String? parentId}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> rename({required String id, required String name}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> dissolve(String folderId) => throw UnimplementedError();
}

class _SubjectRepositoryFake implements SubjectRepository {
  List<Subject> allSubjects = [];
  List<Subject> children = [];
  final childrenCalls = <String?>[];
  final reorderCalls = <({String parentId, List<String> orderedIds})>[];
  final moveCalls = <(String, String, int)>[];

  @override
  Future<Result<List<Subject>>> listAll() async => Success(allSubjects);

  @override
  Future<Result<List<Subject>>> childrenOf(String? parentId) async {
    childrenCalls.add(parentId);
    return Success(children);
  }

  @override
  Future<Result<void>> reorderChildren({
    required String parentId,
    required List<String> orderedIds,
  }) async {
    reorderCalls.add((parentId: parentId, orderedIds: orderedIds));
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> moveSubject({
    required String subjectId,
    required String newParentId,
    required int targetIndex,
  }) async {
    moveCalls.add((subjectId, newParentId, targetIndex));
    return const Success<void>(null);
  }

  @override
  Future<Result<Subject?>> getById(String id) => throw UnimplementedError();

  @override
  Future<Result<String>> create({
    required String name,
    required int level,
    String? parentId,
    String? folderId,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> rename({required String id, required String name}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> softDelete(String id) => throw UnimplementedError();

  @override
  Future<Result<int>> countChildren(String? parentId) =>
      throw UnimplementedError();

  @override
  Future<Result<bool>> isEmpty() => throw UnimplementedError();

  @override
  Future<Result<List<SubjectPath>>> searchPaths(String keyword) =>
      throw UnimplementedError();
}

class _NoteRepositoryFake implements NoteRepository {
  List<Note> children = [];
  final listBySubjectCalls = <String>[];
  final reorderCalls = <({String subjectId, List<String> orderedIds})>[];
  final moveCalls = <(String, String, int)>[];

  @override
  Future<Result<List<Note>>> listBySubject(String subjectId) async {
    listBySubjectCalls.add(subjectId);
    return Success(children);
  }

  @override
  Future<Result<void>> reorderNotes({
    required String subjectId,
    required List<String> orderedIds,
  }) async {
    reorderCalls.add((subjectId: subjectId, orderedIds: orderedIds));
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> moveNote({
    required String noteId,
    required String subjectId,
    required int targetIndex,
  }) async {
    moveCalls.add((noteId, subjectId, targetIndex));
    return const Success<void>(null);
  }

  @override
  Future<Result<List<Note>>> listAll() => throw UnimplementedError();

  @override
  Future<Result<Note?>> getById(String id) => throw UnimplementedError();

  @override
  Future<Result<List<Note>>> search(NoteSearchQuery query) =>
      throw UnimplementedError();

  @override
  Future<Result<Note>> create({
    required String subjectId,
    String? title,
    String? contentJson,
    String? plainText,
    bool isDraft = false,
    Iterable<String> tagNames = const [],
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> update({
    required String id,
    String? title,
    String? contentJson,
    String? plainText,
    bool? isDraft,
    Iterable<String>? tagNames,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> renameTitle({
    required String id,
    required String title,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> softDelete(String id) => throw UnimplementedError();

  @override
  Future<Result<List<NoteVersion>>> listVersions(String noteId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> renameVersion({
    required String noteId,
    required String versionId,
    required String? name,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> deleteVersions({
    required String noteId,
    required Set<String> versionIds,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> restoreVersion({
    required String noteId,
    required int versionNo,
    bool saveCurrentBeforeRestore = false,
  }) => throw UnimplementedError();
}

SubjectFolder _folder(String id) => SubjectFolder(
  id: id,
  parentId: null,
  name: id,
  sortOrder: 0,
  createdAt: 1,
  updatedAt: 1,
  isDeleted: false,
  deletedAt: null,
);

Subject _subject(String id, int level, {String? folderId}) => Subject(
  id: id,
  parentId: null,
  name: id,
  level: level,
  folderId: folderId,
  sortOrder: 0,
  createdAt: 1,
  updatedAt: 1,
  isDeleted: false,
  deletedAt: null,
);

Note _note(String id) => Note(
  id: id,
  subjectId: 'subject',
  title: id,
  contentJson: null,
  plainText: '',
  isDraft: false,
  isAiHidden: false,
  sourceType: null,
  sourceRef: null,
  lastReadAt: null,
  createdAt: 1,
  updatedAt: 1,
  isDeleted: false,
  deletedAt: null,
);

T _success<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}
