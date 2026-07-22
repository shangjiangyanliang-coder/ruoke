// 文件: lib/src/data/database/tables/note_highlight_table.dart
// 作用: 笔记重点条表。kind=red(红字)/underline(下划线)，
//       text 是重点文字内容（F1.18 转题的源文本），
//       start/end 是 content_json 内定位（MVP 存 text 即可，不强依赖定位）。
//       详见技术方案 B §二 笔记块 表4。
import 'package:drift/drift.dart';

/// 笔记重点条表。
@DataClassName('NoteHighlightEntity')
class NoteHighlights extends Table {
  /// UUID 主键
  TextColumn get id => text()();

  /// 所属笔记
  TextColumn get noteId => text()();

  /// red（红字）/ underline（下划线）
  TextColumn get kind => text()();

  /// 重点文字内容（列名用 body 以避开 Drift Table.text 方法冲突）
  TextColumn get body => text()();

  /// content_json 内定位起点（V2 用）
  IntColumn get start => integer().nullable()();

  /// content_json 内定位终点（V2 用）
  IntColumn get end => integer().nullable()();

  /// 创建时间（毫秒）
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
