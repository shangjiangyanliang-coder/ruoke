// 笔记搜索 Repository 数据库行为测试。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/note.dart';
import 'package:ruoke/src/features/notes/models/note_search_query.dart';
import 'package:ruoke/src/features/notes/models/search_match_mode.dart';
import 'package:ruoke/src/features/notes/models/subject_scope.dart';
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

  test('完全匹配会修剪标题和正文首尾空白且不匹配包含关系', () async {
    await _insertNote(db, id: 'exact-title', title: '代数', updatedAt: 10);
    await _insertNote(db, id: 'contains-title', title: '线性代数', updatedAt: 20);
    await _insertNote(db, id: 'exact-body', plainText: '  代数\n', updatedAt: 30);

    final exact = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(
          keyword: '  代数  ',
          keywordMatchMode: SearchMatchMode.exact,
        ),
      ),
    );
    final contains = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(
          keyword: '代数',
          keywordMatchMode: SearchMatchMode.contains,
        ),
      ),
    );

    expect(exact.map((note) => note.id), ['exact-body', 'exact-title']);
    expect(contains.map((note) => note.id), [
      'exact-body',
      'contains-title',
      'exact-title',
    ]);
  });

  test('部分匹配将百分号下划线和反斜杠按字面字符搜索', () async {
    await _insertNote(db, id: 'literal', title: r'进度_50%\路径', updatedAt: 20);
    await _insertNote(db, id: 'ordinary', title: '进度A500路径', updatedAt: 10);

    for (final keyword in [r'_', r'%', r'\']) {
      final notes = _successValue(
        await noteRepository.search(NoteSearchQuery(keyword: keyword)),
      );
      expect(notes.map((note) => note.id), ['literal']);
    }
  });

  test('指定书章节范围按节点自身和后代筛选笔记', () async {
    await _insertSubjectTree(db);
    await _insertScopeNotes(db);

    final book = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(subjectScope: SubjectScope.subtree('book-a')),
      ),
    );
    final chapter = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(subjectScope: SubjectScope.subtree('chapter-a')),
      ),
    );
    final section = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(subjectScope: SubjectScope.subtree('section-a')),
      ),
    );

    expect(book.map((note) => note.id).toSet(), {
      'book-a-note',
      'chapter-a-note',
      'section-a-note',
      'chapter-b-note',
    });
    expect(chapter.map((note) => note.id).toSet(), {
      'chapter-a-note',
      'section-a-note',
    });
    expect(section.map((note) => note.id), ['section-a-note']);
  });

  test('指定层级只搜索直接归属于全部书章节的笔记', () async {
    await _insertSubjectTree(db);
    await _insertScopeNotes(db);

    final books = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(subjectScope: SubjectScope.level(0)),
      ),
    );
    final chapters = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(subjectScope: SubjectScope.level(1)),
      ),
    );
    final sections = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(subjectScope: SubjectScope.level(2)),
      ),
    );

    expect(books.map((note) => note.id).toSet(), {
      'book-a-note',
      'book-b-note',
    });
    expect(chapters.map((note) => note.id).toSet(), {
      'chapter-a-note',
      'chapter-b-note',
    });
    expect(sections.map((note) => note.id), ['section-a-note']);
  });

  test('全部范围包含未分类而指定范围排除未分类', () async {
    await _insertSubjectTree(db);
    await _insertScopeNotes(db);

    final all = _successValue(
      await noteRepository.search(const NoteSearchQuery()),
    );
    final books = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(subjectScope: SubjectScope.level(0)),
      ),
    );

    expect(all.map((note) => note.id), contains('uncategorized-note'));
    expect(books.map((note) => note.id), isNot(contains('uncategorized-note')));
  });

  test('指定文件夹范围递归包含其内书及其书章节的笔记', () async {
    await _insertSubjectTree(db);
    await _insertScopeNotes(db);
    await db.into(db.subjectFolders).insert(
      const SubjectFoldersCompanion(
        id: Value('folder-a'),
        name: Value('资料'),
        createdAt: Value(1),
        updatedAt: Value(1),
      ),
    );
    await db.subjectDao.updateFolder('book-a', 'folder-a', 2);

    final notes = _successValue(
      await noteRepository.search(
        const NoteSearchQuery(subjectScope: SubjectScope.folder('folder-a')),
      ),
    );

    expect(notes.map((note) => note.id).toSet(), {
      'book-a-note',
      'chapter-a-note',
      'section-a-note',
      'chapter-b-note',
    });
  });

  test('指定不存在或已软删除的节点返回范围已不存在', () async {
    await _insertSubjectTree(db);
    await db.subjectDao.softDelete('chapter-a', 99);

    for (final subjectId in ['missing', 'chapter-a']) {
      final result = await noteRepository.search(
        NoteSearchQuery(subjectScope: SubjectScope.subtree(subjectId)),
      );

      expect(result, isA<Failure<List<Note>>>());
      final exception = (result as Failure<List<Note>>).exception;
      expect(exception, isA<ValidationException>());
      expect(exception.userMessage, '所选范围已不存在，请重新选择');
    }
  });
}

Future<void> _insertNote(
  AppDatabase db, {
  required String id,
  String subjectId = 'uncategorized',
  String? title,
  String plainText = '',
  int updatedAt = 1,
}) async {
  await db.noteDao.insertNote(
    NotesCompanion(
      id: Value(id),
      subjectId: Value(subjectId),
      title: Value(title),
      plainText: Value(plainText),
      createdAt: const Value(1),
      updatedAt: Value(updatedAt),
    ),
  );
}

Future<void> _insertSubjectTree(AppDatabase db) async {
  for (final subject in [
    (id: 'book-a', parentId: null, name: '书 A', level: 0, sortOrder: 0),
    (id: 'chapter-a', parentId: 'book-a', name: '章 A', level: 1, sortOrder: 0),
    (
      id: 'section-a',
      parentId: 'chapter-a',
      name: '节 A',
      level: 2,
      sortOrder: 0,
    ),
    (id: 'chapter-b', parentId: 'book-a', name: '章 B', level: 1, sortOrder: 1),
    (id: 'book-b', parentId: null, name: '书 B', level: 0, sortOrder: 1),
  ]) {
    await db.subjectDao.insertSubject(
      SubjectsCompanion(
        id: Value(subject.id),
        parentId: Value(subject.parentId),
        name: Value(subject.name),
        level: Value(subject.level),
        sortOrder: Value(subject.sortOrder),
        createdAt: const Value(1),
        updatedAt: const Value(1),
      ),
    );
  }
}

Future<void> _insertScopeNotes(AppDatabase db) async {
  final fixtures = [
    (id: 'book-a-note', subjectId: 'book-a', updatedAt: 10),
    (id: 'chapter-a-note', subjectId: 'chapter-a', updatedAt: 20),
    (id: 'section-a-note', subjectId: 'section-a', updatedAt: 30),
    (id: 'chapter-b-note', subjectId: 'chapter-b', updatedAt: 40),
    (id: 'book-b-note', subjectId: 'book-b', updatedAt: 50),
    (id: 'uncategorized-note', subjectId: 'uncategorized', updatedAt: 60),
  ];
  for (final fixture in fixtures) {
    await _insertNote(
      db,
      id: fixture.id,
      subjectId: fixture.subjectId,
      updatedAt: fixture.updatedAt,
    );
  }
}

T _successValue<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}
