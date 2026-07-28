// 科目仓储名称搜索与祖先路径补齐测试。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';
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
}

Future<void> _insertSubject(
  AppDatabase db, {
  required String id,
  required String name,
  required int level,
  String? parentId,
  bool isDeleted = false,
}) {
  return db.subjectDao.insertSubject(
    SubjectsCompanion(
      id: Value(id),
      parentId: Value(parentId),
      name: Value(name),
      level: Value(level),
      isDeleted: Value(isDeleted),
      createdAt: const Value(1),
      updatedAt: const Value(1),
    ),
  );
}

List<SubjectPath> _success(Result<List<SubjectPath>> result) {
  expect(result, isA<Success<List<SubjectPath>>>());
  return (result as Success<List<SubjectPath>>).value;
}
