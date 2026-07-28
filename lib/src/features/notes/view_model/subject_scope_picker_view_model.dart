// 搜索范围弹窗状态：按需加载书章节树，并隔离每次弹窗的搜索会话。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../models/subject.dart';
import '../models/subject_path.dart';
import '../providers.dart';

/// 单次范围选择会话的不可变状态。
class SubjectScopePickerState {
  final List<Subject> roots;
  final Map<String, List<Subject>> childrenByParent;
  final Set<String> expandedIds;
  final Set<String> loadingParentIds;
  final Map<String, AppException> branchErrors;
  final String keyword;
  final List<SubjectPath> searchPaths;
  final bool searching;
  final AppException? searchError;

  const SubjectScopePickerState({
    this.roots = const [],
    this.childrenByParent = const {},
    this.expandedIds = const {},
    this.loadingParentIds = const {},
    this.branchErrors = const {},
    this.keyword = '',
    this.searchPaths = const [],
    this.searching = false,
    this.searchError,
  });

  SubjectScopePickerState copyWith({
    List<Subject>? roots,
    Map<String, List<Subject>>? childrenByParent,
    Set<String>? expandedIds,
    Set<String>? loadingParentIds,
    Map<String, AppException>? branchErrors,
    String? keyword,
    List<SubjectPath>? searchPaths,
    bool? searching,
    AppException? searchError,
    bool clearSearchError = false,
  }) {
    return SubjectScopePickerState(
      roots: roots ?? this.roots,
      childrenByParent: childrenByParent ?? this.childrenByParent,
      expandedIds: expandedIds ?? this.expandedIds,
      loadingParentIds: loadingParentIds ?? this.loadingParentIds,
      branchErrors: branchErrors ?? this.branchErrors,
      keyword: keyword ?? this.keyword,
      searchPaths: searchPaths ?? this.searchPaths,
      searching: searching ?? this.searching,
      searchError: clearSearchError ? null : searchError ?? this.searchError,
    );
  }
}

/// 每个弹窗实例独立创建，用会话参数触发 family 隔离和自动销毁。
class SubjectScopePickerVm extends AsyncNotifier<SubjectScopePickerState> {
  final Object sessionKey;
  Timer? _searchTimer;
  int _searchGeneration = 0;

  SubjectScopePickerVm(this.sessionKey);

  @override
  Future<SubjectScopePickerState> build() async {
    ref.onDispose(() => _searchTimer?.cancel());
    final result = await ref.read(subjectRepositoryProvider).childrenOf(null);
    if (result is Success<List<Subject>>) {
      return SubjectScopePickerState(roots: result.value);
    }
    throw (result as Failure<List<Subject>>).exception;
  }

  /// 展开时首次加载直接子节点；收起和再次展开均复用会话缓存。
  Future<void> toggleExpanded(String subjectId) async {
    final current = state.value;
    if (current == null) return;
    final expanded = Set<String>.from(current.expandedIds);
    if (!expanded.add(subjectId)) {
      expanded.remove(subjectId);
      state = AsyncData(current.copyWith(expandedIds: expanded));
      return;
    }
    state = AsyncData(current.copyWith(expandedIds: expanded));
    if (!current.childrenByParent.containsKey(subjectId)) {
      await loadChildren(subjectId);
    }
  }

  /// 单分支加载失败不会破坏根列表和其他已展开分支。
  Future<void> loadChildren(String parentId) async {
    final current = state.value;
    if (current == null || current.loadingParentIds.contains(parentId)) return;
    final loading = Set<String>.from(current.loadingParentIds)..add(parentId);
    final errors = Map<String, AppException>.from(current.branchErrors)
      ..remove(parentId);
    state = AsyncData(
      current.copyWith(loadingParentIds: loading, branchErrors: errors),
    );

    final result = await ref
        .read(subjectRepositoryProvider)
        .childrenOf(parentId);
    if (!ref.mounted) return;
    final latest = state.value;
    if (latest == null) return;
    final nextLoading = Set<String>.from(latest.loadingParentIds)
      ..remove(parentId);
    if (result is Success<List<Subject>>) {
      final children = Map<String, List<Subject>>.from(latest.childrenByParent)
        ..[parentId] = List.unmodifiable(result.value);
      state = AsyncData(
        latest.copyWith(
          childrenByParent: children,
          loadingParentIds: nextLoading,
        ),
      );
      return;
    }
    final nextErrors = Map<String, AppException>.from(latest.branchErrors)
      ..[parentId] = (result as Failure<List<Subject>>).exception;
    state = AsyncData(
      latest.copyWith(loadingParentIds: nextLoading, branchErrors: nextErrors),
    );
  }

  /// 输入采用 250ms 防抖；空关键词立即恢复根书模式。
  void setKeyword(String value) {
    _searchTimer?.cancel();
    final generation = ++_searchGeneration;
    final keyword = value.trim();
    final current = state.value;
    if (current == null) return;
    if (keyword.isEmpty) {
      state = AsyncData(
        current.copyWith(
          keyword: '',
          searchPaths: const [],
          searching: false,
          clearSearchError: true,
        ),
      );
      return;
    }
    state = AsyncData(
      current.copyWith(
        keyword: keyword,
        searching: true,
        clearSearchError: true,
      ),
    );
    _searchTimer = Timer(
      const Duration(milliseconds: 250),
      () => _search(keyword, generation),
    );
  }

  Future<void> retrySearch() async {
    final current = state.value;
    if (current == null || current.keyword.isEmpty) return;
    _searchTimer?.cancel();
    final generation = ++_searchGeneration;
    state = AsyncData(
      current.copyWith(searching: true, clearSearchError: true),
    );
    await _search(current.keyword, generation);
  }

  Future<void> _search(String keyword, int generation) async {
    final result = await ref
        .read(subjectRepositoryProvider)
        .searchPaths(keyword);
    if (!ref.mounted || generation != _searchGeneration) return;
    final current = state.value;
    if (current == null || current.keyword != keyword) return;
    if (result is Success<List<SubjectPath>>) {
      state = AsyncData(
        current.copyWith(
          searchPaths: List.unmodifiable(result.value),
          searching: false,
          clearSearchError: true,
        ),
      );
      return;
    }
    state = AsyncData(
      current.copyWith(
        searching: false,
        searchError: (result as Failure<List<SubjectPath>>).exception,
      ),
    );
  }
}
