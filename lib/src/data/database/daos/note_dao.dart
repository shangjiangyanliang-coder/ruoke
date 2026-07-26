// 文件: lib/src/data/database/daos/note_dao.dart
// 作用: 笔记表的数据访问对象（DAO）。Repository 调 DAO，DAO 不被 ViewModel 直接碰。
//       第2批扩充：插入用 companion、列出全部、更新、取最大版本号（为写快照用）。
//       详见技术方案 A §三 data/database/daos + B §五 Repository 接口约定。
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/note_table.dart';

part 'note_dao.g.dart';

/// DAO 内部排序类型，避免数据层依赖 feature 领域模型。
enum NoteDaoSortOrder { updatedDesc, updatedAsc, titleAsc }

/// 笔记 DAO。
@DriftAccessor(tables: [Notes])
class NoteDao extends DatabaseAccessor<AppDatabase> with _$NoteDaoMixin {
  NoteDao(super.db);

  /// 插入一条笔记（用 companion，可只填部分字段），返回受影响行数。
  Future<int> insertNote(NotesCompanion note) => into(notes).insert(note);

  /// 插入一条完整笔记（用 entity），返回受影响行数。
  Future<int> insertNoteEntity(NoteEntity note) => into(notes).insert(note);

  /// 列出全部未软删笔记，按更新时间倒序（列表/续学排序用）。
  Future<List<NoteEntity>> listAll() {
    return (select(notes)
          ..where((n) => n.isDeleted.equals(false))
          ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
        .get();
  }

  /// 搜索未软删除笔记；多标签为并集，标签子查询避免重复笔记。
  Future<List<NoteEntity>> search({
    String? keyword,
    required Set<String> tagIds,
    required NoteDaoSortOrder sortOrder,
  }) async {
    final query = select(notes);

    var predicate = notes.isDeleted.equals(false);
    if (keyword != null) {
      final pattern = '%$keyword%';
      predicate =
          predicate &
          (notes.title.like(pattern) | notes.plainText.like(pattern));
    }
    if (tagIds.isNotEmpty) {
      final taggedNoteIds = db.selectOnly(db.noteTags)
        ..addColumns([db.noteTags.noteId])
        ..where(db.noteTags.tagId.isIn(tagIds));
      predicate = predicate & notes.id.isInQuery(taggedNoteIds);
    }
    query
      ..where((_) => predicate)
      ..orderBy([
        (n) => switch (sortOrder) {
          NoteDaoSortOrder.updatedDesc => OrderingTerm.desc(n.updatedAt),
          NoteDaoSortOrder.updatedAsc => OrderingTerm.asc(n.updatedAt),
          NoteDaoSortOrder.titleAsc => OrderingTerm.asc(n.title),
        },
        (n) => OrderingTerm.asc(n.id),
      ]);

    return query.get();
  }

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

  /// 更新笔记的可变字段。只写非 absent 的字段。
  Future<int> updateNote(
    String id, {
    String? title,
    String? contentJson,
    String? plainText,
    bool? isDraft,
    int? updatedAt,
  }) {
    return (update(notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        title: title == null ? const Value.absent() : Value(title),
        contentJson: contentJson == null
            ? const Value.absent()
            : Value(contentJson),
        plainText: plainText == null ? const Value.absent() : Value(plainText),
        isDraft: isDraft == null ? const Value.absent() : Value(isDraft),
        updatedAt: updatedAt == null ? const Value.absent() : Value(updatedAt),
      ),
    );
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
