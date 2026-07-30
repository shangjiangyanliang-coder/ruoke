// 文件: lib/src/data/database/daos/folder_dao.dart
// 作用: 提供文件夹表的基础读写查询。
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/subject_folder_table.dart';
import '../tables/subject_table.dart';

part 'folder_dao.g.dart';

/// 文件夹数据访问对象。
@DriftAccessor(tables: [SubjectFolders, Subjects])
class FolderDao extends DatabaseAccessor<AppDatabase> with _$FolderDaoMixin {
  FolderDao(super.db);

  /// 插入一个完整文件夹记录。
  Future<int> insertFolder(SubjectFoldersCompanion folder) =>
      into(subjectFolders).insert(folder);

  /// 更新文件夹名称与更新时间。
  Future<int> rename(String id, String name, int updatedAt) =>
      (update(subjectFolders)..where((folder) => folder.id.equals(id))).write(
        SubjectFoldersCompanion(name: Value(name), updatedAt: Value(updatedAt)),
      );

  /// 更新文件夹父目录与更新时间。
  Future<int> move(String id, String? parentId, int updatedAt) =>
      (update(subjectFolders)..where((folder) => folder.id.equals(id))).write(
        SubjectFoldersCompanion(
          parentId: Value(parentId),
          updatedAt: Value(updatedAt),
        ),
      );

  /// 读取全部活动文件夹，用于移动前的循环关系校验。
  Future<List<SubjectFolderEntity>> listAll() =>
      (select(subjectFolders)
            ..where((folder) => folder.isDeleted.equals(false))
            ..orderBy([(folder) => OrderingTerm.asc(folder.sortOrder)]))
          .get();

  /// 按文件夹读取直属书；null 表示根目录未归类书。
  Future<List<SubjectEntity>> booksIn(String? folderId) {
    final query = select(subjects)
      ..where((subject) =>
          subject.isDeleted.equals(false) & subject.level.equals(0))
      ..orderBy([(subject) => OrderingTerm.asc(subject.sortOrder)]);
    if (folderId == null) {
      query.where((subject) => subject.folderId.isNull());
    } else {
      query.where((subject) => subject.folderId.equals(folderId));
    }
    return query.get();
  }

  /// 按父文件夹读取直属、未软删除的子文件夹。
  Future<List<SubjectFolderEntity>> childrenOf(String? parentId) {
    final query = select(subjectFolders)
      ..where((folder) => folder.isDeleted.equals(false))
      ..orderBy([(folder) => OrderingTerm.asc(folder.sortOrder)]);
    if (parentId == null) {
      query.where((folder) => folder.parentId.isNull());
    } else {
      query.where((folder) => folder.parentId.equals(parentId));
    }
    return query.get();
  }

  /// 按 id 读取活动文件夹，用于校验父目录存在性。
  Future<SubjectFolderEntity?> getActiveById(String id) =>
      (select(subjectFolders)
            ..where(
              (folder) =>
                  folder.id.equals(id) & folder.isDeleted.equals(false),
            ))
          .getSingleOrNull();

  /// 查找同一父目录下名称相同且未删除的文件夹。
  Future<SubjectFolderEntity?> findActiveByParentAndName(
    String? parentId,
    String name,
  ) {
    final query = select(subjectFolders)
      ..where(
        (folder) =>
            folder.isDeleted.equals(false) & folder.name.equals(name),
      );
    if (parentId == null) {
      query.where((folder) => folder.parentId.isNull());
    } else {
      query.where((folder) => folder.parentId.equals(parentId));
    }
    return query.getSingleOrNull();
  }
}
