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
import 'package:ruoke/src/features/notes/view_model/note_version_view_model.dart';
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

    expect(container.read(provider).value?.versions, repository.versions);

    final restored = await notifier.restore(
      versionNo: 1,
      saveCurrentBeforeRestore: false,
    );

    expect(restored, isTrue);
    expect(repository.restoredVersionNo, 1);
    expect(repository.saveCurrentBeforeRestore, isFalse);
    expect(container.read(provider).value?.versions, repository.versions);
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

    final restored = await notifier.restore(
      versionNo: 1,
      saveCurrentBeforeRestore: false,
    );

    expect(restored, isTrue);
    expect(repository.restoredVersionNo, 1);
    expect(
      container.read(provider).value?.operationError,
      isA<DatabaseException>(),
    );
  });

  test('恢复会原样传递保存当前版本选项', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(noteVersionVmProvider('note-1').notifier);
    await container.read(noteVersionVmProvider('note-1').future);

    await notifier.restore(versionNo: 1, saveCurrentBeforeRestore: true);

    expect(repository.saveCurrentBeforeRestore, isTrue);
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

    final restored = await notifier.restore(
      versionNo: 1,
      saveCurrentBeforeRestore: false,
    );

    expect(restored, isFalse);
    expect(container.read(provider).value?.versions, repository.versions);
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
        await container.read(providerA.future) as NoteVersionState;
    final versionsB =
        await container.read(providerB.future) as NoteVersionState;

    expect(versionsA.versions.single.noteId, 'note-a');
    expect(versionsB.versions.single.noteId, 'note-b');
  });

  test('管理模式支持选择、全选和退出时清空选择', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final provider = noteVersionVmProvider('note-1');
    final notifier = container.read(provider.notifier);
    await container.read(provider.future);

    notifier.enterManagement();
    notifier.toggleSelected('version-1');
    expect(container.read(provider).value?.managing, isTrue);
    expect(container.read(provider).value?.selectedIds, {'version-1'});

    notifier.toggleSelectAll();
    expect(container.read(provider).value?.selectedIds, isEmpty);

    notifier.toggleSelectAll();
    expect(container.read(provider).value?.selectedIds, {'version-1'});

    notifier.exitManagement();
    expect(container.read(provider).value?.managing, isFalse);
    expect(container.read(provider).value?.selectedIds, isEmpty);
  });
  test('重命名成功后会刷新版本列表', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = noteVersionVmProvider('note-1');
    final notifier = container.read(provider.notifier);
    await container.read(provider.future);

    final renamed = await notifier.rename(versionId: 'version-1', name: '关键节点');

    expect(renamed, isTrue);
    expect(container.read(provider).value?.versions.single.name, '关键节点');
  });

  test('重命名写入成功但刷新失败仍报告成功', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = noteVersionVmProvider('note-1');
    final notifier = container.read(provider.notifier);
    await container.read(provider.future);
    repository.failList = true;

    final renamed = await notifier.rename(versionId: 'version-1', name: '关键节点');

    expect(renamed, isTrue);
    expect(
      container.read(provider).value?.operationError,
      isA<DatabaseException>(),
    );
  });

  test('批量删除成功后退出管理模式并清空选择', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = noteVersionVmProvider('note-1');
    final notifier = container.read(provider.notifier);
    await container.read(provider.future);

    notifier.enterManagement();
    notifier.toggleSelected('version-1');
    final deleted = await notifier.deleteSelected();

    expect(deleted, isTrue);
    expect(container.read(provider).value?.versions, isEmpty);
    expect(container.read(provider).value?.managing, isFalse);
    expect(container.read(provider).value?.selectedIds, isEmpty);
  });

  test('批量删除写入成功但刷新失败仍退出管理模式', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = noteVersionVmProvider('note-1');
    final notifier = container.read(provider.notifier);
    await container.read(provider.future);
    notifier.enterManagement();
    notifier.toggleSelected('version-1');
    repository.failList = true;

    final deleted = await notifier.deleteSelected();

    expect(deleted, isTrue);
    expect(container.read(provider).value?.managing, isFalse);
    expect(container.read(provider).value?.selectedIds, isEmpty);
    expect(
      container.read(provider).value?.operationError,
      isA<DatabaseException>(),
    );
  });

  test('批量删除失败时保留管理模式和选择', () async {
    final repository = _FakeNoteRepository()..failDelete = true;
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = noteVersionVmProvider('note-1');
    final notifier = container.read(provider.notifier);
    await container.read(provider.future);

    notifier.enterManagement();
    notifier.toggleSelected('version-1');
    final deleted = await notifier.deleteSelected();

    expect(deleted, isFalse);
    expect(container.read(provider).value?.managing, isTrue);
    expect(container.read(provider).value?.selectedIds, {'version-1'});
  });

  test('刷新会清理已不存在版本的选择', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = noteVersionVmProvider('note-1');
    final notifier = container.read(provider.notifier);
    await container.read(provider.future);

    notifier.enterManagement();
    notifier.toggleSelected('version-1');
    repository.versions.clear();
    await notifier.refresh();

    expect(container.read(provider).value?.selectedIds, isEmpty);
  });

  test('刷新遇到意外异常时会退出操作中状态', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = noteVersionVmProvider('note-1');
    final notifier = container.read(provider.notifier);
    await container.read(provider.future);
    repository.throwUnexpectedList = true;

    await notifier.refresh();

    expect(container.read(provider).value?.mutating, isFalse);
    expect(
      container.read(provider).value?.operationError,
      isA<DatabaseException>(),
    );
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
  bool? saveCurrentBeforeRestore;
  bool failList = false;
  bool throwUnexpectedList = false;
  bool failListAfterRestore = false;
  bool failRestore = false;
  bool failDelete = false;

  @override
  Future<Result<List<NoteVersion>>> listVersions(String noteId) async {
    if (throwUnexpectedList) throw StateError('意外刷新失败');
    if (failList || (failListAfterRestore && restoredVersionNo != null)) {
      return const Failure(DatabaseException('刷新失败'));
    }
    return Success(versions);
  }

  @override
  Future<Result<void>> renameVersion({
    required String noteId,
    required String versionId,
    required String? name,
  }) async {
    final index = versions.indexWhere((version) => version.id == versionId);
    if (index < 0) return const Failure(DatabaseException('版本不存在'));
    final version = versions[index];
    versions[index] = NoteVersion(
      id: version.id,
      noteId: version.noteId,
      versionNo: version.versionNo,
      snapshotJson: version.snapshotJson,
      createdAt: version.createdAt,
      name: name,
    );
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> deleteVersions({
    required String noteId,
    required Set<String> versionIds,
  }) async {
    if (failDelete) return const Failure(DatabaseException('删除失败'));
    versions.removeWhere((version) => versionIds.contains(version.id));
    return const Success<void>(null);
  }

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
    this.saveCurrentBeforeRestore = saveCurrentBeforeRestore;
    return const Success<void>(null);
  }

  @override
  Future<Result<List<Note>>> listAll() => throw UnimplementedError();

  @override
  Future<Result<List<Note>>> listBySubject(String subjectId) async =>
      const Success([]);

  @override
  Future<Result<void>> renameTitle({
    required String id,
    required String title,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> moveNote({
    required String noteId,
    required String subjectId,
    required int targetIndex,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> reorderNotes({
    required String subjectId,
    required List<String> orderedIds,
  }) async => const Success<void>(null);

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
