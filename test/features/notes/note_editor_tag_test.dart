// 编辑器自由标签、自动补全、新笔记待保存和失败重试测试。
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/search_match_mode.dart';
import 'package:ruoke/src/features/notes/models/tag.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/local_note_repository.dart';
import 'package:ruoke/src/features/notes/repository/local_tag_repository.dart';
import 'package:ruoke/src/features/notes/repository/tag_repository.dart';
import 'package:ruoke/src/features/notes/view/note_editor_view.dart';

void main() {
  testWidgets('已有笔记可自由创建标签并移除原标签', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final notes = LocalNoteRepository(db);
    final tags = LocalTagRepository(db);
    final note = _successValue(
      await notes.create(subjectId: 'uncategorized', title: '已有笔记'),
    );
    final old = _successValue(await tags.createTag(name: '旧标签'));
    await tags.replaceNoteTags(noteId: note.id, tagIds: [old.id]);

    await _pumpEditor(tester, db, noteId: note.id);
    await _addTag(tester, '新标签');

    var saved = _successValue(await tags.listTagsForNote(note.id));
    expect(saved.map((tag) => tag.name).toSet(), {'旧标签', '新标签'});
    expect(find.text('新标签'), findsOneWidget);

    await tester.tap(find.byTooltip('移除标签 旧标签'));
    await tester.pumpAndSettle();
    saved = _successValue(await tags.listTagsForNote(note.id));
    expect(saved.map((tag) => tag.name), ['新标签']);
  });

  testWidgets('输入时可从建议复用已有标签而不创建重名', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final notes = LocalNoteRepository(db);
    final tags = LocalTagRepository(db);
    final note = _successValue(
      await notes.create(subjectId: 'uncategorized', title: '自动补全'),
    );
    final existing = _successValue(await tags.createTag(name: '复习'));

    await _pumpEditor(tester, db, noteId: note.id);
    await tester.enterText(find.byKey(const ValueKey('editor-tag-input')), '复');
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, '复习'));
    await tester.pumpAndSettle();

    final allTags = _successValue(await tags.listTags());
    final attached = _successValue(await tags.listTagsForNote(note.id));
    expect(allTags, hasLength(1));
    expect(attached.single.id, existing.id);
  });

  testWidgets('新笔记标签先保留为待保存并在正文保存后绑定', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tags = LocalTagRepository(db);
    final notes = LocalNoteRepository(db);

    await _pumpEditor(tester, db, noteId: 'new');
    await tester.enterText(find.byKey(const ValueKey('note-title')), '带标签的新笔记');
    await _addTag(tester, '待复习');

    expect(_successValue(await notes.listAll()), isEmpty);
    expect(_successValue(await tags.listTags()), isEmpty);
    expect(find.text('待复习'), findsOneWidget);

    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    final created = _successValue(await notes.listAll()).single;
    final attached = _successValue(await tags.listTagsForNote(created.id));
    expect(attached.single.name, '待复习');
  });

  testWidgets('空新笔记输入标签后保存不创建笔记标签或关联', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tags = LocalTagRepository(db);
    final notes = LocalNoteRepository(db);

    await _pumpEditor(tester, db, noteId: 'new');
    await _addTag(tester, '不应持久化');
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    expect(_successValue(await notes.listAll()), isEmpty);
    expect(_successValue(await tags.listTags()), isEmpty);
    expect(find.text('空笔记不会保存'), findsOneWidget);
  });

  testWidgets('正文保存成功但标签绑定失败时保留待保存标签', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final notes = LocalNoteRepository(db);
    final tags = _FailingAttachTagRepository();

    await _pumpEditor(tester, db, noteId: 'new', tagRepository: tags);
    await tester.enterText(find.byKey(const ValueKey('note-title')), '正文会保存');
    await _addTag(tester, '稍后重试');
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    expect(_successValue(await notes.listAll()), hasLength(1));
    expect(find.text('稍后重试'), findsOneWidget);
    expect(find.text('笔记已保存，但标签保存失败'), findsWidgets);
    expect(find.text('已保存'), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('未保存的改动'), findsOneWidget);
  });

  testWidgets('新笔记标签绑定未结束时禁用保存以防重复提交', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final gate = Completer<void>();
    final tags = _DelayedAttachTagRepository(gate);

    await _pumpEditor(tester, db, noteId: 'new', tagRepository: tags);
    await tester.enterText(find.byKey(const ValueKey('note-title')), '防止重复绑定');
    await _addTag(tester, '只绑定一次');
    await tester.tap(find.byTooltip('保存'));
    await _pumpUntil(() => tags.attachCallCount == 1, tester);

    final saveButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.save_outlined),
    );
    expect(saveButton.onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(tags.attachCallCount, 1);
  });

  testWidgets('切换编辑会话会清除上一条新笔记的待保存标签', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final second = _successValue(
      await LocalNoteRepository(
        db,
      ).create(subjectId: 'uncategorized', title: '第二条'),
    );
    final noteId = ValueNotifier<String>('new');
    addTearDown(noteId.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: _localizedApp(
          ValueListenableBuilder<String>(
            valueListenable: noteId,
            builder: (_, value, _) => NoteEditorView(noteId: value),
          ),
        ),
      ),
    );
    await _waitForEditor(tester);
    await _addTag(tester, '只属于第一会话');
    expect(find.text('只属于第一会话'), findsOneWidget);

    noteId.value = second.id;
    await tester.pumpAndSettle();
    await _waitForEditor(tester);
    expect(find.text('只属于第一会话'), findsNothing);
  });

  testWidgets('自动补全目录失败时保留输入并允许重试', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tags = _FailingCatalogTagRepository();

    await _pumpEditor(tester, db, noteId: 'new', tagRepository: tags);
    await tester.enterText(
      find.byKey(const ValueKey('editor-tag-input')),
      '保留输入',
    );
    await tester.pumpAndSettle();

    expect(find.text('标签建议加载失败'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '重试建议'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('editor-tag-input')))
          .controller
          ?.text,
      '保留输入',
    );
    await tester.tap(find.widgetWithText(TextButton, '重试建议'));
    await tester.pumpAndSettle();
    expect(tags.listCallCount, 2);
  });

  testWidgets('标签绑定失败后打开历史会重试并阻止跳转', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tags = _FailingAttachTagRepository();

    await _pumpEditor(tester, db, noteId: 'new', tagRepository: tags);
    await tester.enterText(find.byKey(const ValueKey('note-title')), '保留待保存标签');
    await _addTag(tester, '不能被历史清空');
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史版本'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('editor-tag-input')), findsOneWidget);
    expect(find.text('不能被历史清空'), findsOneWidget);
    expect(find.text('笔记已保存，但标签保存失败'), findsWidgets);
  });
}

