// 文件: test/features/notes/local_note_repository_test.dart
// 作用: 验证重点记录、历史快照和版本回退的 Repository 闭环。
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/repository/local_note_repository.dart';

void main() {
  late AppDatabase db;
  late LocalNoteRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LocalNoteRepository(db);
  });

  tearDown(() => db.close());

  test('新建带红字和下划线的笔记会写入重点表', () async {
    final result = await repository.create(
      subjectId: 'uncategorized',
      contentJson: _delta([
        _op('普通'),
        _op('红字', color: 'red'),
        _op('下划线', underline: true),
      ]),
    );
    final noteId = _successValue(result).id;

    final highlights = await db.noteHighlightDao.listByNote(noteId);

    expect(highlights.map((item) => '${item.kind}:${item.body}'), [
      'red:红字',
      'underline:下划线',
    ]);
  });

  test('更新正文会重建重点并保存旧正文版本', () async {
    final oldContent = _delta([_op('旧红字', color: 'red')]);
    final newContent = _delta([_op('新下划线', underline: true)]);
    final createResult = await repository.create(
      subjectId: 'uncategorized',
      contentJson: oldContent,
    );
    final noteId = _successValue(createResult).id;

    final updateResult = await repository.update(
      id: noteId,
      contentJson: newContent,
    );

    expect(updateResult, isA<Success<void>>());
    final highlights = await db.noteHighlightDao.listByNote(noteId);
    final versions = _successValue(await repository.listVersions(noteId));

    expect(highlights.map((item) => '${item.kind}:${item.body}'), [
      'underline:新下划线',
    ]);
    expect(versions, hasLength(1));
    expect(versions.single.snapshotJson, oldContent);
  });

  test('恢复指定版本会保留回退前正文并写回目标快照', () async {
    final firstContent = _delta([_op('第一版', color: 'red')]);
    final secondContent = _delta([_op('第二版', underline: true)]);
    final createResult = await repository.create(
      subjectId: 'uncategorized',
      contentJson: firstContent,
    );
    final noteId = _successValue(createResult).id;
    await repository.update(id: noteId, contentJson: secondContent);

    final restoreResult = await repository.restoreVersion(
      noteId: noteId,
      versionNo: 1,
    );

    expect(restoreResult, isA<Success<void>>());
    final note = _successValue(await repository.getById(noteId));
    final versions = _successValue(await repository.listVersions(noteId));
    final highlights = await db.noteHighlightDao.listByNote(noteId);

    expect(note?.contentJson, firstContent);
    expect(versions, hasLength(2));
    expect(versions.first.snapshotJson, secondContent);
    expect(highlights.map((item) => '${item.kind}:${item.body}'), ['red:第一版']);
  });

  test('非法正文更新失败并回滚笔记、版本和原重点', () async {
    final originalContent = _delta([_op('原重点', color: 'red')]);
    final noteId = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        contentJson: originalContent,
      ),
    ).id;

    final result = await repository.update(
      id: noteId,
      contentJson: '{invalid-json',
    );

    expect(result, isA<Failure<void>>());
    final note = _successValue(await repository.getById(noteId));
    final highlights = await db.noteHighlightDao.listByNote(noteId);
    final versions = _successValue(await repository.listVersions(noteId));
    expect(note?.contentJson, originalContent);
    expect(highlights.map((item) => '${item.kind}:${item.body}'), ['red:原重点']);
    expect(versions, isEmpty);
  });

  test('更新不存在的笔记会失败且不产生孤儿重点', () async {
    final result = await repository.update(
      id: 'missing-note',
      contentJson: _delta([_op('孤儿重点', color: 'red')]),
    );

    expect(result, isA<Failure<void>>());
    expect(await db.noteHighlightDao.listByNote('missing-note'), isEmpty);
  });

  test('正文没有变化时不会新增历史版本', () async {
    final content = _delta([_op('正文')]);
    final noteId = _successValue(
      await repository.create(subjectId: 'uncategorized', contentJson: content),
    ).id;

    final result = await repository.update(
      id: noteId,
      title: '只改标题',
      contentJson: content,
    );

    expect(result, isA<Success<void>>());
    expect(_successValue(await repository.listVersions(noteId)), isEmpty);
  });

  test('恢复不存在的历史版本会失败且当前正文保持不变', () async {
    final content = _delta([_op('当前正文')]);
    final noteId = _successValue(
      await repository.create(subjectId: 'uncategorized', contentJson: content),
    ).id;

    final result = await repository.restoreVersion(
      noteId: noteId,
      versionNo: 99,
    );

    expect(result, isA<Failure<void>>());
    expect(
      _successValue(await repository.getById(noteId))?.contentJson,
      content,
    );
  });

  test('连续正文更新生成严格递增且不重复的版本号', () async {
    final first = _delta([_op('第一版')]);
    final second = _delta([_op('第二版')]);
    final third = _delta([_op('第三版')]);
    final noteId = _successValue(
      await repository.create(subjectId: 'uncategorized', contentJson: first),
    ).id;

    await repository.update(id: noteId, contentJson: second);
    await repository.update(id: noteId, contentJson: third);

    final versions = _successValue(await repository.listVersions(noteId));
    expect(versions.map((item) => item.versionNo), [2, 1]);
    expect(versions.map((item) => item.versionNo).toSet(), hasLength(2));
  });
}

String _delta(List<Map<String, Object>> operations) => jsonEncode(operations);

Map<String, Object> _op(String text, {String? color, bool? underline}) {
  final attributes = <String, Object>{};
  if (color != null) attributes['color'] = color;
  if (underline != null) attributes['underline'] = underline;
  return {'insert': text, if (attributes.isNotEmpty) 'attributes': attributes};
}

T _successValue<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}
