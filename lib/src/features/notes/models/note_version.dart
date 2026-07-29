// 文件: lib/src/features/notes/models/note_version.dart
// 作用: 笔记历史版本领域模型（对应 Drift NoteVersionEntity）。
//       第2批先建模型备用（保存时写快照），回退 UI 在第4批做。
import '../../../data/database/app_database.dart' show NoteVersionEntity;

/// 笔记历史版本领域模型。
class NoteVersion {
  final String id;
  final String noteId;
  final int versionNo;
  final String snapshotJson;
  final int createdAt;
  final String? name;

  const NoteVersion({
    required this.id,
    required this.noteId,
    required this.versionNo,
    required this.snapshotJson,
    required this.createdAt,
    this.name,
  });

  /// 供版本列表使用：未命名的版本回退到稳定的版本号名称。
  String get displayName =>
      name == null || name!.isEmpty ? '版本 $versionNo' : name!;

  factory NoteVersion.fromEntity(NoteVersionEntity e) => NoteVersion(
    id: e.id,
    noteId: e.noteId,
    versionNo: e.versionNo,
    snapshotJson: e.snapshotJson,
    createdAt: e.createdAt,
    name: e.name,
  );
}