Future<void> _pumpEditor(
  WidgetTester tester,
  AppDatabase db, {
  required String noteId,
  TagRepository? tagRepository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        if (tagRepository != null)
          tagRepositoryProvider.overrideWithValue(tagRepository),
      ],
      child: _localizedApp(NoteEditorView(noteId: noteId)),
    ),
  );
  await _waitForEditor(tester);
}

Widget _localizedApp(Widget home) => MaterialApp(
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    FlutterQuillLocalizations.delegate,
  ],
  supportedLocales: const [Locale('zh'), Locale('en', 'US')],
  home: home,
);

Future<void> _waitForEditor(WidgetTester tester) async {
  for (var frame = 0; frame < 30; frame++) {
    if (find.byKey(const ValueKey('editor-tag-input')).evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.byKey(const ValueKey('editor-tag-input')), findsOneWidget);
}

Future<void> _addTag(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const ValueKey('editor-tag-input')), name);
  await tester.tap(find.byTooltip('添加标签'));
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(bool Function() condition, WidgetTester tester) async {
  for (var frame = 0; frame < 30; frame++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue);
}

T _successValue<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}

class _FailingAttachTagRepository implements TagRepository {
  @override
  Future<Result<List<TagWithCount>>> listTags() async => const Success([]);

  @override
  Future<Result<List<Tag>>> listTagsForNote(String noteId) async =>
      const Success([]);

  @override
  Future<Result<List<Tag>>> attachTagsByNames({
    required String noteId,
    required Iterable<String> names,
  }) async => const Failure(DatabaseException('模拟批量绑定失败'));

  @override
  Future<Result<List<Tag>>> searchTags({
    required String keyword,
    required SearchMatchMode matchMode,
  }) => throw UnimplementedError();

  @override
  Future<Result<Tag>> findOrCreateAndAttachTag({
    required String noteId,
    required String tagName,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> replaceNoteTags({
    required String noteId,
    required List<String> tagIds,
  }) => throw UnimplementedError();

  @override
  Future<Result<Tag>> createTag({required String name, String? color}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> deleteTag(String id) => throw UnimplementedError();

  @override
  Future<Result<void>> renameTag({required String id, required String name}) =>
      throw UnimplementedError();
}

class _DelayedAttachTagRepository extends _FailingAttachTagRepository {
  final Completer<void> gate;
  int attachCallCount = 0;

  _DelayedAttachTagRepository(this.gate);

  @override
  Future<Result<List<Tag>>> attachTagsByNames({
    required String noteId,
    required Iterable<String> names,
  }) async {
    attachCallCount++;
    await gate.future;
    return const Success([]);
  }
}

class _FailingCatalogTagRepository extends _FailingAttachTagRepository {
  int listCallCount = 0;

  @override
  Future<Result<List<TagWithCount>>> listTags() async {
    listCallCount++;
    return const Failure(DatabaseException('模拟标签建议加载失败'));
  }
}
