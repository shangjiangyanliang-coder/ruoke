// 文件: lib/src/features/notes/models/subject_folder.dart
// 作用: 在数据访问层与笔记功能之间传递文件夹领域数据。
import '../../../data/database/app_database.dart' show SubjectFolderEntity;

/// 独立于书-章-节树的文件夹领域模型。
class SubjectFolder {
  final String id;
  final String? parentId;
  final String name;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
  final bool isDeleted;
  final int? deletedAt;

  const SubjectFolder({
    required this.id,
    required this.parentId,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    required this.deletedAt,
  });

  /// 将 Drift 实体转换为与界面无关的领域模型。
  factory SubjectFolder.fromEntity(SubjectFolderEntity entity) => SubjectFolder(
    id: entity.id,
    parentId: entity.parentId,
    name: entity.name,
    sortOrder: entity.sortOrder,
    createdAt: entity.createdAt,
    updatedAt: entity.updatedAt,
    isDeleted: entity.isDeleted,
    deletedAt: entity.deletedAt,
  );
}
