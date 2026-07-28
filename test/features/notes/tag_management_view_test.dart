// 标签搜索页入口、匹配模式、多标签并集与范围交互测试。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/main.dart';
import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/search_match_mode.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/local_note_repository.dart';
import 'package:ruoke/src/features/notes/repository/local_tag_repository.dart';
import 'package:ruoke/src/features/notes/view/tag_management_view.dart';
import 'package:ruoke/src/routing/app_router.dart';

void main() {
  testWidgets('笔记列表顶栏提供通用搜索和标签搜索入口', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    appRouter.go('/notes');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const RuokeApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('搜索笔记'), findsOneWidget);
    expect(find.byTooltip('标签搜索'), findsOneWidget);

    await tester.tap(find.byTooltip('标签搜索'));
    await tester.pumpAndSettle();
    expect(find.text('标签搜索'), findsOneWidget);
    expect(find.text('请先搜索并选择标签'), findsOneWidget);
  });

  testWidgets('标签名称支持部分完全匹配和多标签并集', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tags = LocalTagRepository(db);
    final notes = LocalNoteRepository(db);
    final review = _successValue(await tags.createTag(name: '复习'));
    final finalReview = _successValue(await tags.createTag(name: '期末复习'));
    await tags.createTag(name: '错题');
    final first = _successValue(
      await notes.create(subjectId: 'uncategorized', title: '复习笔记'),
    );
    final second = _successValue(
      await notes.create(subjectId: 'uncategorized', title: '期末笔记'),
    );
    await notes.create(subjectId: 'uncategorized', title: '无标签笔记');
    await tags.replaceNoteTags(noteId: first.id, tagIds: [review.id]);
    await tags.replaceNoteTags(noteId: second.id, tagIds: [finalReview.id]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: TagManagementView()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('tag-search-keyword')),
      '复',
    );
    await tester.tap(find.byTooltip('执行标签搜索'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, '复习'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '期末复习'), findsOneWidget);
    expect(find.text('错题'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('tag-search-keyword')),
      '复习',
    );
    await tester.tap(find.byType(DropdownButton<SearchMatchMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完全匹配').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, '复习'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '期末复习'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, '复习'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<SearchMatchMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('部分匹配').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '期末复习'));
    await tester.pumpAndSettle();

    expect(find.text('复习笔记'), findsOneWidget);
    expect(find.text('期末笔记'), findsOneWidget);
    expect(find.text('无标签笔记'), findsNothing);
  });

  testWidgets('标签搜索可按指定书和全部章限制结果', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _insertSubject(db, id: 'book-a', name: '书 A', level: 0);
    await _insertSubject(
      db,
      id: 'chapter-a',
      name: '章 A',
      level: 1,
      parentId: 'book-a',
    );
    await _insertSubject(db, id: 'book-b', name: '书 B', level: 0);
    final tags = LocalTagRepository(db);
    final notes = LocalNoteRepository(db);
    final tag = _successValue(await tags.createTag(name: '重点'));
    final bookNote = _successValue(
      await notes.create(subjectId: 'book-a', title: '书内重点'),
    );
    final chapterNote = _successValue(
      await notes.create(subjectId: 'chapter-a', title: '章内重点'),
    );
    final otherBook = _successValue(
      await notes.create(subjectId: 'book-b', title: '其他书重点'),
    );
    for (final note in [bookNote, chapterNote, otherBook]) {
      await tags.replaceNoteTags(noteId: note.id, tagIds: [tag.id]);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: TagManagementView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('tag-search-keyword')),
      '重点',
    );
    await tester.tap(find.byTooltip('执行标签搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '重点'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('选择标签搜索范围'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书 A').last);
    await tester.pumpAndSettle();
    expect(find.text('书内重点'), findsOneWidget);
    expect(find.text('章内重点'), findsOneWidget);
    expect(find.text('其他书重点'), findsNothing);

    await tester.tap(find.byTooltip('选择标签搜索范围'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择全部或指定层级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部章').last);
    await tester.pumpAndSettle();
    expect(find.text('章内重点'), findsOneWidget);
    expect(find.text('书内重点'), findsNothing);
  });
}

Future<void> _insertSubject(
  AppDatabase db, {
  required String id,
  required String name,
  required int level,
  String? parentId,
}) async {
  await db.subjectDao.insertSubject(
    SubjectsCompanion(
      id: Value(id),
      parentId: Value(parentId),
      name: Value(name),
      level: Value(level),
      createdAt: const Value(1),
      updatedAt: const Value(1),
    ),
  );
}

T _successValue<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}
