// 文件: test/features/notes/note_editor_view_model_test.dart
// 作用: 验证编辑器初始化状态不会被 Provider 的初始构建结果覆盖。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
      overrides: [
        noteRepositoryProvider.overrideWithValue(repository),
        tagRepositoryProvider.overrideWithValue(_TagRepositoryStub(const [])),
      ],
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
      overrides: [
        noteRepositoryProvider.overrideWithValue(repository),
        tagRepositoryProvider.overrideWithValue(_TagRepositoryStub(const [])),
      ],
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
      overrides: [
        noteRepositoryProvider.overrideWithValue(repository),
        tagRepositoryProvider.overrideWithValue(_TagRepositoryStub(const [])),
      ],
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
      overrides: [
        noteRepositoryProvider.overrideWithValue(repository),
        tagRepositoryProvider.overrideWithValue(_TagRepositoryStub(const [])),
      ],
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

  test('首次创建保存期间继续修改标签会保留最新标签草稿', () async {
    final repository = _DelayedCreateRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('new');
    notifier.addTagName('保存前');
    final save = notifier.save(
      title: '标题',
      contentJson: '[{"insert":"正文\\n"}]',
      hasVisibleContent: true,
    );
    await Future<void>.delayed(Duration.zero);

    notifier.addTagName('保存期间');
    repository.completeCreate();

    expect(await save, NoteSaveResult.saved);
    final state = container.read(noteEditorVmProvider).value;
    expect(state?.tagNames, const ['保存前', '保存期间']);
    expect(state?.dirty, isTrue);
  });

  test('已有标签作为编辑器草稿加载且保存前不写数据库', () async {
    final repository = _CreateReturnsNoteRepository()
      ..noteToLoad = _note(id: 'existing-note', title: '标题');
    final tags = _TagRepositoryStub(const ['旧标签']);
    final container = ProviderContainer(
      overrides: [
        noteRepositoryProvider.overrideWithValue(repository),
        tagRepositoryProvider.overrideWithValue(tags),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('existing-note');
    expect(container.read(noteEditorVmProvider).value?.tagNames, const ['旧标签']);

    notifier.addTagName(' 新标签 ');
    notifier.removeTagName('旧标签');

    final draft = container.read(noteEditorVmProvider).value;
    expect(draft?.tagNames, const ['新标签']);
    expect(draft?.dirty, isTrue);
    expect(repository.updateCallCount, 0);

    final result = await notifier.save(
      title: '标题',
      contentJson: '[{"insert":"正文\\n"}]',
      hasVisibleContent: true,
    );

    expect(result, NoteSaveResult.saved);
    expect(repository.lastUpdateTagNames, const ['新标签']);
  });

  test('标签保存失败时保留标签草稿和未保存状态', () async {
    final repository = _CreateReturnsNoteRepository()
      ..noteToLoad = _note(id: 'existing-note', title: '标题')
      ..failUpdate = true;
    final container = ProviderContainer(
      overrides: [
        noteRepositoryProvider.overrideWithValue(repository),
        tagRepositoryProvider.overrideWithValue(
          _TagRepositoryStub(const ['旧标签']),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(noteEditorVmProvider.notifier);
    await notifier.init('existing-note');
    notifier.addTagName('新标签');

    final result = await notifier.save(
      title: '标题',
      contentJson: '[{"insert":"正文\\n"}]',
      hasVisibleContent: true,
    );

    expect(result, NoteSaveResult.failed);
    final state = container.read(noteEditorVmProvider).value;
    expect(state?.tagNames, const ['旧标签', '新标签']);
    expect(state?.dirty, isTrue);
  });
}

class _CreateReturnsNoteRepository implements NoteRepository {
  int createCallCount = 0;
  int updateCallCount = 0;
  Note? noteToLoad;
  bool failUpdate = false;
  List<String>? lastUpdateTagNames;

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
    lastUpdateTagNames = tagNames?.toList();
    if (failUpdate) {
      return const Failure<void>(DatabaseException('模拟保存失败'));
    }
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
    bool saveCurrentBeforeRestore = false,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> softDelete(String id) async => const Success<void>(null);
}

class _TagRepositoryStub implements TagRepository {
  final List<String> names;

  _TagRepositoryStub(this.names);

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
  Future<Result<List<TagWithCount>>> listTags() => throw UnimplementedError();

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
