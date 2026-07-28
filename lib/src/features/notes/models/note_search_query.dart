// 笔记搜索条件与排序定义，供 Repository 和 ViewModel 共用。
import 'search_match_mode.dart';
import 'subject_scope.dart';

enum NoteSortOrder { updatedDesc, updatedAsc, titleAsc }

/// 笔记搜索条件：关键词、标签并集、科目范围和排序。
class NoteSearchQuery {
  final String keyword;
  final SearchMatchMode keywordMatchMode;
  final Set<String> tagIds;
  final SubjectScope subjectScope;
  final NoteSortOrder sortOrder;

  const NoteSearchQuery({
    this.keyword = '',
    this.keywordMatchMode = SearchMatchMode.contains,
    this.tagIds = const {},
    this.subjectScope = const SubjectScope.all(),
    this.sortOrder = NoteSortOrder.updatedDesc,
  });
}
