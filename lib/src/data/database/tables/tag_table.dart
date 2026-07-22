// 文件: lib/src/data/database/tables/tag_table.dart
// 作用: 标签表。名字唯一，附颜色。配合 note_tag 关联表实现笔记-标签 N 对 N。
//       定位：分级（书-章-节）为主、标签辅助（待细化1 已定 A 并用）。
//       详见技术方案 B §二 笔记块 表5。
import 'package:drift/drift.dart';

/// 标签表。
@DataClassName('TagEntity')
class Tags extends Table {
  /// UUID 主键
  TextColumn get id => text()();

  /// 标签名，唯一
  TextColumn get name => text().unique()();

  /// 标签颜色
  TextColumn get color => text().nullable()();

  /// 创建时间（毫秒）
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
