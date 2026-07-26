// 编辑器标签展示、贴/撕及新建笔记保存顺序测试。
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
import 'package:ruoke/src/features/notes/models/tag.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/local_note_repository.dart';
import 'package:ruoke/src/features/notes/repository/local_tag_repository.dart';
import 'package:ruoke/src/features/notes/repository/tag_repository.dart';
import 'package:ruoke/src/features/notes/view/note_editor_view.dart';

void main() {
  testWidgets('已有笔记可在编辑器中贴上和撕下标签', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final notes = LocalNoteRepository(db);
    final tags = LocalTagRepository(db);
    final note = _successValue(
      await notes.create(subjectId: 'uncategorized', title: '已有笔记'),
    );
    final first = _successValue(await tags.createTag(name: '旧标签'));
    final second = _successValue(await tags.createTag(name: '新标签'));
    await tags.replaceNoteTags(noteId: note.id, tagIds: [first.id]);

    await _pumpEditor(tester, db, noteId: note.id);
    expect(find.text('旧标签'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑标签'));
    await _pumpUntilText(tester, '选择标签');
    await tester.tap(find.widgetWithText(CheckboxListTile, '旧标签'));
    await tester.tap(find.widgetWithText(CheckboxListTile, '新标签'));
    await tester.tap(find.widgetWithText(FilledButton, '保存标签'));
    await tester.pumpAndSettle();

    final savedTags = _successValue(await tags.listTagsForNote(note.id));
    expect(savedTags.map((tag) => tag.id), [second.id]);
    expect(find.text('旧标签'), findsNothing);
    expect(find.text('新标签'), findsOneWidget);
  });

  testWidgets('新建有效笔记会先保存真实 noteId 再贴标签', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tags = LocalTagRepository(db);
    final tag = _successValue(await tags.createTag(name: '待复习'));

    await _pumpEditor(tester, db, noteId: 'new');
    await tester.enterText(find.byType(TextField), '新建后贴标签');
    await tester.tap(find.byTooltip('编辑标签'));
    await _pumpUntilText(tester, '选择标签');
    await tester.tap(find.widgetWithText(CheckboxListTile, '待复习'));
    await tester.tap(find.widgetWithText(FilledButton, '保存标签'));
    await tester.pumpAndSettle();

    final createdNotes = _successValue(await LocalNoteRepository(db).listAll());
    expect(createdNotes, hasLength(1));
    final savedTags = _successValue(
      await tags.listTagsForNote(createdNotes.single.id),
    );
    expect(savedTags.single.id, tag.id);
  });

  testWidgets('空新笔记点击标签不会创建数据库记录', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await LocalTagRepository(db).createTag(name: '不会贴上');

    await _pumpEditor(tester, db, noteId: 'new');
    await tester.tap(find.byTooltip('编辑标签'));
    await _pumpUntilText(tester, '空笔记不能添加标签');

    expect(find.text('空笔记不能添加标签'), findsOneWidget);
    final notes = _successValue(await LocalNoteRepository(db).listAll());
    expect(notes, isEmpty);
    expect(find.text('选择标签'), findsNothing);
  });

  testWidgets('标签列表加载失败会显示错误而不是抛出异常', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final note = _successValue(
      await LocalNoteRepository(
        db,
      ).create(subjectId: 'uncategorized', title: '加载失败'),
    );
    final tags = _FakeTagRepository(failList: true);

    await _pumpEditor(tester, db, noteId: note.id, tagRepository: tags);
    await tester.tap(find.byTooltip('编辑标签'));
    final errorText = await _pumpUntilErrorText(tester);

    expect(errorText, '模拟加载标签失败');
    expect(find.text('选择标签'), findsNothing);
  });

  testWidgets('切换编辑会话后旧标签加载结果不会打开对话框', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final notes = LocalNoteRepository(db);
    final first = _successValue(
      await notes.create(subjectId: 'uncategorized', title: '第一条'),
    );
    final second = _successValue(
      await notes.create(subjectId: 'uncategorized', title: '第二条'),
    );
    final loadGate = Completer<void>();
    final tags = _FakeTagRepository(listGate: loadGate);

    await _pumpEditor(tester, db, noteId: first.id, tagRepository: tags);
    await tester.tap(find.byTooltip('编辑标签'));
    await tester.pump();

    await _pumpEditor(tester, db, noteId: second.id, tagRepository: tags);
    loadGate.complete();
    await tester.pumpAndSettle();

    expect(find.text('选择标签'), findsNothing);
  });

  testWidgets('保存标签期间编辑入口禁用以避免并发覆盖', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final note = _successValue(
      await LocalNoteRepository(
        db,
      ).create(subjectId: 'uncategorized', title: '并发保护'),
    );
    final saveGate = Completer<void>();
    final tags = _FakeTagRepository(
      tags: [_tagWithCount('tag-1', '待保存')],
      replaceGate: saveGate,
    );

    await _pumpEditor(tester, db, noteId: note.id, tagRepository: tags);
    await tester.tap(find.byTooltip('编辑标签'));
    await _pumpUntilText(tester, '选择标签');
    await tester.tap(find.widgetWithText(CheckboxListTile, '待保存'));
    await tester.tap(find.widgetWithText(FilledButton, '保存标签'));
    await tester.pump();

    final editButtonFinder = find.widgetWithIcon(
      IconButton,
      Icons.label_outline,
    );
    final editButton = tester.widget<IconButton>(editButtonFinder);
    expect(editButton.onPressed, isNull);

    saveGate.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(editButtonFinder).onPressed, isNotNull);
  });

  testWidgets('一次打开标签对话框只查询一次标签列表和笔记标签', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final note = _successValue(
      await LocalNoteRepository(
        db,
      ).create(subjectId: 'uncategorized', title: '单次查询'),
    );
    final tags = _FakeTagRepository(tags: [_tagWithCount('tag-1', '单次查询标签')]);

    await _pumpEditor(tester, db, noteId: note.id, tagRepository: tags);
    await tester.tap(find.byTooltip('编辑标签'));
    await _pumpUntilText(tester, '选择标签');

    expect(tags.listTagsCallCount, 1);
    expect(tags.listNoteTagsCallCount, 1);
  });

  testWidgets('保存标签失败后可保留旧状态并立即重新打开对话框', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final note = _successValue(
      await LocalNoteRepository(
        db,
      ).create(subjectId: 'uncategorized', title: '失败重试'),
    );
    final tags = _FakeTagRepository(
      tags: [_tagWithCount('tag-1', '可重试标签')],
      replaceFailuresRemaining: 1,
    );

    await _pumpEditor(tester, db, noteId: note.id, tagRepository: tags);
    await tester.tap(find.byTooltip('编辑标签'));
    await _pumpUntilText(tester, '选择标签');
    await tester.tap(find.widgetWithText(CheckboxListTile, '可重试标签'));
    await tester.tap(find.widgetWithText(FilledButton, '保存标签'));
    expect(await _pumpUntilErrorText(tester), '模拟保存标签失败');

    await tester.tap(find.byTooltip('编辑标签'));
    await _pumpUntilText(tester, '选择标签');
    expect(find.text('可重试标签'), findsOneWidget);
  });

  testWidgets('全部标签首次加载失败后再次点击会重新加载', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final note = _successValue(
      await LocalNoteRepository(
        db,
      ).create(subjectId: 'uncategorized', title: '列表重试'),
    );
    final tags = _FakeTagRepository(
      tags: [_tagWithCount('tag-1', '恢复标签')],
      listFailuresRemaining: 1,
    );

    await _pumpEditor(tester, db, noteId: note.id, tagRepository: tags);
    await tester.tap(find.byTooltip('编辑标签'));
    await _pumpUntilText(tester, '模拟加载标签失败');

    await tester.tap(find.byTooltip('编辑标签'));
    await _pumpUntilText(tester, '选择标签');
    expect(tags.listTagsCallCount, 2);
  });

  testWidgets('笔记标签首次加载失败后再次点击会重新加载', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final note = _successValue(
      await LocalNoteRepository(
        db,
      ).create(subjectId: 'uncategorized', title: '笔记标签重试'),
    );
    final tags = _FakeTagRepository(
      tags: [_tagWithCount('tag-1', '恢复笔记标签')],
      listNoteFailuresRemaining: 1,
    );

    await _pumpEditor(tester, db, noteId: note.id, tagRepository: tags);
    expect(find.text('标签加载失败'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑标签'));
    await _pumpUntilText(tester, '选择标签');
    expect(tags.listNoteTagsCallCount, 2);
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
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en', 'US')],
        home: NoteEditorView(noteId: noteId),
      ),
    ),
  );
  for (var frame = 0; frame < 20; frame++) {
    if (find.byTooltip('编辑标签').evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.byTooltip('编辑标签'), findsOneWidget);
}

