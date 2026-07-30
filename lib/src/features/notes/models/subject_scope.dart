/// 科目范围类型。
enum SubjectScopeKind { all, subtree, level, folder, ungroupedBooks }

/// 笔记搜索的书—章—节范围。
class SubjectScope {
  final SubjectScopeKind kind;
  final String? subjectId;
  final int? level;

  const SubjectScope.all()
    : kind = SubjectScopeKind.all,
      subjectId = null,
      level = null;

  const SubjectScope.subtree(this.subjectId)
    : kind = SubjectScopeKind.subtree,
      level = null,
      assert(subjectId != null && subjectId != '');

  const SubjectScope.level(this.level)
    : kind = SubjectScopeKind.level,
      subjectId = null,
      assert(level != null && level >= 0 && level <= 2);

  const SubjectScope.folder(this.subjectId)
    : kind = SubjectScopeKind.folder,
      level = null,
      assert(subjectId != null && subjectId != '');

  const SubjectScope.ungroupedBooks()
    : kind = SubjectScopeKind.ungroupedBooks,
      subjectId = null,
      level = null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubjectScope &&
          kind == other.kind &&
          subjectId == other.subjectId &&
          level == other.level;

  @override
  int get hashCode => Object.hash(kind, subjectId, level);
}
