// 文件: test/features/notes/note_editor_view_model_test.dart
// 作用: 验证编辑器初始化状态不会被 Provider 的初始构建结果覆盖。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/note.dart';
import 'package:ruoke/src/features/notes/models/note_version.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/note_repository.dart';
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
    );
    final firstState = container.read(noteEditorVmProvider).value;

    expect(firstSaved, isTrue);
    expect(firstState?.note?.id, 'created-note');
    expect(firstState?.isNew, isFalse);

    final secondSaved = await notifier.save(
      title: '第二版',
      contentJson: '[{"insert":"第二版\\n"}]',
    );
    expect(secondSaved, isTrue);
    expect(repository.createCallCount, 1);
    expect(repository.updateCallCount, 1);
  });
}

class _CreateReturnsNoteRepository implements NoteRepository {
  int createCallCount = 0;
  int updateCallCount = 0;

  @override
  Future<Result<Note>> create({
    required String subjectId,
    String? title,
    String? contentJson,
    String? plainText,
    bool isDraft = false,
  }) async {
    createCallCount++;
    return Success(
      _note(id: 'created-note', title: title, contentJson: contentJson),
    );
  }

  @override
  Future<Result<Note?>> getById(String id) async => const Success(null);

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
  Future<Result<List<Note>>> listAll() async => const Success([]);

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
