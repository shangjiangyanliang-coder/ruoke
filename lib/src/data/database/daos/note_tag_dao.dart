// 文件: lib/src/data/database/daos/note_tag_dao.dart
// 作用: 笔记-标签关联 DAO。第1批骨架；第5批扩充给笔记贴/撕标签、按标签筛笔记。
//       详见技术方案 B §二 表6。
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/note_tag_table.dart';

part 'note_tag_dao.g.dart';

/// 笔记-标签关联 DAO。
@DriftAccessor(tables: [NoteTags])
class NoteTagDao extends DatabaseAccessor<AppDatabase> with _$NoteTagDaoMixin {
  NoteTagDao(super.db);

  /// 给笔记贴一个标签（关联已存在则忽略，靠复合主键去重）。
  Future<void> insertNoteTag(NoteTagEntity link) async {
    await into(noteTags).insert(link, mode: InsertMode.insertOrIgnore);
  }

  /// 按 noteId 取该笔记所有关联标签 id。
  Future<List<NoteTagEntity>> listByNote(String noteId) {
    return (select(noteTags)..where((nt) => nt.noteId.equals(noteId))).get();
  }

  /// 删除笔记的全部标签关联，供替换标签事务使用。
  Future<int> deleteByNote(String noteId) {
    return (delete(noteTags)..where((link) => link.noteId.equals(noteId))).go();
  }

  /// 删除标签的全部笔记关联，供删除标签事务使用。
  Future<int> deleteByTag(String tagId) {
    return (delete(noteTags)..where((link) => link.tagId.equals(tagId))).go();
  }

  /// 统计关联到标签的未软删除笔记数量。
  Future<int> countActiveNotesForTag(String tagId) async {
    final query = select(noteTags).join([
      innerJoin(db.notes, db.notes.id.equalsExp(noteTags.noteId)),
    ])..where(noteTags.tagId.equals(tagId) & db.notes.isDeleted.equals(false));
    return (await query.get()).length;
  }
}
