// 文件: lib/src/features/notes/view_model/note_version_view_model.dart
// 作用: 管理单条笔记的历史版本列表，以及恢复指定版本后的重新加载。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../models/note_version.dart';
import '../providers.dart';

class NoteVersionState {
  const NoteVersionState({
    required this.versions,
    this.managing = false,
    this.selectedIds = const {},
    this.mutating = false,
    this.operationError,
  });

  final List<NoteVersion> versions;
  final bool managing;
  final Set<String> selectedIds;
  final bool mutating;
  final AppException? operationError;

  NoteVersionState copyWith({
    List<NoteVersion>? versions,
    bool? managing,
    Set<String>? selectedIds,
    bool? mutating,
    AppException? operationError,
    bool clearOperationError = false,
  }) => NoteVersionState(
    versions: versions ?? this.versions,
    managing: managing ?? this.managing,
    selectedIds: selectedIds ?? this.selectedIds,
    mutating: mutating ?? this.mutating,
    operationError: clearOperationError
        ? null
        : operationError ?? this.operationError,
  );
}

/// 历史版本列表 ViewModel。
class NoteVersionVm extends AsyncNotifier<NoteVersionState> {
  final String noteId;

  NoteVersionVm(this.noteId);

  @override
  Future<NoteVersionState> build() async =>
      NoteVersionState(versions: await _load());

  /// 加载当前笔记的历史版本，按 Repository 返回顺序交给页面显示。
  Future<List<NoteVersion>> _load() async {
    final result = await ref.read(noteRepositoryProvider).listVersions(noteId);
    if (result is Success<List<NoteVersion>>) {
      return result.value;
    }
    throw (result as Failure<List<NoteVersion>>).exception;
  }

  /// 恢复版本并重新加载列表，成功后由页面返回编辑器刷新正文。
  void enterManagement() {
    final current = state.value;
    if (current != null) state = AsyncData(current.copyWith(managing: true));
  }

  void exitManagement() {
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(managing: false, selectedIds: {}));
    }
  }

  void toggleSelected(String versionId) {
    final current = state.value;
    if (current == null || !current.managing) return;
    final selected = {...current.selectedIds};
    selected.contains(versionId)
        ? selected.remove(versionId)
        : selected.add(versionId);
    state = AsyncData(current.copyWith(selectedIds: selected));
  }

  void toggleSelectAll() {
    final current = state.value;
    if (current == null || !current.managing) return;
    final allIds = current.versions.map((version) => version.id).toSet();
    state = AsyncData(
      current.copyWith(
        selectedIds: current.selectedIds.length == allIds.length ? {} : allIds,
      ),
    );
  }

  Future<void> refresh() async {
    final current = state.value;
    if (current == null || current.mutating) return;
    state = AsyncData(
      current.copyWith(mutating: true, clearOperationError: true),
    );
    await _refreshAfterMutation(current);
  }

  Future<bool> rename({
    required String versionId,
    required String? name,
  }) async {
    final current = state.value;
    if (current == null || current.mutating) return false;
    state = AsyncData(
      current.copyWith(mutating: true, clearOperationError: true),
    );
    final result = await ref
        .read(noteRepositoryProvider)
        .renameVersion(noteId: noteId, versionId: versionId, name: name);
    if (result is Failure<void>) {
      state = AsyncData(current.copyWith(operationError: result.exception));
      return false;
    }
    await _refreshAfterMutation(current);
    return true;
  }

  Future<bool> deleteSelected() async {
    final current = state.value;
    if (current == null || current.mutating || current.selectedIds.isEmpty) {
      return false;
    }
    state = AsyncData(
      current.copyWith(mutating: true, clearOperationError: true),
    );
    final result = await ref
        .read(noteRepositoryProvider)
        .deleteVersions(noteId: noteId, versionIds: current.selectedIds);
    if (result is Failure<void>) {
      state = AsyncData(current.copyWith(operationError: result.exception));
      return false;
    }
    await _refreshAfterMutation(current, exitManagement: true);
    return true;
  }

  Future<bool> restore({
    required int versionNo,
    required bool saveCurrentBeforeRestore,
  }) async {
    final current = state.value;
    if (current == null || current.mutating) return false;
    state = AsyncData(
      current.copyWith(mutating: true, clearOperationError: true),
    );
    final result = await ref
        .read(noteRepositoryProvider)
        .restoreVersion(
          noteId: noteId,
          versionNo: versionNo,
          saveCurrentBeforeRestore: saveCurrentBeforeRestore,
        );
    if (result is Failure<void>) {
      state = AsyncData(current.copyWith(operationError: result.exception));
      return false;
    }
    await _refreshAfterMutation(current);
    return true;
  }

  Future<bool> _refreshAfterMutation(
    NoteVersionState previous, {
    bool exitManagement = false,
  }) async {
    try {
      final versions = await _load();
      final remainingIds = versions.map((version) => version.id).toSet();
      state = AsyncData(
        previous.copyWith(
          versions: versions,
          managing: exitManagement ? false : previous.managing,
          selectedIds: exitManagement
              ? {}
              : previous.selectedIds.intersection(remainingIds),
          mutating: false,
          clearOperationError: true,
        ),
      );
      return true;
    } catch (error) {
      final exception = error is AppException
          ? error
          : DatabaseException('刷新历史版本失败', techDetail: error.toString());
      state = AsyncData(
        previous.copyWith(
          managing: exitManagement ? false : previous.managing,
          selectedIds: exitManagement ? {} : previous.selectedIds,
          mutating: false,
          operationError: exception,
        ),
      );
      return false;
    }
  }
}
