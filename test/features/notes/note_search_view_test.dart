// 笔记搜索页关键词、标签、排序、空态和结果导航测试。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/note_search_query.dart';
import 'package:ruoke/src/features/notes/models/search_match_mode.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/local_note_repository.dart';
import 'package:ruoke/src/features/notes/repository/local_tag_repository.dart';
import 'package:ruoke/src/features/notes/view/note_search_view.dart';

void main() {
  testWidgets('搜索页支持关键词、标签筛选、排序并打开结果', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final notes = LocalNoteRepository(db);
    final tags = LocalTagRepository(db);
    final algebra = _successValue(
      await notes.create(
        subjectId: 'uncategorized',
        title: 'beta algebra',
        plainText: '矩阵与向量',
      ),
    );
    final newest = _successValue(
      await notes.create(
        subjectId: 'uncategorized',
        title: 'zeta algebra',
        plainText: '群与环',
      ),
    );
    await notes.create(
      subjectId: 'uncategorized',
      title: '英语',
      plainText: '单词',
    );
    await db.noteDao.updateNote(algebra.id, updatedAt: 10);
    await db.noteDao.updateNote(newest.id, updatedAt: 20);
    final important = _successValue(await tags.createTag(name: '重点'));
    await tags.replaceNoteTags(noteId: algebra.id, tagIds: [important.id]);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const NoteSearchView()),
        GoRoute(
          path: '/notes/editor/:noteId',
          builder: (_, state) =>
              Scaffold(body: Text('编辑:${state.pathParameters['noteId']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'algebra');
    await tester.tap(find.byTooltip('执行搜索'));
    await tester.pumpAndSettle();
    expect(find.text('beta algebra'), findsOneWidget);
    expect(find.text('zeta algebra'), findsOneWidget);
    expect(find.text('英语'), findsNothing);
    expect(
      tester.getTopLeft(find.text('zeta algebra')).dy,
      lessThan(tester.getTopLeft(find.text('beta algebra')).dy),
    );

    await tester.tap(find.byType(DropdownButton<NoteSortOrder>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标题升序').last);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('beta algebra')).dy,
      lessThan(tester.getTopLeft(find.text('zeta algebra')).dy),
    );

    await tester.tap(find.widgetWithText(FilterChip, '重点'));
    await tester.pumpAndSettle();
    expect(find.text('beta algebra'), findsOneWidget);
    expect(find.text('zeta algebra'), findsNothing);

    await tester.tap(find.text('beta algebra'));
    await tester.pumpAndSettle();
    expect(find.text('编辑:${algebra.id}'), findsOneWidget);
    await notes.softDelete(algebra.id);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('beta algebra'), findsNothing);
    expect(find.text('没有匹配的笔记'), findsOneWidget);
  });

  testWidgets('没有搜索结果时显示空态', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: NoteSearchView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('没有匹配的笔记'), findsOneWidget);
  });

  testWidgets('标题正文支持部分匹配和完全匹配切换', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final notes = LocalNoteRepository(db);
    await notes.create(
      subjectId: 'uncategorized',
      title: '代数',
      plainText: '基础',
    );
    await notes.create(
      subjectId: 'uncategorized',
      title: '线性代数',
      plainText: '矩阵',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: NoteSearchView()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('note-search-keyword')),
      '代数',
    );
    await tester.tap(find.byTooltip('执行搜索'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '代数'), findsOneWidget);
    expect(find.text('线性代数'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<SearchMatchMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完全匹配').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, '代数'), findsOneWidget);
    expect(find.text('线性代数'), findsNothing);
  });

  testWidgets('搜索范围支持指定书子树和全部章直接归属', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _insertSubject(
      db,
      id: 'book-a',
      name: '书 A',
      level: 0,
    );
    await _insertSubject(
      db,
      id: 'chapter-a',
      parentId: 'book-a',
      name: '章 A',
      level: 1,
    );
    await _insertSubject(
      db,
      id: 'section-a',
      parentId: 'chapter-a',
      name: '节 A',
      level: 2,
    );
    await _insertSubject(
      db,
      id: 'book-b',
      name: '书 B',
      level: 0,
    );
    final notes = LocalNoteRepository(db);
    await notes.create(subjectId: 'book-a', title: '书 A 笔记');
    await notes.create(subjectId: 'chapter-a', title: '章 A 笔记');
    await notes.create(subjectId: 'section-a', title: '节 A 笔记');
    await notes.create(subjectId: 'book-b', title: '书 B 笔记');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: NoteSearchView()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('选择搜索范围'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书 A').last);
    await tester.pumpAndSettle();
    expect(find.text('书 A 笔记'), findsOneWidget);
    expect(find.text('章 A 笔记'), findsOneWidget);
    expect(find.text('节 A 笔记'), findsOneWidget);
    expect(find.text('书 B 笔记'), findsNothing);

    await tester.tap(find.byTooltip('选择搜索范围'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部章').last);
    await tester.pumpAndSettle();
    expect(find.text('章 A 笔记'), findsOneWidget);
    expect(find.text('书 A 笔记'), findsNothing);
    expect(find.text('节 A 笔记'), findsNothing);
  });

  testWidgets('退出搜索页后重新进入会清空全部页面条件', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.push('/search'),
                child: const Text('打开搜索'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/search',
          builder: (_, _) => const NoteSearchView(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('note-search-keyword')),
      '上一次搜索',
    );
    await tester.tap(find.byTooltip('执行搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<SearchMatchMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完全匹配').last);
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开搜索'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('note-search-keyword')),
    );
    final matchMode = tester.widget<DropdownButton<SearchMatchMode>>(
      find.byType(DropdownButton<SearchMatchMode>),
    );
    final sortOrder = tester.widget<DropdownButton<NoteSortOrder>>(
      find.byType(DropdownButton<NoteSortOrder>),
    );
    expect(field.controller?.text, isEmpty);
    expect(matchMode.value, SearchMatchMode.contains);
    expect(sortOrder.value, NoteSortOrder.updatedDesc);
    expect(find.text('全部笔记'), findsOneWidget);
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
