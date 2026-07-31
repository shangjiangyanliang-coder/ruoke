// 文件: lib/src/features/notes/models/note.dart
// 作用: 笔记领域模型（与 Drift 的 NoteEntity 解耦的纯 Dart 类）。
//       Repository 在 DAO(NoteEntity) 与 ViewModel(Note) 之间做转换，
//       让 ViewModel 不直接碰 Drift 生成类（呼应 A 文档"ViewModel 不 import Drift"红线）。
//       字段对齐 B 文档 note 表。
import '../../../data/database/app_database.dart' show NoteEntity;

/// 笔记领域模型。
class Note {
  /// UUID 主键
  final String id;

  /// 所属科目节点 id
  final String subjectId;

  /// 可空标题
  final String? title;

  /// 富文本正文 Delta JSON（决策②）
  final String? contentJson;

  /// 派生纯文字（搜索/备份降级用）
  final String plainText;

  /// 草稿态
  final bool isDraft;

  /// 本条 AI 不可见
  final bool isAiHidden;

  /// 来源：manual/ocr/import/...
  final String? sourceType;

  /// 来源指针
  final String? sourceRef;

  /// 续学时间戳
  final int? lastReadAt;

  /// 同一书、章或节内的显示顺序
  final int sortOrder;

  /// 创建时间（毫秒）
  final int createdAt;

  /// 更新时间（毫秒）
  final int updatedAt;

  /// 是否软删
  final bool isDeleted;

  /// 软删时间
  final int? deletedAt;

  const Note({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.contentJson,
    required this.plainText,
    required this.isDraft,
    required this.isAiHidden,
    required this.sourceType,
    required this.sourceRef,
    required this.lastReadAt,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    required this.deletedAt,
  });

  /// 从 Drift 实体转领域模型。
  factory Note.fromEntity(NoteEntity e) => Note(
    id: e.id,
    subjectId: e.subjectId,
    title: e.title,
    contentJson: e.contentJson,
    plainText: e.plainText,
    isDraft: e.isDraft,
    isAiHidden: e.isAiHidden,
    sourceType: e.sourceType,
    sourceRef: e.sourceRef,
    lastReadAt: e.lastReadAt,
    sortOrder: e.sortOrder,
    createdAt: e.createdAt,
    updatedAt: e.updatedAt,
    isDeleted: e.isDeleted,
    deletedAt: e.deletedAt,
  );

  /// 列表显示用标题：空标题回退"无标题"。
  String get displayTitle =>
      (title == null || title!.trim().isEmpty) ? '无标题' : title!;

  /// 列表摘要：首段纯文字前若干字。
  String get summary {
    final t = plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? '(无正文)' : t;
  }
}
