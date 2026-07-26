// 标签管理与单笔记标签状态的 ViewModel 契约测试。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/tag.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/tag_repository.dart';
import 'package:ruoke/src/features/notes/view_model/view_model_providers.dart';

void main() {
  test('新建、改名和删除标签后都会刷新管理列表', () async {
    final repository = _FakeTagRepository()
      ..tags = [_tagWithCount('tag-1', '旧标签')];
    final container = ProviderContainer(
      overrides: [tagRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(tagManagementVmProvider.notifier);
    await container.read(tagManagementVmProvider.future);

    expect(await notifier.create(name: '新标签'), isTrue);
    expect(
      container
          .read(tagManagementVmProvider)
          .value!
          .tags
          .map((tag) => tag.name),
      ['旧标签', '新标签'],
    );

    expect(await notifier.rename(id: 'tag-1', name: '已改名'), isTrue);
    expect(
      container.read(tagManagementVmProvider).value!.tags.first.name,
      '已改名',
    );

    expect(await notifier.delete('tag-1'), isTrue);
    expect(
      container
          .read(tagManagementVmProvider)
          .value!
          .tags
          .map((tag) => tag.name),
      ['新标签'],
    );
    expect(repository.listTagsCallCount, 4);
  });

  test('标签操作失败时保留原列表并记录可展示错误', () async {
    final repository = _FakeTagRepository()
      ..tags = [_tagWithCount('tag-1', '保留标签')]
      ..failCreate = true;
    final container = ProviderContainer(
      overrides: [tagRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(tagManagementVmProvider.notifier);
    await container.read(tagManagementVmProvider.future);

    expect(await notifier.create(name: '失败标签'), isFalse);

    final state = container.read(tagManagementVmProvider).value!;
    expect(state.tags.single.name, '保留标签');
    expect(state.actionError?.userMessage, '模拟新建失败');
  });

  test('标签写入成功但刷新失败时不误报成功且保留原列表', () async {
    final repository = _FakeTagRepository()
      ..tags = [_tagWithCount('tag-1', '原标签')];
    final container = ProviderContainer(
      overrides: [tagRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(tagManagementVmProvider.notifier);
    await container.read(tagManagementVmProvider.future);
    repository.failList = true;

    expect(await notifier.rename(id: 'tag-1', name: '已写入数据库'), isFalse);

    final state = container.read(tagManagementVmProvider).value!;
    expect(state.tags.single.name, '原标签');
    expect(state.actionError?.userMessage, '模拟刷新失败');
  });

  test('不同 noteId 的标签状态彼此隔离，替换后只刷新当前笔记', () async {
    final first = _tag('tag-1', '第一');
    final second = _tag('tag-2', '第二');
    final third = _tag('tag-3', '第三');
    final repository = _FakeTagRepository()
      ..allTags = [first, second, third]
      ..noteTags = {
        'note-a': [first],
        'note-b': [second],
      };
    final container = ProviderContainer(
      overrides: [tagRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final providerA = noteTagsVmProvider('note-a');
    final providerB = noteTagsVmProvider('note-b');

    expect((await container.read(providerA.future)).tags.single.id, 'tag-1');
    expect((await container.read(providerB.future)).tags.single.id, 'tag-2');

    final saved = await container.read(providerA.notifier).replaceTagIds([
      'tag-3',
    ]);

    expect(saved, isTrue);
    expect(container.read(providerA).value!.tags.single.id, 'tag-3');
    expect(container.read(providerB).value!.tags.single.id, 'tag-2');
    expect(repository.replacedNoteId, 'note-a');
  });

  test('贴标签失败时 Provider 保留旧标签并暴露错误状态', () async {
    final first = _tag('tag-1', '第一');
    final second = _tag('tag-2', '第二');
    final repository = _FakeTagRepository()
      ..allTags = [first, second]
      ..noteTags = {
        'note-a': [first],
      }
      ..failReplace = true;
    final container = ProviderContainer(
      overrides: [tagRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = noteTagsVmProvider('note-a');
    await container.read(provider.future);

    final saved = await container.read(provider.notifier).replaceTagIds([
      'tag-2',
    ]);

    expect(saved, isFalse);
    expect(container.read(provider).value!.tags.single.id, 'tag-1');
    expect(
      container.read(provider).value!.actionError?.userMessage,
      '模拟保存标签失败',
    );
  });
}

class _FakeTagRepository implements TagRepository {
  List<TagWithCount> tags = [];
  List<Tag> allTags = [];
  Map<String, List<Tag>> noteTags = {};
  int listTagsCallCount = 0;
  bool failCreate = false;
  bool failList = false;
  bool failReplace = false;
  String? replacedNoteId;

  @override
  Future<Result<List<TagWithCount>>> listTags() async {
    listTagsCallCount++;
    if (failList) {
      return const Failure(DatabaseException('模拟刷新失败'));
    }
    return Success(List.of(tags));
  }

  @override
  Future<Result<Tag>> createTag({required String name, String? color}) async {
    if (failCreate) {
      return const Failure(DatabaseException('模拟新建失败'));
    }
    final created = _tagWithCount('tag-${tags.length + 1}', name);
    tags = [...tags, created];
    allTags = [...allTags, created];
    return Success(created);
  }

  @override
  Future<Result<void>> renameTag({
    required String id,
    required String name,
  }) async {
    tags = [
      for (final tag in tags)
        if (tag.id == id)
          _tagWithCount(tag.id, name, noteCount: tag.noteCount)
        else
          tag,
    ];
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> deleteTag(String id) async {
    tags = tags.where((tag) => tag.id != id).toList();
    return const Success<void>(null);
  }

  @override
  Future<Result<List<Tag>>> listTagsForNote(String noteId) async =>
      Success(List.of(noteTags[noteId] ?? const []));

  @override
  Future<Result<void>> replaceNoteTags({
    required String noteId,
    required List<String> tagIds,
  }) async {
    if (failReplace) {
      return const Failure(DatabaseException('模拟保存标签失败'));
    }
    replacedNoteId = noteId;
    noteTags[noteId] = [
      for (final id in tagIds) allTags.firstWhere((tag) => tag.id == id),
    ];
    return const Success<void>(null);
  }
}

Tag _tag(String id, String name) =>
    Tag(id: id, name: name, color: null, createdAt: 1);

TagWithCount _tagWithCount(String id, String name, {int noteCount = 0}) =>
    TagWithCount(
      id: id,
      name: name,
      color: null,
      createdAt: 1,
      noteCount: noteCount,
    );
