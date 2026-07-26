// 文件: test/features/notes/note_editor_stability_test.dart
// 作用: 验证空新笔记规则、保存提示和编辑器退出交互。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/note.dart';
import 'package:ruoke/src/features/notes/models/note_search_query.dart';
import 'package:ruoke/src/features/notes/models/note_version.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/note_repository.dart';
import 'package:ruoke/src/features/notes/view/note_editor_view.dart';

void main() {
  testWidgets('完全空白的新笔记点击保存时不创建并给出提示', (tester) async {
    final repository = _StabilityRepository();
    await _pumpEditor(tester, repository);

    await tester.tap(find.byTooltip('保存'));
    await _pumpFrames(tester);

    expect(repository.createCallCount, 0);
    expect(find.text('空笔记不会保存'), findsOneWidget);
  });

  testWidgets('新笔记只有标题时可以保存', (tester) async {
    final repository = _StabilityRepository();
    await _pumpEditor(tester, repository);

    await tester.enterText(find.byType(TextField), '只有标题');
    await tester.tap(find.byTooltip('保存'));
    await _pumpFrames(tester);

    expect(repository.createCallCount, 1);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('新笔记只有正文时可以保存', (tester) async {
    final repository = _StabilityRepository();
    await _pumpEditor(tester, repository);

    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    editor.controller.replaceText(
      0,
      0,
      '只有正文',
      const TextSelection.collapsed(offset: 4),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('保存'));
    await _pumpFrames(tester);

    expect(repository.createCallCount, 1);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('空白新笔记选择保存并离开时退出但不创建', (tester) async {
    final repository = _StabilityRepository();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.push('/editor'),
                child: const Text('打开编辑器'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/editor',
          builder: (_, _) => const NoteEditorView(noteId: 'new'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: _LocalizedRouterApp(router: router),
      ),
    );
    await tester.tap(find.text('打开编辑器'));
    await _waitForEditor(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await _pumpFrames(tester);
    await tester.tap(find.text('保存并离开'));
    await _pumpFrames(tester);

    expect(repository.createCallCount, 0);
    expect(find.text('打开编辑器'), findsOneWidget);
  });

  testWidgets('旧笔记页面复用为新建路由时会清空标题和正文', (tester) async {
    final repository = _StabilityRepository()
      ..noteToLoad = _note(
        id: 'old-note',
        title: '上一条标题',
        contentJson: '[{"insert":"上一条正文\\n"}]',
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: const _LocalizedApp(home: NoteEditorView(noteId: 'old-note')),
      ),
    );
    await _waitForEditor(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '上一条标题',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: const _LocalizedApp(home: NoteEditorView(noteId: 'new')),
      ),
    );
    await _pumpFrames(tester);

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(editor.controller.document.toPlainText().trim(), isEmpty);
  });

  testWidgets('首次读取已有笔记失败时显示错误而不是永久转圈', (tester) async {
    final repository = _StabilityRepository()..failGet = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: const _LocalizedApp(
          home: NoteEditorView(noteId: 'missing-note'),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.textContaining('加载失败'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('已有笔记尚未加载完成时保存按钮不可点击', (tester) async {
    final repository = _StabilityRepository()
      ..delayedGet = Completer<Result<Note?>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: const _LocalizedApp(
          home: NoteEditorView(noteId: 'delayed-note'),
        ),
      ),
    );
    await _pumpFrames(tester);

    final saveButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.save_outlined),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('已有笔记读取失败后保存按钮不可点击', (tester) async {
    final repository = _StabilityRepository()..failGet = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: const _LocalizedApp(
          home: NoteEditorView(noteId: 'missing-note'),
        ),
      ),
    );
    await _pumpFrames(tester);

    final saveButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.save_outlined),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('首次创建保存进行中按钮禁用且完成后恢复', (tester) async {
    final repository = _StabilityRepository()
      ..delayedCreate = Completer<Result<Note>>();
    await _pumpEditor(tester, repository);
    await tester.enterText(find.byType(TextField), '等待创建');

    await tester.tap(find.byTooltip('保存'));
    await tester.pump();

    var saveButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.save_outlined),
    );
    expect(saveButton.onPressed, isNull);
    expect(repository.createCallCount, 1);

    repository.delayedCreate!.complete(
      Success(_note(id: 'created-note', title: '等待创建')),
    );
    await _pumpFrames(tester);

    saveButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.save_outlined),
    );
    expect(saveButton.onPressed, isNotNull);
    expect(repository.createCallCount, 1);
  });

  testWidgets('同一 ProviderScope 下反复退出旧笔记再新建不会残留内容', (tester) async {
    final repository = _StabilityRepository()
      ..noteToLoad = _note(
        id: 'old-note',
        title: '旧笔记标题',
        contentJson: '[{"insert":"旧笔记正文\\n"}]',
      );
    final router = _buildSessionRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: _LocalizedRouterApp(router: router),
      ),
    );

    for (var round = 0; round < 2; round++) {
      await tester.tap(find.text('打开旧笔记'));
      await _waitForEditor(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '旧笔记标题',
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await _pumpFrames(tester);
      await tester.tap(find.text('新建笔记'));
      await _waitForEditor(tester);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
      final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
      expect(editor.controller.document.toPlainText().trim(), isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await _pumpFrames(tester);
    }
  });

  testWidgets('退出加载中的旧笔记后新建不受旧读取延迟返回影响', (tester) async {
    final repository = _StabilityRepository()
      ..delayedGet = Completer<Result<Note?>>();
    final router = _buildSessionRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: _LocalizedRouterApp(router: router),
      ),
    );

    await tester.tap(find.text('打开旧笔记'));
    await _pumpFrames(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await _pumpFrames(tester);
    await tester.tap(find.text('新建笔记'));
    await _waitForEditor(tester);

    repository.delayedGet!.complete(
      Success(
        _note(
          id: 'old-note',
          title: '延迟旧标题',
          contentJson: '[{"insert":"延迟旧正文\\n"}]',
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(editor.controller.document.toPlainText().trim(), isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

GoRouter _buildSessionRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Column(
            children: [
              FilledButton(
                onPressed: () => context.push('/editor/old-note'),
                child: const Text('打开旧笔记'),
              ),
              FilledButton(
                onPressed: () => context.push('/editor/new'),
                child: const Text('新建笔记'),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/editor/:noteId',
        builder: (_, state) =>
            NoteEditorView(noteId: state.pathParameters['noteId']!),
      ),
    ],
  );
}

Future<void> _pumpEditor(
  WidgetTester tester,
  _StabilityRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
      child: const _LocalizedApp(home: NoteEditorView(noteId: 'new')),
    ),
  );
  await _waitForEditor(tester);
}

Future<void> _waitForEditor(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    if (find.byType(QuillEditor).evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.byType(QuillEditor), findsOneWidget);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _LocalizedApp extends StatelessWidget {
  final Widget home;

  const _LocalizedApp({required this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en', 'US')],
      home: home,
    );
  }
}

class _LocalizedRouterApp extends StatelessWidget {
  final GoRouter router;

  const _LocalizedRouterApp({required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en', 'US')],
      routerConfig: router,
    );
  }
}

class _StabilityRepository implements NoteRepository {
  int createCallCount = 0;
  int updateCallCount = 0;
  Note? noteToLoad;
  bool failGet = false;
  Completer<Result<Note?>>? delayedGet;
  Completer<Result<Note>>? delayedCreate;

  @override
  Future<Result<Note>> create({
    required String subjectId,
    String? title,
    String? contentJson,
    String? plainText,
    bool isDraft = false,
  }) async {
    createCallCount++;
    if (delayedCreate case final pending?) {
      return pending.future;
    }
    return Success(
      Note(
        id: 'created-note',
        subjectId: subjectId,
        title: title,
        contentJson: contentJson,
        plainText: plainText ?? '',
        isDraft: isDraft,
        isAiHidden: false,
        sourceType: null,
        sourceRef: null,
        lastReadAt: null,
        createdAt: 1,
        updatedAt: 1,
        isDeleted: false,
        deletedAt: null,
      ),
    );
  }

  @override
  Future<Result<void>> update({
    required String id,
    String? title,
    String? contentJson,
    String? plainText,
    bool? isDraft,
  }) async {
    updateCallCount++;
    return const Success<void>(null);
  }

  @override
  Future<Result<Note?>> getById(String id) async {
    if (delayedGet case final pending?) {
      return pending.future;
    }
    if (failGet) {
      return const Failure(DatabaseException('模拟读取失败'));
    }
    return Success(noteToLoad);
  }

  @override
  Future<Result<List<Note>>> listAll() async => const Success([]);

  @override
  Future<Result<List<Note>>> search(NoteSearchQuery query) async =>
      const Success([]);

  @override
  Future<Result<List<NoteVersion>>> listVersions(String noteId) async =>
      const Success([]);

  @override
  Future<Result<void>> restoreVersion({
    required String noteId,
    required int versionNo,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> softDelete(String id) async => const Success<void>(null);
}

Note _note({required String id, String? title, String? contentJson}) => Note(
  id: id,
  subjectId: 'subject-1',
  title: title,
  contentJson: contentJson,
  plainText: '',
  isDraft: false,
  isAiHidden: false,
  sourceType: null,
  sourceRef: null,
  lastReadAt: null,
  createdAt: 1,
  updatedAt: 1,
  isDeleted: false,
  deletedAt: null,
);
