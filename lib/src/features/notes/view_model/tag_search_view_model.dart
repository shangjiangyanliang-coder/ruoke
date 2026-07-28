import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../models/note.dart';
import '../models/note_search_query.dart';
import '../models/search_match_mode.dart';
import '../models/subject_scope.dart';
import '../models/tag.dart';
import '../providers.dart';

/// 标签搜索页面的完整会话状态。
class TagSearchState {
  final String tagKeyword;
  final SearchMatchMode tagMatchMode;
  final List<Tag> matchedTags;
  final Set<String> selectedTagIds;
  final SubjectScope subjectScope;
  final NoteSortOrder sortOrder;
  final List<Note> results;
  final bool searchingTags;
  final bool searchingNotes;
  final AppException? tagSearchError;
  final AppException? noteSearchError;

  AppException? get actionError => tagSearchError ?? noteSearchError;

  const TagSearchState({
    this.tagKeyword = '',
    this.tagMatchMode = SearchMatchMode.contains,
    this.matchedTags = const [],
    this.selectedTagIds = const {},
    this.subjectScope = const SubjectScope.all(),
    this.sortOrder = NoteSortOrder.updatedDesc,
    this.results = const [],
    this.searchingTags = false,
    this.searchingNotes = false,
    this.tagSearchError,
    this.noteSearchError,
  });

  TagSearchState copyWith({
    String? tagKeyword,
    SearchMatchMode? tagMatchMode,
    List<Tag>? matchedTags,
    Set<String>? selectedTagIds,
    SubjectScope? subjectScope,
    NoteSortOrder? sortOrder,
    List<Note>? results,
    bool? searchingTags,
    bool? searchingNotes,
    AppException? tagSearchError,
    AppException? noteSearchError,
    bool clearTagSearchError = false,
    bool clearNoteSearchError = false,
  }) => TagSearchState(
    tagKeyword: tagKeyword ?? this.tagKeyword,
    tagMatchMode: tagMatchMode ?? this.tagMatchMode,
    matchedTags: matchedTags ?? this.matchedTags,
    selectedTagIds: selectedTagIds ?? this.selectedTagIds,
    subjectScope: subjectScope ?? this.subjectScope,
    sortOrder: sortOrder ?? this.sortOrder,
    results: results ?? this.results,
    searchingTags: searchingTags ?? this.searchingTags,
    searchingNotes: searchingNotes ?? this.searchingNotes,
    tagSearchError: clearTagSearchError
        ? null
        : tagSearchError ?? this.tagSearchError,
    noteSearchError: clearNoteSearchError
        ? null
        : noteSearchError ?? this.noteSearchError,
  );
}

/// 标签搜索页面状态；Provider autoDispose 保证退出后不保留条件。
class TagSearchVm extends AsyncNotifier<TagSearchState> {
  int _tagRequestRevision = 0;
  int _noteRequestRevision = 0;

  @override
  FutureOr<TagSearchState> build() => const TagSearchState();

  Future<void> setTagKeyword(String keyword) async {
    final current = _current;
    state = AsyncData(
      current.copyWith(
        tagKeyword: keyword,
        matchedTags: keyword.trim().isEmpty ? const [] : null,
        searchingTags: keyword.trim().isNotEmpty,
        clearTagSearchError: true,
      ),
    );
    await _refreshMatchedTags();
  }

  Future<void> setTagMatchMode(SearchMatchMode matchMode) async {
    state = AsyncData(
      _current.copyWith(
        tagMatchMode: matchMode,
        searchingTags: _current.tagKeyword.trim().isNotEmpty,
        clearTagSearchError: true,
      ),
    );
    await _refreshMatchedTags();
  }

  Future<void> setSelectedTagIds(Set<String> tagIds) async {
    state = AsyncData(
      _current.copyWith(
        selectedTagIds: Set.unmodifiable(tagIds),
        results: tagIds.isEmpty ? const [] : null,
        clearNoteSearchError: true,
      ),
    );
    await _refreshNotes();
  }

  Future<void> setSubjectScope(SubjectScope subjectScope) async {
    state = AsyncData(
      _current.copyWith(subjectScope: subjectScope, clearNoteSearchError: true),
    );
    await _refreshNotes();
  }

  Future<void> setSortOrder(NoteSortOrder sortOrder) async {
    state = AsyncData(
      _current.copyWith(sortOrder: sortOrder, clearNoteSearchError: true),
    );
    await _refreshNotes();
  }

  Future<void> refresh() => _refreshNotes();
  Future<void> retryTagSearch() => _refreshMatchedTags();
  Future<void> retryNoteSearch() => _refreshNotes();

  TagSearchState get _current => state.value ?? const TagSearchState();

  Future<void> _refreshMatchedTags() async {
    final current = _current;
    final keyword = current.tagKeyword.trim();
    final revision = ++_tagRequestRevision;
    if (keyword.isEmpty) {
      state = AsyncData(
        current.copyWith(
          matchedTags: const [],
          searchingTags: false,
          clearTagSearchError: true,
        ),
      );
      return;
    }

    final result = await ref
        .read(tagRepositoryProvider)
        .searchTags(keyword: keyword, matchMode: current.tagMatchMode);
    if (!ref.mounted) return;
    if (revision != _tagRequestRevision) return;
    final latest = _current;
    if (result is Success<List<Tag>>) {
      state = AsyncData(
        latest.copyWith(
          matchedTags: result.value,
          searchingTags: false,
          clearTagSearchError: true,
        ),
      );
    } else {
      state = AsyncData(
        latest.copyWith(
          searchingTags: false,
          tagSearchError: (result as Failure<List<Tag>>).exception,
        ),
      );
    }
  }

  Future<void> _refreshNotes() async {
    final current = _current;
    final revision = ++_noteRequestRevision;
    if (current.selectedTagIds.isEmpty) {
      state = AsyncData(
        current.copyWith(
          results: const [],
          searchingNotes: false,
          clearNoteSearchError: true,
        ),
      );
      return;
    }
    state = AsyncData(
      current.copyWith(searchingNotes: true, clearNoteSearchError: true),
    );
    final result = await ref
        .read(noteRepositoryProvider)
        .search(
          NoteSearchQuery(
            tagIds: current.selectedTagIds,
            subjectScope: current.subjectScope,
            sortOrder: current.sortOrder,
          ),
        );
    if (!ref.mounted) return;
    if (revision != _noteRequestRevision) return;
    final latest = _current;
    if (result is Success<List<Note>>) {
      state = AsyncData(
        latest.copyWith(
          results: result.value,
          searchingNotes: false,
          clearNoteSearchError: true,
        ),
      );
    } else {
      state = AsyncData(
        latest.copyWith(
          searchingNotes: false,
          noteSearchError: (result as Failure<List<Note>>).exception,
        ),
      );
    }
  }
}
