// 笔记搜索条件与排序定义，供 Repository 和 ViewModel 共用。
enum NoteSortOrder { updatedDesc, updatedAsc, titleAsc }

/// 笔记搜索条件：关键词、标签并集和排序。
class NoteSearchQuery {
  final String keyword;
  final Set<String> tagIds;
  final NoteSortOrder sortOrder;

  const NoteSearchQuery({
    this.keyword = '',
    this.tagIds = const {},
    this.sortOrder = NoteSortOrder.updatedDesc,
  });
}