Future<String?> _pumpUntilErrorText(WidgetTester tester) async {
  for (var frame = 0; frame < 30; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>();
    for (final text in texts) {
      if (text.contains('失败')) return text;
    }
  }
  return null;
}

Future<void> _pumpUntilText(WidgetTester tester, String text) async {
  for (var frame = 0; frame < 30; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text(text).evaluate().isNotEmpty) return;
  }
  expect(
    find.text(text),
    findsOneWidget,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .join(' | '),
  );
}

T _successValue<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}

class _FakeTagRepository implements TagRepository {
  final bool failList;
  final Completer<void>? listGate;
  final Completer<void>? replaceGate;
  final List<TagWithCount> tags;
  int listFailuresRemaining;
  int listNoteFailuresRemaining;
  int replaceFailuresRemaining;
  final Map<String, List<Tag>> noteTags = {};
  int listTagsCallCount = 0;
  int listNoteTagsCallCount = 0;

  _FakeTagRepository({
    this.failList = false,
    this.listGate,
    this.replaceGate,
    this.tags = const [],
    this.listFailuresRemaining = 0,
    this.listNoteFailuresRemaining = 0,
    this.replaceFailuresRemaining = 0,
  });

  @override
  Future<Result<List<TagWithCount>>> listTags() async {
    listTagsCallCount++;
    await listGate?.future;
    if (failList || listFailuresRemaining > 0) {
      if (listFailuresRemaining > 0) listFailuresRemaining--;
      return const Failure(DatabaseException('模拟加载标签失败'));
    }
    return Success(List.of(tags));
  }

  @override
  Future<Result<List<Tag>>> listTagsForNote(String noteId) async {
    listNoteTagsCallCount++;
    if (listNoteFailuresRemaining > 0) {
      listNoteFailuresRemaining--;
      return const Failure(DatabaseException('模拟加载笔记标签失败'));
    }
    return Success(List.of(noteTags[noteId] ?? const []));
  }

  @override
  Future<Result<void>> replaceNoteTags({
    required String noteId,
    required List<String> tagIds,
  }) async {
    await replaceGate?.future;
    if (replaceFailuresRemaining > 0) {
      replaceFailuresRemaining--;
      return const Failure(DatabaseException('模拟保存标签失败'));
    }
    noteTags[noteId] = [
      for (final id in tagIds) tags.firstWhere((tag) => tag.id == id),
    ];
    return const Success<void>(null);
  }

  @override
  Future<Result<Tag>> createTag({required String name, String? color}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> deleteTag(String id) => throw UnimplementedError();

  @override
  Future<Result<void>> renameTag({required String id, required String name}) =>
      throw UnimplementedError();
}

TagWithCount _tagWithCount(String id, String name) =>
    TagWithCount(id: id, name: name, color: null, createdAt: 1, noteCount: 0);
