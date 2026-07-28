// 标签本地仓储的数据库行为测试。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/search_match_mode.dart';
import 'package:ruoke/src/features/notes/repository/local_tag_repository.dart';

void main() {
  late AppDatabase db;
  late LocalTagRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LocalTagRepository(db);
  });

  tearDown(() => db.close());

  test('新建标签会修剪名称并返回标签', () async {
    final result = await repository.createTag(name: '  复习  ', color: '#FF0000');

    final tag = _successValue(result);
    expect(tag.name, '复习');
    expect(tag.color, '#FF0000');
    expect(_successValue(await repository.listTags()).single.name, '复习');
  });

  test('空白标签名返回 ValidationException', () async {
    final result = await repository.createTag(name: '   ');

    expect(result, isA<Failure>());
    expect((result as Failure).exception, isA<ValidationException>());
  });

  test('重名与改名冲突返回可理解的 AppException', () async {
    final first = _successValue(await repository.createTag(name: '数学'));
    await repository.createTag(name: '英语');

    final duplicate = await repository.createTag(name: ' 数学 ');
    final renameConflict = await repository.renameTag(id: first.id, name: '英语');

    expect(_failureValue(duplicate), isA<AppException>());
    expect(_failureValue(duplicate).userMessage, contains('标签'));
    expect(_failureValue(renameConflict), isA<AppException>());
    expect(_failureValue(renameConflict).userMessage, contains('标签'));
  });

  test('非唯一创建异常返回新建标签失败', () async {
    await db.customStatement(
      "CREATE TRIGGER fail_tag_insert BEFORE INSERT ON tags "
      "BEGIN SELECT RAISE(ABORT, 'insert failed'); END;",
    );

    final result = await repository.createTag(name: '创建失败');

    expect(_failureValue(result), isA<DatabaseException>());
    expect(_failureValue(result).userMessage, '新建标签失败');
  });

  test('非唯一改名异常返回重命名标签失败', () async {
    final tag = _successValue(await repository.createTag(name: '旧名'));
    await db.customStatement(
      "CREATE TRIGGER fail_tag_rename BEFORE UPDATE ON tags "
      "BEGIN SELECT RAISE(ABORT, 'rename failed'); END;",
    );

    final result = await repository.renameTag(id: tag.id, name: '新名');

    expect(_failureValue(result), isA<DatabaseException>());
    expect(_failureValue(result).userMessage, '重命名标签失败');
  });

  test('改名会修剪名称并持久化', () async {
    final tag = _successValue(await repository.createTag(name: '旧名'));

    final result = await repository.renameTag(id: tag.id, name: '  新名  ');

    expect(result, isA<Success<void>>());
    expect(_successValue(await repository.listTags()).single.name, '新名');
  });

  test('删除标签会删除关联但不会删除笔记', () async {
    final tag = _successValue(await repository.createTag(name: '删除'));
    final noteId = await _insertNote(db, 'delete-note');
    await repository.replaceNoteTags(noteId: noteId, tagIds: [tag.id]);

    final result = await repository.deleteTag(tag.id);

    expect(result, isA<Success<void>>());
    expect(await db.noteDao.getById(noteId), isNotNull);
    expect(await db.noteTagDao.listByNote(noteId), isEmpty);
    expect(_successValue(await repository.listTags()), isEmpty);
  });

  test('替换笔记标签会贴上、撕下并去重关联', () async {
    final first = _successValue(await repository.createTag(name: '一'));
    final second = _successValue(await repository.createTag(name: '二'));
    final noteId = await _insertNote(db, 'replace-note');

    final addResult = await repository.replaceNoteTags(
      noteId: noteId,
      tagIds: [first.id, first.id, second.id],
    );
    final removeResult = await repository.replaceNoteTags(
      noteId: noteId,
      tagIds: [second.id],
    );

    expect(addResult, isA<Success<void>>());
    expect(removeResult, isA<Success<void>>());
    expect((await db.noteTagDao.listByNote(noteId)).map((link) => link.tagId), [
      second.id,
    ]);
    expect(
      _successValue(
        await repository.listTagsForNote(noteId),
      ).map((tag) => tag.id),
      [second.id],
    );
  });

  test('标签计数只包含未软删除的笔记', () async {
    final tag = _successValue(await repository.createTag(name: '计数'));
    final activeNoteId = await _insertNote(db, 'active-note');
    final deletedNoteId = await _insertNote(db, 'deleted-note');
    await repository.replaceNoteTags(noteId: activeNoteId, tagIds: [tag.id]);
    await repository.replaceNoteTags(noteId: deletedNoteId, tagIds: [tag.id]);
    await db.noteDao.softDelete(deletedNoteId, 1);

    final tags = _successValue(await repository.listTags());

    expect(tags.single.noteCount, 1);
  });

  test('标签名称支持部分匹配和完全匹配', () async {
    await repository.createTag(name: '复习');
    await repository.createTag(name: '期末复习');
    await repository.createTag(name: '错题');

    final contains = _successValue(
      await repository.searchTags(
        keyword: '  复  ',
        matchMode: SearchMatchMode.contains,
      ),
    );
    final exact = _successValue(
      await repository.searchTags(
        keyword: '  复习  ',
        matchMode: SearchMatchMode.exact,
      ),
    );

    expect(contains.map((tag) => tag.name).toSet(), {'复习', '期末复习'});
    expect(exact.map((tag) => tag.name), ['复习']);
  });

  test('按名称添加会复用已有标签并避免重复关联', () async {
    final existing = _successValue(await repository.createTag(name: '重点'));
    final noteId = await _insertNote(db, 'reuse-note');

    final first = _successValue(
      await repository.findOrCreateAndAttachTag(
        noteId: noteId,
        tagName: '  重点  ',
      ),
    );
    final second = _successValue(
      await repository.findOrCreateAndAttachTag(
        noteId: noteId,
        tagName: '重点',
      ),
    );

    expect(first.id, existing.id);
    expect(second.id, existing.id);
    expect(_successValue(await repository.listTags()), hasLength(1));
    expect(await db.noteTagDao.listByNote(noteId), hasLength(1));
  });

  test('按名称添加不存在的标签会创建并绑定', () async {
    final noteId = await _insertNote(db, 'create-and-attach-note');

    final tag = _successValue(
      await repository.findOrCreateAndAttachTag(
        noteId: noteId,
        tagName: '  新标签  ',
      ),
    );

    expect(tag.name, '新标签');
    expect(
      (await db.noteTagDao.listByNote(noteId)).single.tagId,
      tag.id,
    );
  });

  test('批量按名称绑定会修剪名称并去重', () async {
    final noteId = await _insertNote(db, 'batch-note');

    final tags = _successValue(
      await repository.attachTagsByNames(
        noteId: noteId,
        names: [' 重点 ', '重点', ' 待复习 '],
      ),
    );

    expect(tags.map((tag) => tag.name).toSet(), {'重点', '待复习'});
    expect(await db.noteTagDao.listByNote(noteId), hasLength(2));
    expect(_successValue(await repository.listTags()), hasLength(2));
  });

  test('按名称绑定空标签返回校验错误且不写数据', () async {
    final noteId = await _insertNote(db, 'blank-tag-note');

    final result = await repository.findOrCreateAndAttachTag(
      noteId: noteId,
      tagName: '   ',
    );

    expect(_failureValue(result), isA<ValidationException>());
    expect(_successValue(await repository.listTags()), isEmpty);
    expect(await db.noteTagDao.listByNote(noteId), isEmpty);
  });

  test('笔记不存在时按名称绑定失败且事务不留下孤立标签', () async {
    final result = await repository.attachTagsByNames(
      noteId: 'missing-note',
      names: ['不应保留'],
    );

    expect(_failureValue(result), isA<ValidationException>());
    expect(_successValue(await repository.listTags()), isEmpty);
  });
}

Future<String> _insertNote(AppDatabase db, String id) async {
  await db.noteDao.insertNote(
    NotesCompanion(
      id: Value(id),
      subjectId: const Value('uncategorized'),
      createdAt: const Value(1),
      updatedAt: const Value(1),
    ),
  );
  return id;
}

T _successValue<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}

AppException _failureValue<T>(Result<T> result) {
  expect(result, isA<Failure<T>>());
  return (result as Failure<T>).exception;
}
