// 文件: test/features/notes/local_note_repository_test.dart
// 作用: 验证重点记录、历史快照和版本回退的 Repository 闭环。
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/app_exception.dart';
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

  test('新建笔记会把空白标题规范化为 null', () async {
    final result = await repository.create(
      subjectId: 'uncategorized',
      title: '   ',
      contentJson: _delta([_op('正文')]),
    );

    expect(_successValue(result).title, isNull);
  });

  test('连续新建笔记会追加到同一书章节末尾', () async {
    final first = _successValue(
      await repository.create(subjectId: 'book', title: '第一条'),
    );
    final second = _successValue(
      await repository.create(subjectId: 'book', title: '第二条'),
    );

    expect((first.sortOrder, second.sortOrder), (0, 1));
    expect(
      _successValue(
        await repository.listBySubject('book'),
      ).map((note) => (note.id, note.sortOrder)),
      [(first.id, 0), (second.id, 1)],
    );
  });

  test('按书章节读取在顺序重复时按创建时间与 id 稳定排序', () async {
    await _insertNote(db, id: 'note-b', sortOrder: 2, createdAt: 20);
    await _insertNote(db, id: 'note-c', sortOrder: 2, createdAt: 10);
    await _insertNote(db, id: 'note-a', sortOrder: 2, createdAt: 10);

    expect(
      _successValue(
        await repository.listBySubject('book'),
      ).map((note) => note.id),
      ['note-a', 'note-c', 'note-b'],
    );
  });

  test('笔记可按完整同级列表重排', () async {
    await _insertNote(db, id: 'note-a', sortOrder: 0);
    await _insertNote(db, id: 'note-b', sortOrder: 1);
    await _insertNote(db, id: 'note-c', sortOrder: 2);

    final result = await repository.reorderNotes(
      subjectId: 'book',
      orderedIds: const ['note-c', 'note-a', 'note-b'],
    );

    expect(result, isA<Success<void>>());
    expect(
      _successValue(
        await repository.listBySubject('book'),
      ).map((note) => (note.id, note.sortOrder)),
      [('note-c', 0), ('note-a', 1), ('note-b', 2)],
    );
  });

  test('笔记可跨书章节准确插入并连续重排来源与目标', () async {
    await _insertSubject(db, id: 'chapter', level: 1);
    await _insertNote(db, id: 'source-a', sortOrder: 0);
    await _insertNote(db, id: 'moving', sortOrder: 1);
    await _insertNote(db, id: 'source-b', sortOrder: 2);
    await _insertNote(db, id: 'target-a', subjectId: 'chapter', sortOrder: 0);
    await _insertNote(db, id: 'target-b', subjectId: 'chapter', sortOrder: 1);

    final result = await repository.moveNote(
      noteId: 'moving',
      subjectId: 'chapter',
      targetIndex: 1,
    );

    expect(result, isA<Success<void>>());
    expect(
      _successValue(
        await repository.listBySubject('book'),
      ).map((note) => (note.id, note.sortOrder)),
      [('source-a', 0), ('source-b', 1)],
    );
    expect(
      _successValue(
        await repository.listBySubject('chapter'),
      ).map((note) => (note.id, note.sortOrder)),
      [('target-a', 0), ('moving', 1), ('target-b', 2)],
    );
  });

  test('非法重排和越界移动会失败并保持原位置', () async {
    await _insertSubject(db, id: 'chapter', level: 1);
    await _insertNote(db, id: 'note-a', sortOrder: 0);
    await _insertNote(db, id: 'note-b', sortOrder: 1);

    final invalidOrder = await repository.reorderNotes(
      subjectId: 'book',
      orderedIds: const ['note-a', 'note-a'],
    );
    final outOfRange = await repository.moveNote(
      noteId: 'note-a',
      subjectId: 'chapter',
      targetIndex: 1,
    );

    for (final result in [invalidOrder, outOfRange]) {
      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).exception, isA<ValidationException>());
    }
    expect(
      _successValue(
        await repository.listBySubject('book'),
      ).map((note) => (note.id, note.sortOrder)),
      [('note-a', 0), ('note-b', 1)],
    );
    expect(_successValue(await repository.listBySubject('chapter')), isEmpty);
  });

  test('菜单重命名只改标题不建版本，正文更新仍建立版本', () async {
    final note = _successValue(
      await repository.create(
        subjectId: 'book',
        title: '旧标题',
        contentJson: _delta([_op('旧正文')]),
      ),
    );

    final rename = await repository.renameTitle(id: note.id, title: '  新标题  ');

    expect(rename, isA<Success<void>>());
    expect((_successValue(await repository.getById(note.id)))!.title, '新标题');
    expect(_successValue(await repository.listVersions(note.id)), isEmpty);

    await repository.update(id: note.id, contentJson: _delta([_op('新正文')]));
    expect(_successValue(await repository.listVersions(note.id)), hasLength(1));
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

  test('默认恢复指定版本不会保存回退前正文快照', () async {
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
    expect(versions, hasLength(1));
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
      saveCurrentBeforeRestore: true,
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
    final legacyContent = _delta([_op('旧正文\n')]);
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

  test('历史版本 DAO 可按 ID 读取完整版本行', () async {
    await db.noteVersionDao.insertVersion(
      const NoteVersionsCompanion(
        id: Value('version-by-id'),
        noteId: Value('note-by-id'),
        versionNo: Value(4),
        snapshotJson: Value('[]'),
        createdAt: Value(40),
        name: Value('复习前'),
      ),
    );

    final version = await db.noteVersionDao.getById('version-by-id');

    expect(version?.noteId, 'note-by-id');
    expect(version?.versionNo, 4);
    expect(version?.name, '复习前');
  });

  test('历史版本 DAO 按名称查询时可排除当前版本', () async {
    await db.noteVersionDao.insertVersion(
      const NoteVersionsCompanion(
        id: Value('version-name-a'),
        noteId: Value('note-by-name'),
        versionNo: Value(1),
        snapshotJson: Value('[]'),
        createdAt: Value(1),
        name: Value('阶段总结'),
      ),
    );
    await db.noteVersionDao.insertVersion(
      const NoteVersionsCompanion(
        id: Value('version-name-b'),
        noteId: Value('note-by-name'),
        versionNo: Value(2),
        snapshotJson: Value('[]'),
        createdAt: Value(2),
        name: Value('阶段总结'),
      ),
    );

    final conflict = await db.noteVersionDao.getByName(
      noteId: 'note-by-name',
      name: '阶段总结',
      excludingVersionId: 'version-name-a',
    );

    expect(conflict?.id, 'version-name-b');
  });

  test('历史版本 DAO 可将自定义名称清空为 null', () async {
    await db.noteVersionDao.insertVersion(
      const NoteVersionsCompanion(
        id: Value('version-clear-name'),
        noteId: Value('note-clear-name'),
        versionNo: Value(1),
        snapshotJson: Value('[]'),
        createdAt: Value(1),
        name: Value('临时名称'),
      ),
    );

    final changed = await db.noteVersionDao.renameVersion(
      'version-clear-name',
      null,
    );

    expect(changed, 1);
    expect(
      (await db.noteVersionDao.getById('version-clear-name'))?.name,
      isNull,
    );
  });

  test('历史版本 DAO 按 ID 集合只返回实际存在的版本', () async {
    await db.noteVersionDao.insertVersion(
      const NoteVersionsCompanion(
        id: Value('version-selected'),
        noteId: Value('note-selected'),
        versionNo: Value(1),
        snapshotJson: Value('[]'),
        createdAt: Value(1),
      ),
    );

    final versions = await db.noteVersionDao.listByIds({
      'version-selected',
      'already-missing',
    });

    expect(versions.map((item) => item.id), ['version-selected']);
  });

  test('历史版本 DAO 批量删除不重排保留版本号', () async {
    await db.noteVersionDao.insertVersion(
      const NoteVersionsCompanion(
        id: Value('version-delete-1'),
        noteId: Value('note-delete'),
        versionNo: Value(1),
        snapshotJson: Value('[]'),
        createdAt: Value(1),
      ),
    );
    await db.noteVersionDao.insertVersion(
      const NoteVersionsCompanion(
        id: Value('version-delete-3'),
        noteId: Value('note-delete'),
        versionNo: Value(3),
        snapshotJson: Value('[]'),
        createdAt: Value(3),
      ),
    );

    final deleted = await db.noteVersionDao.deleteByIds({'version-delete-1'});
    final remaining = await db.noteVersionDao.listByNote('note-delete');

    expect(deleted, 1);
    expect(remaining.single.id, 'version-delete-3');
    expect(remaining.single.versionNo, 3);
  });

  test('重命名历史版本会修剪名称并持久化', () async {
    final noteId = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        contentJson: _delta([_op('旧正文')]),
      ),
    ).id;
    await repository.update(id: noteId, contentJson: _delta([_op('新正文')]));
    final version = _successValue(await repository.listVersions(noteId)).single;

    final result = await repository.renameVersion(
      noteId: noteId,
      versionId: version.id,
      name: '  考前复习  ',
    );

    expect(result, isA<Success<void>>());
    expect(
      _successValue(await repository.listVersions(noteId)).single.name,
      '考前复习',
    );

    final cleared = await repository.renameVersion(
      noteId: noteId,
      versionId: version.id,
      name: '   ',
    );

    expect(cleared, isA<Success<void>>());
    expect(
      _successValue(await repository.listVersions(noteId)).single.name,
      isNull,
    );
  });

  test('批量删除历史版本会忽略已不存在 ID 且不重排版本号', () async {
    final noteId = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        contentJson: _delta([_op('第一版')]),
      ),
    ).id;
    await repository.update(id: noteId, contentJson: _delta([_op('第二版')]));
    await repository.update(id: noteId, contentJson: _delta([_op('第三版')]));
    final versionsBefore = _successValue(await repository.listVersions(noteId));
    final firstVersion = versionsBefore.singleWhere(
      (version) => version.versionNo == 1,
    );

    final result = await repository.deleteVersions(
      noteId: noteId,
      versionIds: {firstVersion.id, 'already-missing'},
    );

    expect(result, isA<Success<void>>());
    final remaining = _successValue(await repository.listVersions(noteId));
    expect(remaining.map((version) => version.versionNo), [2]);
  });

  test('同一笔记的历史版本不能使用重复自定义名称', () async {
    final noteId = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        contentJson: _delta([_op('第一版')]),
      ),
    ).id;
    await repository.update(id: noteId, contentJson: _delta([_op('第二版')]));
    await repository.update(id: noteId, contentJson: _delta([_op('第三版')]));
    final versions = _successValue(await repository.listVersions(noteId));

    await repository.renameVersion(
      noteId: noteId,
      versionId: versions.first.id,
      name: '阶段总结',
    );
    final result = await repository.renameVersion(
      noteId: noteId,
      versionId: versions.last.id,
      name: '阶段总结',
    );

    expect(result, isA<Failure<void>>());
    expect((result as Failure<void>).exception, isA<ValidationException>());
  });

  test('历史版本自定义名称超过50个字符会失败', () async {
    final noteId = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        contentJson: _delta([_op('旧正文')]),
      ),
    ).id;
    await repository.update(id: noteId, contentJson: _delta([_op('新正文')]));
    final version = _successValue(await repository.listVersions(noteId)).single;

    final result = await repository.renameVersion(
      noteId: noteId,
      versionId: version.id,
      name: List.filled(51, '字').join(),
    );

    expect(result, isA<Failure<void>>());
    expect((result as Failure<void>).exception, isA<ValidationException>());
  });

  test('批量删除混入另一笔记版本时会整体失败且不删除本笔记版本', () async {
    final noteA = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        contentJson: _delta([_op('A1')]),
      ),
    ).id;
    final noteB = _successValue(
      await repository.create(
        subjectId: 'uncategorized',
        contentJson: _delta([_op('B1')]),
      ),
    ).id;
    await repository.update(id: noteA, contentJson: _delta([_op('A2')]));
    await repository.update(id: noteB, contentJson: _delta([_op('B2')]));
    final versionA = _successValue(await repository.listVersions(noteA)).single;
    final versionB = _successValue(await repository.listVersions(noteB)).single;

    final result = await repository.deleteVersions(
      noteId: noteA,
      versionIds: {versionA.id, versionB.id},
    );

    expect(result, isA<Failure<void>>());
    expect(
      _successValue(
        await repository.listVersions(noteA),
      ).map((version) => version.id),
      [versionA.id],
    );
  });
}

Future<void> _insertNote(
  AppDatabase db, {
  required String id,
  String subjectId = 'book',
  int sortOrder = 0,
  int createdAt = 1,
}) {
  return db.noteDao.insertNote(
    NotesCompanion(
      id: Value(id),
      subjectId: Value(subjectId),
      title: Value(id),
      plainText: const Value(''),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(createdAt),
    ),
  );
}

Future<void> _insertSubject(
  AppDatabase db, {
  required String id,
  required int level,
}) {
  return db.subjectDao.insertSubject(
    SubjectsCompanion(
      id: Value(id),
      name: Value(id),
      level: Value(level),
      createdAt: const Value(1),
      updatedAt: const Value(1),
    ),
  );
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
