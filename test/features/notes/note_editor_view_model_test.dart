// 文件: test/features/notes/note_editor_view_model_test.dart
// 作用: 验证编辑器初始化状态不会被 Provider 的初始构建结果覆盖。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/note.dart';
import 'package:ruoke/src/features/notes/models/note_search_query.dart';
import 'package:ruoke/src/features/notes/models/note_version.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/note_repository.dart';
import 'package:ruoke/src/features/notes/view_model/note_editor_view_model.dart';
import 'package:ruoke/src/features/notes/view_model/view_model_providers.dart';

void main() {
  test('新建笔记初始化后仍保持就绪状态', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('new', subjectId: 'subject-1');
    await Future<void>.delayed(Duration.zero);

    final state = container.read(noteEditorVmProvider).value;
    expect(state?.ready, isTrue);
    expect(state?.isNew, isTrue);
    expect(state?.subjectId, 'subject-1');
  });

  test('首次创建成功后编辑器立即持有真实笔记并可继续更新', () async {
    final repository = _CreateReturnsNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('new', subjectId: 'subject-1');

    final firstSaved = await notifier.save(
      title: '第一版',
      contentJson: '[{"insert":"第一版\\n"}]',
      hasVisibleContent: true,
    );
    final firstState = container.read(noteEditorVmProvider).value;

    expect(firstSaved, NoteSaveResult.saved);
    expect(firstState?.note?.id, 'created-note');
    expect(firstState?.isNew, isFalse);

    final secondSaved = await notifier.save(
      title: '第二版',
      contentJson: '[{"insert":"第二版\\n"}]',
      hasVisibleContent: true,
    );
    expect(secondSaved, NoteSaveResult.saved);
    expect(repository.createCallCount, 1);
    expect(repository.updateCallCount, 1);
  });

  test('完全空白的新笔记跳过创建', () async {
    final repository = _CreateReturnsNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('new');

    final result = await notifier.save(
      title: null,
      contentJson: '[{"insert":"\\n"}]',
      hasVisibleContent: false,
    );

    expect(result, NoteSaveResult.skippedEmpty);
    expect(repository.createCallCount, 0);
  });

  test('新笔记只有标题时可以创建', () async {
    final repository = _CreateReturnsNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('new');

    final result = await notifier.save(
      title: '只有标题',
      contentJson: '[{"insert":"\\n"}]',
      hasVisibleContent: false,
    );

    expect(result, NoteSaveResult.saved);
    expect(repository.createCallCount, 1);
  });

  test('新笔记只有正文时可以创建', () async {
    final repository = _CreateReturnsNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('new');

    final result = await notifier.save(
      title: null,
      contentJson: '[{"insert":"只有正文\\n"}]',
      hasVisibleContent: true,
    );

    expect(result, NoteSaveResult.saved);
    expect(repository.createCallCount, 1);
  });

  test('已有笔记被清空时仍执行更新', () async {
    final repository = _CreateReturnsNoteRepository()
      ..noteToLoad = _note(id: 'existing-note', title: '原标题');
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('existing-note');

    final result = await notifier.save(
      title: null,
      contentJson: '[{"insert":"\\n"}]',
      hasVisibleContent: false,
    );

    expect(result, NoteSaveResult.saved);
    expect(repository.updateCallCount, 1);
  });

  test('较慢的旧笔记读取不会覆盖随后完成的新建会话', () async {
    final repository = _DelayedLoadRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    final oldInit = notifier.init('old-note');
    await Future<void>.delayed(Duration.zero);
    await notifier.init('new', subjectId: 'subject-new');
    repository.completeOldLoad();
    await oldInit;

    final state = container.read(noteEditorVmProvider).value;
    expect(state?.ready, isTrue);
    expect(state?.isNew, isTrue);
    expect(state?.subjectId, 'subject-new');
    expect(state?.note, isNull);
  });

  test('较慢的旧新建保存完成后不会覆盖新的编辑器会话', () async {
    final repository = _DelayedCreateRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('new', subjectId: 'subject-old');
    final oldSave = notifier.save(
      title: '旧会话标题',
      contentJson: '[{"insert":"旧会话正文\\n"}]',
      hasVisibleContent: true,
    );
    await Future<void>.delayed(Duration.zero);

    await notifier.init('new', subjectId: 'subject-new');
    repository.completeCreate();
    expect(await oldSave, NoteSaveResult.saved);

    final state = container.read(noteEditorVmProvider).value;
    expect(state?.ready, isTrue);
    expect(state?.isNew, isTrue);
    expect(state?.subjectId, 'subject-new');
    expect(state?.note, isNull);
  });

  test('较慢的旧更新保存完成后不会覆盖随后加载的新笔记', () async {
    final repository = _DelayedUpdateRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('note-a');
    final oldSave = notifier.save(
      title: 'A 的新标题',
      contentJson: '[{"insert":"A 的新正文\\n"}]',
      hasVisibleContent: true,
    );
    await Future<void>.delayed(Duration.zero);

    await notifier.init('note-b');
    repository.completeUpdate();
    expect(await oldSave, NoteSaveResult.saved);

    final state = container.read(noteEditorVmProvider).value;
    expect(state?.ready, isTrue);
    expect(state?.note?.id, 'note-b');
    expect(state?.note?.title, '标题 note-b');
  });

  test('更新保存期间继续编辑时返回后仍保留未保存标记', () async {
    final repository = _DelayedUpdateRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('note-a');
    notifier.markDirty();
    final save = notifier.save(
      title: '已提交标题',
      contentJson: '[{"insert":"已提交正文\\n"}]',
      hasVisibleContent: true,
    );
    await Future<void>.delayed(Duration.zero);

    notifier.markDirty();
    repository.completeUpdate();
    expect(await save, NoteSaveResult.saved);
    expect(container.read(noteEditorVmProvider).value?.dirty, isTrue);
  });

  test('首次创建尚未完成时重复保存只发起一次创建', () async {
    final repository = _DelayedCreateRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('new');
    notifier.markDirty();
    final firstSave = notifier.save(
      title: '首次标题',
      contentJson: '[{"insert":"首次正文\\n"}]',
      hasVisibleContent: true,
    );
    await Future<void>.delayed(Duration.zero);

    final secondSave = notifier.save(
      title: '重复标题',
      contentJson: '[{"insert":"重复正文\\n"}]',
      hasVisibleContent: true,
    );
    expect(repository.createCallCount, 1);

    repository.completeCreate();
    expect(await firstSave, NoteSaveResult.saved);
    expect(await secondSave, NoteSaveResult.failed);
    expect(repository.createCallCount, 1);
  });
}

