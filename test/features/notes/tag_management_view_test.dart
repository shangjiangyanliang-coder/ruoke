// 标签管理页入口、增改删与多选筛选交互测试。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/main.dart';
import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/local_note_repository.dart';
import 'package:ruoke/src/features/notes/repository/local_tag_repository.dart';
import 'package:ruoke/src/features/notes/view/tag_management_view.dart';
import 'package:ruoke/src/routing/app_router.dart';

void main() {
  testWidgets('笔记列表顶栏提供搜索和标签管理入口', (tester) async {
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
    expect(find.byTooltip('标签管理'), findsOneWidget);

    await tester.tap(find.byTooltip('搜索笔记'));
    await tester.pumpAndSettle();
    expect(find.text('搜索笔记'), findsWidgets);
    appRouter.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('标签管理'));
    await tester.pumpAndSettle();
    expect(find.text('标签管理'), findsOneWidget);
  });

  testWidgets('标签页支持新建、改名和删除二次确认', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = LocalTagRepository(db);
    final oldTag = _successValue(await repository.createTag(name: '旧标签'));
    final note = _successValue(
      await LocalNoteRepository(
        db,
      ).create(subjectId: 'uncategorized', title: '计数笔记'),
    );
    await repository.replaceNoteTags(noteId: note.id, tagIds: [oldTag.id]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: TagManagementView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 条笔记'), findsOneWidget);

    await tester.tap(find.byTooltip('新建标签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新标签');
    await tester.tap(find.widgetWithText(FilledButton, '新建'));
    await tester.pumpAndSettle();
    expect(find.text('新标签'), findsOneWidget);

    await tester.tap(find.byTooltip('改名').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '已改名');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('已改名'), findsOneWidget);

    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    expect(find.text('删除标签？'), findsOneWidget);
    expect(find.text('已改名'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('已改名'), findsNothing);
  });

  testWidgets('生产路由解析多选标签并显示并集搜索结果', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tags = LocalTagRepository(db);
    final notes = LocalNoteRepository(db);
    final firstTag = _successValue(await tags.createTag(name: '重点'));
    final secondTag = _successValue(await tags.createTag(name: '待复习'));
    final firstNote = _successValue(
      await notes.create(subjectId: 'uncategorized', title: '重点笔记'),
    );
    final secondNote = _successValue(
      await notes.create(subjectId: 'uncategorized', title: '复习笔记'),
    );
    await notes.create(subjectId: 'uncategorized', title: '无标签笔记');
    await tags.replaceNoteTags(noteId: firstNote.id, tagIds: [firstTag.id]);
    await tags.replaceNoteTags(noteId: secondNote.id, tagIds: [secondTag.id]);
    appRouter.go('/notes');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const RuokeApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('标签管理'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('重点'));
    await tester.pump();
    await tester.tap(find.text('待复习'));
    await tester.pump();
    await tester.tap(find.text('筛选已选标签 (2)'));
    await tester.pumpAndSettle();

    expect(find.text('搜索笔记'), findsWidgets);
    expect(find.text('重点笔记'), findsOneWidget);
    expect(find.text('复习笔记'), findsOneWidget);
    expect(find.text('无标签笔记'), findsNothing);
  });
}

T _successValue<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}
