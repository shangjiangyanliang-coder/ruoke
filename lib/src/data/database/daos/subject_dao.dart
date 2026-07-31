// 文件: lib/src/data/database/daos/subject_dao.dart
// 作用: 科目树 DAO。第3批扩充：插入用 companion、按 id 取、软删、子节点计数
//       （判空/判叶用）。树形查询靠 childrenOf 递归（数据量小，无需递归CTE）。
//       详见技术方案 A §三 + B §二 表1。
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/subject_table.dart';

part 'subject_dao.g.dart';

/// 科目树 DAO。
@DriftAccessor(tables: [Subjects])
class SubjectDao extends DatabaseAccessor<AppDatabase> with _$SubjectDaoMixin {
  SubjectDao(super.db);

  /// 插入一个科目节点（用 companion，可只填部分字段），返回受影响行数。
  Future<int> insertSubject(SubjectsCompanion node) =>
      into(subjects).insert(node);

  /// 插入一个完整科目节点（用 entity）。
  Future<int> insertSubjectEntity(SubjectEntity node) =>
      into(subjects).insert(node);

  /// 列出所有未软删节点（UI 树形展示用，按 sortOrder 升序）。
  Future<List<SubjectEntity>> listAll() {
    return (select(subjects)
          ..where((s) => s.isDeleted.equals(false))
          ..orderBy([
            (s) => OrderingTerm.asc(s.sortOrder),
            (s) => OrderingTerm.asc(s.createdAt),
            (s) => OrderingTerm.asc(s.id),
          ]))
        .get();
  }

  /// 按 parentId 取直接子节点（构造树用）。
  Future<List<SubjectEntity>> childrenOf(String? parentId) {
    final query = select(subjects)
      ..where((s) => s.isDeleted.equals(false))
      ..orderBy([
        (s) => OrderingTerm.asc(s.sortOrder),
        (s) => OrderingTerm.asc(s.createdAt),
        (s) => OrderingTerm.asc(s.id),
      ]);
    if (parentId == null) {
      query.where((s) => s.parentId.isNull());
    } else {
      query.where((s) => s.parentId.equals(parentId));
    }
    return query.get();
  }

  /// 按名称部分匹配未软删除节点，LIKE 特殊字符按普通字符处理。
  Future<List<SubjectEntity>> searchByName(String keyword) {
    final query = select(subjects)
      ..where(
        (subject) =>
            subject.isDeleted.equals(false) &
            subject.name.like(
              '%${_escapeLikePattern(keyword)}%',
              escapeChar: r'\',
            ),
      )
      ..orderBy([
        (subject) => OrderingTerm.asc(subject.name),
        (subject) => OrderingTerm.asc(subject.level),
        (subject) => OrderingTerm.asc(subject.sortOrder),
      ]);
    return query.get();
  }

  String _escapeLikePattern(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  /// 按 id 取一条（含软删，交由 Repository 决定是否过滤）。
  Future<SubjectEntity?> getById(String id) {
    return (select(subjects)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  /// 软删：置 isDeleted=true + deletedAt=nowMs。
  Future<int> softDelete(String id, int deletedAtMs) {
    return (update(subjects)..where((s) => s.id.equals(id))).write(
      SubjectsCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(deletedAtMs),
      ),
    );
  }

  /// 同时更新书的文件夹归属、目标顺序与更新时间。
  Future<int> updateBookFolderAndOrder(
    String id,
    String? folderId,
    int sortOrder,
    int updatedAt,
  ) => (update(subjects)..where((subject) => subject.id.equals(id))).write(
    SubjectsCompanion(
      folderId: Value(folderId),
      sortOrder: Value(sortOrder),
      updatedAt: Value(updatedAt),
    ),
  );

  /// 兼容只调整书归属的既有调用；新移动流程应同时写入目标顺序。
  Future<int> updateFolder(String id, String? folderId, int updatedAt) =>
      (update(subjects)..where((subject) => subject.id.equals(id))).write(
        SubjectsCompanion(
          folderId: Value(folderId),
          updatedAt: Value(updatedAt),
        ),
      );

  /// 更新书、章或节在同级同类列表中的顺序。
  Future<int> updateSubjectSortOrder(String id, int sortOrder) =>
      (update(subjects)..where((subject) => subject.id.equals(id))).write(
        SubjectsCompanion(sortOrder: Value(sortOrder)),
      );

  /// 统计未软删子节点数（判叶/判空用）。parentId 为 null 时数顶层。
  Future<int> countChildren(String? parentId) async {
    final count = countAll();
    final query = selectOnly(subjects)
      ..addColumns([count])
      ..where(subjects.isDeleted.equals(false));
    if (parentId == null) {
      query.where(subjects.parentId.isNull());
    } else {
      query.where(subjects.parentId.equals(parentId));
    }
    final result = await query.get();
    return result.first.read(count) ?? 0;
  }

  /// 表是否为空（含软删的也判在内，seed 幂等用：仅真的没有任何节点时才 seed）。
  Future<int> totalCount() async {
    final count = countAll();
    final query = selectOnly(subjects)..addColumns([count]);
    final result = await query.get();
    return result.first.read(count) ?? 0;
  }
}
