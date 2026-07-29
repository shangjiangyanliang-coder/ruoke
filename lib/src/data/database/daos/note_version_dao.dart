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

  /// 按版本主键查询，供 Repository 校验版本所属笔记。
  Future<NoteVersionEntity?> getById(String id) {
    return (select(
      noteVersions,
    )..where((v) => v.id.equals(id))).getSingleOrNull();
  }

  /// 按笔记和自定义名称查询，可排除正在被重命名的版本。
  Future<NoteVersionEntity?> getByName({
    required String noteId,
    required String name,
    String? excludingVersionId,
  }) {
    final query = select(noteVersions)
      ..where((v) => v.noteId.equals(noteId))
      ..where((v) => v.name.equals(name));
    if (excludingVersionId != null) {
      query.where((v) => v.id.equals(excludingVersionId).not());
    }
    return query.getSingleOrNull();
  }

  /// 只更新版本元数据名称，快照内容保持不变。
  Future<int> renameVersion(String id, String? name) {
    return (update(noteVersions)..where((v) => v.id.equals(id))).write(
      NoteVersionsCompanion(name: Value(name)),
    );
  }

  /// 按主键集合读取实际存在的版本；空集合避免生成无效 IN 查询。
  Future<List<NoteVersionEntity>> listByIds(Set<String> ids) {
    if (ids.isEmpty) return Future.value([]);
    return (select(noteVersions)..where((v) => v.id.isIn(ids))).get();
  }

  /// 按主键集合永久删除版本；版本号由调用方保留原值，不在此处重排。
  Future<int> deleteByIds(Set<String> ids) {
    if (ids.isEmpty) return Future.value(0);
    return (delete(noteVersions)..where((v) => v.id.isIn(ids))).go();
  }

  /// 按 noteId 列版本，新版本在前。
  Future<List<NoteVersionEntity>> listByNote(String noteId) {
    return (select(noteVersions)
          ..where((v) => v.noteId.equals(noteId))
          ..orderBy([(v) => OrderingTerm.desc(v.versionNo)]))
        .get();
  }

  /// 取某笔记当前最大版本号（无版本返回 0）。Repository 写新快照时用。
  Future<int> maxVersionNo(String noteId) async {
    final versions =
        await (select(noteVersions)
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
