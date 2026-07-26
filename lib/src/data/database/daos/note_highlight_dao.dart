// 文件: lib/src/data/database/daos/note_highlight_dao.dart
// 作用: 笔记重点条 DAO。第1批骨架；第4批做"划重点"时扩充写入、按笔记列重点。
//       详见技术方案 B §二 表4。
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/note_highlight_table.dart';

part 'note_highlight_dao.g.dart';

/// 笔记重点条 DAO。
@DriftAccessor(tables: [NoteHighlights])
class NoteHighlightDao extends DatabaseAccessor<AppDatabase>
    with _$NoteHighlightDaoMixin {
  NoteHighlightDao(super.db);

  /// 写一条重点。
  Future<int> insertHighlight(NoteHighlightsCompanion highlight) =>
      into(noteHighlights).insert(highlight);

  /// 按笔记列出所有重点条。
  Future<List<NoteHighlightEntity>> listByNote(String noteId) {
    return (select(noteHighlights)
          ..where((h) => h.noteId.equals(noteId))
          ..orderBy([(h) => OrderingTerm.asc(h.createdAt)]))
        .get();
  }

  /// 删除某笔记全部重点（重存正文时先清后写，保持一致）。
  Future<int> deleteByNote(String noteId) {
    return (delete(noteHighlights)..where((h) => h.noteId.equals(noteId))).go();
  }
}
