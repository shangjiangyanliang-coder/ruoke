// 文件: lib/src/data/database/tables/note_tag_table.dart
// 作用: 笔记-标签关联表（N 对 N）。复合主键 (noteId, tagId)。
//       详见技术方案 B §二 笔记块 表6。
import 'package:drift/drift.dart';

/// 笔记-标签关联表（N 对 N，复合主键）。
@DataClassName('NoteTagEntity')
class NoteTags extends Table {
  /// 笔记 id
  TextColumn get noteId => text()();

  /// 标签 id
  TextColumn get tagId => text()();

  /// 关联创建时间（毫秒）
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {noteId, tagId};
}
