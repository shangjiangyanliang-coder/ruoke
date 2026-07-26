// 笔记搜索 Repository 数据库行为测试。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/note.dart';
import 'package:ruoke/src/features/notes/models/note_search_query.dart';
import 'package:ruoke/src/features/notes/repository/local_note_repository.dart';
import 'package:ruoke/src/features/notes/repository/local_tag_repository.dart';

void main() {
  late AppDatabase db;
  late LocalNoteRepository noteRepository;
  late LocalTagRepository tagRepository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    noteRepository = LocalNoteRepository(db);
    tagRepository = LocalTagRepository(db);
  });

  tearDown(() => db.close());

  test('关键词匹配标题', () async {
    await _insertNote(db, id: 'title-hit', title: '线性代数复习');
    await _insertNote(db, id: 'miss', title: '英语单词');

    final notes = _successValue(
      await noteRepository.search(const NoteSearchQuery(keyword: '  代数  ')),
    );

    expect(notes.map((note) => note.id), ['title-hit']);
  });

  test('关键词匹配纯文本正文', () async {
    await _insertNote(db, id: 'body-hit', title: '课堂记录', plainText: '牛顿第二定律');
    await _insertNote(db, id: 'miss', plainText: '光合作用');

    final notes = _successValue(
      await noteRepository.search(const NoteSearchQuery(keyword: '第二定律')),
    );

    expect(notes.map((note) => note.id), ['body-hit']);
  });

  test('空关键词不添加 LIKE 条件并返回全部未删除笔记', () async {
    await _insertNote(db, id: 'older', updatedAt: 10);
    await _insertNote(db, id: 'newer', updatedAt: 20);

    final notes = _successValue(
      await noteRepository.search(const NoteSearchQuery(keyword: '   ')),
    );

    expect(notes.map((note) => note.id), ['newer', 'older']);
  });

  test('没有匹配项时返回空列表', () async {
    await _insertNote(db, id: 'only-note', title: '高等数学');

    final notes = _successValue(
      await noteRepository.search(const NoteSearchQuery(keyword: '不存在')),
    );

    expect(notes, isEmpty);
  });

  test('数据库异常会转换为搜索失败', () async {
    await db.customStatement('DROP TABLE notes');

    final result = await noteRepository.search(const NoteSearchQuery());

    expect(result, isA<Failure<List<Note>>>());
    final exception = (result as Failure<List<Note>>).exception;
    expect(exception, isA<DatabaseException>());
    expect(exception.userMessage, '搜索笔记失败');
  });

  test('搜索排除软删除笔记', () async {
    await _insertNote(db, id: 'active', title: '共同关键词', updatedAt: 10);
    await _insertNote(db, id: 'deleted', title: '共同关键词', updatedAt: 20);
    await db.noteDao.softDelete('deleted', 30);

    final notes = _successValue(
      await noteRepository.search(const NoteSearchQuery(keyword: '关键词')),
    );

    expect(notes.map((note) => note.id), ['active']);
  });

  test('多标签筛选使用并集且同一笔记只出现一次', () async {
    final firstTag = _successValue(await tagRepository.createTag(name: '重点'));
    final secondTag = _successValue(await tagRepository.createTag(name: '待复习'));
    await _insertNote(db, id: 'first-only', updatedAt: 10);
    await _insertNote(db, id: 'second-only', updatedAt: 20);
    await _insertNote(db, id: 'both', updatedAt: 30);
    await _insertNote(db, id: 'untagged', updatedAt: 40);
    await tagRepository.replaceNoteTags(
      noteId: 'first-only',
      tagIds: [firstTag.id],
    );
    await tagRepository.replaceNoteTags(
      noteId: 'second-only',
      tagIds: [secondTag.id],
    );
    await tagRepository.replaceNoteTags(
      noteId: 'both',
      tagIds: [firstTag.id, secondTag.id],
    );

    final notes = _successValue(
      await noteRepository.search(
        NoteSearchQuery(tagIds: {firstTag.id, secondTag.id}),
      ),
    );

    expect(notes.map((note) => note.id), ['both', 'second-only', 'first-only']);
  });

  test('关键词和标签条件同时生效', () async {
    final tag = _successValue(await tagRepository.createTag(name: '考试'));
    await _insertNote(db, id: 'match', title: '概率论考点', updatedAt: 30);
    await _insertNote(db, id: 'keyword-only', title: '概率论习题', updatedAt: 20);
    await _insertNote(db, id: 'tag-only', title: '微积分考点', updatedAt: 10);
    await tagRepository.replaceNoteTags(noteId: 'match', tagIds: [tag.id]);
    await tagRepository.replaceNoteTags(noteId: 'tag-only', tagIds: [tag.id]);

    final notes = _successValue(
      await noteRepository.search(
        NoteSearchQuery(keyword: '概率论', tagIds: {tag.id}),
      ),
    );

    expect(notes.map((note) => note.id), ['match']);
  });

  test('支持最近更新、最早更新和标题升序', () async {
    await _insertNote(db, id: 'middle', title: 'beta', updatedAt: 20);
    await _insertNote(db, id: 'newest', title: 'gamma', updatedAt: 30);
    await _insertNote(db, id: 'oldest', title: 'alpha', updatedAt: 10);

    final newestFirst = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(sortOrder: NoteSortOrder.updatedDesc),
      ),
    );
    final oldestFirst = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(sortOrder: NoteSortOrder.updatedAsc),
      ),
    );
    final titleFirst = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(sortOrder: NoteSortOrder.titleAsc),
      ),
    );

    expect(newestFirst.map((note) => note.id), ['newest', 'middle', 'oldest']);
    expect(oldestFirst.map((note) => note.id), ['oldest', 'middle', 'newest']);
    expect(titleFirst.map((note) => note.id), ['oldest', 'middle', 'newest']);
  });

  test('排序字段相同时按笔记 ID 保持稳定次序', () async {
    await _insertNote(db, id: 'note-b', title: 'same', updatedAt: 10);
    await _insertNote(db, id: 'note-a', title: 'same', updatedAt: 10);

    for (final sortOrder in NoteSortOrder.values) {
      final notes = _successValue(
        await noteRepository.search(NoteSearchQuery(sortOrder: sortOrder)),
      );
      expect(notes.map((note) => note.id), ['note-a', 'note-b']);
    }
  });
}

Future<void> _insertNote(
  AppDatabase db, {
  required String id,
  String? title,
  String plainText = '',
  int updatedAt = 1,
}) async {
  await db.noteDao.insertNote(
    NotesCompanion(
      id: Value(id),
      subjectId: const Value('uncategorized'),
      title: Value(title),
      plainText: Value(plainText),
      createdAt: const Value(1),
      updatedAt: Value(updatedAt),
    ),
  );
}

T _successValue<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}
