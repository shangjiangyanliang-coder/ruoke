// 科目仓储名称搜索与祖先路径补齐测试。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/subject_path.dart';
import 'package:ruoke/src/features/notes/repository/local_subject_repository.dart';

void main() {
  late AppDatabase db;
  late LocalSubjectRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LocalSubjectRepository(db);
  });

  tearDown(() => db.close());

  test('搜索同名章会返回各自所属书路径，搜索节会补齐完整路径', () async {
    await _insertSubject(db, id: 'book-a', name: '数学上册', level: 0);
    await _insertSubject(db, id: 'book-b', name: '数学下册', level: 0);
    await _insertSubject(
      db,
      id: 'chapter-a',
      parentId: 'book-a',
      name: '函数',
      level: 1,
    );
    await _insertSubject(
      db,
      id: 'chapter-b',
      parentId: 'book-b',
      name: '函数',
      level: 1,
    );
    await _insertSubject(
      db,
      id: 'section-a',
      parentId: 'chapter-a',
      name: '一次函数',
      level: 2,
    );

    final chapters = _success(await repository.searchPaths('函数'));
    expect(
      chapters.map((path) => path.nodes.map((node) => node.id).toList()),
      containsAll([
        ['book-a', 'chapter-a'],
        ['book-b', 'chapter-b'],
        ['book-a', 'chapter-a', 'section-a'],
      ]),
    );

    final sections = _success(await repository.searchPaths('一次'));
    expect(sections, hasLength(1));
    expect(sections.single.nodes.map((node) => node.id), [
      'book-a',
      'chapter-a',
      'section-a',
    ]);
  });

  test('搜索忽略软删除节点和祖先不完整的路径', () async {
    await _insertSubject(db, id: 'book', name: '有效书', level: 0);
    await _insertSubject(
      db,
      id: 'deleted',
      parentId: 'book',
      name: '目标已删除',
      level: 1,
      isDeleted: true,
    );
    await _insertSubject(
      db,
      id: 'orphan',
      parentId: 'missing',
      name: '目标孤儿',
      level: 1,
    );

    expect(_success(await repository.searchPaths('目标')), isEmpty);
    expect(_success(await repository.searchPaths('   ')), isEmpty);
  });

  test(r'LIKE 特殊字符按普通字符匹配', () async {
    await _insertSubject(db, id: 'percent', name: '百分比 100%', level: 0);
    await _insertSubject(db, id: 'underscore', name: '下划线_a', level: 0);
    await _insertSubject(db, id: 'slash', name: r'路径\章节', level: 0);
    await _insertSubject(db, id: 'ordinary', name: '普通章节', level: 0);

    expect(
      _success(await repository.searchPaths('%')).single.target.id,
      'percent',
    );
    expect(
      _success(await repository.searchPaths('_')).single.target.id,
      'underscore',
    );
    expect(
      _success(await repository.searchPaths(r'\')).single.target.id,
      'slash',
    );
  });

  test('新建书章节会按各自真实父级追加到末尾', () async {
    await _insertFolder(db, 'folder');
    final bookA = _success(
      await repository.create(name: '书 A', level: 0, folderId: 'folder'),
    );
    final bookB = _success(
      await repository.create(name: '书 B', level: 0, folderId: 'folder'),
    );
    final chapterA = _success(
      await repository.create(name: '章 A', level: 1, parentId: bookA),
    );
    final chapterB = _success(
      await repository.create(name: '章 B', level: 1, parentId: bookA),
    );
    final sectionA = _success(
      await repository.create(name: '节 A', level: 2, parentId: chapterA),
    );
    final sectionB = _success(
      await repository.create(name: '节 B', level: 2, parentId: chapterA),
    );

    expect(
      (await db.folderDao.booksIn(
        'folder',
      )).map((book) => (book.id, book.sortOrder)),
      [(bookA, 0), (bookB, 1)],
    );
    expect(
      _success(
        await repository.childrenOf(bookA),
      ).map((subject) => (subject.id, subject.sortOrder)),
      [(chapterA, 0), (chapterB, 1)],
    );
    expect(
      _success(
        await repository.childrenOf(chapterA),
      ).map((subject) => (subject.id, subject.sortOrder)),
      [(sectionA, 0), (sectionB, 1)],
    );
  });

  test('新建会修剪名称并拒绝空名称、错误父级和不存在文件夹', () async {
    await _insertSubject(db, id: 'book', name: '书', level: 0);
    await _insertSubject(
      db,
      id: 'chapter',
      parentId: 'book',
      name: '章',
      level: 1,
    );

    final valid = _success(
      await repository.create(name: '  新节  ', level: 2, parentId: 'chapter'),
    );
    final empty = await repository.create(
      name: '   ',
      level: 1,
      parentId: 'book',
    );
    final wrongParent = await repository.create(
      name: '错误章',
      level: 1,
      parentId: 'chapter',
    );
    final missingFolder = await repository.create(
      name: '孤立书',
      level: 0,
      folderId: 'missing',
    );

    expect((await db.subjectDao.getById(valid))!.name, '新节');
    expect(empty, isA<Failure<String>>());
    expect(wrongParent, isA<Failure<String>>());
    expect(missingFolder, isA<Failure<String>>());
  });

  test('重命名会修剪名称，空名称和不存在节点不会写入', () async {
    await _insertSubject(db, id: 'book', name: '旧名称', level: 0);

    final success = await repository.rename(id: 'book', name: '  新名称  ');
    final empty = await repository.rename(id: 'book', name: '   ');
    final missing = await repository.rename(id: 'missing', name: '名称');

    expect(success, isA<Success<void>>());
    expect(empty, isA<Failure<void>>());
    expect(missing, isA<Failure<void>>());
    expect((await db.subjectDao.getById('book'))!.name, '新名称');
  });

  test('章可跨书准确插入并连续重排来源与目标', () async {
    await _insertSubject(db, id: 'book-a', name: '书 A', level: 0);
    await _insertSubject(db, id: 'book-b', name: '书 B', level: 0);
    await _insertSubject(
      db,
      id: 'source-a',
      parentId: 'book-a',
      name: '来源 A',
      level: 1,
      sortOrder: 0,
    );
    await _insertSubject(
      db,
      id: 'moving',
      parentId: 'book-a',
      name: '待移动',
      level: 1,
      sortOrder: 1,
    );
    await _insertSubject(
      db,
      id: 'source-b',
      parentId: 'book-a',
      name: '来源 B',
      level: 1,
      sortOrder: 2,
    );
    await _insertSubject(
      db,
      id: 'target-a',
      parentId: 'book-b',
      name: '目标 A',
      level: 1,
      sortOrder: 0,
    );

    final result = await repository.moveSubject(
      subjectId: 'moving',
      newParentId: 'book-b',
      targetIndex: 1,
    );

    expect(result, isA<Success<void>>());
    expect(
      _success(
        await repository.childrenOf('book-a'),
      ).map((subject) => (subject.id, subject.sortOrder)),
      [('source-a', 0), ('source-b', 1)],
    );
    expect(
      _success(
        await repository.childrenOf('book-b'),
      ).map((subject) => (subject.id, subject.sortOrder)),
      [('target-a', 0), ('moving', 1)],
    );
  });

  test('节可跨章插入中间，同父级重排也使用完整列表', () async {
    await _insertSubject(db, id: 'book', name: '书', level: 0);
    await _insertSubject(
      db,
      id: 'chapter-a',
      parentId: 'book',
      name: '章 A',
      level: 1,
    );
    await _insertSubject(
      db,
      id: 'chapter-b',
      parentId: 'book',
      name: '章 B',
      level: 1,
    );
    await _insertSubject(
      db,
      id: 'moving',
      parentId: 'chapter-a',
      name: '待移动节',
      level: 2,
    );
    await _insertSubject(
      db,
      id: 'target-a',
      parentId: 'chapter-b',
      name: '目标 A',
      level: 2,
      sortOrder: 0,
    );
    await _insertSubject(
      db,
      id: 'target-b',
      parentId: 'chapter-b',
      name: '目标 B',
      level: 2,
      sortOrder: 1,
    );

    final move = await repository.moveSubject(
      subjectId: 'moving',
      newParentId: 'chapter-b',
      targetIndex: 1,
    );
    final reorder = await repository.reorderChildren(
      parentId: 'chapter-b',
      orderedIds: const ['target-b', 'moving', 'target-a'],
    );

    expect(move, isA<Success<void>>());
    expect(reorder, isA<Success<void>>());
    expect(
      _success(
        await repository.childrenOf('chapter-b'),
      ).map((subject) => (subject.id, subject.sortOrder)),
      [('target-b', 0), ('moving', 1), ('target-a', 2)],
    );
  });

  test('错误层级目标、越界索引和非法重排列表会回滚', () async {
    await _insertSubject(db, id: 'book', name: '书', level: 0);
    await _insertSubject(
      db,
      id: 'chapter',
      parentId: 'book',
      name: '章',
      level: 1,
      sortOrder: 0,
    );
    await _insertSubject(
      db,
      id: 'chapter-b',
      parentId: 'book',
      name: '章 B',
      level: 1,
      sortOrder: 1,
    );
    await _insertSubject(
      db,
      id: 'section',
      parentId: 'chapter',
      name: '节',
      level: 2,
    );

    final wrongTarget = await repository.moveSubject(
      subjectId: 'section',
      newParentId: 'book',
      targetIndex: 0,
    );
    final outOfRange = await repository.moveSubject(
      subjectId: 'chapter',
      newParentId: 'book',
      targetIndex: 2,
    );
    final invalidOrder = await repository.reorderChildren(
      parentId: 'book',
      orderedIds: const ['chapter', 'chapter'],
    );

    for (final result in [wrongTarget, outOfRange, invalidOrder]) {
      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).exception, isA<ValidationException>());
    }
    expect(
      _success(
        await repository.childrenOf('book'),
      ).map((subject) => (subject.id, subject.sortOrder)),
      [('chapter', 0), ('chapter-b', 1)],
    );
    expect((await db.subjectDao.getById('section'))!.parentId, 'chapter');
  });
}

Future<void> _insertFolder(AppDatabase db, String id) {
  return db.folderDao.insertFolder(
    SubjectFoldersCompanion(
      id: Value(id),
      name: Value(id),
      createdAt: const Value(1),
      updatedAt: const Value(1),
    ),
  );
}

Future<void> _insertSubject(
  AppDatabase db, {
  required String id,
  required String name,
  required int level,
  String? parentId,
  String? folderId,
  int sortOrder = 0,
  int createdAt = 1,
  bool isDeleted = false,
}) {
  return db.subjectDao.insertSubject(
    SubjectsCompanion(
      id: Value(id),
      parentId: Value(parentId),
      folderId: Value(folderId),
      name: Value(name),
      level: Value(level),
      sortOrder: Value(sortOrder),
      isDeleted: Value(isDeleted),
      createdAt: Value(createdAt),
      updatedAt: Value(createdAt),
    ),
  );
}

T _success<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}
