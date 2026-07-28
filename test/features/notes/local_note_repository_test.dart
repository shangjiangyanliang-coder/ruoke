// 文件: test/features/notes/local_note_repository_test.dart
// 作用: 验证重点记录、历史快照和版本回退的 Repository 闭环。
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/note_edit_snapshot.dart';
import 'package:ruoke/src/features/notes/repository/local_note_repository.dart';
import 'package:ruoke/src/features/notes/repository/local_tag_repository.dart';

void main() {
  late AppDatabase db;
  late LocalNoteRepository repository;
  late LocalTagRepository tagRepository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LocalNoteRepository(db);
    tagRepository = LocalTagRepository(db);
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
    final snapshot = NoteEditSnapshot.decode(versions.single.snapshotJson);
    expect(snapshot.contentJson, oldContent);
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
    expect(
      NoteEditSnapshot.decode(versions.first.snapshotJson).contentJson,
      secondContent,
    );
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

  test('标题变化也会新增完整历史版本', () async {
    final content = _delta([_op('正文')]);
    final noteId = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        title: '旧标题',
        contentJson: content,
      ),
    ).id;

    final result = await repository.update(
      id: noteId,
      title: '新标题',
      contentJson: content,
    );

    expect(result, isA<Success<void>>());
    final versions = _successValue(await repository.listVersions(noteId));
    expect(versions, hasLength(1));
    expect(NoteEditSnapshot.decode(versions.single.snapshotJson).title, '旧标题');
  });

  test('显式传入空标题会清空已有标题并保存旧标题版本', () async {
    final noteId = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        title: '旧标题',
        contentJson: _delta([_op('正文')]),
      ),
    ).id;

    final result = await repository.update(id: noteId, title: '');

    expect(result, isA<Success<void>>());
    expect(_successValue(await repository.getById(noteId))?.title, isNull);
    final versions = _successValue(await repository.listVersions(noteId));
    expect(versions, hasLength(1));
    expect(NoteEditSnapshot.decode(versions.single.snapshotJson).title, '旧标题');
  });

  test('完整状态没有变化时不会新增历史版本', () async {
    final content = _delta([_op('正文')]);
    final noteId = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        title: '标题',
        contentJson: content,
        tagNames: const ['重点'],
      ),
    ).id;

    final result = await repository.update(
      id: noteId,
      title: '标题',
      contentJson: content,
      tagNames: const ['重点'],
    );

    expect(result, isA<Success<void>>());
    expect(_successValue(await repository.listVersions(noteId)), isEmpty);
  });

  test('只修改标签会保存旧的标题正文和标签版本', () async {
    final content = _delta([_op('正文')]);
    final noteId = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        title: '标题',
        contentJson: content,
        tagNames: const ['旧标签'],
      ),
    ).id;

    final result = await repository.update(
      id: noteId,
      title: '标题',
      contentJson: content,
      tagNames: const ['新标签'],
    );

    expect(result, isA<Success<void>>());
    final tags = _successValue(await tagRepository.listTagsForNote(noteId));
    expect(tags.map((tag) => tag.name), ['新标签']);
    final versions = _successValue(await repository.listVersions(noteId));
    expect(versions, hasLength(1));
    final snapshot = NoteEditSnapshot.decode(versions.single.snapshotJson);
    expect(snapshot.title, '标题');
    expect(snapshot.contentJson, content);
    expect(snapshot.tagNames, ['旧标签']);
  });

  test('恢复完整版本会恢复标题正文标签并保存恢复前状态', () async {
    final firstContent = _delta([_op('第一版\n', color: 'red')]);
    final secondContent = _delta([_op('第二版\n', underline: true)]);
    final noteId = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        title: '标题 A',
        contentJson: firstContent,
        tagNames: const ['标签 A'],
      ),
    ).id;
    await repository.update(
      id: noteId,
      title: '标题 B',
      contentJson: secondContent,
      tagNames: const ['标签 B'],
    );

    final result = await repository.restoreVersion(
      noteId: noteId,
      versionNo: 1,
    );

    expect(result, isA<Success<void>>());
    final note = _successValue(await repository.getById(noteId));
    final tags = _successValue(await tagRepository.listTagsForNote(noteId));
    expect(note?.title, '标题 A');
    expect(note?.contentJson, firstContent);
    expect(note?.plainText, '第一版\n');
    expect(tags.map((tag) => tag.name), ['标签 A']);
    final versions = _successValue(await repository.listVersions(noteId));
    expect(versions, hasLength(2));
    final beforeRestore = NoteEditSnapshot.decode(versions.first.snapshotJson);
    expect(beforeRestore.title, '标题 B');
    expect(beforeRestore.contentJson, secondContent);
    expect(beforeRestore.tagNames, ['标签 B']);
  });

  test('恢复旧正文快照会保留当前标题和标签', () async {
    final currentContent = _delta([_op('当前正文')]);
    final legacyContent = _delta([_op('旧正文')]);
    final noteId = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        title: '当前标题',
        contentJson: currentContent,
        tagNames: const ['当前标签'],
      ),
    ).id;
    await db.noteVersionDao.insertVersion(
      NoteVersionsCompanion(
        id: const Value('legacy-version'),
        noteId: Value(noteId),
        versionNo: const Value(1),
        snapshotJson: Value(legacyContent),
        createdAt: const Value(1),
      ),
    );

    final result = await repository.restoreVersion(
      noteId: noteId,
      versionNo: 1,
    );

    expect(result, isA<Success<void>>());
    final note = _successValue(await repository.getById(noteId));
    final tags = _successValue(await tagRepository.listTagsForNote(noteId));
    expect(note?.title, '当前标题');
    expect(note?.contentJson, legacyContent);
    expect(tags.map((tag) => tag.name), ['当前标签']);
  });

  test('损坏的旧正文快照恢复失败且不会覆盖当前状态', () async {
    final currentContent = _delta([_op('当前正文')]);
    final noteId = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        title: '当前标题',
        contentJson: currentContent,
        tagNames: const ['当前标签'],
      ),
    ).id;
    await db.noteVersionDao.insertVersion(
      NoteVersionsCompanion(
        id: const Value('broken-version'),
        noteId: Value(noteId),
        versionNo: const Value(1),
        snapshotJson: const Value('[{}]'),
        createdAt: const Value(1),
      ),
    );

    final result = await repository.restoreVersion(
      noteId: noteId,
      versionNo: 1,
    );

    expect(result, isA<Failure<void>>());
    final note = _successValue(await repository.getById(noteId));
    final tags = _successValue(await tagRepository.listTagsForNote(noteId));
    expect(note?.title, '当前标题');
    expect(note?.contentJson, currentContent);
    expect(tags.map((tag) => tag.name), ['当前标签']);
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
