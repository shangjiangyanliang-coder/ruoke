// 文件夹浏览页的交互回归测试。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/main.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/local_folder_repository.dart';
import 'package:ruoke/src/features/notes/repository/local_note_repository.dart';
import 'package:ruoke/src/features/notes/repository/local_subject_repository.dart';
import 'package:ruoke/src/features/notes/models/library_location.dart';
import 'package:ruoke/src/features/notes/models/library_organization.dart';
import 'package:ruoke/src/features/notes/view/library_browser_view.dart';
import 'package:ruoke/src/features/notes/view/library_expanded_tree.dart';
import 'package:ruoke/src/features/notes/view/library_item_action_menu.dart';
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
    expect(
      find.byKey(const Key('library-browser-expanded-mode')),
      findsOneWidget,
    );

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

  testWidgets('展开树逐层显示五类统一菜单并回传项目动作', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folderId =
        (await LocalFolderRepository(db).create(name: '资料') as Success).value;
    final subjects = LocalSubjectRepository(db);
    final bookId =
        (await subjects.create(name: '数学', level: 0, folderId: folderId)
                as Success)
            .value;
    final chapterId =
        (await subjects.create(name: '函数', level: 1, parentId: bookId)
                as Success)
            .value;
    final sectionId =
        (await subjects.create(name: '定义域', level: 2, parentId: chapterId)
                as Success)
            .value;
    final note =
        (await LocalNoteRepository(db).create(subjectId: bookId, title: '函数笔记')
                as Success)
            .value;
    final selected = <Object>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: LibraryExpandedTree(
              location: const LibraryLocation.root(),
              onAction: (kind, id, name, parentId, action) {
                selected.addAll([kind, id, name, parentId ?? '', action]);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('library-item-menu-folder-$folderId')),
      findsOneWidget,
    );
    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('library-item-menu-book-$bookId')),
      findsOneWidget,
    );
    await tester.tap(find.text('数学'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('library-item-menu-chapter-$chapterId')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('library-item-menu-note-${note.id}')),
      findsOneWidget,
    );
    await tester.tap(find.text('函数'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('library-item-menu-section-$sectionId')),
      findsOneWidget,
    );

    await _selectMenuAction(
      tester,
      'library-item-menu-section-$sectionId',
      '移动',
    );
    expect(selected, [
      LibraryItemKind.section,
      sectionId,
      '定义域',
      chapterId,
      LibraryItemAction.move,
    ]);
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
    final bookId =
        (await repository.create(name: '数学', level: 0) as Success).value;
    final chapterId =
        (await repository.create(name: '函数', level: 1, parentId: bookId)
                as Success)
            .value;
    final sectionId =
        (await repository.create(name: '定义域', level: 2, parentId: chapterId)
                as Success)
            .value;
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

  testWidgets('逐级浏览的文件夹书章节笔记均使用统一三点菜单', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folders = LocalFolderRepository(db);
    final subjects = LocalSubjectRepository(db);
    final folderId = (await folders.create(name: '资料') as Success).value;
    final bookId =
        (await subjects.create(name: '数学', level: 0) as Success).value;
    final chapterId =
        (await subjects.create(name: '函数', level: 1, parentId: bookId)
                as Success)
            .value;
    final sectionId =
        (await subjects.create(name: '定义域', level: 2, parentId: chapterId)
                as Success)
            .value;
    final note =
        (await LocalNoteRepository(db).create(subjectId: bookId, title: '函数笔记')
                as Success)
            .value;

    await _pumpBrowser(tester, db, const LibraryLocation.root());
    expect(
      find.byKey(ValueKey('library-item-menu-folder-$folderId')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('library-item-menu-book-$bookId')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.drive_file_move_outlined), findsNothing);

    await _pumpBrowser(tester, db, LibraryLocation.subject(bookId));
    expect(
      find.byKey(ValueKey('library-item-menu-chapter-$chapterId')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('library-item-menu-note-${note.id}')),
      findsOneWidget,
    );

    await _pumpBrowser(tester, db, LibraryLocation.subject(chapterId));
    expect(
      find.byKey(ValueKey('library-item-menu-section-$sectionId')),
      findsOneWidget,
    );
    expect(find.byType(LibraryItemActionMenu), findsOneWidget);
  });

  testWidgets('五类菜单按真实父级构造排序请求并按项目构造移动请求', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folders = LocalFolderRepository(db);
    final subjects = LocalSubjectRepository(db);
    final folderId = (await folders.create(name: '资料') as Success).value;
    final bookId =
        (await subjects.create(name: '数学', level: 0, folderId: folderId)
                as Success)
            .value;
    final chapterId =
        (await subjects.create(name: '函数', level: 1, parentId: bookId)
                as Success)
            .value;
    final sectionId =
        (await subjects.create(name: '定义域', level: 2, parentId: chapterId)
                as Success)
            .value;
    final note =
        (await LocalNoteRepository(db).create(subjectId: bookId, title: '函数笔记')
                as Success)
            .value;
    final moves = <LibraryMoveRequest>[];
    final reorders = <LibraryReorderRequest>[];
    Future<bool?> moveLauncher(_, request) async {
      moves.add(request);
      return false;
    }

    Future<bool?> reorderLauncher(_, request) async {
      reorders.add(request);
      return false;
    }

    await _pumpBrowser(
      tester,
      db,
      const LibraryLocation.root(),
      moveLauncher: moveLauncher,
      reorderLauncher: reorderLauncher,
    );
    await _selectMenuAction(
      tester,
      'library-item-menu-folder-$folderId',
      '调整顺序',
    );
    await _selectMenuAction(tester, 'library-item-menu-folder-$folderId', '移动');

    await _pumpBrowser(
      tester,
      db,
      LibraryLocation.folder(folderId),
      moveLauncher: moveLauncher,
      reorderLauncher: reorderLauncher,
    );
    await _selectMenuAction(tester, 'library-item-menu-book-$bookId', '调整顺序');
    await _selectMenuAction(tester, 'library-item-menu-book-$bookId', '移动');

    await _pumpBrowser(
      tester,
      db,
      LibraryLocation.subject(bookId),
      moveLauncher: moveLauncher,
      reorderLauncher: reorderLauncher,
    );
    await _selectMenuAction(
      tester,
      'library-item-menu-chapter-$chapterId',
      '调整顺序',
    );
    await _selectMenuAction(tester, 'library-item-menu-note-${note.id}', '移动');

    await _pumpBrowser(
      tester,
      db,
      LibraryLocation.subject(chapterId),
      moveLauncher: moveLauncher,
      reorderLauncher: reorderLauncher,
    );
    await _selectMenuAction(
      tester,
      'library-item-menu-section-$sectionId',
      '移动',
    );

    expect(reorders.map((request) => request.kind), [
      LibraryItemKind.folder,
      LibraryItemKind.book,
      LibraryItemKind.chapter,
    ]);
    expect(reorders[0].parentId, isNull);
    expect(reorders[1].parentId, folderId);
    expect(reorders[2].parentId, bookId);
    expect(moves.map((request) => request.kind), [
      LibraryItemKind.folder,
      LibraryItemKind.book,
      LibraryItemKind.note,
      LibraryItemKind.section,
    ]);
    expect(moves[0].itemId, folderId);
    expect(moves[1].itemId, bookId);
    expect(moves[2].itemId, note.id);
    expect(moves[3].itemId, sectionId);
  });

  testWidgets('书和笔记菜单重命名后立即刷新且笔记不生成历史版本', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final subjects = LocalSubjectRepository(db);
    final notes = LocalNoteRepository(db);
    final bookId =
        (await subjects.create(name: '数学', level: 0) as Success).value;
    final note =
        (await notes.create(subjectId: bookId, title: '旧笔记名', plainText: '正文')
                as Success)
            .value;

    await _pumpBrowser(tester, db, const LibraryLocation.root());
    await _selectMenuAction(tester, 'library-item-menu-book-$bookId', '重命名');
    await tester.enterText(find.byType(TextField), '高等数学');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('高等数学'), findsOneWidget);
    final renamedBook = (await subjects.getById(bookId) as Success).value;
    expect(renamedBook?.name, '高等数学');

    await _pumpBrowser(tester, db, LibraryLocation.subject(bookId));
    await _selectMenuAction(tester, 'library-item-menu-note-${note.id}', '重命名');
    await tester.enterText(find.byType(TextField), '新笔记名');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('新笔记名'), findsOneWidget);
    final renamedNote = (await notes.getById(note.id) as Success).value;
    expect(renamedNote?.title, '新笔记名');
    expect((await notes.listVersions(note.id) as Success).value, isEmpty);
  });

  testWidgets('展开模式移动书成功后立即刷新来源与目标目录', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folders = LocalFolderRepository(db);
    final subjects = LocalSubjectRepository(db);
    final folderId = (await folders.create(name: '资料') as Success).value;
    final bookId =
        (await subjects.create(name: '数学', level: 0, folderId: folderId)
                as Success)
            .value;

    await _pumpBrowser(
      tester,
      db,
      const LibraryLocation.root(),
      moveLauncher: (_, request) async {
        final result = await folders.moveBook(
          bookId: request.itemId,
          folderId: null,
          targetIndex: 0,
        );
        return result is Success<void>;
      },
    );
    await tester.tap(find.byTooltip('展开浏览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();
    expect(find.text('数学'), findsOneWidget);

    await _selectMenuAction(tester, 'library-item-menu-book-$bookId', '移动');

    expect(find.text('未归类书籍'), findsOneWidget);
    await tester.tap(find.text('未归类书籍'));
    await tester.pumpAndSettle();
    expect(find.text('数学'), findsOneWidget);
  });

  testWidgets('展开模式排序成功后根目录文件夹顺序立即变化', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folders = LocalFolderRepository(db);
    final firstId = (await folders.create(name: '资料 A') as Success).value;
    final secondId = (await folders.create(name: '资料 B') as Success).value;

    await _pumpBrowser(
      tester,
      db,
      const LibraryLocation.root(),
      reorderLauncher: (_, request) async {
        final result = await folders.reorderFolders(
          parentId: request.parentId,
          orderedIds: [secondId, firstId],
        );
        return result is Success<void>;
      },
    );
    await tester.tap(find.byTooltip('展开浏览'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('资料 A')).dy,
      lessThan(tester.getTopLeft(find.text('资料 B')).dy),
    );

    await _selectMenuAction(
      tester,
      'library-item-menu-folder-$firstId',
      '调整顺序',
    );

    expect(
      tester.getTopLeft(find.text('资料 B')).dy,
      lessThan(tester.getTopLeft(find.text('资料 A')).dy),
    );
  });
}

Future<void> _pumpBrowser(
  WidgetTester tester,
  AppDatabase db,
  LibraryLocation location, {
  Future<bool?> Function(BuildContext, LibraryMoveRequest)? moveLauncher,
  Future<bool?> Function(BuildContext, LibraryReorderRequest)? reorderLauncher,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: LibraryBrowserView(
          location: location,
          moveLauncher: moveLauncher,
          reorderLauncher: reorderLauncher,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectMenuAction(
  WidgetTester tester,
  String menuKey,
  String actionLabel,
) async {
  await tester.tap(find.byKey(ValueKey(menuKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(actionLabel));
  await tester.pumpAndSettle();
}
