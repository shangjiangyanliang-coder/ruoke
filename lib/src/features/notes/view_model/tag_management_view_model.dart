// 标签管理与单笔记标签状态，负责把 Repository Result 转换为页面状态。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../models/tag.dart';
import '../providers.dart';

/// 标签管理页状态；操作失败时保留当前列表并记录可展示错误。
class TagManagementState {
  final List<TagWithCount> tags;
  final AppException? actionError;

  const TagManagementState({this.tags = const [], this.actionError});
}

/// 标签管理页 ViewModel。
class TagManagementVm extends AsyncNotifier<TagManagementState> {
  @override
  Future<TagManagementState> build() => _load();

  Future<TagManagementState> _load() async {
    final result = await ref.read(tagRepositoryProvider).listTags();
    if (result is Success<List<TagWithCount>>) {
      return TagManagementState(tags: result.value);
    }
    throw (result as Failure<List<TagWithCount>>).exception;
  }

  Future<bool> create({required String name, String? color}) async {
    final result = await ref
        .read(tagRepositoryProvider)
        .createTag(name: name, color: color);
    if (result is Success<Tag>) {
      return _reload(preserveCurrentOnError: true);
    }
    _recordError((result as Failure<Tag>).exception);
    return false;
  }

  Future<bool> rename({required String id, required String name}) async {
    final result = await ref
        .read(tagRepositoryProvider)
        .renameTag(id: id, name: name);
    if (result is Success<void>) {
      return _reload(preserveCurrentOnError: true);
    }
    _recordError((result as Failure<void>).exception);
    return false;
  }

  Future<bool> delete(String id) async {
    final result = await ref.read(tagRepositoryProvider).deleteTag(id);
    if (result is Success<void>) {
      return _reload(preserveCurrentOnError: true);
    }
    _recordError((result as Failure<void>).exception);
    return false;
  }

  void clearActionError() {
    final current = state.value;
    if (current != null) {
      state = AsyncData(TagManagementState(tags: current.tags));
    }
  }

  Future<void> refresh() async {
    await _reload(preserveCurrentOnError: true);
  }

  Future<bool> _reload({required bool preserveCurrentOnError}) async {
    final previous = state;
    try {
      state = AsyncData(await _load());
      return true;
    } catch (error, stackTrace) {
      final current = previous.value;
      if (preserveCurrentOnError && current != null) {
        final exception = error is AppException
            ? error
            : DatabaseException(
                '刷新标签列表失败',
                techDetail: error.runtimeType.toString(),
              );
        state = AsyncData(
          TagManagementState(tags: current.tags, actionError: exception),
        );
      } else {
        state = AsyncError(error, stackTrace);
      }
      return false;
    }
  }

  void _recordError(AppException error) {
    final current = state.value ?? const TagManagementState();
    state = AsyncData(
      TagManagementState(tags: current.tags, actionError: error),
    );
  }
}

/// 单条笔记标签状态；操作失败时保留当前标签和可展示错误。
class NoteTagsState {
  final List<Tag> tags;
  final AppException? actionError;

  const NoteTagsState({this.tags = const [], this.actionError});
}

/// 单条笔记的标签 ViewModel；构造参数确保不同 noteId 不共享状态。
class NoteTagsVm extends AsyncNotifier<NoteTagsState> {
  final String noteId;

  NoteTagsVm(this.noteId);

  @override
  Future<NoteTagsState> build() => _load();

  Future<NoteTagsState> _load() async {
    final result = await ref
        .read(tagRepositoryProvider)
        .listTagsForNote(noteId);
    if (result is Success<List<Tag>>) {
      return NoteTagsState(tags: result.value);
    }
    throw (result as Failure<List<Tag>>).exception;
  }

  Future<bool> replaceTagIds(Iterable<String> tagIds) async {
    final previous = state.value ?? const NoteTagsState();
    final result = await ref
        .read(tagRepositoryProvider)
        .replaceNoteTags(noteId: noteId, tagIds: tagIds.toSet().toList());
    if (result is Failure<void>) {
      state = AsyncData(
        NoteTagsState(tags: previous.tags, actionError: result.exception),
      );
      return false;
    }
    try {
      state = AsyncData(await _load());
      return true;
    } catch (error) {
      state = AsyncData(
        NoteTagsState(tags: previous.tags, actionError: _asAppException(error)),
      );
      return false;
    }
  }

  Future<bool> addByName(String name) async {
    final previous = state.value ?? const NoteTagsState();
    final result = await ref
        .read(tagRepositoryProvider)
        .findOrCreateAndAttachTag(noteId: noteId, tagName: name);
    if (result is Failure<Tag>) {
      state = AsyncData(
        NoteTagsState(tags: previous.tags, actionError: result.exception),
      );
      return false;
    }
    return _reloadAfterWrite(previous);
  }

  Future<bool> attachNames(Iterable<String> names) async {
    final previous = state.value ?? const NoteTagsState();
    final result = await ref
        .read(tagRepositoryProvider)
        .attachTagsByNames(noteId: noteId, names: names);
    if (result is Failure<List<Tag>>) {
      state = AsyncData(
        NoteTagsState(tags: previous.tags, actionError: result.exception),
      );
      return false;
    }
    return _reloadAfterWrite(previous);
  }

  Future<bool> removeTag(String tagId) {
    final remaining = (state.value?.tags ?? const <Tag>[])
        .where((tag) => tag.id != tagId)
        .map((tag) => tag.id);
    return replaceTagIds(remaining);
  }

  Future<void> refresh() async {
    final previous = state.value ?? const NoteTagsState();
    try {
      state = AsyncData(await _load());
    } catch (error) {
      state = AsyncData(
        NoteTagsState(tags: previous.tags, actionError: _asAppException(error)),
      );
    }
  }

  Future<bool> _reloadAfterWrite(NoteTagsState previous) async {
    try {
      state = AsyncData(await _load());
      return true;
    } catch (error) {
      state = AsyncData(
        NoteTagsState(tags: previous.tags, actionError: _asAppException(error)),
      );
      return false;
    }
  }

  AppException _asAppException(Object error) {
    return error is AppException
        ? error
        : DatabaseException(
            '刷新笔记标签失败',
            techDetail: error.runtimeType.toString(),
          );
  }
}
