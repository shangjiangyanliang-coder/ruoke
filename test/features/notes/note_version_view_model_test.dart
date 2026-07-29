// 文件: test/features/notes/note_version_view_model_test.dart
// 作用: 验证历史版本 ViewModel 的加载与恢复契约。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/note.dart';
import 'package:ruoke/src/features/notes/models/note_search_query.dart';
import 'package:ruoke/src/features/notes/models/note_version.dart';
import 'package:ruoke/src/features/notes/repository/note_repository.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/view_model/view_model_providers.dart';

void main() {
  test('加载版本并恢复后会重新读取版本列表', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final provider = noteVersionVmProvider('note-1');
    final notifier = container.read(provider.notifier);
    await container.read(provider.future);

    expect(container.read(provider).value, repository.versions);

    final restored = await notifier.restore(versionNo: 1);

    expect(restored, isTrue);
    expect(repository.restoredVersionNo, 1);
    expect(container.read(provider).value, repository.versions);
  });

  test('恢复已完成时，列表刷新失败仍报告恢复成功', () async {
    final repository = _FakeNoteRepository()..failListAfterRestore = true;
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final provider = noteVersionVmProvider('note-1');
    final notifier = container.read(provider.notifier);
    await container.read(provider.future);

    final restored = await notifier.restore(versionNo: 1);

    expect(restored, isTrue);
    expect(repository.restoredVersionNo, 1);
    expect(container.read(provider).hasError, isTrue);
  });

  test('恢复操作失败时返回 false 并保留当前版本列表', () async {
    final repository = _FakeNoteRepository()..failRestore = true;
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = noteVersionVmProvider('note-1');
    final notifier = container.read(provider.notifier);
    await container.read(provider.future);

    final restored = await notifier.restore(versionNo: 1);

    expect(restored, isFalse);
    expect(container.read(provider).value, repository.versions);
  });

  test('不同笔记的版本 Provider 会隔离各自状态', () async {
    final repository = _PerNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    dynamic providerA;
    dynamic providerB;
    try {
      final dynamic family = noteVersionVmProvider;
      providerA = family('note-a');
      providerB = family('note-b');
    } on NoSuchMethodError {
      providerA = null;
      providerB = null;
    }

    expect(providerA, isNotNull, reason: '历史版本 Provider 必须按 noteId family 化');
    expect(providerB, isNotNull, reason: '历史版本 Provider 必须按 noteId family 化');
    if (providerA == null || providerB == null) return;

    final versionsA =
        await container.read(providerA.future) as List<NoteVersion>;
    final versionsB =
        await container.read(providerB.future) as List<NoteVersion>;

    expect(versionsA.single.noteId, 'note-a');
    expect(versionsB.single.noteId, 'note-b');
  });
}

class _PerNoteRepository extends _FakeNoteRepository {
  @override
  Future<Result<List<NoteVersion>>> listVersions(String noteId) async {
    return Success([
      NoteVersion(
        id: 'version-$noteId',
        noteId: noteId,
        versionNo: 1,
        snapshotJson: '[]',
        createdAt: 1,
      ),
    ]);
  }
}

class _FakeNoteRepository implements NoteRepository {
  final versions = [
    const NoteVersion(
      id: 'version-1',
      noteId: 'note-1',
      versionNo: 1,
      snapshotJson: '[]',
      createdAt: 1,
    ),
  ];
  int? restoredVersionNo;
  bool failListAfterRestore = false;
  bool failRestore = false;

  @override
  Future<Result<List<NoteVersion>>> listVersions(String noteId) async {
    if (failListAfterRestore && restoredVersionNo != null) {
      return const Failure(DatabaseException('刷新失败'));
    }
    return Success(versions);
  }

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
  }) async {
    if (failRestore) {
      return const Failure(DatabaseException('恢复失败'));
    }
    restoredVersionNo = versionNo;
    return const Success<void>(null);
  }

  @override
  Future<Result<List<Note>>> listAll() => throw UnimplementedError();

  @override
  Future<Result<List<Note>>> search(NoteSearchQuery query) =>
      throw UnimplementedError();

  @override
  Future<Result<Note?>> getById(String id) => throw UnimplementedError();

  @override
  Future<Result<Note>> create({
    required String subjectId,
    String? title,
    String? contentJson,
    String? plainText,
    bool isDraft = false,
    Iterable<String> tagNames = const [],
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> update({
    required String id,
    String? title,
    String? contentJson,
    String? plainText,
    bool? isDraft,
    Iterable<String>? tagNames,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> softDelete(String id) => throw UnimplementedError();
}
