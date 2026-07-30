// 文件: lib/src/data/database/tables/subject_folder_table.dart
// 作用: 定义独立于书-章-节树的可嵌套文件夹表。
import 'package:drift/drift.dart';

/// 文件夹节点表。parentId 为 null 时表示根文件夹。
@DataClassName('SubjectFolderEntity')
class SubjectFolders extends Table {
  /// UUID 主键。
  TextColumn get id => text()();

  /// 父文件夹 id；根文件夹为 null。
  TextColumn get parentId => text().nullable()();

  /// 同一父目录内必须由仓储层保证唯一的名称。
  TextColumn get name => text()();

  /// 同一目录内的显示顺序。
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 创建时间（毫秒）。
  IntColumn get createdAt => integer()();

  /// 更新时间（毫秒）。
  IntColumn get updatedAt => integer()();

  /// 软删标志，避免解散或移动失败时丢失数据。
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// 软删时间。
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
