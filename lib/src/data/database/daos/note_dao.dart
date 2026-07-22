// 文件: lib/src/data/database/daos/note_dao.dart
// 作用: 笔记表的数据访问对象（DAO）。Repository 调 DAO，DAO 不被 ViewModel 直接碰。
//       当前阶段（第1批）仅放骨架方法：插入、按 subject 列出、按 id 取、软删。
//       第2批 LocalNoteRepository 实现里会扩充 watch/listVersions/create/update 等。
//       详见技术方案 A §三 data/database/daos + B §五 Repository 接口约定。
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/note_table.dart';

part 'note_dao.g.dart';

/// 笔记 DAO。
@DriftAccessor(tables: [Notes])
class NoteDao extends DatabaseAccessor<AppDatabase> with _$NoteDaoMixin {
  NoteDao(super.db);

  /// 插入一条笔记，返回受影响行数。
  Future<int> insertNote(NoteEntity note) => into(notes).insert(note);

  /// 按 subject 列出未软删笔记（不含已删）。
  Future<List<NoteEntity>> listBySubject(String subjectId) {
    return (select(notes)
          ..where((n) => n.subjectId.equals(subjectId))
          ..where((n) => n.isDeleted.equals(false)))
        .get();
  }

  /// 按 id 取一条（含软删，交由 Repository 决定是否过滤）。
  Future<NoteEntity?> getById(String id) {
    return (select(notes)..where((n) => n.id.equals(id))).getSingleOrNull();
  }

  /// 软删：置 isDeleted=true + deletedAt=nowMs，不真删。
  Future<int> softDelete(String id, int deletedAtMs) {
    return (update(notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(deletedAtMs),
      ),
    );
  }
}
