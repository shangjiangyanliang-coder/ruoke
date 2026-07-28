import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/note.dart';
import 'package:ruoke/src/features/notes/models/note_search_query.dart';
import 'package:ruoke/src/features/notes/models/note_version.dart';
import 'package:ruoke/src/features/notes/models/search_match_mode.dart';
import 'package:ruoke/src/features/notes/models/subject_scope.dart';
import 'package:ruoke/src/features/notes/models/tag.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/note_repository.dart';
import 'package:ruoke/src/features/notes/repository/tag_repository.dart';
import 'package:ruoke/src/features/notes/view_model/view_model_providers.dart';

void main() {
  test('空标签关键词保持引导态且不查询 Repository', () async {
    final tags = _FakeTagRepository();
    final notes = _FakeNoteRepository();
    final container = _container(tags, notes);
    addTearDown(container.dispose);
    final subscription = container.listen(tagSearchVmProvider, (_, _) {});
    addTearDown(subscription.close);

    final initial = await container.read(tagSearchVmProvider.future);
    await container.read(tagSearchVmProvider.notifier).setTagKeyword('   ');
    final state = container.read(tagSearchVmProvider).value!;

    expect(initial.tagKeyword, isEmpty);
    expect(state.matchedTags, isEmpty);
    expect(state.selectedTagIds, isEmpty);
    expect(state.results, isEmpty);
    expect(tags.searches, isEmpty);
    expect(notes.queries, isEmpty);
  });

  test('标签部分和完全匹配会刷新匹配标签', () async {
    final tags = _FakeTagRepository();
    final notes = _FakeNoteRepository();
    final container = _container(tags, notes);
    addTearDown(container.dispose);
    final subscription = container.listen(tagSearchVmProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(tagSearchVmProvider.future);
    final notifier = container.read(tagSearchVmProvider.notifier);

    await notifier.setTagKeyword('复');
    expect(
      container
          .read(tagSearchVmProvider)
          .value!
          .matchedTags
          .map((tag) => tag.name),
      ['复习', '期末复习'],
    );

    await notifier.setTagKeyword('复习');
    await notifier.setTagMatchMode(SearchMatchMode.exact);

    final state = container.read(tagSearchVmProvider).value!;
    expect(state.matchedTags.map((tag) => tag.name), ['复习']);
    expect(tags.searches.last.matchMode, SearchMatchMode.exact);
  });

  test('多选标签、范围和排序组合传入统一笔记查询', () async {
    final tags = _FakeTagRepository();
    final notes = _FakeNoteRepository();
    final container = _container(tags, notes);
    addTearDown(container.dispose);
    final subscription = container.listen(tagSearchVmProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(tagSearchVmProvider.future);
    final notifier = container.read(tagSearchVmProvider.notifier);

    await notifier.setSelectedTagIds({'tag-review', 'tag-final'});
    await notifier.setSubjectScope(const SubjectScope.subtree('book-a'));
    await notifier.setSortOrder(NoteSortOrder.titleAsc);

    final query = notes.queries.last;
    final state = container.read(tagSearchVmProvider).value!;
    expect(query.tagIds, {'tag-review', 'tag-final'});
    expect(query.subjectScope, const SubjectScope.subtree('book-a'));
    expect(query.sortOrder, NoteSortOrder.titleAsc);
    expect(state.results.single.title, '查询结果 3');
  });

  test('较慢的旧标签查询不会覆盖最新关键词', () async {
    final first = Completer<Result<List<Tag>>>();
    final tags = _FakeTagRepository()..firstSearch = first;
    final notes = _FakeNoteRepository();
    final container = _container(tags, notes);
    addTearDown(container.dispose);
    final subscription = container.listen(tagSearchVmProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(tagSearchVmProvider.future);
    final notifier = container.read(tagSearchVmProvider.notifier);

    final oldSearch = notifier.setTagKeyword('旧');
    await Future<void>.delayed(Duration.zero);
    await notifier.setTagKeyword('复');
    first.complete(Success([_tag('old', '旧标签')]));
    await oldSearch;

    final state = container.read(tagSearchVmProvider).value!;
    expect(state.tagKeyword, '复');
    expect(state.matchedTags.map((tag) => tag.name), ['复习', '期末复习']);
  });

  test('标签查询失败保留条件并暴露领域错误', () async {
    final tags = _FakeTagRepository()..failSearch = true;
    final notes = _FakeNoteRepository();
    final container = _container(tags, notes);
    addTearDown(container.dispose);
    final subscription = container.listen(tagSearchVmProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(tagSearchVmProvider.future);

    await container.read(tagSearchVmProvider.notifier).setTagKeyword('失败');

    final state = container.read(tagSearchVmProvider).value!;
    expect(state.tagKeyword, '失败');
    expect(state.actionError, isA<DatabaseException>());
    expect(state.actionError?.userMessage, '模拟标签搜索失败');
  });
  test('标签请求挂起期间销毁 Provider 后完成请求不会回写旧状态', () async {
    final gate = Completer<Result<List<Tag>>>();
    final tags = _FakeTagRepository()..firstSearch = gate;
    final notes = _FakeNoteRepository();
    final container = _container(tags, notes);
    addTearDown(container.dispose);
    final subscription = container.listen(tagSearchVmProvider, (_, _) {});
    await container.read(tagSearchVmProvider.future);

    final pending = container
        .read(tagSearchVmProvider.notifier)
        .setTagKeyword('即将销毁');
    await Future<void>.delayed(Duration.zero);
    subscription.close();
    await container.pump();
    gate.complete(Success([_tag('late', '迟到标签')]));

    await expectLater(pending, completes);
  });

  test('笔记查询失败只重试笔记查询且不清除标签条件', () async {
    final tags = _FakeTagRepository();
    final notes = _FakeNoteRepository()..failSearch = true;
    final container = _container(tags, notes);
    addTearDown(container.dispose);
    final subscription = container.listen(tagSearchVmProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(tagSearchVmProvider.future);
    final notifier = container.read(tagSearchVmProvider.notifier);

    await notifier.setTagKeyword('复习');
    await notifier.setSelectedTagIds({'tag-review'});
    final tagSearchCount = tags.searches.length;
    expect(
      container.read(tagSearchVmProvider).value!.noteSearchError,
      isA<DatabaseException>(),
    );

    notes.failSearch = false;
    await notifier.retryNoteSearch();

    final state = container.read(tagSearchVmProvider).value!;
    expect(state.noteSearchError, isNull);
    expect(state.selectedTagIds, {'tag-review'});
    expect(tags.searches, hasLength(tagSearchCount));
    expect(state.results, hasLength(1));
  });
}

ProviderContainer _container(TagRepository tags, NoteRepository notes) =>
    ProviderContainer(
      overrides: [
        tagRepositoryProvider.overrideWithValue(tags),
        noteRepositoryProvider.overrideWithValue(notes),
      ],
    );

class _FakeTagRepository implements TagRepository {
  final searches = <({String keyword, SearchMatchMode matchMode})>[];
  Completer<Result<List<Tag>>>? firstSearch;
  bool failSearch = false;

  @override
  Future<Result<List<Tag>>> searchTags({
    required String keyword,
    required SearchMatchMode matchMode,
  }) {
    searches.add((keyword: keyword, matchMode: matchMode));
    if (searches.length == 1 && firstSearch != null) {
      return firstSearch!.future;
    }
    if (failSearch) {
      return Future.value(const Failure(DatabaseException('模拟标签搜索失败')));
    }
    final all = [_tag('tag-review', '复习'), _tag('tag-final', '期末复习')];
    return Future.value(
      Success(
        all.where((tag) {
          return switch (matchMode) {
            SearchMatchMode.contains => tag.name.contains(keyword.trim()),
            SearchMatchMode.exact => tag.name == keyword.trim(),
          };
        }).toList(),
      ),
    );
  }

  @override
  Future<Result<List<TagWithCount>>> listTags() => throw UnimplementedError();

  @override
  Future<Result<Tag>> createTag({required String name, String? color}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> renameTag({required String id, required String name}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> deleteTag(String id) => throw UnimplementedError();

  @override
  Future<Result<List<Tag>>> listTagsForNote(String noteId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> replaceNoteTags({
    required String noteId,
    required List<String> tagIds,
  }) => throw UnimplementedError();

  @override
  Future<Result<Tag>> findOrCreateAndAttachTag({
    required String noteId,
    required String tagName,
  }) => throw UnimplementedError();

  @override
  Future<Result<List<Tag>>> attachTagsByNames({
    required String noteId,
    required Iterable<String> names,
  }) => throw UnimplementedError();
}

class _FakeNoteRepository implements NoteRepository {
  final queries = <NoteSearchQuery>[];
  bool failSearch = false;

  @override
  Future<Result<List<Note>>> search(NoteSearchQuery query) async {
    queries.add(query);
    if (failSearch) {
      return const Failure(DatabaseException('模拟笔记搜索失败'));
    }
    return Success([
      _note('result-${queries.length}', '查询结果 ${queries.length}'),
    ]);
  }

  @override
  Future<Result<List<Note>>> listAll() => throw UnimplementedError();

  @override
  Future<Result<Note?>> getById(String id) => throw UnimplementedError();

  @override
  Future<Result<Note>> create({
    required String subjectId,
    String? title,
    String? contentJson,
    String? plainText,
    bool isDraft = false,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> update({
    required String id,
    String? title,
    String? contentJson,
    String? plainText,
    bool? isDraft,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> softDelete(String id) => throw UnimplementedError();

  @override
  Future<Result<List<NoteVersion>>> listVersions(String noteId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> restoreVersion({
    required String noteId,
    required int versionNo,
  }) => throw UnimplementedError();
}

Tag _tag(String id, String name) =>
    Tag(id: id, name: name, color: null, createdAt: 1);

Note _note(String id, String title) => Note(
  id: id,
  subjectId: 'uncategorized',
  title: title,
  contentJson: null,
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
