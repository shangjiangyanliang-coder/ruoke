// 文件: lib/src/data/database/tables/subject_table.dart
// 作用: 科目树表（书-章-节容器），自引用树形。
//       level: 0=书 1=章 2=节（呼应 F1.1.6 四级链，章/节可缺省）。
//       笔记和题挂到 subject 任一级实现降级（整本/整章/整节笔记）。
//       详见技术方案 B §二 笔记块 表1。
import 'package:drift/drift.dart';

/// 科目树节点表（书-章-节容器）。
@DataClassName('SubjectEntity')
class Subjects extends Table {
  /// UUID 主键
  TextColumn get id => text()();

  /// 父节点 id；顶级科目为 null，形成自引用树
  TextColumn get parentId => text().nullable()();

  /// 科目/书/章名
  TextColumn get name => text()();

  /// 0=书 1=章 2=节
  IntColumn get level => integer()();

  /// 同级排序
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 创建时间（毫秒）
  IntColumn get createdAt => integer()();

  /// 更新时间（毫秒）
  IntColumn get updatedAt => integer()();

  /// 软删标志
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// 软删时间（回收站排序/清理用）
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
