// 笔记搜索页关键词、标签、排序、空态和结果导航测试。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/note_search_query.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/local_note_repository.dart';
import 'package:ruoke/src/features/notes/repository/local_tag_repository.dart';
import 'package:ruoke/src/features/notes/view/note_search_view.dart';
import 'package:ruoke/src/features/notes/view_model/view_model_providers.dart';

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

  testWidgets('页面重开时控件恢复已有关键词、标签和排序', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tag = _successValue(
      await LocalTagRepository(db).createTag(name: '重点'),
    );
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await container.read(noteSearchVmProvider.future);
    final notifier = container.read(noteSearchVmProvider.notifier);
    await notifier.setKeyword('矩阵');
    await notifier.setTagIds({tag.id});
    await notifier.setSortOrder(NoteSortOrder.titleAsc);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NoteSearchView()),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    final dropdown = tester.widget<DropdownButton<NoteSortOrder>>(
      find.byType(DropdownButton<NoteSortOrder>),
    );
    final chip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '重点'),
    );
    expect(field.controller?.text, '矩阵');
    expect(dropdown.value, NoteSortOrder.titleAsc);
    expect(chip.selected, isTrue);
  });
}

T _successValue<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}
