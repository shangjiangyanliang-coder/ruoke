// 文件: lib/src/data/database/daos/note_version_dao.dart
// 作用: 笔记历史版本快照 DAO。第1批骨架；第4批做"历史版本/回退"时扩充
//       写快照、列版本、按 versionNo 取快照等。
//       详见技术方案 B §二 表3。
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/note_version_table.dart';

part 'note_version_dao.g.dart';

/// 笔记历史版本 DAO。
@DriftAccessor(tables: [NoteVersions])
class NoteVersionDao extends DatabaseAccessor<AppDatabase>
    with _$NoteVersionDaoMixin {
  NoteVersionDao(super.db);

  /// 写一条版本快照（用 companion，Repository 直接传字段）。
  Future<int> insertVersion(NoteVersionsCompanion version) =>
      into(noteVersions).insert(version);

  /// 按 noteId 列版本，新版本在前。
  Future<List<NoteVersionEntity>> listByNote(String noteId) {
    return (select(noteVersions)
          ..where((v) => v.noteId.equals(noteId))
          ..orderBy([(v) => OrderingTerm.desc(v.versionNo)]))
        .get();
  }

  /// 取某笔记当前最大版本号（无版本返回 0）。Repository 写新快照时用。
  Future<int> maxVersionNo(String noteId) async {
    final versions = await (select(noteVersions)
          ..where((v) => v.noteId.equals(noteId))
          ..orderBy([(v) => OrderingTerm.desc(v.versionNo)])
          ..limit(1))
        .get();
    return versions.isEmpty ? 0 : versions.first.versionNo;
  }

  /// 取某版本号的快照（第4批回退用）。
  Future<NoteVersionEntity?> getByVersion(String noteId, int versionNo) {
    return (select(noteVersions)
          ..where((v) => v.noteId.equals(noteId))
          ..where((v) => v.versionNo.equals(versionNo)))
        .getSingleOrNull();
  }
}
