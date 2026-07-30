// 文件: lib/src/features/notes/models/subject.dart
// 作用: 科目树领域模型（与 Drift SubjectEntity 解耦的纯 Dart 类）。
//       Repository 在 DAO(SubjectEntity) 与 ViewModel(Subject) 间做转换。
//       level: 0=书 1=章 2=节（呼应 F1.1.6 四级链，章/节可省）。
//       详见技术方案 B §二 表1。
import '../../../data/database/app_database.dart' show SubjectEntity;

/// 科目节点领域模型。
class Subject {
  /// UUID 主键
  final String id;

  /// 父节点 id；顶级科目(书)为 null
  final String? parentId;

  /// 科目/书/章/节名
  final String name;

  /// 0=书 1=章 2=节
  final int level;

  /// 仅书可设置的文件夹归属；null 表示未归类书。
  final String? folderId;

  /// 同级排序
  final int sortOrder;

  /// 创建时间（毫秒）
  final int createdAt;

  /// 更新时间（毫秒）
  final int updatedAt;

  /// 是否软删
  final bool isDeleted;

  /// 软删时间
  final int? deletedAt;

  const Subject({
    required this.id,
    required this.parentId,
    required this.name,
    required this.level,
    required this.folderId,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    required this.deletedAt,
  });

  /// 从 Drift 实体转领域模型。
  factory Subject.fromEntity(SubjectEntity e) => Subject(
        id: e.id,
        parentId: e.parentId,
        name: e.name,
        level: e.level,
        folderId: e.folderId,
        sortOrder: e.sortOrder,
        createdAt: e.createdAt,
        updatedAt: e.updatedAt,
        isDeleted: e.isDeleted,
        deletedAt: e.deletedAt,
      );

  /// 层级中文标签（UI 面包屑/弹窗用）。
  String get levelLabel =>
      const {0: '书', 1: '章', 2: '节'}[level] ?? '科目';
}
