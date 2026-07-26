// 笔记搜索条件与结果状态，统一驱动关键词、标签筛选和排序刷新。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/result.dart';
import '../models/note.dart';
import '../models/note_search_query.dart';
import '../providers.dart';

/// 搜索页状态。
class NoteSearchState {
  final NoteSearchQuery query;
  final List<Note> results;

  const NoteSearchState({
    this.query = const NoteSearchQuery(),
    this.results = const [],
  });
}

/// 搜索页 ViewModel；请求序号避免较慢的旧查询覆盖新条件结果。
class NoteSearchVm extends AsyncNotifier<NoteSearchState> {
  NoteSearchQuery _currentQuery = const NoteSearchQuery();
  int _requestRevision = 0;
  Future<NoteSearchState>? _latestRequest;

  /// 当前实际查询条件；页面在 AsyncLoading 时也能恢复筛选控件。
  NoteSearchQuery get currentQuery => _currentQuery;

  @override
  Future<NoteSearchState> build() {
    final revision = ++_requestRevision;
    final request = _search(_currentQuery);
    _latestRequest = request;
    return _resolveLatest(revision, request);
  }

  Future<void> setKeyword(String keyword) =>
      _refresh(_copyQuery(keyword: keyword));

  Future<void> setTagIds(Set<String> tagIds) =>
      _refresh(_copyQuery(tagIds: Set.unmodifiable(tagIds)));

  Future<void> setSortOrder(NoteSortOrder sortOrder) =>
      _refresh(_copyQuery(sortOrder: sortOrder));

  Future<void> refresh() => _refresh(_currentQuery);

  NoteSearchQuery _copyQuery({
    String? keyword,
    Set<String>? tagIds,
    NoteSortOrder? sortOrder,
  }) {
    return NoteSearchQuery(
      keyword: keyword ?? _currentQuery.keyword,
      tagIds: tagIds ?? _currentQuery.tagIds,
      sortOrder: sortOrder ?? _currentQuery.sortOrder,
    );
  }

  Future<NoteSearchState> _search(NoteSearchQuery query) async {
    final result = await ref.read(noteRepositoryProvider).search(query);
    if (result is Success<List<Note>>) {
      return NoteSearchState(query: query, results: result.value);
    }
    throw (result as Failure<List<Note>>).exception;
  }

  Future<void> _refresh(NoteSearchQuery query) async {
    _currentQuery = query;
    final revision = ++_requestRevision;
    final request = _search(query);
    _latestRequest = request;
    state = const AsyncLoading<NoteSearchState>();
    try {
      final next = await request;
      if (revision == _requestRevision) {
        state = AsyncData(next);
      }
    } catch (error, stackTrace) {
      if (revision == _requestRevision) {
        state = AsyncError(error, stackTrace);
      }
    }
  }

  /// 初始 build 若已过期，等待并返回最新请求，避免框架写回旧结果。
  Future<NoteSearchState> _resolveLatest(
    int revision,
    Future<NoteSearchState> request,
  ) async {
    var followedRevision = revision;
    var followedRequest = request;
    while (true) {
      try {
        final result = await followedRequest;
        if (followedRevision == _requestRevision) {
          return result;
        }
      } catch (_) {
        if (followedRevision == _requestRevision) {
          rethrow;
        }
      }
      followedRevision = _requestRevision;
      followedRequest = _latestRequest!;
    }
  }
}
