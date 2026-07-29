// 笔记搜索条件与结果状态的 ViewModel 契约测试。
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
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/note_repository.dart';
import 'package:ruoke/src/features/notes/view_model/view_model_providers.dart';

void main() {
  test('搜索条件改变后立即使用新条件刷新结果', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(noteSearchVmProvider, (_, _) {});
    addTearDown(subscription.close);
    final notifier = container.read(noteSearchVmProvider.notifier);
    await container.read(noteSearchVmProvider.future);

    await notifier.setKeyword('  代数  ');
    await notifier.setTagIds({'tag-1', 'tag-2'});

    final state = container.read(noteSearchVmProvider).value!;
    expect(state.query.keyword, '  代数  ');
    expect(state.query.tagIds, {'tag-1', 'tag-2'});
    expect(state.results.single.title, '结果 3');
    expect(repository.queries.length, 3);
  });

  test('切换排序后保留关键词和标签并刷新结果', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(noteSearchVmProvider, (_, _) {});
    addTearDown(subscription.close);
    final notifier = container.read(noteSearchVmProvider.notifier);
    await container.read(noteSearchVmProvider.future);
    await notifier.setKeyword('正文');
    await notifier.setTagIds({'tag-1'});

    await notifier.setSortOrder(NoteSortOrder.titleAsc);

    final query = container.read(noteSearchVmProvider).value!.query;
    expect(query.keyword, '正文');
    expect(query.tagIds, {'tag-1'});
    expect(query.sortOrder, NoteSortOrder.titleAsc);
    expect(repository.queries.last.sortOrder, NoteSortOrder.titleAsc);
  });

  test('搜索加载中仍暴露页面恢复所需的真实查询条件', () async {
    final repository = _FakeNoteRepository()
      ..secondSearch = Completer<Result<List<Note>>>();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(noteSearchVmProvider, (_, _) {});
    addTearDown(subscription.close);
    final notifier = container.read(noteSearchVmProvider.notifier);
    await container.read(noteSearchVmProvider.future);

    final searching = notifier.setKeyword('加载中条件');
    await Future<void>.delayed(Duration.zero);

    expect(container.read(noteSearchVmProvider).isLoading, isTrue);
    expect(notifier.currentQuery.keyword, '加载中条件');

    repository.secondSearch!.complete(Success([_note('loaded', '加载完成')]));
    await searching;
  });

  test('连续三次查询时旧请求不会覆盖最新条件结果', () async {
    final repository = _FakeNoteRepository()
      ..firstSearch = Completer<Result<List<Note>>>()
      ..secondSearch = Completer<Result<List<Note>>>();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(noteSearchVmProvider, (_, _) {});
    addTearDown(subscription.close);
    final notifier = container.read(noteSearchVmProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    final secondRequest = notifier.setKeyword('条件 B');
    await Future<void>.delayed(Duration.zero);
    repository.firstSearch!.complete(Success([_note('old-a', '旧结果 A')]));
    await Future<void>.delayed(Duration.zero);

    await notifier.setKeyword('条件 C');
    repository.secondSearch!.complete(Success([_note('old-b', '旧结果 B')]));
    await secondRequest;
    await Future<void>.delayed(Duration.zero);

    final state = container.read(noteSearchVmProvider).value!;
    expect(state.query.keyword, '条件 C');
    expect(state.results.single.title, '结果 3');
  });

  test('搜索失败时状态保留领域错误', () async {
    final repository = _FakeNoteRepository()..failSearch = true;
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final error = Completer<Object>();
    final subscription = container.listen(noteSearchVmProvider, (_, next) {
      if (next.hasError && !error.isCompleted) {
        error.complete(next.error!);
      }
    }, fireImmediately: true);
    addTearDown(subscription.close);

    await expectLater(
      error.future,
      completion(
        isA<DatabaseException>().having(
          (exception) => exception.userMessage,
          'userMessage',
          '模拟搜索失败',
        ),
      ),
    );
    expect(container.read(noteSearchVmProvider).hasError, isTrue);
  });

  test('切换匹配模式和科目范围会保留其他条件并刷新', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(noteSearchVmProvider, (_, _) {});
    addTearDown(subscription.close);
    final notifier = container.read(noteSearchVmProvider.notifier);
    await container.read(noteSearchVmProvider.future);
    await notifier.setKeyword('代数');
    await notifier.setTagIds({'tag-1'});

    await notifier.setKeywordMatchMode(SearchMatchMode.exact);
    await notifier.setSubjectScope(const SubjectScope.level(1));

    final query = container.read(noteSearchVmProvider).value!.query;
    expect(query.keyword, '代数');
    expect(query.tagIds, {'tag-1'});
    expect(query.keywordMatchMode, SearchMatchMode.exact);
    expect(query.subjectScope, const SubjectScope.level(1));
    expect(repository.queries.last.subjectScope, const SubjectScope.level(1));
  });

  test('搜索 Provider 销毁后重新进入恢复默认条件', () async {
    final repository = _FakeNoteRepository();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final firstSubscription = container.listen(noteSearchVmProvider, (_, _) {});
    await container.read(noteSearchVmProvider.future);
    await container.read(noteSearchVmProvider.notifier).setKeyword('不应保留');
    firstSubscription.close();
    await container.pump();

    final secondSubscription = container.listen(
      noteSearchVmProvider,
      (_, _) {},
    );
    addTearDown(secondSubscription.close);
    final reopened = await container.read(noteSearchVmProvider.future);

    expect(reopened.query.keyword, isEmpty);
    expect(reopened.query.tagIds, isEmpty);
    expect(reopened.query.keywordMatchMode, SearchMatchMode.contains);
    expect(reopened.query.subjectScope, const SubjectScope.all());
    expect(reopened.query.sortOrder, NoteSortOrder.updatedDesc);
  });
  test('搜索请求挂起期间销毁 Provider 后完成请求不会回写旧状态', () async {
    final repository = _FakeNoteRepository()
      ..secondSearch = Completer<Result<List<Note>>>();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(noteSearchVmProvider, (_, _) {});
    await container.read(noteSearchVmProvider.future);

    final pending = container
        .read(noteSearchVmProvider.notifier)
        .setKeyword('即将销毁');
    await Future<void>.delayed(Duration.zero);
    subscription.close();
    await container.pump();
    repository.secondSearch!.complete(Success([_note('late', '迟到结果')]));

    await expectLater(pending, completes);
  });
}

class _FakeNoteRepository implements NoteRepository {
  final List<NoteSearchQuery> queries = [];
  bool failSearch = false;
  Completer<Result<List<Note>>>? firstSearch;
  Completer<Result<List<Note>>>? secondSearch;

  @override
  Future<Result<List<Note>>> search(NoteSearchQuery query) async {
    queries.add(query);
    final pending = firstSearch;
    if (queries.length == 1 && pending != null) {
      return pending.future;
    }
    final nextPending = secondSearch;
    if (queries.length == 2 && nextPending != null) {
      return nextPending.future;
    }
    if (failSearch) {
      return const Failure(DatabaseException('模拟搜索失败'));
    }
    return Success([_note('result-${queries.length}', '结果 ${queries.length}')]);
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

  @override
  Future<Result<List<NoteVersion>>> listVersions(String noteId) =>
      throw UnimplementedError();

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
  }) => throw UnimplementedError();
}

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
