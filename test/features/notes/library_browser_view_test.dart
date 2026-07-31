// 文件夹浏览页的交互回归测试。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/main.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/local_folder_repository.dart';
import 'package:ruoke/src/features/notes/repository/local_subject_repository.dart';
import 'package:ruoke/src/features/notes/models/library_location.dart';
import 'package:ruoke/src/features/notes/view/library_browser_view.dart';
import 'package:ruoke/src/features/notes/view/library_expanded_tree.dart';
import 'package:ruoke/src/routing/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('笔记根页在原页切换展开浏览且不显示旧书章节管理', (tester) async {
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

    expect(find.byTooltip('书章节管理'), findsNothing);
    await tester.tap(find.byTooltip('展开浏览'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-browser-expanded-mode')), findsOneWidget);

    await tester.tap(find.byTooltip('逐级浏览'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('新建内容'), findsOneWidget);
    expect(find.byTooltip('新建笔记'), findsOneWidget);
  });

  testWidgets('文件夹浏览页也提供展开浏览切换', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          home: LibraryBrowserView(
            location: LibraryLocation.folder('folder-a'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('展开浏览'), findsOneWidget);
  });

  testWidgets('展开树接收当前文件夹位置作为范围根', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          home: LibraryExpandedTree(
            location: LibraryLocation.folder('folder-a'),
          ),
        ),
      ),
    );
    expect(find.byType(LibraryExpandedTree), findsOneWidget);
  });

  testWidgets('文件夹展开浏览不显示兄弟文件夹', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folders = LocalFolderRepository(db);
    final folderA = (await folders.create(name: '资料') as Success).value;
    await folders.create(name: '其他资料');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: LibraryExpandedTree(
              location: LibraryLocation.folder(folderA),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('资料'), findsOneWidget);
    expect(find.text('其他资料'), findsNothing);
  });

  testWidgets('新建内容草稿后进入同页创建位置选择模式', (tester) async {
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

    await tester.tap(find.byTooltip('新建内容'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '数学资料');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(find.text('选择创建位置'), findsOneWidget);
    expect(find.byTooltip('新建笔记'), findsNothing);
    expect(find.byTooltip('搜索笔记'), findsNothing);
    expect(find.text('在当前目录创建'), findsOneWidget);

    await tester.tap(find.text('在当前目录创建'));
    await tester.pumpAndSettle();

    final folders = await LocalFolderRepository(db).listAll();
    expect((folders as Success).value.single.name, '数学资料');
    expect(find.text('选择创建位置'), findsNothing);
  });

  testWidgets('在文件夹内创建书会直接归属该文件夹', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folderId =
        (await LocalFolderRepository(db).create(name: '资料') as Success).value;
    appRouter.go('/notes/folder/$folderId');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const RuokeApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件夹').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('书').last);
    await tester.enterText(find.byType(TextField), '高等数学');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('在当前目录创建'));
    await tester.pumpAndSettle();

    final books = await LocalSubjectRepository(db).listAll();
    expect((books as Success).value.single.folderId, folderId);
  });

  testWidgets('选择创建章节位置时书提供在此创建动作', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await LocalSubjectRepository(db).create(name: '数学', level: 0);
    appRouter.go('/notes');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const RuokeApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件夹').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('章').last);
    await tester.enterText(find.byType(TextField), '集合');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(find.text('在此创建'), findsOneWidget);
  });

  testWidgets('新建笔记从当前目录进入同页位置选择', (tester) async {
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

    await tester.tap(find.byTooltip('新建笔记'));
    await tester.pumpAndSettle();

    expect(find.text('选择创建位置'), findsOneWidget);
    expect(find.text('选择笔记归属'), findsNothing);
  });

  testWidgets('选择笔记位置时点击节直接打开编辑器', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = LocalSubjectRepository(db);
    final bookId = (await repository.create(name: '数学', level: 0) as Success).value;
    final chapterId = (await repository.create(
      name: '函数',
      level: 1,
      parentId: bookId,
    ) as Success).value;
    final sectionId = (await repository.create(
      name: '定义域',
      level: 2,
      parentId: chapterId,
    ) as Success).value;
    appRouter.go('/notes/subject/$chapterId');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const RuokeApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('定义域'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('保存'), findsOneWidget);
    expect(sectionId, isNotEmpty);
  });

  testWidgets('从子层级取消位置选择会返回启动位置', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folderId =
        (await LocalFolderRepository(db).create(name: '资料') as Success).value;
    appRouter.go('/notes');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const RuokeApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '笔记'), findsOneWidget);
    expect(folderId, isNotEmpty);
  });

  testWidgets('启动位置按系统返回键只取消位置选择', (tester) async {
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

    await tester.tap(find.byTooltip('新建笔记'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byTooltip('新建笔记'), findsOneWidget);
    expect(find.text('选择创建位置'), findsNothing);
  });
}
