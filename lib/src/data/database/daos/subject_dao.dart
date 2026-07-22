// 文件: lib/src/data/database/daos/subject_dao.dart
// 作用: 科目树 DAO。第1批先放骨架：插入、列出全部、按 parentId 取子节点。
//       第3批做"书-章-节树"时扩充树形查询、移动、软删恢复等。
//       详见技术方案 A §三 + B §二 表1。
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/subject_table.dart';

part 'subject_dao.g.dart';

/// 科目树 DAO。
@DriftAccessor(tables: [Subjects])
class SubjectDao extends DatabaseAccessor<AppDatabase> with _$SubjectDaoMixin {
  SubjectDao(super.db);

  /// 插入一个科目节点。
  Future<int> insertSubject(SubjectEntity node) => into(subjects).insert(node);

  /// 列出所有未软删节点（UI 树形展示用）。
  Future<List<SubjectEntity>> listAll() {
    return (select(subjects)
          ..where((s) => s.isDeleted.equals(false))
          ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]))
        .get();
  }

  /// 按 parentId 取直接子节点（构造树用）。
  Future<List<SubjectEntity>> childrenOf(String? parentId) {
    final query = select(subjects)
      ..where((s) => s.isDeleted.equals(false))
      ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]);
    if (parentId == null) {
      query.where((s) => s.parentId.isNull());
    } else {
      query.where((s) => s.parentId.equals(parentId));
    }
    return query.get();
  }
}
