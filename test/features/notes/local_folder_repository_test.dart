// 文件夹本地仓储的真实 SQLite 行为测试。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/repository/local_folder_repository.dart';

void main() {
  late AppDatabase db;
  late LocalFolderRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LocalFolderRepository(db);
  });

  tearDown(() => db.close());

  test('创建根文件夹会修剪名称并持久化', () async {
    final folderId = _success(await repository.create(name: '  高中课程  '));

    final roots = _success(await repository.childrenOf(null));

    expect(roots, hasLength(1));
    expect(roots.single.id, folderId);
    expect(roots.single.parentId, isNull);
    expect(roots.single.name, '高中课程');
  });

  test('连续创建文件夹会追加到同级末尾并使用连续顺序', () async {
    final first = _success(await repository.create(name: '第一'));
    final second = _success(await repository.create(name: '第二'));

    expect(
      _success(
        await repository.childrenOf(null),
      ).map((folder) => (folder.id, folder.sortOrder)),
      [(first, 0), (second, 1)],
    );
  });

  test('文件夹和书读取在顺序重复时按创建时间与 id 稳定排序', () async {
    await _insertFolder(db, id: 'folder-b', sortOrder: 2, createdAt: 20);
    await _insertFolder(db, id: 'folder-c', sortOrder: 2, createdAt: 10);
    await _insertFolder(db, id: 'folder-a', sortOrder: 2, createdAt: 10);
    await _insertBook(db, id: 'book-b', sortOrder: 3, createdAt: 20);
    await _insertBook(db, id: 'book-c', sortOrder: 3, createdAt: 10);
    await _insertBook(db, id: 'book-a', sortOrder: 3, createdAt: 10);

    expect(
      _success(await repository.childrenOf(null)).map((folder) => folder.id),
      ['folder-a', 'folder-c', 'folder-b'],
    );
    expect(_success(await repository.booksIn(null)).map((book) => book.id), [
      'book-a',
      'book-c',
      'book-b',
    ]);
  });

  test('空白文件夹名称会被拒绝且不写入记录', () async {
    final result = await repository.create(name: '   ');

    expect(result, isA<Failure<String>>());
    expect((result as Failure<String>).exception, isA<ValidationException>());
    expect(_success(await repository.childrenOf(null)), isEmpty);
  });

  test('同一父目录下的重名文件夹会被拒绝', () async {
    final firstId = _success(await repository.create(name: '数学'));

    final duplicate = await repository.create(name: ' 数学 ');

    expect(duplicate, isA<Failure<String>>());
    expect(
      (duplicate as Failure<String>).exception,
      isA<ValidationException>(),
    );
    final roots = _success(await repository.childrenOf(null));
    expect(roots, hasLength(1));
    expect(roots.single.id, firstId);
  });

  test('不存在的父文件夹会阻止创建子文件夹', () async {
    final result = await repository.create(name: '孤立文件夹', parentId: 'missing');

    expect(result, isA<Failure<String>>());
    expect((result as Failure<String>).exception, isA<ValidationException>());
    expect(_success(await repository.childrenOf(null)), isEmpty);
  });

  test('重命名文件夹会修剪名称并持久化', () async {
    final folderId = _success(await repository.create(name: '旧名称'));

    final result = await repository.rename(id: folderId, name: '  新名称  ');

    expect(result, isA<Success<void>>());
    expect(_success(await repository.childrenOf(null)).single.name, '新名称');
  });

  test('重命名为同级已存在名称会被拒绝', () async {
    final firstId = _success(await repository.create(name: '语文'));
    await repository.create(name: '数学');

    final result = await repository.rename(id: firstId, name: ' 数学 ');

    expect(result, isA<Failure<void>>());
    expect((result as Failure<void>).exception, isA<ValidationException>());
    expect(
      _success(await repository.childrenOf(null)).map((folder) => folder.name),
      containsAll(['语文', '数学']),
    );
  });

  test('重命名为空白名称会被拒绝且原名称保持不变', () async {
    final folderId = _success(await repository.create(name: '原名称'));

    final result = await repository.rename(id: folderId, name: '   ');

    expect(result, isA<Failure<void>>());
    expect(_success(await repository.childrenOf(null)).single.name, '原名称');
  });

  test('文件夹和书可按完整同级 id 列表重排', () async {
    await _insertFolder(db, id: 'folder-a', sortOrder: 0);
    await _insertFolder(db, id: 'folder-b', sortOrder: 1);
    await _insertFolder(db, id: 'folder-c', sortOrder: 2);
    await _insertBook(db, id: 'book-a', sortOrder: 0);
    await _insertBook(db, id: 'book-b', sortOrder: 1);
    await _insertBook(db, id: 'book-c', sortOrder: 2);

    final folderResult = await repository.reorderFolders(
      parentId: null,
      orderedIds: const ['folder-c', 'folder-a', 'folder-b'],
    );
    final bookResult = await repository.reorderBooks(
      folderId: null,
      orderedIds: const ['book-b', 'book-c', 'book-a'],
    );

    expect(folderResult, isA<Success<void>>());
    expect(bookResult, isA<Success<void>>());
    expect(
      _success(
        await repository.childrenOf(null),
      ).map((folder) => (folder.id, folder.sortOrder)),
      [('folder-c', 0), ('folder-a', 1), ('folder-b', 2)],
    );
    expect(
      _success(
        await repository.booksIn(null),
      ).map((book) => (book.id, book.sortOrder)),
      [('book-b', 0), ('book-c', 1), ('book-a', 2)],
    );
  });

  test('非法文件夹重排列表会失败并保持原顺序', () async {
    await _insertFolder(db, id: 'folder-a', sortOrder: 0);
    await _insertFolder(db, id: 'folder-b', sortOrder: 1);
    await _insertFolder(db, id: 'folder-c', sortOrder: 2, isDeleted: true);
    final invalidLists = <List<String>>[
      ['folder-a'],
      ['folder-a', 'folder-a'],
      ['folder-a', 'folder-c'],
      ['folder-a', 'missing'],
    ];

    for (final orderedIds in invalidLists) {
      final result = await repository.reorderFolders(
        parentId: null,
        orderedIds: orderedIds,
      );

      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).exception, isA<ValidationException>());
      expect(
        _success(await repository.childrenOf(null)).map((folder) => folder.id),
        ['folder-a', 'folder-b'],
      );
    }
  });

  test('非法书重排列表会失败并保持原顺序', () async {
    final folder = _success(await repository.create(name: '目标目录'));
    await _insertBook(db, id: 'book-a', folderId: folder, sortOrder: 0);
    await _insertBook(db, id: 'book-b', folderId: folder, sortOrder: 1);
    await _insertBook(db, id: 'book-other', sortOrder: 0);

    final result = await repository.reorderBooks(
      folderId: folder,
      orderedIds: const ['book-b', 'book-other'],
    );

    expect(result, isA<Failure<void>>());
    expect((result as Failure<void>).exception, isA<ValidationException>());
    expect(_success(await repository.booksIn(folder)).map((book) => book.id), [
      'book-a',
      'book-b',
    ]);
  });

  test('移动文件夹会改变直属归属', () async {
    final sourceParent = _success(await repository.create(name: '来源'));
    final targetParent = _success(await repository.create(name: '目标'));
    final child = _success(
      await repository.create(name: '待移动', parentId: sourceParent),
    );

    final result = await repository.moveFolder(
      folderId: child,
      newParentId: targetParent,
      targetIndex: 0,
    );

    expect(result, isA<Success<void>>());
    expect(_success(await repository.childrenOf(sourceParent)), isEmpty);
    expect(
      _success(await repository.childrenOf(targetParent)).single.id,
      child,
    );
  });

  test('跨目录移动文件夹会准确插入并重排来源与目标', () async {
    final source = _success(await repository.create(name: '来源'));
    final target = _success(await repository.create(name: '目标'));
    final sourceFirst = _success(
      await repository.create(name: '来源第一', parentId: source),
    );
    final moving = _success(
      await repository.create(name: '待移动', parentId: source),
    );
    final sourceLast = _success(
      await repository.create(name: '来源末尾', parentId: source),
    );
    final targetFirst = _success(
      await repository.create(name: '目标第一', parentId: target),
    );
    final targetLast = _success(
      await repository.create(name: '目标末尾', parentId: target),
    );

    final result = await repository.moveFolder(
      folderId: moving,
      newParentId: target,
      targetIndex: 1,
    );

    expect(result, isA<Success<void>>());
    expect(
      _success(
        await repository.childrenOf(source),
      ).map((folder) => (folder.id, folder.sortOrder)),
      [(sourceFirst, 0), (sourceLast, 1)],
    );
    expect(
      _success(
        await repository.childrenOf(target),
      ).map((folder) => (folder.id, folder.sortOrder)),
      [(targetFirst, 0), (moving, 1), (targetLast, 2)],
    );
  });

  test('同目录移动文件夹可插入开头', () async {
    final first = _success(await repository.create(name: '第一'));
    final second = _success(await repository.create(name: '第二'));
    final third = _success(await repository.create(name: '第三'));

    final result = await repository.moveFolder(
      folderId: third,
      newParentId: null,
      targetIndex: 0,
    );

    expect(result, isA<Success<void>>());
    expect(
      _success(await repository.childrenOf(null)).map((folder) => folder.id),
      [third, first, second],
    );
  });

  test('移动文件夹到其后代会被拒绝', () async {
    final ancestor = _success(await repository.create(name: '祖先'));
    final child = _success(
      await repository.create(name: '后代', parentId: ancestor),
    );

    final result = await repository.moveFolder(
      folderId: ancestor,
      newParentId: child,
      targetIndex: 0,
    );

    expect(result, isA<Failure<void>>());
    expect((result as Failure<void>).exception, isA<ValidationException>());
    expect(_success(await repository.childrenOf(null)).single.id, ancestor);
    expect(_success(await repository.childrenOf(ancestor)).single.id, child);
  });

  test('移动书会更新其文件夹归属', () async {
    final folderId = _success(await repository.create(name: '归档'));
    await db.subjectDao.insertSubject(
      SubjectsCompanion(
        id: const Value('book'),
        name: const Value('待归档书'),
        level: const Value(0),
        createdAt: const Value(1),
        updatedAt: const Value(1),
      ),
    );

    final result = await repository.moveBook(
      bookId: 'book',
      folderId: folderId,
      targetIndex: 0,
    );

    expect(result, isA<Success<void>>());
    expect((await db.subjectDao.getById('book'))!.folderId, folderId);
  });

  test('跨目录移动书会准确插入并重排来源与目标', () async {
    final source = _success(await repository.create(name: '来源'));
    final target = _success(await repository.create(name: '目标'));
    await _insertBook(db, id: 'source-a', folderId: source, sortOrder: 0);
    await _insertBook(db, id: 'moving', folderId: source, sortOrder: 1);
    await _insertBook(db, id: 'source-b', folderId: source, sortOrder: 2);
    await _insertBook(db, id: 'target-a', folderId: target, sortOrder: 0);
    await _insertBook(db, id: 'target-b', folderId: target, sortOrder: 1);

    final result = await repository.moveBook(
      bookId: 'moving',
      folderId: target,
      targetIndex: 1,
    );

    expect(result, isA<Success<void>>());
    expect(
      _success(
        await repository.booksIn(source),
      ).map((book) => (book.id, book.sortOrder)),
      [('source-a', 0), ('source-b', 1)],
    );
    expect(
      _success(
        await repository.booksIn(target),
      ).map((book) => (book.id, book.sortOrder)),
      [('target-a', 0), ('moving', 1), ('target-b', 2)],
    );
  });

  test('移动索引越界会失败且来源与目标保持不变', () async {
    final source = _success(await repository.create(name: '来源'));
    final target = _success(await repository.create(name: '目标'));
    await _insertBook(db, id: 'moving', folderId: source, sortOrder: 0);

    final result = await repository.moveBook(
      bookId: 'moving',
      folderId: target,
      targetIndex: 1,
    );

    expect(result, isA<Failure<void>>());
    expect((result as Failure<void>).exception, isA<ValidationException>());
    expect(_success(await repository.booksIn(source)).single.id, 'moving');
    expect(_success(await repository.booksIn(target)), isEmpty);
  });

  test('解散文件夹会将直属内容上移且保留书', () async {
    final parent = _success(await repository.create(name: '父目录'));
    final target = _success(
      await repository.create(name: '待解散', parentId: parent),
    );
    final child = _success(
      await repository.create(name: '子目录', parentId: target),
    );
    await db.subjectDao.insertSubject(
      SubjectsCompanion(
        id: const Value('dissolve-book'),
        name: const Value('保留的书'),
        level: const Value(0),
        folderId: Value(target),
        createdAt: const Value(1),
        updatedAt: const Value(1),
      ),
    );

    final result = await repository.dissolve(target);

    expect(result, isA<Success<void>>());
    expect(_success(await repository.childrenOf(parent)).single.id, child);
    expect((await db.subjectDao.getById('dissolve-book'))!.folderId, parent);
    final targetRow = await db
        .customSelect(
          "SELECT is_deleted FROM subject_folders WHERE id = '$target'",
        )
        .getSingle();
    expect(targetRow.read<bool>('is_deleted'), isTrue);
  });

  test('解散根文件夹会让直属书变为未归类', () async {
    final target = _success(await repository.create(name: '待解散'));
    await db.subjectDao.insertSubject(
      SubjectsCompanion(
        id: const Value('root-dissolve-book'),
        name: const Value('未归类书'),
        level: const Value(0),
        folderId: Value(target),
        createdAt: const Value(1),
        updatedAt: const Value(1),
      ),
    );

    final result = await repository.dissolve(target);

    expect(result, isA<Success<void>>());
    expect(
      (await db.subjectDao.getById('root-dissolve-book'))!.folderId,
      isNull,
    );
  });

  test('安全解散会把直属文件夹和书追加到目标上级末尾', () async {
    final parent = _success(await repository.create(name: '父目录'));
    final existingFolder = _success(
      await repository.create(name: '原子目录', parentId: parent),
    );
    final target = _success(
      await repository.create(name: '待解散', parentId: parent),
    );
    final movedFolderA = _success(
      await repository.create(name: '上移 A', parentId: target),
    );
    final movedFolderB = _success(
      await repository.create(name: '上移 B', parentId: target),
    );
    await _insertBook(db, id: 'existing-book', folderId: parent, sortOrder: 0);
    await _insertBook(db, id: 'moved-book-a', folderId: target, sortOrder: 0);
    await _insertBook(db, id: 'moved-book-b', folderId: target, sortOrder: 1);

    final result = await repository.dissolve(target);

    expect(result, isA<Success<void>>());
    expect(
      _success(
        await repository.childrenOf(parent),
      ).map((folder) => (folder.id, folder.sortOrder)),
      [(existingFolder, 0), (movedFolderA, 1), (movedFolderB, 2)],
    );
    expect(
      _success(
        await repository.booksIn(parent),
      ).map((book) => (book.id, book.sortOrder)),
      [('existing-book', 0), ('moved-book-a', 1), ('moved-book-b', 2)],
    );
  });

  test('章节不能作为书移动到文件夹', () async {
    final folderId = _success(await repository.create(name: '归档'));
    await db.subjectDao.insertSubject(
      SubjectsCompanion(
        id: const Value('chapter'),
        name: const Value('章节'),
        level: const Value(1),
        createdAt: const Value(1),
        updatedAt: const Value(1),
      ),
    );

    final result = await repository.moveBook(
      bookId: 'chapter',
      folderId: folderId,
      targetIndex: 0,
    );

    expect(result, isA<Failure<void>>());
    expect((await db.subjectDao.getById('chapter'))!.folderId, isNull);
  });
}

T _success<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}

Future<void> _insertFolder(
  AppDatabase db, {
  required String id,
  String? parentId,
  int sortOrder = 0,
  int createdAt = 1,
  bool isDeleted = false,
}) async {
  await db.folderDao.insertFolder(
    SubjectFoldersCompanion(
      id: Value(id),
      parentId: Value(parentId),
      name: Value(id),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(createdAt),
      isDeleted: Value(isDeleted),
    ),
  );
}

Future<void> _insertBook(
  AppDatabase db, {
  required String id,
  String? folderId,
  int sortOrder = 0,
  int createdAt = 1,
  bool isDeleted = false,
}) async {
  await db.subjectDao.insertSubject(
    SubjectsCompanion(
      id: Value(id),
      name: Value(id),
      level: const Value(0),
      folderId: Value(folderId),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(createdAt),
      isDeleted: Value(isDeleted),
    ),
  );
}
