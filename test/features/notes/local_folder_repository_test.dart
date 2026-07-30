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
    expect((duplicate as Failure<String>).exception, isA<ValidationException>());
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

  test('移动文件夹会改变直属归属', () async {
    final sourceParent = _success(await repository.create(name: '来源'));
    final targetParent = _success(await repository.create(name: '目标'));
    final child = _success(
      await repository.create(name: '待移动', parentId: sourceParent),
    );

    final result = await repository.moveFolder(
      folderId: child,
      newParentId: targetParent,
    );

    expect(result, isA<Success<void>>());
    expect(_success(await repository.childrenOf(sourceParent)), isEmpty);
    expect(
      _success(await repository.childrenOf(targetParent)).single.id,
      child,
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

    final result = await repository.moveBook(bookId: 'book', folderId: folderId);

    expect(result, isA<Success<void>>());
    expect((await db.subjectDao.getById('book'))!.folderId, folderId);
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
    final targetRow = await db.customSelect(
      "SELECT is_deleted FROM subject_folders WHERE id = '$target'",
    ).getSingle();
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
    expect((await db.subjectDao.getById('root-dissolve-book'))!.folderId, isNull);
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

    final result = await repository.moveBook(bookId: 'chapter', folderId: folderId);

    expect(result, isA<Failure<void>>());
    expect((await db.subjectDao.getById('chapter'))!.folderId, isNull);
  });
}

T _success<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}
