// 文件: test/features/notes/note_editor_history_entry_test.dart
// 作用: 验证历史版本入口会保存未保存内容，且新笔记首次保存后立即可用。
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
import 'package:ruoke/src/features/notes/models/search_match_mode.dart';
import 'package:ruoke/src/features/notes/models/tag.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/note_repository.dart';
import 'package:ruoke/src/features/notes/repository/tag_repository.dart';
import 'package:ruoke/src/features/notes/view/note_editor_view.dart';

void main() {
  testWidgets('新笔记首次保存后立即显示历史版本入口', (tester) async {
    final repository = _FakeNoteRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteRepositoryProvider.overrideWithValue(repository),
          tagRepositoryProvider.overrideWithValue(_FakeTagRepository()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: [Locale('zh'), Locale('en', 'US')],
          home: NoteEditorView(noteId: 'new'),
        ),
      ),
    );
    await _waitForEditor(tester);

    await tester.enterText(find.byKey(const ValueKey('note-title')), '首次保存');
    await tester.tap(find.byTooltip('保存'));
    await _pumpFrames(tester);
    expect(find.byType(QuillEditor), findsOneWidget);
    await tester.tap(find.byTooltip('更多'));
    await _pumpFrames(tester);

    expect(find.text('历史版本'), findsOneWidget);
  });

  testWidgets('进入历史版本前会保存未保存的编辑内容', (tester) async {
    final repository = _FakeNoteRepository()
      ..note = _note(id: 'note-1', title: '旧标题');
    final router = GoRouter(
      initialLocation: '/notes/editor/note-1',
      routes: [
        GoRoute(
          path: '/notes/editor/:noteId',
          builder: (_, state) =>
              NoteEditorView(noteId: state.pathParameters['noteId']!),
        ),
        GoRoute(
          path: '/notes/editor/:noteId/versions',
          builder: (_, _) => const Scaffold(body: Text('版本页')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteRepositoryProvider.overrideWithValue(repository),
          tagRepositoryProvider.overrideWithValue(_FakeTagRepository()),
        ],
        child: MaterialApp.router(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en', 'US')],
          routerConfig: router,
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.enterText(find.byKey(const ValueKey('note-title')), '未保存标题');
    await tester.pump();
    await tester.tap(find.byTooltip('更多'));
    await _pumpFrames(tester);
    await tester.tap(find.text('历史版本'));
    await _pumpFrames(tester);

    expect(repository.updateCallCount, 1);
    expect(repository.lastUpdatedTitle, '未保存标题');
    expect(find.text('版本页'), findsOneWidget);
  });

  testWidgets('未保存内容保存失败时不会进入历史版本', (tester) async {
    final repository = _FakeNoteRepository()
      ..note = _note(id: 'note-1', title: '旧标题')
      ..failUpdate = true;
    final router = GoRouter(
      initialLocation: '/notes/editor/note-1',
      routes: [
        GoRoute(
          path: '/notes/editor/:noteId',
          builder: (_, state) =>
              NoteEditorView(noteId: state.pathParameters['noteId']!),
        ),
        GoRoute(
          path: '/notes/editor/:noteId/versions',
          builder: (_, _) => const Scaffold(body: Text('版本页')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteRepositoryProvider.overrideWithValue(repository),
          tagRepositoryProvider.overrideWithValue(_FakeTagRepository()),
        ],
        child: MaterialApp.router(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en', 'US')],
          routerConfig: router,
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.enterText(find.byKey(const ValueKey('note-title')), '无法保存的标题');
    await tester.pump();
    await tester.tap(find.byTooltip('更多'));
    await _pumpFrames(tester);
    await tester.tap(find.text('历史版本'));
    await _pumpFrames(tester);

    expect(repository.updateCallCount, 1);
    expect(find.text('版本页'), findsNothing);
    expect(find.text('保存失败，无法打开历史版本'), findsOneWidget);
  });

  testWidgets('恢复成功返回编辑器后会重新读取正文并显示提示', (tester) async {
    final repository = _FakeNoteRepository()
      ..note = _note(id: 'note-1', title: '当前标题');
    final router = GoRouter(
      initialLocation: '/notes/editor/note-1',
      routes: [
        GoRoute(
          path: '/notes/editor/:noteId',
          builder: (_, state) =>
              NoteEditorView(noteId: state.pathParameters['noteId']!),
        ),
        GoRoute(
          path: '/notes/editor/:noteId/versions',
          builder: (context, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  repository.note = _note(
                    id: 'note-1',
                    title: '恢复后标题',
                    contentJson: '[{"insert":"恢复后的正文\\n"}]',
                  );
                  context.pop(true);
                },
                child: const Text('模拟恢复成功'),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteRepositoryProvider.overrideWithValue(repository),
          tagRepositoryProvider.overrideWithValue(_FakeTagRepository()),
        ],
        child: MaterialApp.router(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en', 'US')],
          routerConfig: router,
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.byTooltip('更多'));
    await _pumpFrames(tester);
    await tester.tap(find.text('历史版本'));
    await _pumpFrames(tester);
    await tester.tap(find.text('模拟恢复成功'));
    await _pumpFrames(tester);

    expect(repository.getByIdCallCount, 2);
    expect(find.text('已恢复历史版本'), findsOneWidget);
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(editor.controller.document.toPlainText(), '恢复后的正文\n');
  });

  testWidgets('只修改标签时进入历史版本前会保存标签草稿', (tester) async {
    final repository = _FakeNoteRepository()
      ..note = _note(id: 'note-1', title: '标题');
    final router = GoRouter(
      initialLocation: '/notes/editor/note-1',
      routes: [
        GoRoute(
          path: '/notes/editor/:noteId',
          builder: (_, state) =>
              NoteEditorView(noteId: state.pathParameters['noteId']!),
        ),
        GoRoute(
          path: '/notes/editor/:noteId/versions',
          builder: (_, _) => const Scaffold(body: Text('版本页')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteRepositoryProvider.overrideWithValue(repository),
          tagRepositoryProvider.overrideWithValue(
            _FakeTagRepository(const ['旧标签']),
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en', 'US')],
          routerConfig: router,
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.enterText(
      find.byKey(const ValueKey('editor-tag-input')),
      '新标签',
    );
    await tester.tap(find.byTooltip('添加标签'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史版本'));
    await _pumpFrames(tester);

    expect(repository.updateCallCount, 1);
    expect(repository.lastUpdatedTagNames, const ['旧标签', '新标签']);
    expect(find.text('版本页'), findsOneWidget);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _waitForEditor(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    if (find.byType(QuillEditor).evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.byType(QuillEditor), findsOneWidget);
}

class _FakeNoteRepository implements NoteRepository {
  Note? note;
  int updateCallCount = 0;
  int getByIdCallCount = 0;
  String? lastUpdatedTitle;
  List<String>? lastUpdatedTagNames;
  bool failUpdate = false;

  @override
  Future<Result<Note>> create({
    required String subjectId,
    String? title,
    String? contentJson,
    String? plainText,
    bool isDraft = false,
    Iterable<String> tagNames = const [],
  }) async {
    note = _note(id: 'note-1', title: title, contentJson: contentJson);
    return Success(note!);
  }

  @override
  Future<Result<Note?>> getById(String id) async {
    getByIdCallCount++;
    return Success(note);
  }

  @override
  Future<Result<void>> update({
    required String id,
    String? title,
    String? contentJson,
    String? plainText,
    bool? isDraft,
    Iterable<String>? tagNames,
  }) async {
    updateCallCount++;
    if (failUpdate) {
      return const Failure(DatabaseException('模拟保存失败'));
    }
    lastUpdatedTitle = title;
    lastUpdatedTagNames = tagNames?.toList();
    note = _note(
      id: id,
      title: title ?? note?.title,
      contentJson: contentJson ?? note?.contentJson,
    );
    return const Success<void>(null);
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
  Future<Result<void>> renameVersion({
    required String noteId,
    required String versionId,
    required String? name,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> deleteVersions({
    required String noteId,
    required Set<String> versionIds,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> restoreVersion({
    required String noteId,
    required int versionNo,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> softDelete(String id) async => const Success<void>(null);
}

class _FakeTagRepository implements TagRepository {
  final List<String> names;

  _FakeTagRepository([this.names = const []]);

  @override
  Future<Result<List<Tag>>> listTagsForNote(String noteId) async => Success([
    for (var index = 0; index < names.length; index++)
      Tag(id: 'tag-$index', name: names[index], color: null, createdAt: 1),
  ]);

  @override
  Future<Result<List<Tag>>> attachTagsByNames({
    required String noteId,
    required Iterable<String> names,
  }) => throw UnimplementedError();

  @override
  Future<Result<Tag>> createTag({required String name, String? color}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> deleteTag(String id) => throw UnimplementedError();

  @override
  Future<Result<Tag>> findOrCreateAndAttachTag({
    required String noteId,
    required String tagName,
  }) => throw UnimplementedError();

  @override
  Future<Result<List<TagWithCount>>> listTags() async => const Success([]);

  @override
  Future<Result<void>> renameTag({required String id, required String name}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> replaceNoteTags({
    required String noteId,
    required List<String> tagIds,
  }) => throw UnimplementedError();

  @override
  Future<Result<List<Tag>>> searchTags({
    required String keyword,
    required SearchMatchMode matchMode,
  }) => throw UnimplementedError();
}

Note _note({String? id, String? title, String? contentJson}) => Note(
  id: id ?? 'note-1',
  subjectId: 'uncategorized',
  title: title,
  contentJson: contentJson ?? '[{"insert":"旧正文\\n"}]',
  plainText: '旧正文',
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
