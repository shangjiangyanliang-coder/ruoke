// 文件: lib/src/data/database/daos/tag_dao.dart
// 作用: 标签 DAO。第1批骨架；第5批做"标签管理 + 搜索"时扩充改删、改名查重。
//       详见技术方案 B §二 表5。
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/tag_table.dart';

part 'tag_dao.g.dart';

/// DAO 内部标签名称匹配方式，避免数据层依赖 feature 模型。
enum TagDaoMatchMode { contains, exact }

/// 标签 DAO。
@DriftAccessor(tables: [Tags])
class TagDao extends DatabaseAccessor<AppDatabase> with _$TagDaoMixin {
  TagDao(super.db);

  /// 插入标签（name 唯一，重复会抛约束异常，交由 Repository 翻译）。
  Future<int> insertTag(TagEntity tag) => into(tags).insert(tag);

  /// 列出全部标签。
  Future<List<TagEntity>> listAll() {
    return (select(tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  }

  /// 按标签名称查询并按名称升序。
  Future<List<TagEntity>> searchByName(
    String keyword,
    TagDaoMatchMode matchMode,
  ) {
    final query = select(tags)
      ..where(
        (tag) => switch (matchMode) {
          TagDaoMatchMode.contains => tag.name.like(
            '%${_escapeLikePattern(keyword)}%',
            escapeChar: r'\',
          ),
          TagDaoMatchMode.exact => tag.name.equals(keyword),
        },
      )
      ..orderBy([(tag) => OrderingTerm.asc(tag.name)]);
    return query.get();
  }

  String _escapeLikePattern(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  /// 按名字取标签（查重/反查用）。
  Future<TagEntity?> getByName(String name) {
    return (select(tags)..where((t) => t.name.equals(name))).getSingleOrNull();
  }

  /// 按标签 id 批量获取标签，空集合无需查询。
  Future<List<TagEntity>> listByIds(List<String> ids) {
    if (ids.isEmpty) return Future.value([]);
    return (select(tags)
          ..where((tag) => tag.id.isIn(ids))
          ..orderBy([(tag) => OrderingTerm.asc(tag.name)]))
        .get();
  }

  /// 重命名标签，唯一约束异常由 Repository 翻译。
  Future<int> renameTag(String id, String name) {
    return (update(tags)..where((tag) => tag.id.equals(id))).write(
      TagsCompanion(name: Value(name)),
    );
  }

  /// 删除标签实体；关联记录必须先由调用方在同一事务中删除。
  Future<int> deleteTag(String id) {
    return (delete(tags)..where((tag) => tag.id.equals(id))).go();
  }
}
