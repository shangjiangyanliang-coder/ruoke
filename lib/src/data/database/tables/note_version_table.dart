// 文件: lib/src/data/database/tables/note_version_table.dart
// 作用: 笔记历史版本快照表。每次保存正文且内容变化时写一条快照（F1.1.4 回退）。
//       保留近 N 版（MVP 先不裁剪，N 版上限留 V2）。
//       详见技术方案 B §二 笔记块 表3。
import 'package:drift/drift.dart';

/// 笔记历史版本表。
@DataClassName('NoteVersionEntity')
class NoteVersions extends Table {
  /// UUID 主键
  TextColumn get id => text()();

  /// 所属笔记
  TextColumn get noteId => text()();

  /// 版本号，递增
  IntColumn get versionNo => integer()();

  /// 该版本完整正文快照（Delta JSON）
  TextColumn get snapshotJson => text()();

  /// 版本生成时间（毫秒）
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
