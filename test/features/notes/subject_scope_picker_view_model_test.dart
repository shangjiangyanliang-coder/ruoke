// 搜索范围树 ViewModel 的按需加载、缓存、防抖与竞态测试。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/subject.dart';
import 'package:ruoke/src/features/notes/models/subject_path.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/repository/subject_repository.dart';
import 'package:ruoke/src/features/notes/view_model/view_model_providers.dart';

void main() {
  test('初始化只读取顶层书，展开节点只加载一次并复用缓存', () async {
    final repository = _SubjectRepositoryFake(
      children: {
        null: [_subject('book', '数学', 0)],
        'book': [_subject('chapter', '函数', 1, parentId: 'book')],
      },
    );
    final container = ProviderContainer(
      overrides: [subjectRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = subjectScopePickerVmProvider(Object());
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);

    expect(repository.childrenCalls, [null]);
    expect(container.read(provider).value!.roots.single.id, 'book');

    final notifier = container.read(provider.notifier);
    await notifier.toggleExpanded('book');
    await notifier.toggleExpanded('book');
    await notifier.toggleExpanded('book');

    expect(repository.childrenCalls, [null, 'book']);
    expect(
      container.read(provider).value!.childrenByParent['book']!.single.id,
      'chapter',
    );
    expect(container.read(provider).value!.expandedIds, contains('book'));
  });

  test('关键词输入防抖，只搜索最后一个非空关键词', () async {
    final repository = _SubjectRepositoryFake(children: {null: const []});
    final container = ProviderContainer(
      overrides: [subjectRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = subjectScopePickerVmProvider(Object());
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);

    notifier.setKeyword('数');
    notifier.setKeyword('数学');
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(repository.searchCalls, ['数学']);
    expect(container.read(provider).value!.keyword, '数学');
  });

  test('较慢的旧搜索结果不会覆盖较新的结果', () async {
    final repository = _SubjectRepositoryFake(children: {null: const []});
    final oldSearch = Completer<Result<List<SubjectPath>>>();
    repository.pendingSearch['旧'] = oldSearch;
    repository.searchResults['新'] = [
      SubjectPath([_subject('new', '新结果', 0)]),
    ];
    final container = ProviderContainer(
      overrides: [subjectRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = subjectScopePickerVmProvider(Object());
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);

    notifier.setKeyword('旧');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    notifier.setKeyword('新');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(container.read(provider).value!.searchPaths.single.target.id, 'new');

    oldSearch.complete(
      Success([
        SubjectPath([_subject('old', '旧结果', 0)]),
      ]),
    );
    await Future<void>.delayed(Duration.zero);

    expect(container.read(provider).value!.searchPaths.single.target.id, 'new');
  });

  test('清空关键词立即恢复根书且不调用搜索', () async {
    final repository = _SubjectRepositoryFake(
      children: {
        null: [_subject('book', '数学', 0)],
      },
    );
    final container = ProviderContainer(
      overrides: [subjectRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = subjectScopePickerVmProvider(Object());
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);

    notifier.setKeyword('数学');
    notifier.setKeyword(' ');

    expect(container.read(provider).value!.keyword, isEmpty);
    expect(container.read(provider).value!.searchPaths, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(repository.searchCalls, isEmpty);
  });
}

class _SubjectRepositoryFake implements SubjectRepository {
  final Map<String?, List<Subject>> children;
  final List<String?> childrenCalls = [];
  final List<String> searchCalls = [];
  final Map<String, List<SubjectPath>> searchResults = {};
  final Map<String, Completer<Result<List<SubjectPath>>>> pendingSearch = {};

  _SubjectRepositoryFake({required this.children});

  @override
  Future<Result<List<Subject>>> childrenOf(String? parentId) async {
    childrenCalls.add(parentId);
    return Success(children[parentId] ?? const []);
  }

  @override
  Future<Result<List<SubjectPath>>> searchPaths(String keyword) {
    searchCalls.add(keyword);
    final pending = pendingSearch[keyword];
    if (pending != null) return pending.future;
    return Future.value(Success(searchResults[keyword] ?? const []));
  }

  @override
  Future<Result<List<Subject>>> listAll() => throw UnimplementedError();

  @override
  Future<Result<Subject?>> getById(String id) => throw UnimplementedError();

  @override
  Future<Result<String>> create({
    required String name,
    required int level,
    String? parentId,
    String? folderId,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> rename({
    required String id,
    required String name,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> moveSubject({
    required String subjectId,
    required String newParentId,
    required int targetIndex,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> reorderChildren({
    required String parentId,
    required List<String> orderedIds,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> softDelete(String id) => throw UnimplementedError();

  @override
  Future<Result<int>> countChildren(String? parentId) =>
      throw UnimplementedError();

  @override
  Future<Result<bool>> isEmpty() => throw UnimplementedError();
}

Subject _subject(String id, String name, int level, {String? parentId}) =>
    Subject(
      id: id,
      parentId: parentId,
      name: name,
      level: level,
      folderId: null,
      sortOrder: 0,
      createdAt: 1,
      updatedAt: 1,
      isDeleted: false,
      deletedAt: null,
    );
