// 标签领域模型，隔离 Drift 实体供笔记功能使用。
import '../../../data/database/app_database.dart' show TagEntity;

/// 笔记标签的领域模型。
class Tag {
  final String id;
  final String name;
  final String? color;
  final int createdAt;

  const Tag({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
  });

  factory Tag.fromEntity(TagEntity entity) => Tag(
    id: entity.id,
    name: entity.name,
    color: entity.color,
    createdAt: entity.createdAt,
  );
}

/// 带有未删除笔记数量的标签，用于标签管理列表。
class TagWithCount extends Tag {
  final int noteCount;

  const TagWithCount({
    required super.id,
    required super.name,
    required super.color,
    required super.createdAt,
    required this.noteCount,
  });
}