class _CreateReturnsNoteRepository implements NoteRepository {
  int createCallCount = 0;
  int updateCallCount = 0;
  Note? noteToLoad;

  @override
  Future<Result<Note>> create({
    required String subjectId,
    String? title,
    String? contentJson,
    String? plainText,
    bool isDraft = false,
    Iterable<String> tagNames = const [],
  }) async {
    createCallCount++;
    return Success(
      _note(id: 'created-note', title: title, contentJson: contentJson),
    );
  }

  @override
  Future<Result<Note?>> getById(String id) async => Success(noteToLoad);

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
  Future<Result<void>> restoreVersion({
    required String noteId,
    required int versionNo,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> softDelete(String id) async => const Success<void>(null);
}

class _DelayedLoadRepository extends _CreateReturnsNoteRepository {
  final _oldLoad = Completer<Result<Note?>>();

  @override
  Future<Result<Note?>> getById(String id) => _oldLoad.future;

  void completeOldLoad() {
    _oldLoad.complete(Success(_note(id: 'old-note', title: '旧标题')));
  }
}

class _DelayedCreateRepository extends _CreateReturnsNoteRepository {
  final _create = Completer<Result<Note>>();

  @override
  Future<Result<Note>> create({
    required String subjectId,
    String? title,
    String? contentJson,
    String? plainText,
    bool isDraft = false,
    Iterable<String> tagNames = const [],
  }) {
    createCallCount++;
    return _create.future;
  }

  void completeCreate() {
    _create.complete(Success(_note(id: 'old-created-note', title: '旧会话标题')));
  }
}

class _DelayedUpdateRepository extends _CreateReturnsNoteRepository {
  final _update = Completer<Result<void>>();

  @override
  Future<Result<Note?>> getById(String id) async =>
      Success(_note(id: id, title: '标题 $id'));

  @override
  Future<Result<void>> update({
    required String id,
    String? title,
    String? contentJson,
    String? plainText,
    bool? isDraft,
    Iterable<String>? tagNames,
  }) {
    updateCallCount++;
    return _update.future;
  }

  void completeUpdate() {
    _update.complete(const Success<void>(null));
  }
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
